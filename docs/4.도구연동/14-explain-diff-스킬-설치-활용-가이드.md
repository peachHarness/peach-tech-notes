# explain-diff 스킬 설치·활용 가이드

> AI가 작성한 코드 변경분을 "읽는" 대신 "이해하게" 만드는 explain-diff 스킬을 Claude Code와 Codex CLI에 설치·운영하는 방법을 정리한다.

---

## 0. 먼저 결론

1. 스킬 본체는 GitHub Gist 두 파일이다. `curl`로 받아서 `SKILL.md`로 저장하면 설치가 끝난다.
2. `explain-diff-html`(HTML 출력)과 `explain-diff-notion`(Notion 페이지 출력) 두 가지가 있다.
3. skills.sh 레지스트리에는 **원본이 없다.** 동명 스킬이 검색되지만 제3자가 다시 쓴 별개 스킬이다.
4. 스킬 실체는 `~/.agents/skills/`에 두고 Claude Code와 Codex CLI에서 심링크로 공유한다.
5. 스킬은 3단 프롬프트(설명서 → 퀴즈 → 놀이터) 중 첫 번째를 자동화한 것이다. 나머지 둘은 프롬프트로 이어붙인다.

---

## 1. 배경: 인지 부채

Notion 디자인 엔지니어 Geoffrey Litt가 AI Engineer World's Fair 2026에서 발표한 *"Understanding is the new bottleneck"*의 결과물이다.

| 개념 | 내용 |
|---|---|
| 문제 | 에이전트가 한 번에 수만 줄을 바꾼다. 한 줄씩 읽어서는 못 따라간다 |
| 인지 부채 | 기술 부채는 코드에 쌓이지만, 인지 부채는 머릿속에 쌓인다. 코드는 멀쩡한데 작성자가 그 코드를 모른다 |
| 왜 읽나 | 검증하려고가 아니라 **참여**하려고. 검증은 갈수록 에이전트가 잘한다 |
| 구조 이해의 효용 | 구조를 아는 사람은 머릿속에서 굴려보며 아이디어가 나온다. 모르면 매번 물어보고 답을 기다린다 |
| 한 줄 요약 | **확인은 맡기고, 이해는 내가 챙긴다** |

방법론은 교육학에서 셋을 빌려왔다 — 설명서, 퀴즈, 놀이터.

### 참고 링크

- 요약 영상(한국어): <https://youtu.be/iv60GIHpijE>
- 원본 발표: <https://www.youtube.com/watch?v=WkBPX-oDMnA>
- 스킬 Gist: <https://gist.github.com/geoffreylitt/a29df1b5f9865506e8952488eac3d524>

---

## 2. 스킬 두 종류

Gist에는 파일이 두 개 있고, 본문 구성(Background / Intuition / Code / Quiz)은 같다. 출력 매체만 다르다.

| 스킬 | 출력 | 전제 조건 | 쓰는 상황 |
|---|---|---|---|
| `explain-diff-html` | 단일 self-contained HTML 파일 (CSS·JS 인라인) | 없음 | 혼자 이해할 때. 기본값 |
| `explain-diff-notion` | Notion 페이지, URL 반환 | Notion MCP 연결 필수 | 팀에 공유할 때 |

공통 본문 구성:

1. **Background** — 변경과 관련된 기존 시스템 설명. 초심자용 깊은 배경 + 변경에 직결된 좁은 배경 두 단계
2. **Intuition** — 세부가 아니라 본질. 토이 데이터 예시와 다이어그램 위주
3. **Code** — 변경분을 이해 가능한 순서로 묶어 상위 레벨 워크스루
4. **Quiz** — 중간 난이도 5문항 객관식. 함정 문제가 아니라 "실제로 이해했는지" 확인용

문체는 Martin Kleppmann(『Designing Data-Intensive Applications』 저자)의 명료함을 따르도록 지시돼 있다.

---

## 3. 설치

### 3-1. 스킬 본체 내려받기

실체를 `~/.agents/skills/`에 두고 두 에이전트가 공유하는 구조를 전제로 한다.

```bash
mkdir -p ~/.agents/skills/explain-diff-html ~/.agents/skills/explain-diff-notion

curl -sL -o ~/.agents/skills/explain-diff-html/SKILL.md \
  https://gist.githubusercontent.com/geoffreylitt/a29df1b5f9865506e8952488eac3d524/raw/explain-diff-html.md

curl -sL -o ~/.agents/skills/explain-diff-notion/SKILL.md \
  https://gist.githubusercontent.com/geoffreylitt/a29df1b5f9865506e8952488eac3d524/raw/explain-diff-notion.md
```

Gist 원본 파일명이 `explain-diff-html.md`지만, 스킬로 인식되려면 파일명이 반드시 `SKILL.md`여야 한다. 폴더명이 스킬 이름이 된다.

### 3-2. 양쪽 에이전트에 연결

```bash
for s in explain-diff-html explain-diff-notion; do
  ln -sfn "$HOME/.agents/skills/$s" ~/.claude/skills/$s
  ln -sfn "$HOME/.agents/skills/$s" ~/.codex/skills/$s
done
```

이 구조의 이점은 Gist가 갱신되면 `curl -o`로 한 번만 덮어써도 양쪽에 동시 반영된다는 것이다.

공유 구조를 쓰지 않는다면 각 경로에 직접 저장해도 된다.

```
~/.claude/skills/explain-diff-html/SKILL.md
~/.codex/skills/explain-diff-html/SKILL.md
```

### 3-3. 설치 확인

