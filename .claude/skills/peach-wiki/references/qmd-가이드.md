# qmd CLI 레퍼런스

> qmd(Quick Markdown Search): 마크다운·코드 파일 로컬 하이브리드 검색 도구
> BM25 + 벡터 + LLM 리랭킹 조합

---

## 설치

```bash
npm install -g @tobilu/qmd
qmd --version
```

전제: Node.js v22+, 디스크 ~3GB. 플랫폼별 GPU/CPU 임베딩 기준은 `qmd-platform-embedding.md`를 참조한다.

---

## Named Index 분리 운영 (필수 패턴)

### 왜 `--index`를 써야 하는가

`qmd update/embed`는 컬렉션 범위 지정 플래그가 없다.
plain 실행 시 `~/.config/qmd/index.yml`에 등록된 **전체 컬렉션**이 처리된다.
여러 프로젝트·개인 옵시디언·CloudStorage 경로가 섞인 환경에서는 의도치 않은 재인덱싱이 발생한다.

`--index <name>` 플래그를 사용하면 **DB와 설정 파일이 동시에 분리**된다:

| 항목 | 기본 (`--index` 없음) | `--index my-project` |
|------|----------------------|----------------|
| DB 파일 | `~/.cache/qmd/index.sqlite` | `~/.cache/qmd/my-project.sqlite` |
| 설정 파일 | `~/.config/qmd/index.yml` | `~/.config/qmd/my-project.yml` |

- DB는 `--index` 지정 즉시 생성된다.
- 설정 파일(yml)은 `collection add` 시점에 생성된다.
- 모델 파일(`~/.cache/qmd/models/`)은 인덱스 간 **공유** — 추가 디스크 불필요.
- 공식 문서(README.md 739행): `qmd --index work search "quarterly reports"` — "Use separate index for different knowledge base"

### 표준 패턴

```bash
# 프로젝트명을 인덱스명으로 고정 (세션 시작 시 선언)
QMD_INDEX=$(basename $(pwd))   # 예: peach-wiki, my-project

# 초기 등록
qmd --index "$QMD_INDEX" collection add . --name "$QMD_INDEX" --mask "**/*.{ts,vue,md,sql,py,go,js}"
qmd --index "$QMD_INDEX" context add "qmd://$QMD_INDEX/" "프로젝트 한 줄 설명"
qmd --index "$QMD_INDEX" update
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32

# 갱신 (대량 변경)
qmd --index "$QMD_INDEX" update
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32

# 갱신 (소규모 수정)
qmd --index "$QMD_INDEX" update

# 기본 검색 (BM25, 빠름 — 위치 파악)
qmd --index "$QMD_INDEX" search "키워드" -c "$QMD_INDEX"

# 의미 검색 폴백 (search가 0건이거나 동의어·다국어·자연어 질문일 때)
qmd --index "$QMD_INDEX" query "질문" -c "$QMD_INDEX" --no-rerank

# GPU 오류 시 CPU 우회
QMD_FORCE_CPU=1 qmd --index "$QMD_INDEX" query "키워드" -c "$QMD_INDEX" --no-gpu --no-rerank

# 상태 확인 + 임베딩 벡터 정합성 진단
qmd --index "$QMD_INDEX" status
qmd --index "$QMD_INDEX" collection list
qmd --index "$QMD_INDEX" doctor
```

### `--index` 누락 위험

`--index`를 빠뜨리면 기본 `index.sqlite`에 컬렉션이 등록되고,
이후 plain `qmd update/embed`가 기본 인덱스의 전체 컬렉션(다른 프로젝트 포함)을 처리한다.
반드시 `--index "$QMD_INDEX"`를 붙여라.

> **plain `qmd doctor` 오진 주의 (실측)**: `--index` 없이 doctor를 실행하면 컬렉션이 없는 기본
> `index.sqlite`를 진단해 "no vectors"로 보고한다 — named index는 정상인데 "embed 미완"으로
> 오판하기 쉽다. **인덱스 상태 확인은 항상 `qmd --index "$QMD_INDEX" status`를 기준**으로 하고,
> doctor도 반드시 `--index`를 붙여 실행한다.

### MCP 서버 연동 주의

