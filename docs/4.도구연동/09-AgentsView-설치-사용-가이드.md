# AgentsView 설치·사용 가이드

> Claude Code, Codex 등 여러 AI 코딩 에이전트의 로컬 세션을 검색하고 사용량·비용을 확인하는 방법을 정리한다.

---

## 0. 먼저 결론

개인 PC에서 사용하는 기본 구성은 다음이 가장 단순하다.

1. 네이티브 바이너리를 설치한다.
2. 기본 저장소인 로컬 SQLite를 사용한다.
3. 최초에는 `agentsview serve`로 실행 결과를 확인한다.
4. 평소에는 `agentsview daemon start`로 백그라운드 실행한다.
5. 브라우저에서 `http://127.0.0.1:8080`을 연다.

Docker와 PostgreSQL은 필수가 아니다.

- **Docker**: 서버·NAS·격리된 컨테이너 환경에서 운영할 때 선택
- **PostgreSQL**: 여러 PC의 세션을 한곳에 모아 공유할 때 선택
- **로컬 SQLite**: 한 대의 PC에서 개인적으로 사용할 때 권장

---

## 1. AgentsView가 하는 일

AgentsView는 AI 코딩 에이전트가 로컬에 남긴 세션 파일을 찾아 하나의 검색 가능한 보관소로 만든다.

주요 기능:

- Claude Code, Codex, Cursor, Gemini CLI, OpenCode 등 여러 도구의 세션 탐색
- 프로젝트·에이전트·날짜별 세션 조회
- 프롬프트와 응답의 전체 텍스트 검색
- 토큰 사용량과 추정 비용 확인
- 활동량, 모델 비중, 프로젝트별 통계 확인
- 웹 UI와 CLI 동시 제공

기본 동작 구조는 다음과 같다.

```text
로컬 AI 에이전트 세션 파일
  ├─ ~/.claude/projects
  ├─ ~/.codex/sessions
  └─ 그 밖의 지원 도구 저장소
              ↓ 읽기·동기화
       ~/.agentsview/sessions.db
              ↓
      AgentsView 로컬 서버
              ↓
      http://127.0.0.1:8080
```

AgentsView는 원본 세션 파일을 대체하지 않는다. 원본을 읽어 로컬 SQLite에 검색용 데이터를 구축한다.

---

## 2. 설치 방법

### 2.1 macOS·Linux 설치 스크립트

공식 설치 명령:

```bash
curl -fsSL https://agentsview.io/install.sh | bash
```

설치 스크립트는 운영체제와 CPU 아키텍처를 감지하고, GitHub Releases에서 바이너리를 내려받아 SHA-256 체크섬을 확인한 뒤 설치한다.

설치 후 확인:

```bash
command -v agentsview
agentsview --version
```

일반적으로 쓰기 가능한 `/usr/local/bin`을 우선 사용하고, 그렇지 않으면 `~/.local/bin/agentsview`에 설치한다. `agentsview`를 찾지 못하면 PATH를 확인한다.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

지속 적용하려면 사용하는 셸의 설정 파일에 위 내용을 추가한다. 예를 들어 zsh는 `~/.zshrc`를 사용한다.

> `curl | bash`는 내려받은 스크립트를 즉시 실행한다. 보안 정책상 직접 실행이 어려우면 스크립트 내용을 먼저 검토하거나 GitHub Releases·Homebrew 설치 방식을 사용한다.

### 2.2 macOS 데스크톱 앱

웹 UI를 직접 실행·종료하기보다 일반 앱처럼 사용하려면 데스크톱 앱을 선택할 수 있다.

```bash
brew install --cask agentsview
```

또는 GitHub Releases에서 macOS 설치 파일을 내려받는다. 데스크톱 앱과 CLI는 같은 로컬 데이터 디렉터리와 daemon을 공유한다.

### 2.3 Windows

