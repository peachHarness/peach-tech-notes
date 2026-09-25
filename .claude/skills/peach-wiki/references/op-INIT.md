# INIT — 최초 설정

> `docs/wiki/WIKI-AGENTS.md`가 없을 때 실행. INIT preflight·qmd 등록·신규 생성 흐름의 SoT.
> 기본 경로는 항상 `docs/wiki/`이며, `.wiki/`와 `5-Wiki/`는 레거시 호환 마이그레이션 대상으로만 취급한다.
> qmd 명령·플랫폼 옵션 상세는 `qmd-가이드.md` / `qmd-platform-embedding.md`를 따른다.

---

## 1. Preflight (4단계)

### Step 1: 모드 감지

```bash
ls -d .obsidian 2>/dev/null && echo "OBSIDIAN=true" || echo "OBSIDIAN=false"
ls -d .git 2>/dev/null && echo "GIT=true" || echo "GIT=false"
```

| .obsidian | .git | 모드 | DRIFT |
|-----------|------|------|-------|
| true | false | 옵시디언 | 비활성 |
| false | true | code | 활성 |
| true | true | code | 활성 |
| false | false | 일반 | 비활성 |

### Step 2: qmd 상태 확인

```bash
QMD_INDEX=$(basename $(pwd))
qmd --index "$QMD_INDEX" status 2>/dev/null
```

- 성공 → Step 3으로
- 실패 (`command not found`) → 아래 설치 권고 후 Step 4로 (qmd 없이 진행)
  ```
  qmd가 미설치 상태입니다.
  wiki는 동작하지만 qmd 설치 시 토큰 절약 + 검색 정확도가 크게 향상됩니다.
  설치: npm install -g @tobilu/qmd
  ```

### Step 3: qmd 컬렉션 확인

```bash
qmd --index "$QMD_INDEX" collection list
```

- 현재 디렉토리가 등록된 컬렉션에 포함? → 스킵
- 미등록 → 등록 진행 (§2)

### Step 4: 기존 wiki 감지

```bash
ls -d docs/wiki 2>/dev/null && echo "docs/wiki/ 이미 존재 → INIT 불필요"
ls -d .wiki 2>/dev/null && echo ".wiki/ 발견 → 마이그레이션 필요"
ls -d 5-Wiki 2>/dev/null && echo "5-Wiki/ 발견 → 마이그레이션 필요"
```

- `docs/wiki/WIKI-AGENTS.md` 존재 → INIT 중단 ("이미 초기화됨" 안내)
- `.wiki/` 또는 `5-Wiki/` 발견 → 레거시 호환이 필요한 경우에만 §3 마이그레이션
- 아무것도 없음 → §4 신규 생성

---

## 2. qmd 컬렉션 등록

**`--index "$QMD_INDEX"` 패턴을 항상 사용한다.** 이 플래그는 DB(`~/.cache/qmd/$QMD_INDEX.sqlite`)와 설정(`~/.config/qmd/$QMD_INDEX.yml`)을 기본 인덱스와 완전히 분리해 다른 프로젝트·para 컬렉션을 건드리지 않는다. (격리 원리 상세: `qmd-가이드.md`)

### code 모드
```bash
qmd --index "$QMD_INDEX" collection add . --name "$QMD_INDEX" --mask "**/*.{ts,vue,md,sql,py,go,js}"
qmd --index "$QMD_INDEX" context add "qmd://$QMD_INDEX/" "프로젝트 한 줄 설명"
qmd --index "$QMD_INDEX" update
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32
```

### 옵시디언 모드
```bash
qmd --index "$QMD_INDEX" collection add . --name para --mask "**/*.md"
qmd --index "$QMD_INDEX" context add "qmd://para/" "옵시디언 노트 컬렉션"
qmd --index "$QMD_INDEX" update
qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32
```

대형 인덱스와 플랫폼별 GPU/CPU 옵션(M4/M5·Windows CUDA/Vulkan·CPU-only)은 `qmd-platform-embedding.md`를 따른다.

embed 직후 정합성을 검증한다. "differ"가 보이면 `embed --force`로 마무리한다 (embed 성공 ≠ 전체 벡터 정합):
```bash
qmd --index "$QMD_INDEX" doctor | grep -i "vector sample"
# "differ" 시: qmd --index "$QMD_INDEX" embed --force
```

### 등록 실패 시
- 에러 메시지 출력 후 **중단**
- "qmd 컬렉션 등록에 실패했습니다. 수동으로 등록해주세요:" + 명령어 안내
- wiki 생성은 진행하지 않음 (환경 문제이므로 해결 후 재시도 권장)

---

## 3. 레거시 마이그레이션

과거 POC 구조를 흡수해야 할 때만 쓴다. 기본 흐름은 신규 생성 또는 기존 `docs/wiki/` 재사용이다.

### .wiki/ → docs/wiki/
```bash
mkdir -p docs/wiki
cp -r .wiki/* docs/wiki/
mv .wiki .wiki.bak
# WIKI-AGENTS.md 내 .wiki/ → docs/wiki/ 경로 치환
```

### 5-Wiki/ → docs/wiki/
```bash
mkdir -p docs/wiki
cp -r 5-Wiki/* docs/wiki/
mv 5-Wiki 5-Wiki.bak
```

마이그레이션 실패 시: 복사 실패면 `.bak` 생성 전이므로 원본 보존 → 사용자에게 수동 이동 안내.

---

## 4. 신규 생성

```bash
mkdir -p docs/wiki/{concepts,entities,synthesis,sources,diagrams}
```

