#!/usr/bin/env python3
import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUGSCAN = ROOT / 'automation' / 'bugscan'
STATE_DIR = BUGSCAN / 'state'
VALIDATION_DIR = BUGSCAN / 'validation'
VALIDATION_DIR.mkdir(parents=True, exist_ok=True)
EVENTS_PATH = VALIDATION_DIR / 'events.jsonl'
VALIDATOR_STATE = STATE_DIR / 'validator.json'
RENDER_SCRIPT = BUGSCAN / 'scripts' / 'render_report.py'


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def load_json(path: Path):
    return json.loads(path.read_text()) if path.exists() else {}


def write_json(path: Path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')


def load_jsonl(path: Path):
    if not path.exists():
        return []
    out = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            out.append(json.loads(line))
    return out


def append_jsonl(path: Path, items):
    if not items:
        return
    with path.open('a', encoding='utf-8') as f:
        for item in items:
            f.write(json.dumps(item, ensure_ascii=False) + '\n')


def event_key(ev: dict):
    return (
        ev.get('type'),
        ev.get('findingId'),
        ev.get('relatedFindingId'),
        (ev.get('detail') or '').strip(),
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--events', required=True, help='Path to validator result JSON list/object')
    args = ap.parse_args()

    raw = json.loads(Path(args.events).read_text())
    events_in = raw.get('events', raw if isinstance(raw, list) else [])
    if not isinstance(events_in, list):
        raise SystemExit('events payload must be a list or contain an events list')

    existing = load_jsonl(EVENTS_PATH)
    seen = {event_key(ev) for ev in existing}
    ts = now_iso()
    added = []
    for ev in events_in:
        out = dict(ev)
        out['timestamp'] = (out.get('timestamp') or ts)
        out['source'] = 'validator'
        key = event_key(out)
        if key in seen:
            continue
        seen.add(key)
        added.append(out)

    append_jsonl(EVENTS_PATH, added)

    state = load_json(VALIDATOR_STATE)
    state['lastRunAt'] = ts
    state['totalEventsProcessed'] = int(state.get('totalEventsProcessed', 0)) + len(added)
    subprocess.check_call(['python3', str(RENDER_SCRIPT)], cwd=str(ROOT))
    state['lastReportRenderAt'] = now_iso()
    write_json(VALIDATOR_STATE, state)

    print(json.dumps({
        'applied': True,
        'addedEventCount': len(added),
        'totalEventsProcessed': state['totalEventsProcessed'],
        'lastRunAt': state['lastRunAt'],
        'lastReportRenderAt': state['lastReportRenderAt'],
        'eventsPath': str(EVENTS_PATH),
        'validatorStatePath': str(VALIDATOR_STATE),
    }, indent=2))


if __name__ == '__main__':
    main()