PowerShell에서 실행한다.

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://agentsview.io/install.ps1 | iex"
```

설치 확인:

```powershell
agentsview --version
```

### 2.4 설치 방식 선택

| 상황 | 권장 방식 |
|---|---|
| 개인 Mac·Linux PC에서 CLI 중심 사용 | 설치 스크립트 |
| macOS에서 일반 앱처럼 사용 | Homebrew Cask 또는 데스크톱 앱 |
| Windows 로컬 사용 | PowerShell 설치 스크립트 또는 데스크톱 앱 |
| 서버·NAS·컨테이너 운영 | Docker Compose |

---

## 3. 최초 실행

### 3.1 포그라운드 실행

처음에는 터미널에서 서버를 직접 실행해 동기화 과정과 오류를 확인한다.

```bash
agentsview serve
```

최초 실행 시 다음 작업이 진행된다.

1. `~/.agentsview/` 데이터 디렉터리를 만든다.
2. 지원되는 AI 에이전트의 세션을 탐색한다.
3. `~/.agentsview/sessions.db` SQLite 데이터베이스를 만든다.
4. 세션 디렉터리 변경 감시를 시작한다.
5. `http://127.0.0.1:8080`에서 웹 UI를 연다.

브라우저가 자동으로 열리지 않으면 직접 접속한다.

```text
http://127.0.0.1:8080
```

macOS에서는 터미널에서 열 수도 있다.

```bash
open http://127.0.0.1:8080
```

포그라운드 서버는 `Ctrl+C`로 종료한다.

### 3.2 실행 검증

다른 터미널에서 상태와 HTTP 응답을 확인한다.

```bash
agentsview daemon status
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080
```

정상이라면 실행 주소가 표시되고 HTTP 응답을 받을 수 있다.

---

## 4. 평소 실행 방법

최초 동기화가 정상적으로 끝났다면 daemon을 사용한다. daemon은 터미널을 닫아도 동작하는 백그라운드 서버다.

```bash
# 시작
agentsview daemon start

# 상태 확인
agentsview daemon status

# 설정을 다시 읽어 재시작
agentsview daemon restart

# 종료
agentsview daemon stop
```

기본 daemon은 사용 요청이나 daemon 소유 작업이 없으면 일정 시간 후 자동 종료될 수 있다. 항상 실행해야 하는 장비에서는 `~/.agentsview/config.toml`에 다음 값을 설정한다.

```toml
daemon_idle_timeout = "0s"
```

특정 `serve` 옵션이 필요한 일회성 백그라운드 실행은 다음 명령을 사용한다.

```bash
agentsview serve --background --no-browser
```

일반적인 백그라운드 운영은 `agentsview daemon start`가 기준이다.

---

## 5. 데이터베이스와 저장 위치

### 5.1 기본값은 SQLite

AgentsView는 별도 설정이 없으면 PostgreSQL이 아니라 로컬 SQLite를 사용한다.

기본 데이터 위치:

```text
~/.agentsview/
├── sessions.db       # 기본 SQLite 데이터베이스
├── sessions.db-wal   # SQLite Write-Ahead Log
├── sessions.db-shm   # SQLite 공유 메모리 파일
├── config.toml       # 지속 설정
├── serve.log         # 백그라운드 서버 로그
└── uploads/          # 가져온 파일 저장소
```

데이터 디렉터리를 바꾸려면 환경변수를 사용한다.

```bash
export AGENTSVIEW_DATA_DIR=/path/to/agentsview-data
```

SQLite가 적합한 경우:

- 한 명이 한 대의 PC에서 사용
- 세션 원본이 같은 PC에 있음
- 별도 DB 서버를 운영하고 싶지 않음
- 로컬 검색과 사용량 분석이 목적

### 5.2 PostgreSQL은 선택 기능

PostgreSQL은 여러 장비나 사용자의 AgentsView 데이터를 중앙 DB로 모을 때 사용한다.

```text
각 개발 PC의 로컬 세션
        ↓ agentsview pg push
공유 PostgreSQL
        ↓ agentsview pg serve
공용 읽기 전용 웹 UI
```

연결 URL을 설정한 뒤 로컬 SQLite 데이터를 전송한다.