`qmd mcp`는 항상 기본 `index.sqlite`만 참조한다.
named index 데이터를 MCP로 노출하려면 별도 인스턴스를 띄워야 한다:

```bash
qmd --index "$QMD_INDEX" mcp
```

---

## 컬렉션 등록

```bash
# 코드 프로젝트
qmd --index "$QMD_INDEX" collection add . --name "$QMD_INDEX" --mask "**/*.{ts,vue,md,sql,py,go,js}"

# 옵시디언 노트
qmd --index "$QMD_INDEX" collection add . --name "$QMD_INDEX" --mask "**/*.md"

# 컨텍스트 설명 추가 (검색 품질 핵심)
qmd --index "$QMD_INDEX" context add "qmd://$QMD_INDEX/" "프로젝트 한 줄 설명"

# 인덱싱 + 임베딩
qmd --index "$QMD_INDEX" update
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32

# GPU 오류 시 CPU 우회
QMD_FORCE_CPU=1 qmd --index "$QMD_INDEX" update
QMD_FORCE_CPU=1 qmd --index "$QMD_INDEX" embed --max-docs-per-batch 16 --max-batch-mb 16
```

> **plain 등록 사용 시 주의**: `--index` 없이 실행하면 기본 인덱스의 전체 컬렉션이 처리된다.
> CloudStorage/Synology 경로가 포함된 경우 fileproviderd 부하가 발생할 수 있다.
> 반드시 `--index "$QMD_INDEX"` 패턴을 사용한다.

---

## 검색

검색 명령은 비용 차이가 크므로 단계적으로 escalation 한다.

| 명령 | 비용 (M5 / CPU 환경 관찰값) | 용도 |
|------|------------------|------|
| `search` | ~0.1~0.4초 | 위치 파악 (기본). 키워드·식별자·동일 표현이면 거의 항상 충분 |
| `query --no-rerank` | M5 ~3초 / CPU ~6초 | **search 0건 폴백** — 동의어·다국어·자연어 "어떻게/왜" 질문 |
| `query -C 5` | rerank만 M5 20~29초 / CPU 20초+ | rerank가 꼭 필요할 때, 후보 수 제한 |

> **search vs query 선택 (M5 실측 근거)**: 키워드가 본문에 그대로 있으면 search가 20~30배 빠르고 정확도도 동등하다.
> 반대로 동의어("벡터 어긋났을 때 다시 만드는 법")나 다국어(영어 질의→한글 문서)는 **search가 0건**이 되고 query(벡터)만 찾아낸다.
> 따라서 **search 먼저 → 0건이거나 의미/언어가 다르면 query로 폴백**이 정답이다.

> **소스 코드 식별자는 rg가 더 빠르다 (실측)**: 정의 위치를 찾는 단순 식별자·심볼 검색은
> `rg`(ripgrep, 0.01~0.02초)가 qmd search(0.1~0.4초)보다 빠르고 정의 파일을 직접 지목한다.
> qmd의 고유 가치는 **자연어·동의어 개념 검색**(코드에 없는 표현으로 wiki/spec/코드에 도달)에 있다.
> 도구 선택: 심볼 정의 위치 = rg → 키워드+문맥 = qmd search → 개념·자연어 = qmd query 폴백.

> **모드별 기본 비중 (IR 연구 + 실측)**: 검색 전략은 코퍼스 성격에 따라 다르다.
> - **코드 프로젝트(.git)**: `search` 비중을 높게. 코드는 식별자·심볼 정확 매칭이 산문보다 더 중요하다(BM25 강점). `query`는 "어떻게 동작" 자연어 질문에만.
> - **옵시디언 노트(.obsidian)**: `query`(하이브리드) 비중을 높게. 산문은 자연어·동의어·다국어 질의가 많아 BM25만으로는 자주 0건이 된다. 단발 키워드·고유명사는 여전히 search가 빠르다.
> 근거: BM25는 정확 토큰·코드에 강하고 dense(벡터)는 의미·패러프레이즈·cross-lingual에 강하다(BEIR, CodeSearchNet, HyDE 연구). 산문 노트일수록 dense 의존도가 높다.

