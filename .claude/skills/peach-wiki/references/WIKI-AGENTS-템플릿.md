# WIKI-AGENTS.md 템플릿

> INIT 시 이 템플릿을 기반으로 `docs/wiki/WIKI-AGENTS.md`를 생성한다.
> 프로젝트명, 컬렉션명, 모드를 치환하여 적용.
> 템플릿 버전: 0.2.0

---

```markdown
# WIKI-AGENTS — {프로젝트명} 위키 운영 규칙

> Karpathy LLM Wiki 패턴 기반. 세션 시작 시 이 파일을 먼저 읽는다.
> 템플릿 버전: 0.2.0

## 역할 분리

| 역할 | 책임 |
|------|------|
| 사람 | 소스 추가, 방향 설정, 질문, INGEST 요청 |
| LLM | `docs/wiki/` 파일 생성·업데이트, Raw Source는 읽기만 |

## 3계층 구조

| 계층 | 위치 |
|------|------|
| Raw Source (읽기 전용) | {raw_source_paths} |
| Wiki Layer (LLM 소유) | docs/wiki/ |
| Schema (협력 진화) | docs/wiki/WIKI-AGENTS.md |

## qmd 컬렉션

- 컬렉션명: `{컬렉션명}`
- URI 접두사: `qmd://{컬렉션명}/`
- 기본 검색: `qmd --index {컬렉션명} search "키워드" -c {컬렉션명}` (BM25, 빠름)
- 의미 검색: `qmd --index {컬렉션명} query "질문" -c {컬렉션명} --no-rerank` (필요할 때만)
- fallback: `qmd --index {컬렉션명} search ...` → `qmd --index {컬렉션명} query ... --no-rerank` → `rg "키워드"`
- 한 번에 여러 `qmd query`를 동시에 실행하지 않는다 (CPU 경합)

## 오퍼레이션

| 오퍼레이션 | 트리거 | 동작 |
|-----------|-------|------|
| INGEST | "wiki에 추가", 모듈/노트 언급 | 소스 → 위키 생성/업데이트 |
| INGEST-INCREMENTAL | 개발 스킬 완료 스텝, `.tmp/wiki-events/` 큐, 게이트 대상 경로 변경 완료 | 변경분만 자동 갱신 (사람 확인 없음, 주기 LINT 필수 짝) |
| QUERY | "어떻게 동작해?", "설명해줘" | 위키 기반 답변 |
| DRIFT | "wiki 업데이트" | git 변경 → 위키 갱신 ({drift_status}) |
| LINT | "wiki 점검", "lint" | 모순·고아·드리프트 탐지 |

## wiki 복리 게이트

아래 경로를 수정하는 작업은 완료 전에 wiki 갱신 여부를 판단한다.

- `.claude/skills/`, `hooks/`, `.claude/settings.json`, `.codex/`
- `AGENTS.md`, `CLAUDE.md`, `README.md`
- `docs/spec/`, `docs/계획/`, `docs/wiki/WIKI-AGENTS.md`
- 그 외 기능·구조에 의미 있는 코드 변경

필수 규칙:
- 반영할 내용이 있으면 관련 wiki 페이지와 `docs/wiki/wiki-log.md`를 갱신한다.
- 반영할 내용이 없으면 `docs/wiki/wiki-log.md`에 `SKIP` 사유를 남긴다.
- 완료 보고에 반드시 `wiki 갱신: 완료(페이지)` 또는 `wiki 갱신: 스킵(사유)`를 포함한다.

## 핵심 원칙

- Raw Source 절대 수정 금지
- `docs/wiki/` 하위에만 쓰기
- qmd search 우선, 의미 검색이 꼭 필요할 때만 qmd query --no-rerank 사용
- 모든 qmd 명령에 `--index {컬렉션명}` 필수
- qmd 갱신은 `update` 우선, 새 wiki 문서 생성 시에만 `embed`. 실패는 경고만 남기고 진행 (비차단 — 색인 실패가 개발 흐름을 막지 않는다)
- 언어: 한국어 (기술 용어는 영어 유지)
```

---

## 치환 변수

| 변수 | code 모드 | 옵시디언 모드 |
|------|----------|----------|
| `{프로젝트명}` | 프로젝트 디렉토리명 | 옵시디언 |
| `{raw_source_paths}` | `api/`, `front/`, `docs/` 등 | `0-Inbox/`, `1-Project/`, `2-Area/`, `3-Resource/`, `4-Archive/` |
| `{컬렉션명}` | qmd 컬렉션명 | `para` |
| `{drift_status}` | `.git 있음 — 활성` | `.git 없음 — 비활성` |