```bash
export AGENTSVIEW_PG_URL='postgres://<사용자>:<비밀번호>@db.example.com:5432/agentsview?sslmode=require'
agentsview pg push
```

PostgreSQL에서 읽기 전용 웹 UI를 제공하려면 다음 명령을 사용한다.

```bash
agentsview pg serve
```

연결 상태 확인:

```bash
agentsview pg status
```

PostgreSQL을 사용하더라도 각 개발 PC의 기본 수집 저장소는 SQLite다. `pg push`는 로컬 보관소의 데이터를 공유 PostgreSQL로 보내는 역할이다.

---

## 6. 세션 경로 설정

### 6.1 기본 탐색 경로

대표적인 기본 경로:

| 도구 | 기본 세션 경로 |
|---|---|
| Claude Code | `~/.claude/projects/` |
| Codex | `~/.codex/sessions/` |
| Cursor | `~/.cursor/projects/` |
| Gemini CLI | `~/.gemini/` |
| OpenCode | `~/.local/share/opencode/` |

기본 위치에 세션이 있으면 별도 설정 없이 탐색한다.

### 6.2 환경변수로 단일 경로 변경

세션 경로가 기본값과 다르면 환경변수로 지정할 수 있다.

```bash
export CLAUDE_PROJECTS_DIR=/path/to/claude/projects
export CODEX_SESSIONS_DIR=/path/to/codex/sessions
```

이 환경변수를 daemon에 적용하려면 같은 환경에서 daemon을 시작하거나 재시작한다.

```bash
agentsview daemon restart
```

### 6.3 같은 도구의 여러 경로 등록

기본 Codex와 별도 런타임의 Codex 세션을 함께 읽는 경우처럼 경로가 여러 개라면 `~/.agentsview/config.toml` 배열을 사용한다.

```toml
claude_project_dirs = [
  "~/.claude/projects",
  "/path/to/another-claude/projects",
]

codex_sessions_dirs = [
  "~/.codex/sessions",
  "/path/to/custom-codex/sessions",
]
```

변경 후 재시작한다.

```bash
agentsview daemon restart
```

세션이 누락될 때는 가장 먼저 실제 세션 저장 경로와 위 설정을 대조한다.

---

## 7. 주요 사용 명령

### 7.1 세션과 프로젝트 조회

```bash
# 세션 목록
agentsview session list

# 프로젝트별 세션 수
agentsview projects

# 특정 세션의 사용량과 추정 비용
agentsview session usage <세션-ID>
```

### 7.2 토큰 사용량과 비용

```bash
# 최근 30일 일별 요약
agentsview usage daily

# 모델별 상세
agentsview usage daily --breakdown

# 특정 에이전트와 날짜 범위
agentsview usage daily --agent claude --since 2026-07-01

# 상태 표시줄용 한 줄 요약
agentsview usage statusline
```

### 7.3 통계와 상태 확인

```bash
# 활동·세션 통계
agentsview stats

# 세션 상태와 이상 신호
agentsview health

# 원본 세션 다시 동기화
agentsview sync
```

### 7.4 업데이트

```bash
agentsview update
agentsview --version
```

업데이트 후 daemon이 실행 중이면 재시작해 새 바이너리를 반영한다.

```bash
agentsview daemon restart
```

---

## 8. Docker로 실행하기

개인 PC에서 로컬 세션을 보는 목적이라면 네이티브 바이너리가 단순하다. Docker는 다음 조건에서 선택한다.

- 서버나 NAS에서 지속 실행
- 프로세스와 의존성을 컨테이너로 격리
- Docker Compose로 재시작 정책과 볼륨을 관리
- PostgreSQL 기반 공용 UI 운영

### 8.1 기본 Docker 실행

Claude Code와 Codex 세션을 함께 마운트하는 예시:

```bash
docker run --rm \
  -p 127.0.0.1:8080:8080 \
  -v agentsview-data:/data \
  -v "$HOME/.claude/projects:/agents/claude:ro" \
  -v "$HOME/.codex/sessions:/agents/codex:ro" \
  -e CLAUDE_PROJECTS_DIR=/agents/claude \
  -e CODEX_SESSIONS_DIR=/agents/codex \
  ghcr.io/kenn-io/agentsview:latest
```

주의사항:

- 컨테이너는 명시적으로 마운트한 세션 디렉터리만 볼 수 있다.
- 원본 세션 경로는 `:ro`로 읽기 전용 마운트한다.
- `/data`는 호스트 바인드 마운트보다 이름 있는 Docker 볼륨을 권장한다.
- 포트는 기본적으로 `127.0.0.1`에만 공개한다.

### 8.2 Docker Compose

공식 저장소의 `docker-compose.prod.yaml`을 사용한다.

```bash
docker compose -f docker-compose.prod.yaml up -d
docker compose -f docker-compose.prod.yaml ps
docker compose -f docker-compose.prod.yaml logs -f
docker compose -f docker-compose.prod.yaml down
```

Compose 예제도 기본 세션 경로만 마운트한다. 커스텀 세션 저장소가 있으면 `volumes`와 대응 환경변수를 함께 추가한다.

### 8.3 Docker에서 PostgreSQL 사용

```bash
docker run --rm \
  -p 127.0.0.1:8080:8080 \
  -e PG_SERVE=1 \
  -e AGENTSVIEW_PG_URL='postgres://<사용자>:<비밀번호>@db.example.com:5432/agentsview?sslmode=require' \
  ghcr.io/kenn-io/agentsview:latest
```

`PG_SERVE=1`이 없으면 Docker 이미지도 로컬 SQLite 기반 `agentsview serve`로 실행된다.

---

## 9. 원격 접속과 보안

AgentsView는 기본적으로 `127.0.0.1`에만 바인딩한다. 같은 PC의 브라우저만 접근할 수 있는 안전한 기본값이다.

SSH 포트 포워딩이나 원격 개발 환경에서 접속할 때는 브라우저에서 실제로 여는 주소를 `--public-url`에 지정한다.

```bash
agentsview serve \
  --public-url http://127.0.0.1:18080 \
  --no-browser
```

로컬호스트 밖으로 직접 공개할 때는 반드시 인증을 활성화한다.

```bash
agentsview serve \
  --host 0.0.0.0 \
  --require-auth \
  --public-url https://agentsview.example.com
```

운영 원칙:

- 인터넷에 8080 포트를 그대로 공개하지 않는다.
- 비로컬 바인딩에는 `--require-auth`를 사용한다.
- TLS가 필요한 경우 인증된 리버스 프록시나 공식 관리 프록시 구성을 사용한다.
- 세션 DB에는 프롬프트와 응답이 포함될 수 있으므로 일반 로그보다 민감하게 취급한다.

---

## 10. 개인정보와 외부 통신

기본 세션 데이터는 로컬 SQLite에 저장된다. 기본 상태에서 세션 내용, 프로젝트명, 프롬프트, 파일 경로를 외부로 전송하지 않는다.

다만 다음 자동 통신은 발생할 수 있다.

- 새 버전 확인을 위한 GitHub API 요청
- 서버 시작 시와 24시간마다 익명 daemon 활성 신호

익명 활성 신호에는 앱 버전, 커밋, 운영체제, CPU 아키텍처, 무작위 설치 ID가 포함된다. 세션 내용과 프로젝트 경로는 포함되지 않는다.

텔레메트리를 끄려면 daemon 시작 환경에 다음 변수를 설정한다.

```bash
export AGENTSVIEW_TELEMETRY_ENABLED=0
```

업데이트 확인을 끄려면 `~/.agentsview/config.toml`에 설정한다.

```toml
disable_update_check = true
```

세션 내용을 외부로 보내는 선택 기능:

- `pg push`: 사용자가 지정한 PostgreSQL로 전송
- 원격 Quack·DuckDB 구성: 사용자가 외부 엔드포인트를 설정한 경우
- Session Insights: 사용자가 선택한 AI 제공자에게 요약 대상 내용 전송
- GitHub Gist 게시: 선택한 세션을 GitHub에 업로드