```bash
# BM25 키워드 검색 (빠름 — 위치 파악 기본)
qmd --index "$QMD_INDEX" search "키워드" -c "$QMD_INDEX"

# 하이브리드 검색 (search가 0건이거나 동의어·다국어·자연어 질문일 때 폴백)
qmd --index "$QMD_INDEX" query "질문" -c "$QMD_INDEX" --no-rerank

# rerank 후보 수 제한 (rerank가 꼭 필요할 때)
qmd --index "$QMD_INDEX" query "질문" -c "$QMD_INDEX" -C 5

# 파일 경로만 (첫 컬럼이 #docid)
qmd --index "$QMD_INDEX" search "키워드" -c "$QMD_INDEX" --files

# 특정 문서 읽기 — search/query/--files 출력의 #docid(6자리 hex)로 호출한다.
#   URI(qmd://...)나 파일 경로 직접 입력은 "Document not found"로 실패한다.
qmd --index "$QMD_INDEX" get <docid>          # 예: qmd --index "$QMD_INDEX" get 425ec5
qmd --index "$QMD_INDEX" get <docid>:1:40     # from:count 라인 범위 (docid 기준)

# 컬렉션 파일 목록
qmd --index "$QMD_INDEX" ls "$QMD_INDEX"
```

> **CPU 환경 주의**: `qmd query`는 query expansion + embedding + reranking 비용을 포함한다.
> 한 번에 여러 `qmd query`를 동시에 실행하면 CPU 경합으로 체감 시간이 더 늘어난다.
> 위치 파악은 `qmd search`가 거의 항상 충분하고, search가 빈손일 때만 query로 폴백한다.

---

## 플랫폼별 임베딩 권장값

대형 인덱스나 GPU backend를 사용하는 환경은 `qmd-platform-embedding.md`의 기준을 우선 적용한다.

요약:

| 환경 | 우선 옵션 | 병렬도 | batch |
|------|-----------|--------|-------|
| Apple Silicon M4/M5 | `QMD_LLAMA_GPU=metal` | 2 | 32 docs / 32MB |
| Windows NVIDIA | `QMD_LLAMA_GPU=cuda` | 1 | 32 docs / 32MB |
| Windows AMD/Intel | `QMD_LLAMA_GPU=vulkan` | 1 | 32 docs / 32MB |
| CPU-only | `QMD_FORCE_CPU=1` 또는 `--no-gpu` | 1~2 | 16~32 docs / 16~32MB |

---

## Apple Metal 메시지 — 무해(폴백) vs 실제 장애 구분

Apple Silicon에서 `qmd query`, `qmd embed`, `qmd doctor` 실행 중 아래 메시지가 출력된다.

```text
[node-llama-cpp] ggml_metal_library_init_from_source: error compiling source
```

> **이 메시지 자체는 무해하다.** Metal 셰이더 **소스 컴파일**만 실패하고 사전컴파일된 Metal 백엔드로 폴백할 뿐, 임베딩·검색은 GPU로 정상 수행된다. (M5 실측: 메시지 출력 후에도 `doctor`가 `✓ device mode: metal`, `✓ device probe: GPU metal`을 보고하고 검색 결과도 정상)

**무해/장애 판정은 doctor로 한다:**

```bash
qmd --index "$QMD_INDEX" doctor | grep -iE "device|embedding|vector"
```

- `✓ device mode: metal` + `✓ device probe: GPU metal` → **정상**. 위 메시지는 무시한다.
- search는 LLM을 쓰지 않아 이 메시지가 아예 나오지 않는다 (메시지 유무로 검색 정상 여부를 판단하지 말 것).

진짜로 명령이 **멈추거나 결과가 비정상**일 때만 아래 CPU 우회를 검증한다:

```bash
qmd --index "$QMD_INDEX" search "키워드" -c "$QMD_INDEX" -n 5
QMD_FORCE_CPU=1 qmd --index "$QMD_INDEX" status
QMD_FORCE_CPU=1 qmd --index "$QMD_INDEX" query "키워드" -c "$QMD_INDEX" --no-gpu --no-rerank
QMD_FORCE_CPU=1 qmd --index "$QMD_INDEX" embed --max-docs-per-batch 16 --max-batch-mb 16
```

