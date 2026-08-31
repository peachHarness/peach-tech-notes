# Context7 설치·사용 가이드

> 최신 라이브러리 공식 문서를 실시간으로 컨텍스트에 주입하는 MCP 서버.
> 저장소: https://github.com/upstash/context7 · 대시보드: https://context7.com/dashboard

## 1. 무엇인가

Upstash가 만든 문서 그라운딩 서비스. LLM의 학습 컷오프 때문에 생기는 **없는 API 환각**과 **구버전 문법 답변**을 막는다. 라이브러리 이름과 질문을 주면 해당 프로젝트의 현재 문서·코드 예제를 골라 돌려준다.

기존 웹 검색과 다른 점: 블로그·스택오버플로가 아니라 라이브러리 공식 문서 원본을 버전 단위로 색인해 둔다. 그래서 "Next.js 14 미들웨어"처럼 버전이 섞인 질문에서 정확도가 높다.

## 2. 두 가지 동작 모드

| 모드 | 방식 | 특징 |
|---|---|---|
| MCP 서버 | `https://mcp.context7.com/mcp` 원격 HTTP(또는 로컬 stdio) | 에이전트가 툴로 직접 호출. 권장 |
| CLI + Skill | `ctx7` 명령 + 스킬 파일 | MCP 없이 셸 호출만으로 동작 |

MCP 모드가 기본. CLI 모드는 MCP를 못 쓰는 환경용 대안이다.

## 3. 설치

### 3.1 공통 (권장) — `ctx7 setup`

Node 18+ 필요. 클라이언트별 플래그만 바꿔 두 번 실행한다.

```bash
npx -y ctx7@latest setup --claude --mcp --oauth -y   # Claude Code
npx -y ctx7@latest setup --codex  --mcp --oauth -y   # Codex
```

`setup` 주요 플래그:

| 플래그 | 의미 |
|---|---|
| `--claude` / `--codex` / `--cursor` / `--gemini` / `--opencode` / `--antigravity` | 대상 에이전트 |
| `--mcp` / `--cli` | MCP 서버 모드 / CLI+Skill 모드 |
| `--oauth` | API 키 없이 클라이언트가 OAuth 인증을 처리 (아래 4장) |
| `--api-key <key>` | 발급받은 API 키를 직접 박아 넣기 |
| `--stdio` | 원격 HTTP 대신 로컬 stdio 프로세스로 등록 |
| `-p, --project` | 전역이 아니라 현재 프로젝트에만 설정 |
| `-y, --yes` | 확인 프롬프트 생략 (비대화형) |

`--oauth` 없이 그냥 `npx ctx7 setup --claude`를 실행하면 브라우저 OAuth를 띄워 API 키를 발급하고 설정까지 자동으로 써 준다. 대화형이므로 터미널에서 직접 실행해야 한다.

설치 결과로 건드리는 파일:

- Claude Code: `~/.claude.json`(MCP 등록), `~/.claude/rules/context7.md`(사용 규칙), `~/.claude/skills/context7-mcp/SKILL.md`
- Codex: `~/.codex/config.toml`(MCP 등록), `~/.codex/AGENTS.md`(`<!-- context7 -->` 블록 추가), `~/.agents/skills/context7-mcp/SKILL.md`

제거:

```bash
npx -y ctx7@latest remove --claude --mcp
npx -y ctx7@latest remove --codex --all
```

### 3.2 수동 설정

**Claude Code** — API 키 방식:

```bash
claude mcp add --transport http context7 https://mcp.context7.com/mcp \
  --header "Authorization: Bearer YOUR_API_KEY"
```

**Codex** (`~/.codex/config.toml`) — 원격:

```toml
[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
http_headers = { "Authorization" = "Bearer YOUR_API_KEY" }
```

**Codex** — 로컬 stdio:

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp", "--api-key", "YOUR_API_KEY"]
startup_timeout_ms = 20_000
```

`~/.codex/config.toml`은 Codex CLI·Desktop·IDE 확장이 공유하므로 한 번만 설정하면 된다.

OAuth 방식으로 등록되면 URL이 `/mcp` 대신 `/mcp/oauth`가 되고 헤더는 비어 있다:

```toml
[mcp_servers.context7]
type = "http"
url = "https://mcp.context7.com/mcp/oauth"
```

## 4. 인증 (OAuth 방식일 때)

등록만으로는 `Not logged in` 상태다. 클라이언트별로 한 번 로그인해야 툴이 뜬다.

- **Claude Code**: 재시작 후 `/mcp` → `context7` 선택 → Authenticate → 브라우저 승인
- **Codex**: `codex mcp login context7` → 브라우저 승인

확인:

```bash
codex mcp list          # context7 Auth 열이 Not logged in → 로그인됨으로 바뀐다
npx -y ctx7@latest whoami
```

## 5. 사용법

두 에이전트 모두 프롬프트에 트리거만 넣으면 된다.

```
Next.js 14 미들웨어 설정 방법 알려줘. use context7
```

라이브러리 ID를 직접 주면 해석 단계를 건너뛰어 더 빠르고 정확하다:

```
Supabase 인증 구현해줘. use library /supabase/supabase for API and docs.
```

버전은 자동 매칭된다. `Next.js 14`처럼 질문에 버전을 쓰면 그 버전 문서를 고른다.

설치 시 함께 깔리는 규칙 파일(`rules/context7.md`, `AGENTS.md` 블록)이 "라이브러리 질문이면 Context7을 먼저 써라"를 지시하므로, `use context7`을 매번 붙이지 않아도 대체로 자동 호출된다.

### MCP 툴

| 툴 | 역할 | 인자 |
|---|---|---|
| `resolve-library-id` | 라이브러리 이름 → `/org/project` ID | `libraryName`, `query` |
| `query-docs` | ID + 질의 → 문서 조각 | `libraryId`, `query` |

호출 순서는 `resolve-library-id` → `query-docs`. ID를 이미 아는 경우 1단계 생략.

ID 선택 기준(설치된 규칙 파일 기준): 이름 정확 일치 > 설명 관련성 > 코드 스니펫 수 > 출처 신뢰도(High/Medium) > 벤치마크 점수.

질의 팁:
- 단어 하나가 아니라 **문장**으로 묻는다 (`"useEffect"` ✗ → `"useEffect cleanup 패턴"` ○)
- 한 호출에 한 개념만. 라우팅·인증·캐싱을 한꺼번에 물으면 랭킹이 희석돼 각 주제가 얕게 나온다 → 개념별로 나눠 호출
- 결과가 엉뚱하면 이름 표기를 바꿔 재시도 (`nextjs` → `next.js`)

### CLI 직접 호출

```bash
npx -y ctx7@latest library react "how to use hooks"
npx -y ctx7@latest docs /facebook/react "useEffect examples"
```

## 6. 쓸 곳 / 안 쓸 곳

**쓴다**: API 문법, 설정 방법, 버전 마이그레이션, 라이브러리 고유 에러 디버깅, CLI 도구 사용법. 잘 안다고 생각되는 라이브러리도 포함 — 학습 데이터가 최근 변경을 반영하지 못한다.

**안 쓴다**: 리팩터링, 스크립트 신규 작성, 비즈니스 로직 디버깅, 코드 리뷰, 일반 프로그래밍 개념.

## 7. 참고

- README: https://github.com/upstash/context7
- Codex 공식 설정 문서: https://context7.com/docs/clients/codex
- API 키 발급: https://context7.com/dashboard