→ `WIKI-AGENTS-템플릿.md` 기반 WIKI-AGENTS.md 생성
→ wiki-index.md 초기화
→ wiki-log.md 초기화
→ entities/project-overview.md 생성 (프로젝트 구조 파악 후)

---

## 5. AGENTS.md에 wiki 규칙 추가

대상 프로젝트의 AGENTS.md에 아래 섹션을 추가한다. **AGENTS.md가 없으면 이 규칙만으로 새 파일을 만들지 않는다** — 이미 존재하는 AGENTS.md에만 추가한다.

> **`프로젝트명` 자리에 `$QMD_INDEX` 실제 값을 삽입한다.** (예: `my-project`, `peach-www`)
> 섹션 소유권·충돌 방지는 `wiki-경계규칙.md`의 "AGENTS.md 섹션 소유권" 표를 따른다.

```markdown
## wiki 참조 (필수)
코드 생성·분석 전 아래 순서를 따른다.
1. `qmd --index 프로젝트명 search "키워드" -c 프로젝트명` 으로 wiki + 소스 위치를 먼저 파악
2. search가 0건이거나 동의어·다국어·자연어 질문이면 `qmd --index 프로젝트명 query "질문" -c 프로젝트명 --no-rerank` 로 폴백
3. qmd 미설치 시 `docs/wiki/wiki-index.md` → 관련 페이지 직접 Read
4. `docs/wiki/`도 없으면 기존 방식대로 진행

## qmd 인덱스 (필수)
이 프로젝트의 qmd 인덱스명: `프로젝트명`
모든 qmd 명령에 `--index 프로젝트명`을 붙인다.
plain `qmd update/embed`는 다른 프로젝트 인덱스를 오염시킬 수 있으므로 금지.

qmd 사용 기준:
- 기본 검색은 `qmd search`를 사용한다 (BM25, 빠름). 키워드·식별자·동일 표현이면 거의 항상 충분하다.
- search가 0건이거나 동의어·다국어·자연어 질문이면 `qmd query --no-rerank`로 폴백한다 (벡터 검색).
- rerank가 꼭 필요하면 `-C 5`처럼 후보 수를 제한한다 (rerank는 느림).
- 한 번에 여러 개의 `qmd query`를 동시에 실행하지 않는다 (CPU 경합으로 더 느려짐).
- `embed`/`query` 중 `ggml_metal_library_init_from_source: error compiling source` 메시지는 무해하다 (사전컴파일 백엔드로 폴백, 검색 정상).

    qmd --index 프로젝트명 search "키워드" -c 프로젝트명
    qmd --index 프로젝트명 query "질문" -c 프로젝트명 --no-rerank
    qmd --index 프로젝트명 update
    qmd --index 프로젝트명 embed --max-docs-per-batch 32 --max-batch-mb 32

## wiki 복리 게이트 (필수)
아래 경로를 수정하는 작업은 완료 전에 wiki 갱신 여부를 판단한다.

- `.claude/skills/`, `hooks/`, `.claude/settings.json`, `.codex/`
- `AGENTS.md`, `CLAUDE.md`, `README.md`
- `docs/spec/`, `docs/계획/`, `docs/wiki/WIKI-AGENTS.md`
- 그 외 기능·구조에 의미 있는 코드 변경

필수 규칙:
- 반영할 내용이 있으면 `docs/wiki/` 관련 페이지와 `docs/wiki/wiki-log.md`를 갱신한다.
- 반영할 내용이 없으면 `docs/wiki/wiki-log.md`에 `SKIP` 사유를 남긴다.
- 완료 보고에 반드시 `wiki 갱신: 완료(페이지)` 또는 `wiki 갱신: 스킵(사유)`를 포함한다.
- qmd 갱신은 `qmd --index 프로젝트명 update`를 우선하고, 새 wiki 문서를 만든 경우에만 `embed`를 실행한다. 실패하면 경고로 기록하고 작업은 계속한다 (비차단).
```

> 조회 규칙만 설치하면 갱신 압력이 없어 복리 루프가 축적 없이 끊긴다 (실측: 조회 규칙만 있던 프로젝트에서 22일간 코드 30커밋 동안 wiki 갱신 0건).
> 게이트 집행 주체는 **스킬 완료 스텝 + AGENTS.md 규칙**이다. hook 기반 게이트(commit 전 wiki-log 누락 감지)는 **선택 설치**이며 기본 절차에 포함하지 않는다 (2026-07-07 결정: 스킬 베이스 우선, hook은 2단계 보류). hook에서 qmd·인제스트를 직접 실행하지 않는다 (느림·SQLite 경합으로 개발 흐름 차단 위험).
> **중복 방지**: 대상 AGENTS.md에 이미 wiki 복리 루프/갱신 원칙 섹션이 있으면 게이트를 별도 섹션으로 만들지 않는다. 기존 섹션에 게이트 고유 내용(대상 경로 + SKIP 기록 + `wiki 갱신: 완료/스킵` 보고 의무)만 "완료 게이트" 소절로 병합하고, qmd update/embed 규칙이 이미 있으면 반복하지 않는다.

---

## 6. 첫 ingest 영역 확인 + 완료

사람에게 첫 ingest 영역을 확인한다. 완료 확인:

```bash
ls docs/wiki/WIKI-AGENTS.md && echo "INIT 성공"
ls docs/wiki/wiki-index.md && echo "wiki-index 존재"
ls docs/wiki/wiki-log.md && echo "wiki-log 존재"
```

wiki-log.md에 기록:
```
## [YYYY-MM-DD] init | {프로젝트명}
- 모드: {code|para|일반}
- qmd 컬렉션: {등록됨|미등록}
- 마이그레이션: {.wiki/|5-Wiki/|없음}
```
