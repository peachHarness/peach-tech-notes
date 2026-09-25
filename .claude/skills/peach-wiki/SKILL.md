---
name: peach-wiki
description: docs/wiki/ 지식베이스를 구축·유지한다.
---

# peach-wiki — LLM Wiki 지식 관리

Andrej Karpathy의 LLM Wiki 패턴을 적용한 단일 스킬. 코드 프로젝트와 옵시디언 노트 모두 동일한 구조(`docs/wiki/`)로 관리한다.
RAG가 매 질문마다 지식을 재발견하는 것과 달리, wiki는 지식이 **누적·복리**된다. 패턴 배경은 필요 시 `references/Karpathy-패턴.md`.

> **이 파일은 라우터다.** 아래에서 오퍼레이션을 고른 뒤, 해당 `references/*.md`만 읽어 실행한다.
> 오퍼레이션 상세를 SKILL.md 본문에서 찾지 말고, 필요한 reference 한 개만 로드해 토큰을 아낀다.

---

## 1. 모드 자동 감지

스킬 호출 시 현재 디렉토리를 감지해 모드를 결정한다.

```bash
ls -d .obsidian 2>/dev/null && echo "OBSIDIAN=true" || echo "OBSIDIAN=false"
ls -d .git 2>/dev/null && echo "GIT=true" || echo "GIT=false"
```

| .obsidian | .git | 모드 | DRIFT / INGEST-INCREMENTAL |
|-----------|------|------|------|
| true | false | 옵시디언 | 비활성 |
| false | true | code | 활성 |
| true | true | code (우선) | 활성 |
| false | false | 일반 | 비활성 (wiki는 정상 동작) |

qmd 인덱스명은 세션 시작 시 한 번 선언한다: `QMD_INDEX=$(basename $(pwd))`

---

## 2. wiki 저장 위치 (모든 모드 동일)

```
[프로젝트 루트 또는 옵시디언 보관소]/
└── docs/wiki/
    ├── WIKI-AGENTS.md       ← 운영 규칙 (세션 시작 시 먼저 읽기)
    ├── wiki-index.md        ← 전체 위키 카탈로그
    ├── wiki-log.md          ← 작업 타임라인 (append-only)
    ├── concepts/            ← 아키텍처 패턴·도메인 개념
    ├── entities/            ← 모듈·서비스·컴포넌트·인물·프로젝트
    ├── synthesis/           ← 데이터 흐름·의사결정·트레이드오프
    ├── sources/             ← 원본 문서 요약 (옵시디언 모드)
    ├── diagrams/            ← Mermaid 다이어그램
    └── events/              ← 운영 계측 로그 (YYYY-MM.jsonl)
```

---

## 3. 오퍼레이션 라우팅

사용자 요청/트리거를 보고 **아래 표에서 하나를 골라 해당 reference만 읽는다.**

| 오퍼레이션 | 트리거 | 읽을 파일 |
|-----------|--------|-----------|
| **INIT** | `docs/wiki/WIKI-AGENTS.md`가 없음 (최초 설정) | `references/op-INIT.md` |
| **INGEST** | "ingest", "wiki에 추가", "문서화해줘", 파일/모듈 언급 (전량 스캔 + 사람 확인) | `references/op-INGEST.md` |
| **INGEST-INCREMENTAL** | 개발 스킬 완료 스텝, `.tmp/wiki-events/` 큐, 복리 게이트 대상 경로 변경 (자동, code 모드 전용) | `references/op-INCREMENTAL.md` |
| **QUERY** | "어떻게 동작해?", "흐름 설명해줘", "~관계", "~정리" | `references/op-QUERY.md` |
| **DRIFT** | "wiki 업데이트해줘", "변경사항 반영" (code 모드 전용) | `references/op-DRIFT-LINT.md` |
| **LINT** | "wiki 점검", "lint", "정합성 확인" | `references/op-DRIFT-LINT.md` |

qmd 명령·검색 escalation·플랫폼별 embed 옵션이 필요하면 그때만 추가로 읽는다:
- `references/qmd-가이드.md` — CLI 명령, named index 격리, search/query escalation, Metal 메시지 판정
- `references/qmd-platform-embedding.md` — M4/M5·Windows CUDA/Vulkan·CPU·WSL2 embed 기준
- `references/wiki-경계규칙.md` — wiki entities vs `docs/기능별설명` 판단, AGENTS.md 섹션 소유권
- `references/WIKI-AGENTS-템플릿.md` — INIT 시 WIKI-AGENTS.md 생성 템플릿

---

## 4. 핵심 원칙

- **Raw Source는 절대 수정 금지** — 읽기만 (코드, 옵시디언 노트 모두)
- **`docs/wiki/` 하위에만 쓰기** — LLM 전용 공간
- **모든 qmd 명령에 `--index "$QMD_INDEX"` 필수** — plain `qmd update/embed`는 다른 인덱스를 오염시킨다
- **search 우선, query는 폴백** — 위치 파악은 `qmd search`(BM25, M5 실측 0.1~0.4초)로 먼저. search가 0건이거나 동의어·다국어·자연어 "어떻게/왜" 질문이면 `qmd query --no-rerank`로 폴백. rerank는 비싸므로 꼭 필요할 때만 `-C 5`. (상세 근거: `qmd-가이드.md`)
- **모드별 검색 비중** — code(.git)는 식별자 정확 매칭이 중요해 `search` 비중을 높게, 옵시디언(.obsidian)은 산문 자연어·동의어가 많아 `query` 비중을 높게 둔다.
- **비차단 qmd 갱신** — `update` 우선, 새 wiki 문서 생성 시에만 `embed`. 실패는 경고만 남기고 작업 계속.
- **복리 효과** — Ingest할수록 교차참조가 깊어지고 Query 품질이 오른다. 단, 자동 축적(INGEST-INCREMENTAL)에는 주기 LINT를 반드시 짝으로 운영한다.
- **언어**: 한국어 (코드·기술 용어는 영어 유지). 링크: `[[파일명]]`(para) / 파일 경로(code).
