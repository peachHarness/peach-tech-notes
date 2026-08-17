# herdr 파일 탐색기 플러그인 설치·사용 가이드

> 코딩 에이전트용 터미널 워크스페이스 매니저 herdr에 파일 탐색기 계열 플러그인(yazi 래퍼, git 연동 파일 뷰어)을 설치하고, 패널로 띄우고, 단축키에 등록하는 방법을 정리한다.

---

## 0. 먼저 결론

1. 비대화형 셸(에이전트 포함)에서 설치할 때는 `--yes`가 필수다. 없으면 `remote plugin install requires --yes when stdin is not interactive`로 실패한다.
2. 액션 호출 문법은 `herdr plugin action invoke <action_id> --plugin <plugin_id>`다. `<plugin_id>/<action_id>` 슬래시 형태는 `plugin_action_not_found`가 된다.
3. `smarzban/herdr-file-viewer`는 Rust 툴체인이 없어도 프리빌트 바이너리를 받아오므로 `cargo` 설치가 필요 없다.
4. 두 플러그인 모두 TUI라 herdr 패널 안에서만 뜬다. 바이너리를 직접 실행하면 `Device not configured`가 난다.
5. 단축키는 `~/.config/herdr/config.toml`의 `[[keys.command]]`에 `type = "plugin_action"`으로 등록하고 `herdr server reload-config`로 적용한다.

---

## 1. 후보 플러그인 비교

herdr 플러그인은 GitHub `herdr-plugin` 토픽으로 인덱싱된다. 파일 탐색기 계열은 크게 세 갈래다.

| 플러그인 | 성격 | 빌드 의존성 | 쓰기 작업 |
|---|---|---|---|
| `speardragon/herdr-yazi` | yazi를 패널에 띄우는 얇은 래퍼 | 없음 (yazi만 있으면 됨) | yazi 기능 그대로 |
| `smarzban/herdr-file-viewer` | git 인식 트리 + 본문 2패널 뷰어 | 프리빌트 바이너리 자동 수신 | 읽기 전용 |
| `alexarthurs/herdr-sidebar` | VS Code 사이드바형 (탐색기 + 소스 컨트롤) | Rust 빌드, Nerd Font 권장 | 파일 조작·커밋 가능 |

선택 기준은 단순하다.

- 이미 yazi에 익숙하다 → `herdr-yazi`. 빌드 시간 0.
- 변경분을 diff로 훑고 싶다 → `herdr-file-viewer`. 트리에 git 상태가 섞여 나온다.
- 패널에서 파일을 만들고 커밋까지 하고 싶다 → `herdr-sidebar`. 다만 성숙도는 위 둘보다 낮다.

이 문서는 앞의 두 개를 함께 쓰는 구성을 다룬다. 역할이 겹치지 않는다. yazi는 파일 조작용, file-viewer는 변경분 열람용이다.

---

## 2. 사전 확인

```bash
herdr --version          # 0.7 이상 필요
herdr plugin list        # 현재 설치 목록
which yazi               # herdr-yazi 전제 조건
```

`yazi`가 없으면 플러그인의 build 훅이 `brew install yazi`를 자동 실행한다.

file-viewer의 선택적 렌더러:

```bash
brew install glow git-delta bat
```

- `glow` — 마크다운 렌더링
- `git-delta` — diff 표시
- `bat` — 문법 강조

없어도 동작하지만 플레인 텍스트로 나온다.

---

## 3. 설치

### 3.1 yazi 탐색기

```bash
herdr plugin install speardragon/herdr-yazi --yes
```

설치 결과:

```
id: ray.file-explorer
name: Yazi Explorer
actions: 2   panes: 1
Config: ~/.config/herdr/plugins/config/ray.file-explorer
```

플러그인 id가 저장소 이름(`herdr-yazi`)이 아니라 `ray.file-explorer`다. 이후 명령에서는 이 id를 쓴다.

### 3.2 git 연동 파일 뷰어

```bash
herdr plugin install smarzban/herdr-file-viewer --yes
```

설치 결과:

