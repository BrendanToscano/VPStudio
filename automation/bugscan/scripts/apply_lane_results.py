#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUGSCAN = ROOT / 'automation' / 'bugscan'
FINDINGS_DIR = BUGSCAN / 'findings'
STATE_DIR = BUGSCAN / 'state'
TMP_DIR = BUGSCAN / 'tmp'
TMP_DIR.mkdir(parents=True, exist_ok=True)


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def git_head() -> str:
    try:
        return subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
    except Exception:
        return ''


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


def next_id(lane: str, existing_ids: set[str]) -> str:
    today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    prefix = f'LANE-{lane.upper()}-{today}-{lane.upper()}-'
    n = 1
    while True:
        candidate = f'{prefix}{n:03d}'
        if candidate not in existing_ids:
            return candidate
        n += 1


def normalize_finding(raw: dict, lane: str, existing_ids: set[str]) -> dict:
    out = dict(raw)
    fid = (out.get('id') or '').strip()
    if not fid.startswith(f'LANE-{lane.upper()}-'):
        fid = next_id(lane, existing_ids)
    out['id'] = fid
    existing_ids.add(fid)
    out['title'] = (out.get('title') or 'Untitled finding').strip()
    out['confidence'] = 'high'
    out['paths'] = [p.strip() for p in out.get('paths', []) if str(p).strip()]
    for field in ['why_it_is_a_bug', 'trigger_or_repro', 'impact', 'evidence']:
        out[field] = (out.get(field) or '').strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lane', required=True, choices=['a', 'b', 'c'])
    ap.add_argument('--result', required=True, help='Path to result JSON')
    args = ap.parse_args()

    lane = args.lane
    result = json.loads(Path(args.result).read_text())
    findings_path = FINDINGS_DIR / f'lane-{lane}.jsonl'
    state_path = STATE_DIR / f'lane-{lane}.json'

    existing = load_jsonl(findings_path)
    existing_ids = {f.get('id', '') for f in existing}

    raw_new = result.get('newFindings', []) or []
    new_findings = [normalize_finding(item, lane, existing_ids) for item in raw_new]

    append_jsonl(findings_path, new_findings)
    all_findings = load_jsonl(findings_path)

    state = load_json(state_path)
    ts = now_iso()
    state['lastScanAt'] = ts
    state['lastScannedCommit'] = git_head()
    if new_findings:
        state['noNewValidBugStreak'] = 0
    else:
        state['noNewValidBugStreak'] = int(state.get('noNewValidBugStreak', 0)) + 1
    requested_sat = (result.get('saturationState') or '').strip() or state.get('saturationState', 'ACTIVE')
    if requested_sat == 'SATURATED_FOR_NOW' and state['noNewValidBugStreak'] >= 3:
        state['saturationState'] = 'SATURATED_FOR_NOW'
    elif new_findings:
        state['saturationState'] = 'ACTIVE'
    else:
        state['saturationState'] = requested_sat
    summary = (result.get('summary') or '').strip()
    if summary:
        previous = (state.get('lastSummary') or '').strip()
        prior = list(state.get('priorNotes', []))
        if previous and previous != summary and previous not in prior:
            prior.insert(0, previous)
        state['priorNotes'] = prior[:8]
        state['lastSummary'] = summary
    state['findingCount'] = len(all_findings)
    write_json(state_path, state)

    print(json.dumps({
        'applied': True,
        'lane': lane,
        'newFindingCount': len(new_findings),
        'findingCount': len(all_findings),
        'lastScanAt': state['lastScanAt'],
        'lastScannedCommit': state.get('lastScannedCommit'),
        'saturationState': state.get('saturationState'),
        'newFindingIds': [f['id'] for f in new_findings],
        'statePath': str(state_path),
        'findingsPath': str(findings_path),
    }, indent=2))


if __name__ == '__main__':
    main()
