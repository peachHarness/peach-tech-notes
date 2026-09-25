# Whiteboard 설치·사용 가이드

> AI 에이전트가 만든 코드 변경을 다이어그램·설명·구조 diff로 캔버스에 그려 주는 리뷰 전용 데스크톱 앱.
> 저장소: https://github.com/devdotfast/whiteboard (MIT) · 소개: https://news.hada.io/topic?id=34245

## 1. 무엇인가

Code OSS(VS Code 오픈소스판) 기반 앱이다. 파일을 **편집하지 않고 읽고 리뷰만** 한다. 에이전트가 MCP로 캔버스에 문서를 작성하면 사람이 앱에서 읽는다.

- 시퀀스·플로우 다이어그램, DB 렌즈. 각 요소가 실제 코드 줄에 연결된다
- AST 기반 구조 diff. 의미 있는 변경만 보여 준다
- 코드 peek, VS Code 키바인딩, LSP 탐색
- 흐름: 계획 → 승인 → 에이전트 구현 → Whiteboard로 리뷰

## 2. 설치

### 2.1 앱

| OS | 다운로드 | 비고 |
|---|---|---|
| macOS | https://install.dev.fast | Apple Silicon(arm64) DMG만 제공 |
| Linux | https://install.dev.fast/linux | x86_64 RPM(Fedora 계열) |

앱을 설치하면 CLI `~/.local/bin/whiteboard`도 함께 생긴다.

### 2.2 Claude Code 연결

설치할 명령은 CLI가 알려 준다.

```bash
whiteboard connect claude
```

안내에 나오는 명령은 다음과 같다.

```bash
claude plugin marketplace add devdotfast/whiteboard
claude plugin install whiteboard@devfast --scope user
claude mcp remove -s user whiteboard   # 예전에 수동 등록했다면
```

이후 `/reload-plugins`를 실행하거나 Claude Code를 재시작한다. 연결 확인:

```bash
claude mcp list | grep whiteboard
# plugin:whiteboard:whiteboard: ... - ✔ Connected
```

Codex, Cursor, OpenCode, Pi는 `whiteboard connect <agent>`로 같은 방식으로 연결한다.

## 3. 사용법

앱을 켜 둔 상태에서 에이전트에게 요청한다.

| 요청 예시 | 결과 |
|---|---|
| "현재 브랜치를 최신 main과 비교해서 Whiteboard로 열어줘" | 브랜치 리뷰 문서 생성 후 앱에서 열림 |
| "PR https://github.com/org/repo/pull/123 Whiteboard로 리뷰해줘" | PR head·base 기준 리뷰 |
| "커밋 `abc123..def456` Whiteboard로 설명해줘" | 커밋 범위 리뷰 |
| "이 모듈 동작을 그림으로 보여줘" | 스크래치패드에 다이어그램 작성 |

에이전트가 작성하는 문서 구조는 What/Why → Requirements → Design(다이어그램) → Implementation(코드 peek·호출 흐름) 순이다. 수정할 점은 캔버스에서 복사해 에이전트에게 넘기면 다시 그린다.

**주의**: 비교할 diff가 있어야 한다. `main`에 있고 변경이 없으면 만들 문서가 없으므로 커밋 범위나 PR을 지정한다.

## 4. 텔레메트리

익명 사용 통계가 **기본으로 켜져 있다**. 코드, diff, 경로, 프롬프트는 수집하지 않는다고 명시돼 있다. 다만 크래시 덤프에는 열린 소스 텍스트가 포함될 수 있고, 텔레메트리가 켜져 있으면 업로드된다.

- 앱: Preferences → Settings → **Share anonymous usage data** 끄기
- 셸: `DO_NOT_TRACK=1`

회사 코드에 쓸 때는 끄는 편을 권장한다. 로컬 데이터는 `~/.dev/`에 저장된다.

## 5. 한계

- 파일 편집 불가(리뷰 전용)
- 공유 링크는 공유 시점의 스냅샷이며, 이후 변경은 반영되지 않는다
- v0.1 초기 버전이다(2026-09 기준)