```
id: herdr-file-viewer
version: 1.15.0
actions: 4   panes: 1
build: /bin/sh scripts/fetch-or-build.sh
```

이름 그대로 `fetch-or-build`다. 플랫폼에 맞는 프리빌트 바이너리를 먼저 받아보고, 없을 때만 소스를 빌드한다. macOS(arm64)에서는 수신에 성공하므로 Rust 툴체인이 필요 없다.

### 3.3 설치 확인

```bash
herdr plugin list
```

```
2 plugins installed:
- herdr-file-viewer (herdr-file-viewer) enabled [github:smarzban/herdr-file-viewer@...]
- ray.file-explorer (Yazi Explorer) enabled [github:speardragon/herdr-yazi@...]
```

액션 목록은 다음으로 본다.

```bash
herdr plugin action list
```

---

## 4. 실행

### 4.1 CLI로 호출

```bash
# yazi 탐색기
herdr plugin action invoke open --plugin ray.file-explorer            # 현재 패널 옆 split
herdr plugin action invoke open-tab --plugin ray.file-explorer        # 새 탭

# git 파일 뷰어
herdr plugin action invoke open-file-viewer --plugin herdr-file-viewer      # split
herdr plugin action invoke open-file-viewer-tab --plugin herdr-file-viewer  # 새 탭
```

문법 함정이 하나 있다. 플러그인 id와 액션 id를 슬래시로 붙이면 실패한다.

```bash
# 실패
herdr plugin action invoke ray.file-explorer/open
# → {"error":{"code":"plugin_action_not_found","message":"plugin action not found"}}
```

액션 id는 위치 인자, 플러그인 id는 `--plugin` 옵션이다.

호출은 herdr 세션 밖의 일반 터미널에서 해도 된다. CLI가 소켓 API를 타고 서버에 요청하므로, 현재 포커스된 워크스페이스에 패널이 열린다. 응답의 `context`에 어디로 갔는지 찍힌다.

```json
"context": {
  "focused_pane_id": "w3:p4",
  "workspace_id": "w3",
  "workspace_label": "lab",
  "invocation_source": "cli"
}
```

에이전트(Claude Code 등)가 herdr 패널 안에서 돌고 있다면, 에이전트에게 이 명령을 실행시키는 것만으로 사용자 화면에 패널이 열린다.

### 4.2 UI에서 호출

herdr 안에서 Actions 메뉴 또는 커맨드 팔레트를 열고 액션 제목으로 찾는다.

- `Open file explorer` / `Open file explorer (new tab)`
- `Open file viewer` / `Open file viewer (tab)`

### 4.3 패널 직접 열기

액션을 우회해 패널 배치를 직접 지정할 수도 있다.

```bash
herdr plugin pane open \
  --plugin ray.file-explorer \
  --entrypoint explorer \
  --placement split \
  --direction right \
  --cwd "$PWD"
```

`--placement`는 `overlay`, `split`, `tab`, `zoomed` 중 하나다.

### 4.4 열린 패널 확인

```bash
herdr pane list
```

```json
{"label":"Explorer","pane_id":"w3:p5","terminal_title":"Yazi: ~/source/..."}
```

---

## 5. 단축키 등록

### 5.1 설정 파일

`~/.config/herdr/config.toml`에 등록한다. 파일이 없으면 새로 만들면 된다.

```toml
[[keys.command]]
key = "prefix+e"
type = "plugin_action"
command = "ray.file-explorer.open"
description = "파일 탐색기 (yazi)"

[[keys.command]]
key = "prefix+g"
type = "plugin_action"
command = "herdr-file-viewer.open-file-viewer"
description = "git 파일 뷰어"
```

- `prefix` 기본값은 `ctrl+b`다(tmux 방식). 즉 위 설정은 `ctrl+b` → `e`, `ctrl+b` → `g`가 된다.
- `command`는 `<plugin_id>.<action_id>` 형태다. CLI의 `--plugin` 분리 문법과 다르다는 점을 주의한다.
- `type`은 `popup`, `pane`, `shell`, `plugin_action` 중 선택한다.

### 5.2 검증과 적용

