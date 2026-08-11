# Archify 설치·사용 가이드

> 시스템 설명이나 코드베이스를 검증된 JSON IR을 거쳐 단일 HTML 인터랙티브 기술 다이어그램으로 변환하는 에이전트 스킬 Archify의 설치·운영 방법을 정리한다.

---

## 0. 먼저 결론

1. `npx skills add tt-a1i/archify -g` 한 줄로 설치된다. Node.js 18 이상이 필요하다.
2. 설치 위치는 `~/.agents/skills/archify`이며, Claude Code에는 `~/.claude/skills/archify` 심링크로 연결된다.
3. 설치 후 `node bin/archify.mjs doctor`로 렌더러 5종이 모두 `[ok]`인지 확인한다.
4. 호출은 `/archify` 또는 자연어("archify로 이 저장소 아키텍처 그려줘")로 한다.
5. Mermaid 자동 파싱·범용 auto-layout·호스팅 공유는 **의도적으로 제외**되어 있다.

---

## 1. Archify가 하는 일

Mermaid처럼 "텍스트를 그림으로 바꾸는" 변환기가 아니다. **타입드 JSON IR(중간 표현) + 스키마 검증 + 렌더 파이프라인**을 갖춘 도구이며, 출력물은 외부 의존성이 없는 단일 HTML 파일이다.

```
  [입력]                    [처리]                        [출력]
 ┌────────────┐        ┌───────────────┐          ┌──────────────────┐
 │ 자연어 설명 │        │  ① GENERATE   │          │ 단일 HTML 파일    │
 │  또는      │───────▶│  타입드 JSON  │────┐     │ (자체 완결형)     │
 │ 코드베이스  │        │  IR 생성      │    │     ├──────────────────┤
 └────────────┘        └───────────────┘    │     │ PNG / SVG / WebM │
                              │             │     │ 1200×630 공유카드 │
                              ▼             │     └──────────────────┘
                       ┌───────────────┐    │
                       │  ② VALIDATE   │    │   실패 시
                       │  스키마·레이아웃│────┼──▶ 기계가 읽는
                       │  검증          │    │    "수리 지시서" 반환
                       └───────────────┘    │        │
                              │             │        └──▶ ⑤ ITERATE
                              ▼             │             (무관한 구조는
                       ┌───────────────┐    │              그대로 유지)
                       │  ③ PREVIEW    │    │
                       │  파일 감시·검증 │    │
                       │  된 리비전만   │    │
                       │  리로드        │    │
                       └───────────────┘    │
                              │             │
                              ▼             ▼
                       ┌────────────────────────┐
                       │  ④ DELIVER             │
                       │  후보 렌더 → 검사 통과  │
                       │  → 원자적 교체(atomic)  │
                       └────────────────────────┘
```

핵심은 **검증을 통과하지 못한 결과물은 최종 파일을 덮어쓰지 않는다**는 점이다. 실패하면 사람이 아니라 에이전트가 읽을 수 있는 형식의 수리 안내가 반환되고, 에이전트가 JSON을 고쳐 다시 시도한다.

---

## 2. 다이어그램 5종과 선택 기준

| 종류 | 용도 |
|---|---|
| `architecture` | 컴포넌트, 서비스, 스토리지, 신뢰 경계 |
| `workflow` | CI/CD, 승인 절차, 툴 호출, 런북 |
| `sequence` | API 호출, 캐시 폴백, 인증 추적 |
| `dataflow` | 파이프라인, 데이터 리니지, PII 흐름, 소비자 |
| `lifecycle` | 상태, 재시도, 대기, 종료 결과 |

---

## 3. 설치

### 3.1 요구사항

```bash
node --version   # v18 이상
```

### 3.2 설치 명령

```bash
npx skills add tt-a1i/archify -g
```

`skills` CLI가 감지된 모든 에이전트 호스트에 한 번에 설치한다. 결과 구조는 다음과 같다.

```
~/.agents/skills/archify        # 실제 스킬 본체
~/.claude/skills/archify        # → ../../.agents/skills/archify (심링크)
```

Cursor만 명시적으로 지정하려면:

```bash
npx -y skills add tt-a1i/archify --skill archify --agent cursor --global --copy --yes
```

> 설치 로그 마지막에 `PromptScript does not support global skill installation` 같은 실패 항목이 보일 수 있다. 이는 설치되지 않은 다른 호스트에 대한 것이므로 Claude Code 사용에는 영향이 없다.

### 3.3 설치 확인

```bash
cd ~/.agents/skills/archify
node bin/archify.mjs doctor
```

렌더러·스키마·예제가 5종 모두 `[ok]`로 나오고 마지막에 `Archify is ready.`가 출력되면 정상이다.

---

## 4. 스킬 호출 방법

### 4.1 Claude Code 세션에서

```
/archify
```