```bash
head -4 ~/.claude/skills/explain-diff-html/SKILL.md
```

frontmatter의 `name`과 `description`이 출력되면 정상이다. Claude Code는 새 세션부터, Codex CLI는 다음 실행부터 스킬을 인식한다.

### 3-4. skills.sh를 쓸 수 없는 이유

skills.sh 레지스트리를 검색하면 `explain-diff`가 나오지만, 이는 제3자가 같은 이름으로 다시 작성한 별개 스킬이다. 원본은 Gist라서 레지스트리에 등록돼 있지 않다. `curl` 두 줄이면 끝나므로 레지스트리 클라이언트를 별도로 설치할 이유가 없다.

---

## 4. 사용법: 3단 프롬프트

스킬이 자동화하는 것은 1단계(설명서)뿐이다. 2·3단계는 이어서 프롬프트로 입력한다.

### ① 설명서 — 스킬 호출

```
방금 바뀐 거 설명해줘. 나는 이 코드가 처음이니까 구조부터 이해시켜 주고,
코드는 맨 마지막에 보여줘.
```

Claude Code에서는 `/explain-diff-html`로 직접 호출해도 된다. 출력 원칙 네 가지:

1. 바뀐 걸 보여주기 전에 구조부터 잡아준다
2. 코드보다 한 줄 요약으로 먼저 감을 잡게 한다
3. 상호작용 가능하게 만든다
4. 코드는 맨 마지막에 실행 순서대로 보여준다

### ② 퀴즈 — 이해 게이트

```
방금 설명해준 내용으로 중간 난이도 퀴즈 다섯 문항만 내줘.
내가 다 맞히기 전에는 정답 알려주지 말고 내가 이해 못한 것을 알려줘.
```

읽는 것과 답하는 것은 다르다. 설명서를 다 읽고도 동료의 기본 질문에 막히는 상황을 막는 속도 조절기다.

### ③ 놀이터 — 마이크로월드

```
방금 개발한 코드를 이해하고 싶어. 시각화해서 상호작용 가능한 HTML 페이지로
알려줘. 서비스 코드는 건드리지 말고 파일 하나로만.
```

출시할 코드가 아니라 **나를 이해시키는 코드**를 만들게 하는 것이다. "서비스 코드는 건드리지 말고"가 안전장치이므로 생략하지 않는다.

---

## 5. explain-diff-notion 사용 조건

`explain-diff-notion`은 마지막 출력 단계에서 **Notion MCP 도구를 호출해 페이지를 생성하고 URL을 반환**하도록 지시돼 있다. 따라서 Notion MCP가 연결돼 있지 않으면 스킬이 중간에 멈춘다.

HTML 버전과의 실질적 차이는 퀴즈 표현 방식이다.

| 항목 | HTML | Notion |
|---|---|---|
| 퀴즈 정답 숨김 | JavaScript 클릭 이벤트 | 토글 블록(▶) |
| 다이어그램 | 인라인 HTML/CSS | Notion 블록 |
| 저장 위치 | 로컬 파일, 저장소 밖 | Notion 워크스페이스 |
| 공유 | 파일 전달 | URL 공유 |

Notion 토글 퀴즈 형식 예시:

```
1. 질문
   ▶ 선택지 1
     ❌ 오답인 이유
   ▶ 선택지 2
     ✅ 정답인 이유
```

### 연결 방법

Claude Code에서 Notion 커넥터를 연결한 뒤 사용한다. 연결 상태는 `/mcp`로 확인한다. 연결돼 있지 않다면 HTML 버전만 쓰고, `explain-diff-notion` 폴더는 지워도 무방하다.

---

## 6. 출력 파일 관리 주의점

`explain-diff-html`은 결과 HTML을 **저장소 바깥의 전역 경로**에 저장하도록 지시돼 있고, 파일명은 `YYYY-MM-DD-` 로 시작한다.

```
/tmp/2026-08-14-explanation-<slug>.html
```

- 저장소 안에 생성되지 않으므로 버전 관리를 오염시키지 않는다
- 날짜 접두사 덕분에 시간순 정렬이 유지된다
- `/tmp`에 저장되면 재부팅 시 사라진다. 보존이 필요하면 출력 경로를 명시적으로 지정한다

---

## 7. 부수 효과: 버그 발견

설명서를 작성하려면 에이전트가 코드를 제대로 훑어야 한다. 그 과정에서 원 발표자와 영상 제작자 모두 기존 버그를 발견한 사례가 있다(같은 값이 두 파일에 서로 다른 숫자로 적혀 있던 케이스). 리뷰 목적이 아니어도 부수적으로 검증 효과가 따라온다.

다만 발표자 본인이 단서를 달았듯 이 방법이 만능은 아니다. 설명서를 읽었다고 이해한 것은 아니어서 퀴즈 단계가 추가된 것이다.

---

## 8. 언제 쓰나

| 대상 | 권장 범위 |
|---|---|
| 개발자·PM | 구조와 핵심 코드는 직접 본다. "확인해보고 답 드릴게요"만 반복하면 전달자에 머문다 |
| 비개발자 | 코드는 안 봐도 되지만 **구조는 챙긴다**. 데이터가 어디서 어디로 넘어가는지만 알아도 프롬프트가 달라진다 |

잘못돼도 크게 탈이 안 나는 개인 프로젝트라면 만들면서 재미 붙이는 편이 낫다. 매 변경마다 3단을 전부 돌릴 필요는 없고, 나중에 손대야 할 코드에 선택적으로 적용한다.
