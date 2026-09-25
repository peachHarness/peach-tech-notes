#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-docs/wiki/events}"

if [ ! -e "$TARGET" ]; then
  echo "계측 데이터 없음: $TARGET"
  exit 0
fi

python3 - "$TARGET" <<'PY'
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

target = Path(sys.argv[1])
if target.is_file():
    files = [target]
else:
    files = sorted(target.glob("*.jsonl"))

if not files:
    print(f"계측 데이터 없음: {target}")
    raise SystemExit(0)

cutoff = datetime.now() - timedelta(days=30)
events = []
invalid = 0
timezone_missing = 0

for file in files:
    with file.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                invalid += 1
                continue
            if event.get("schema") != "wiki-event-v1":
                continue
            ts_raw = str(event.get("ts", ""))
            try:
                parsed_ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
                ts_has_timezone = parsed_ts.tzinfo is not None
                ts = parsed_ts.astimezone().replace(tzinfo=None) if ts_has_timezone else parsed_ts
            except ValueError:
                invalid += 1
                continue
            if ts >= cutoff:
                events.append(event)
                if not ts_has_timezone:
                    timezone_missing += 1

if not events:
    print("최근 30일 계측 데이터 없음")
    if invalid:
        print(f"무시한 잘못된 이벤트: {invalid}")
    raise SystemExit(0)

def pct(num, den):
    if den == 0:
        return "n/a"
    return f"{num / den * 100:.1f}% ({num}/{den})"

# 소비 정보(wiki_read/wiki_hit)의 정식 소유자는 start지만, start를 생략하고
# finish 한 건에 몰아 기록하는 run도 있다. phase로 거르면 그 run이 분모에서
# 통째로 빠지므로, run_id 단위로 실값(yes/no)을 가진 이벤트를 집는다.
read_by_run = {}
for event in events:
    run_id = str(event.get("run_id", "")).strip()
    if not run_id or event.get("wiki_read") not in {"yes", "no"}:
        continue
    if event.get("phase") == "start" or run_id not in read_by_run:
        read_by_run[run_id] = event

read_runs = list(read_by_run.values())
read_yes = [e for e in read_runs if e.get("wiki_read") == "yes"]
hit_yes = [e for e in read_yes if e.get("wiki_hit") == "yes"]

update_events = [
    e for e in events
    if e.get("phase") in {"finish", "ingest"} and e.get("wiki_update") not in {None, "", "n/a"}
]

def compliant_update(event):
    update = event.get("wiki_update")
    reason = str(event.get("skip_reason", "")).strip()
    if update == "skip":
        return bool(reason) and reason != "사유 없음"
    return update in {"done", "queued"}

compliant = [e for e in update_events if compliant_update(e)]
bad_skip = [
    e for e in update_events
    if e.get("wiki_update") == "skip"
    and str(e.get("skip_reason", "")).strip() in {"", "사유 없음"}
]

all_run_ids = {
    str(e.get("run_id", "")).strip()
    for e in events
    if str(e.get("run_id", "")).strip()
}
unmeasured_runs = len(all_run_ids) - len(read_runs)

print("wiki events 최근 30일 집계")
print(f"- 이벤트 수: {len(events)}")
print(f"- wiki 소비율: {pct(len(read_yes), len(read_runs))}")
print(f"- wiki hit율: {pct(len(hit_yes), len(read_yes))}")
print(f"- wiki 갱신 준수율: {pct(len(compliant), len(update_events))}")
print(f"- 부실 스킵률: {pct(len(bad_skip), len(update_events))}")
if unmeasured_runs > 0:
    print(f"- wiki_read 미기록 run: {unmeasured_runs}건 (소비율 분모에서 제외)")
if timezone_missing:
    print(f"- timezone 없는 ts: {timezone_missing}건 (로컬시간으로 간주)")
if invalid:
    print(f"- 무시한 잘못된 이벤트: {invalid}")
PY
