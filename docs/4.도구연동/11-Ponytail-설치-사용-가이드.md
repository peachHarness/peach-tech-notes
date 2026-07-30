# Ponytail 설치·사용 가이드

> AI 코딩 에이전트가 불필요한 코드를 작성하지 않도록 유도하는 플러그인 Ponytail을 Claude Code와 Codex CLI에 설치·운영하는 방법을 정리한다.

---

## 0. 먼저 결론

1. Node.js가 PATH에 잡혀 있는지 먼저 확인한다.
2. Claude Code는 marketplace 추가와 설치를 **두 개의 별도 프롬프트**로 나눠서 입력한다.
3. Codex CLI는 `codex plugin` 서브커맨드로 동일한 순서로 설치한다.
4. 설치 후 `/ponytail full`처럼 강도를 지정해 동작을 확인한다.
5. 코드 리뷰에는 `/ponytail-review`, 저장소 전체 점검에는 `/ponytail-audit`을 쓴다.

---

## 1. Ponytail이 하는 일

Ponytail은 "가장 좋은 코드는 작성하지 않은 코드"라는 철학으로, 에이전트가 코드를 작성하기 전에 다음 7단계 판단을 거치게 만든다.

1. 이것이 필요한가? (YAGNI)
2. 이미 코드베이스에 있는가? → 재사용
3. 표준 라이브러리에 있는가? → 사용
4. 네이티브 플랫폼 기능인가? → 사용
5. 설치된 의존성인가? → 사용
6. 한 줄로 가능한가? → 한 줄로 작성
7. 위 전부 아니면 → 최소 필수 코드만 작성

공개된 벤치마크 기준 효과:

- 코드량 약 54% 감소 (최대 94%)
- 비용 약 20% 절감
- 속도 약 27% 단축
- 검증·보안·접근성 등 안전성은 100% 유지

---

## 2. 설치 전 요구사항

- **Node.js가 PATH에 있어야 한다.** Nix, nvm처럼 셸마다 PATH 구성이 달라지는 환경에서는 비상호작용 셸(non-interactive shell)에서도 `node`가 잡히는지 확인한다.

```bash
node --version
```

Node.js를 찾지 못하면 설치가 중간에 실패할 수 있으므로, 위 명령이 버전을 출력하는지 먼저 확인한다.

---

## 3. Claude Code 설치

marketplace 추가와 플러그인 설치는 **하나의 메시지에 이어 쓰지 말고 두 개의 별도 프롬프트**로 나눠서 입력한다.

```
/plugin marketplace add DietrichGebert/ponytail
```

응답을 받은 뒤, 다음 프롬프트로 설치한다.

```
/plugin install ponytail@ponytail
```

### 3.1 설치 확인

```
/ponytail-help
```

명령어 목록이 출력되면 설치가 정상이다.

### 3.2 제거

```
/plugin remove ponytail
```

---

## 4. Codex CLI 설치

Codex CLI는 `codex plugin` 서브커맨드로 동일한 순서를 따른다.

```bash
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add ponytail@ponytail
```

> Codex CLI의 `plugin` 서브커맨드는 비교적 최근에 추가된 기능이다. 로컬 Codex CLI 버전에서 지원하지 않을 수 있으니, 설치 전에 아래로 지원 여부를 먼저 확인한다.

```bash
codex --version
codex plugin --help
```

### 4.1 제거

```bash
codex plugin remove ponytail
```

---

## 5. 주요 커맨드

설치된 호스트(Claude Code, Codex CLI 등)에서 공통으로 사용할 수 있다.

| 커맨드 | 기능 |
|---|---|
| `/ponytail [lite\|full\|ultra\|off]` | 최적화 강도 설정 또는 비활성화 |
| `/ponytail-review` | 현재 diff에서 과도한 설계·불필요한 코드를 점검 |
| `/ponytail-audit` | 저장소 전체를 대상으로 점검 |
| `/ponytail-debt` | 의도적으로 미룬 `ponytail:` 주석 단축키를 수집 |
| `/ponytail-gain` | 코드량·비용·속도 개선 대시보드 표시 |
| `/ponytail-help` | 커맨드 빠른 참조 |

### 5.1 강도 수준

| 강도 | 설명 |
|---|---|
| `lite` | 가벼운 최적화, 판단 단계를 완화해서 적용 |
| `full` | 기본값, 균형 잡힌 최적화 |
| `ultra` | 공격적 최적화, 코드 최소화를 최우선 |
| `off` | 비활성화 |

일상적인 개발에는 `full`을 기본으로 두고, 프로토타입·PoC처럼 최소 코드가 특히 중요한 작업에서만 `ultra`로 전환하는 방식을 권장한다.

---

## 6. 설정

기본 강도를 프로젝트/환경별로 고정하려면 다음 중 하나를 사용한다.

**환경변수**

```bash
export PONYTAIL_DEFAULT_MODE=full   # lite | full | ultra | off
```

**설정 파일**

- macOS·Linux: `~/.config/ponytail/config.json`
- Windows: `%APPDATA%\ponytail\config.json`

---

## 7. 완전 제거

호스트별 플러그인 제거 명령을 실행한 뒤, 저장소가 제공하는 정리 스크립트를 실행한다.

```bash
# 호스트별 제거 (예: Claude Code)
/plugin remove ponytail

# Codex CLI
codex plugin remove ponytail

# 부가 설정·캐시 정리
node scripts/uninstall.js
```

---

## 8. 확인 기준과 참고 자료

문서 작성 기준:

- 작성일: 2026-07-30
- 라이선스: MIT

공식 자료:

- GitHub: https://github.com/DietrichGebert/ponytail
- 소개 게시글(GeekNews): https://news.hada.io/topic?id=30701