- `search`가 통과하면 DB와 컬렉션은 정상이고, LLM/GPU 경로 문제일 가능성이 높다.
- `QMD_FORCE_CPU=1` 또는 `--no-gpu`는 CPU 강제 경로다. 느리지만 검색과 임베딩을 완료할 수 있다.
- CPU 경로에서는 리랭킹이 느릴 수 있으므로 우선 `--no-rerank`로 검증하고, 필요할 때만 리랭킹을 켠다.

---

## 인덱스 갱신 기준

| 상황 | 명령 |
|------|------|
| 새 파일 추가·이동·이름변경·대량수정 | `qmd --index "$QMD_INDEX" update` 후 `qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32` |
| 소규모 텍스트 수정 | `qmd --index "$QMD_INDEX" update` |
| 변경 없음 | 실행하지 않음 |
| embed 후 정합성 검증 | `qmd --index "$QMD_INDEX" doctor \| grep -i "vector sample"` — "differ"면 아래 force |
| 벡터 어긋남 (differ) | `qmd --index "$QMD_INDEX" embed --force` — 전 벡터 삭제 후 재임베딩 |

> **embed 성공 ≠ 전체 벡터 정합**: 일반 `embed`는 변경분만 임베딩하므로, 임베딩 파이프라인/모델이 바뀌면
> 기존 벡터가 현재 파이프라인에서 재현되지 않고 어긋난 채 남는다. `doctor`가 `embedding vector sample: N/M differ`를
> 보고하면 `embed --force`로 전체 재구축해야 `✓ reproduce stored vectors`로 돌아온다.

---

## 전역 컬렉션 설정과 위험 (plain 실행 시)

`--index` 없이 plain `qmd update/embed`를 실행하면 `~/.config/qmd/index.yml`에
등록된 전체 컬렉션이 처리된다.

**실제 사례**:
```yaml
# ~/.config/qmd/index.yml 예시 — 여러 컬렉션이 섞인 상태
collections:
  para:
    path: ~/{CLOUD_STORAGE}/Obsidian/PARA
    pattern: "**/*.md"
  my-project:
    path: ~/source/my-project
    pattern: "**/*.{php,md,sql,js}"
```

`my-project`에서 `qmd update`를 실행하면 `Updating 6 collection(s)...` 형태로
`para` 컬렉션까지 함께 처리될 수 있다.

**해결책**: `--index "$QMD_INDEX"` 패턴을 사용하면 이 문제가 완전히 해소된다.
각 프로젝트는 별도 인덱스(`my-project.yml`, `peach-wiki.yml` 등)를 가지므로
서로 영향을 주지 않는다.

**code 모드 인덱싱 범위**: mask 패턴에 `php/js/sql`이 포함되면 md뿐 아니라
소스 파일 전체가 인덱싱 대상이 된다. 의도된 동작이지만 첫 실행 시 확인 필요.

---

## CloudStorage/동기화 폴더 주의사항

`~/Library/CloudStorage/*`, Synology Drive, OneDrive, iCloud Drive 경로가
컬렉션에 등록된 상태에서 `qmd embed`를 실행하면:

- `fileproviderd`, `SynologyDriveFileProvider` 등 동기화 데몬이 재색인을 시작한다
- 대량 파일 스캔으로 CPU 상승 및 체감 성능 저하가 발생할 수 있다
- background 실행(`qmd embed &`)과 동기화 경로 임베딩이 겹치면 영향이 더 커진다

**권장 대응**:
1. `--index` 패턴으로 프로젝트별 인덱스를 분리하면 다른 인덱스의 CloudStorage 컬렉션은 건드리지 않는다
2. CloudStorage 컬렉션 자체는 별도 타이밍(동기화 안정 후)에만 임베딩
3. 이상 감지 시 확인 명령:
   ```bash
   ps -Ao pid,%cpu,comm,args | grep 'fileproviderd\|SynologyDriveFileProvider'
   ```

---

## 상태 확인

```bash
qmd --index "$QMD_INDEX" status    # 해당 인덱스 상태
qmd --index "$QMD_INDEX" collection list  # 해당 인덱스 컬렉션 목록
```