사용하지 않은 선택 기능이 자동으로 세션 원문을 외부에 보내지는 않는다.

---

## 11. 문제 해결

### `agentsview: command not found`

설치 위치와 PATH를 확인한다.

```bash
ls -l "$HOME/.local/bin/agentsview"
echo "$PATH"
export PATH="$HOME/.local/bin:$PATH"
```

### 브라우저에서 연결할 수 없음

daemon과 포트를 확인한다.

```bash
agentsview daemon status
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

daemon이 없으면 다시 시작한다.

```bash
agentsview daemon start
```

### 최초 실행이 오래 걸림

세션이 많으면 최초 SQLite 구축에 시간이 걸릴 수 있다. 상태와 로그를 확인한다.

```bash
agentsview daemon status
tail -f "$HOME/.agentsview/serve.log"
```

### 일부 에이전트 세션이 보이지 않음

1. 실제 세션 디렉터리가 존재하는지 확인한다.
2. 기본 경로와 다른지 확인한다.
3. Docker라면 해당 경로가 컨테이너에 마운트됐는지 확인한다.
4. `config.toml`의 다중 경로 설정을 확인한다.
5. 설정을 바꾼 뒤 daemon을 재시작한다.

### 8080 포트가 이미 사용 중임

포그라운드 서버를 다른 포트로 실행한다.

```bash
agentsview serve --port 18080
```

접속 주소:

```text
http://127.0.0.1:18080
```

### 원격 접속에서 `403 Forbidden`

브라우저에서 여는 정확한 origin을 `--public-url` 또는 `--public-origin`에 등록한다. 외부 공개라면 인증도 함께 활성화한다.

---

## 12. 제거 방법

먼저 daemon을 종료한다.

```bash
agentsview daemon stop
```

설치된 바이너리 위치를 확인한 뒤 해당 파일만 제거한다.

```bash
command -v agentsview
```

예를 들어 `~/.local/bin/agentsview`에 설치됐다면:

```bash
rm "$HOME/.local/bin/agentsview"
```

`~/.agentsview/`에는 세션 인덱스와 설정이 남는다. 재설치 가능성을 고려해 바로 삭제하지 않는 편이 안전하다. 완전히 제거해야 한다면 먼저 필요한 설정과 데이터를 백업한 뒤 별도로 정리한다.

---

## 13. 빠른 확인 체크리스트

```bash
# 1. 설치 확인
agentsview --version

# 2. 백그라운드 실행
agentsview daemon start

# 3. 상태 확인
agentsview daemon status

# 4. 웹 UI 접속
open http://127.0.0.1:8080  # macOS

# 5. 사용량 확인
agentsview usage daily

# 6. 종료
agentsview daemon stop
```

정상 기준:

- `agentsview --version`이 버전을 출력한다.
- `daemon status`가 `http://127.0.0.1:8080`을 표시한다.
- 웹 UI에서 세션과 프로젝트 목록이 보인다.
- `usage daily`가 사용 가능한 세션의 토큰·비용 요약을 출력한다.

---

## 14. 확인 기준과 참고 자료

문서 작성 기준:

- 작성일: 2026-07-18
- 확인한 최신 릴리스: `v0.38.1` (2026-07-13)
- 기본 백엔드: 로컬 SQLite
- 선택 백엔드: PostgreSQL, DuckDB 미러·Quack

공식 자료:

- GitHub: https://github.com/kenn-io/agentsview
- 최신 릴리스: https://github.com/kenn-io/agentsview/releases/latest
- Quick Start: https://www.agentsview.io/quickstart/
- Configuration: https://www.agentsview.io/configuration/
- CLI Reference: https://www.agentsview.io/commands/
- 설계 문서: https://github.com/kenn-io/agentsview/blob/main/DESIGN.md
- Docker Compose 예제: https://github.com/kenn-io/agentsview/blob/main/docker-compose.prod.yaml