```bash
herdr config check          # config: ok
herdr server reload-config  # {"status":"applied","diagnostics":[]}
```

리로드는 패널을 재시작하지 않고 대부분의 UI 설정을 반영한다. 앱 안에서는 글로벌 메뉴의 `reload config`로도 된다.

키바인딩을 되돌리려면:

```bash
herdr config reset-keys     # config.toml 백업 후 커스텀 키 제거
```

### 5.3 플러그인 안쪽 단축키 (file-viewer)

| 키 | 기능 |
|---|---|
| `f` | 파일 검색 |
| `v` | 뷰 전환 (diff ↔ 렌더 ↔ 문법 강조) |
| `b` | diff 기준선(baseline) 변경 |
| `W` | 워크트리 전환 |
| `L` | `경로:줄번호` 복사 |
| `Z` | 전체화면 |
| `?` | 도움말 |

yazi 패널은 yazi 자체 키맵을 그대로 쓴다(`~/.config/yazi/keymap.toml`).

---

## 6. 문제 해결

| 증상 | 원인과 대응 |
|---|---|
| `remote plugin install requires --yes when stdin is not interactive` | 비대화형 셸. `--yes`를 붙인다. |
| `plugin_action_not_found` | 슬래시 문법. `invoke <action_id> --plugin <plugin_id>`로 바꾼다. |
| 바이너리 직접 실행 시 `Os { code: 6, ... "Device not configured" }` | TTY가 없어서 나는 정상 동작. TUI는 herdr 패널 안에서만 뜬다. |
| diff·코드가 색 없이 플레인 텍스트 | `git-delta`, `bat`, `glow` 미설치. `brew install git-delta bat glow`. |
| 아이콘이 깨져 보임 | Nerd Font 미적용. 플러그인 설정에서 이모지 아이콘 테마로 바꾸거나 터미널 폰트를 교체한다. |

플러그인 실행 로그는 다음으로 본다.

```bash
herdr plugin log list
```

---

## 7. 제거

```bash
herdr plugin uninstall ray.file-explorer
herdr plugin uninstall herdr-file-viewer
```

로컬 개발용으로 `herdr plugin link`로 붙인 것은 `herdr plugin unlink <id>`로 뗀다.

---

## 8. 참고: 플러그인 개발·배포 구조

herdr 플러그인은 매니페스트 하나로 정의되고, Bash·JavaScript·Lua·Rust 등으로 작성할 수 있다. 매니페스트 구성 요소는 설치 시 preview로 그대로 출력된다.

- `actions` — 호출 가능한 명령 (플랫폼별 분기 가능)
- `panes` — 패널 진입점(entrypoint)과 실행 커맨드
- `build commands` — 설치 시 1회 실행 (바이너리 수신·컴파일·의존성 설치)
- `startup commands`, `events`, `link handlers`

로컬 개발 중에는 다음으로 연결한다.

```bash
herdr plugin link /path/to/plugin
```

설치 명령은 저장소 루트뿐 아니라 하위 디렉터리도 가리킬 수 있다.

```bash
herdr plugin install owner/repo/subdir
```

---

## 9. 확인 기준과 참고 자료

문서 작성 기준:

- 작성일: 2026-08-14
- 확인 환경: macOS (Darwin 25.5.0), herdr 0.8.0 (stable, protocol 19)
- 확인 버전: `ray.file-explorer` 1.0.0, `herdr-file-viewer` 1.15.0
- 설치·호출·단축키 등록·리로드까지 실제 실행으로 확인

공식 자료:

- herdr 저장소: https://github.com/herdrdev/herdr
- 플러그인 문서: https://herdr.dev/docs/plugins/
- 설정 문서: https://herdr.dev/docs/configuration/
- 연동 문서: https://herdr.dev/docs/integrations/
- 플러그인 마켓플레이스: https://herdr.dev/plugins/
- GitHub 토픽: https://github.com/topics/herdr-plugin

플러그인 저장소:

- https://github.com/speardragon/herdr-yazi
- https://github.com/smarzban/herdr-file-viewer
- https://github.com/alexarthurs/herdr-sidebar
