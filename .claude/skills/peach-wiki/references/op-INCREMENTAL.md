# INGEST-INCREMENTAL — 개발 완료 후 증분 인제스트

> 자동 트리거 전용 경량 경로. INGEST(전량 스캔 + 사람 확인)와 달리 **사람 확인 없이 변경분만** 처리한다.
> **code 모드 전용.** 개발 사이클 안에서 wiki 축적을 자동으로 잇는 것이 목적이다 (복리 루프의 축적 담당).

트리거: "증분 인제스트", 개발 스킬(node-team-dev / node-loop / node-team-e2e) 완료 스텝, `.tmp/wiki-events/` 큐 존재,
wiki 복리 게이트 대상 경로(프로젝트 로컬 스킬 `.claude/skills/` · `AGENTS.md`/`CLAUDE.md` · `docs/spec/` · hook/설정 파일) 변경 작업의 완료 스텝

> `$QMD_INDEX` 미선언 시: `QMD_INDEX=$(basename $(pwd))`로 재선언

---

## 입력 (둘 중 하나)

1. 호출 시 전달받은 변경 모듈/파일 목록
2. `.tmp/wiki-events/*.jsonl` 큐 — loop runner·개발 스킬 완료 스텝이 기록. 여러 파일이면 전부 읽어 **모듈 기준으로 dedup**
3. wiki 복리 게이트 대상 경로의 staged/변경 파일 목록 — 커밋 직전 게이트 판단에서 넘어온 경우

## 절차

1. **변경 목록 dedup** 후 영향받은 wiki 페이지 파악 (`related_files` 역참조 — DRIFT 2단계와 동일)
2. **해당 entities/concepts 페이지만 갱신** (`updated` 날짜 갱신). 페이지가 없는 신규 모듈은 entities 초안을 생성하고 완료 보고에 "정식 INGEST 권장"을 남긴다. `docs/기능별설명/` 운용 프로젝트에서는 `wiki-경계규칙.md`의 판단표를 따른다 (feature-docs 영역 내용은 링크만)
3. **wiki-index.md · wiki-log.md 기록**
4. **qmd 반영 (비차단)**:
   ```bash
   # 상태 확인은 named index status로 — 플레인 `qmd doctor`는 기본 index.sqlite를 봐 "no vectors" 오진 유발
   qmd --index "$QMD_INDEX" status
   qmd --index "$QMD_INDEX" update
   # 새 wiki 파일을 생성했을 때만 embed 수행
   ```
   실패(SQLITE_READONLY 등) 시 경고만 남기고 인제스트 자체는 완료 처리한다 — 색인 실패가 개발 흐름을 막지 않는다
5. **wiki events 계측 로그 기록** (아래 §events)
6. **처리한 큐 파일 정리** — 삭제 또는 `.done` rename

## 멱등성 · 실행 소유권 (loop 중복 방지)

- 이 모드는 변경 모듈 기준 갱신이라 **두 번 실행돼도 결과가 같다** (qmd update도 증분 — 중복 실행은 오염이 아니라 토큰 낭비 수준)
- **실행 소유권은 최외곽 오케스트레이터에 있다**: loop 내부(작업 폴더에 `loop-status.md`가 존재하고 `status: running`)에서는 team-dev/team-e2e가 이 모드를 실행하지 않고 **큐 기록만** 한다. loop 정상 종료 시 runner가 1회 트리거한다. 단독 실행(team-dev 등)일 때만 완료 스텝에서 직접 실행한다
- 사람 확인 단계 없음 — 본문 병합·모순 정리·pruning은 LINT/DRIFT(사람 트리거)의 몫이다. **자동 축적에는 주기 LINT를 반드시 짝으로 운영한다** (없으면 stale 지식이 틀린 컨텍스트를 주입하는 마이너스 복리)

## events — wiki 계측 로그

- `docs/wiki/events/YYYY-MM.jsonl`에 처리 결과를 1줄 append한다.
- `.tmp/wiki-events/`는 로컬 처리 큐이며 팀 공유 지표로 해석하지 않는다.
- `docs/wiki/events/YYYY-MM.jsonl`은 wiki 소비율, hit율, 갱신 준수율을 집계하는 공유 운영 로그다.
- 프롬프트 원문, raw tool output, 서버 응답, 토큰, 개인정보, 시크릿은 저장하지 않는다. 경로, enum, 숫자, 짧은 사유만 남긴다.
- `wiki_update=skip`이면 `skip_reason`을 비워 두지 않는다.

필수 필드:
- `schema`: `wiki-event-v1`
- `ts`: ISO 시각
- `run_id`: 작업 단위 식별자
- `skill`: 이벤트를 남긴 스킬
- `phase`: `start | finish | ingest | lint | drift | qmd-refresh`
- `wiki_read`: `yes | no | skipped | n/a`
- `wiki_hit`: `yes | no | n/a`
- `wiki_update`: `done | skip | queued | failed | n/a`
- `skip_reason`: skip이면 필수
- `updated_pages`: 변경된 `docs/wiki` 페이지 배열

예시:
```json
{"schema":"wiki-event-v1","ts":"2026-07-08T12:05:00","run_id":"260708-120500-example","skill":"peach-wiki","phase":"ingest","wiki_read":"n/a","wiki_hit":"n/a","wiki_update":"done","skip_reason":"","updated_pages":["docs/wiki/entities/example.md"]}
```

## events 집계

최근 운영 지표 확인은 읽기 전용 스크립트를 사용한다.

```bash
bash <이 스킬 경로>/assets/wiki-events-metrics.sh docs/wiki/events
```

집계 기준:
- 1차 지표 대상은 `docs/wiki/`를 운용하는 프로젝트로 한정한다. wiki 미운용 프로젝트의 도입률은 별도 지표로 분리하고, 계측만을 위해 `docs/wiki/`를 새로 만들지 않는다.
- wiki 소비율 = `run_id`별 `wiki_read` 실값(`yes|no`) 중 `yes` / 실값을 가진 `run_id` 전체.
  한 run에 start와 finish가 모두 실값을 담으면 start를 채택한다. `phase=start`로 세지 않는다 —
  start를 생략하고 finish 한 건에 소비 정보를 몰아 기록하는 run이 있어 분모가 결손된다(실측 52 run 중 11건).
- wiki hit율 = `wiki_read=yes` 중 `wiki_hit=yes` / `wiki_read=yes`
- wiki 갱신 준수율 = `phase=finish|ingest` 중 `wiki_update=done|skip|queued`이고 skip 사유 규칙을 만족한 이벤트 / 대상 이벤트 전체
- 부실 스킵률 = `wiki_update=skip`인데 `skip_reason`이 비었거나 `사유 없음`인 이벤트 / 대상 이벤트 전체