또는 자연어로 요청한다. 스킬 설명에 트리거 조건이 들어 있어 아래처럼 말하면 자동으로 호출된다.

```
이 저장소를 분석한 다음 archify로 런타임 아키텍처 다이어그램을 만들어줘.
핵심 컴포넌트 8~12개, 주요 경로 1개, 외부 의존성, 신뢰 경계를 표시해줘.
```

요청에 포함하면 결과가 좋아지는 요소:

- 다이어그램 종류 (architecture / workflow / sequence / dataflow / lifecycle)
- 노드 개수 상한 (예: 8~12개)
- 강조할 주요 경로
- 외부 의존성, 신뢰 경계 표시 여부
- 정적/애니메이션 여부

### 4.2 CLI 직접 사용

```bash
cd ~/.agents/skills/archify

# 진단
node bin/archify.mjs doctor

# 데모 생성
node bin/archify.mjs demo /tmp/archify-demo

# 요구사항으로 작성 가이드 받기
node bin/archify.mjs guide "CI 검사, 승인, 배포, 롤백을 보여줘"

# 검증
node bin/archify.mjs validate workflow examples/agent-tool-call.workflow.json --quality showcase --json

# 미리보기
node bin/archify.mjs preview workflow examples/agent-tool-call.workflow.json /tmp/workflow.html --quality showcase

# 최종 전달 (검증 통과 시 원자적 교체)
node bin/archify.mjs deliver workflow examples/agent-tool-call.workflow.json /tmp/workflow.html --quality showcase --open --json

# Architecture Delta: 스냅샷 비교
node bin/archify.mjs compare architecture base.json head.json architecture-delta.html --json
```

---

## 5. 결과물 조작

출력 HTML을 브라우저에서 열면 키보드로 탐색할 수 있다.

| 키 | 기능 |
|---|---|
| `?` | 다이어그램 가이드 |
| `/` | 노드 검색·포커스 |
| `R` | 경로 추적 (PATH) |
| `L` | 역할 비교 (LENS) |
| `M` | 전체 개요 레이더 |
| `P` / `[` `]` | 스토리 재생 / 챕터 이동 |
| `F` | 발표 모드 |
| `S` / `T` / `E` | 스타일 / 테마 / 내보내기 |
| `+` `-` `0` | 확대 / 축소 / 초기화 |

내보내기 형식: PNG, SVG, WebM, 1200×630 공유 카드(다이어그램·경로·도달범위 변형).

딥링크로 특정 상태를 공유할 수 있다.

```
#focus=<id>
#reach=upstream|downstream
#route=<source>~<target>
#lens=<kind>~<kind>
#view=<view-id>
```

---

## 6. JSON 옵션

`meta`에 선택 항목을 넣어 표현을 조정한다.

```json
{
  "meta": {
    "animation": "trace",
    "visual_preset": "signal-flow"
  }
}
```

- `animation` 생략 → 정적 다이어그램 (기본)
- `visual_preset`: `classic`(기본), `editorial`(출판용 스타일), `signal-flow` 등

---

## 7. 포함 범위와 제외 범위

| 포함 | 의도적 제외 |
|---|---|
| 타입드·재현 가능한 JSON IR | Mermaid 자동 파싱 |
| 전달 전 원자적 검증 + 수리 리시트 | 범용 auto-layout |
| Architecture Delta (base vs head 비교) | 호스팅 공유 |
| Git 검증 기반 소스 근거 첨부 | WYSIWYG 편집 |
| 유한 모션, 시맨틱 검색, 공유 링크 | |

"없는 토폴로지는 만들지 않는다(grounded interaction)"는 원칙에 따라, 작성된 관계만 재사용하고 관계를 추측해서 추가하지 않는다.

---

## 8. 활용 포인트

가장 실용적인 기능은 **`compare` 기반 Architecture Delta**다. PR 리뷰 시 변경 전후의 검증된 스냅샷을 비교해 구조 변화만 부각한 HTML을 생성하므로, 아키텍처가 어떻게 달라졌는지 리뷰어에게 그림으로 전달할 수 있다.

---

## 9. 제거

```bash
rm -rf ~/.agents/skills/archify
rm -f ~/.claude/skills/archify
```

---

## 10. 확인 기준과 참고 자료

문서 작성 기준:

- 작성일: 2026-08-11
- 버전: v2.13.0
- 라이선스: MIT
- 확인 환경: macOS (Darwin 25.5.0), Node.js v24.16.0, Claude Code

공식 자료:

- GitHub: https://github.com/tt-a1i/archify
- 프로젝트 페이지: https://tt-a1i.github.io/archify/
- 시나리오 가이드: https://tt-a1i.github.io/archify/guide.html
- Proof Lab (검증된 11개 시나리오): https://tt-a1i.github.io/archify/gallery.html
