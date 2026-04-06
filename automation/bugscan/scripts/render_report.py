#!/usr/bin/env python3
"""
render_report.py — Regenerate marchVPStudioBugFixes.md from machine-readable
JSONL findings, validation events, and lane state files.

Usage:
    python3 render_report.py              # writes to PROJECT_ROOT/marchVPStudioBugFixes.md
    python3 render_report.py --dry-run    # prints to stdout instead
"""

import json
import os
import sys
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BUGSCAN_DIR = os.path.dirname(SCRIPT_DIR)
PROJECT_ROOT = os.path.dirname(os.path.dirname(BUGSCAN_DIR))
REPORT_PATH = os.path.join(PROJECT_ROOT, "marchVPStudioBugFixes.md")

FINDINGS_DIR = os.path.join(BUGSCAN_DIR, "findings")
STATE_DIR = os.path.join(BUGSCAN_DIR, "state")
VALIDATION_DIR = os.path.join(BUGSCAN_DIR, "validation")


def read_jsonl(path):
    items = []
    if not os.path.exists(path):
        return items
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                items.append(json.loads(line))
    return items


def read_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def iso_sort_key(ts):
    if not ts:
        return ""
    return ts


def finding_matches_lane(finding_id, lane_letter):
    if not finding_id:
        return False
    return finding_id.startswith(f"LANE-{lane_letter}-") or finding_id.startswith(f"{lane_letter}-")


def terminal_event_by_finding(events):
    terminal_types = {"duplicate", "invalid", "superseded"}
    out = {}
    for ev in sorted(events, key=lambda e: iso_sort_key(e.get("timestamp", ""))):
        fid = ev.get("findingId")
        if fid and ev.get("type") in terminal_types and fid.startswith("LANE-"):
            out[fid] = ev
    return out


def render_finding(f):
    lines = []
    lines.append(f"- `[{f['id']}] {f['title']}`")
    lines.append(f"  - confidence: {f.get('confidence', 'high')}")
    paths = f.get("paths", [])
    paths_str = ", ".join(f"`{p}`" for p in paths)
    lines.append(f"  - paths: {paths_str}")
    for field in ["why_it_is_a_bug", "trigger_or_repro", "impact", "evidence"]:
        val = (f.get(field) or "").strip()
        if val:
            lines.append(f"  - {field}: {val}")
    return "\n".join(lines)


def render_lane_status(state):
    lines = []
    lines.append(f"- scope: {state.get('scope', '')}")
    lines.append("- paths:")
    for p in state.get("relevantPaths", []):
        lines.append(f"  - `{p}`")
    lines.append(f"- owner_model: {state.get('ownerModel', 'minimax')}")
    lines.append(f"- last_scan: {state.get('lastScanAt', 'never') or 'never'}")
    lines.append(f"- no_new_valid_bug_streak: {state.get('noNewValidBugStreak', 0)}")
    lines.append(f"- saturation_state: {state.get('saturationState', 'ACTIVE')}")
    lines.append(f"- scan_mode: {state.get('scanMode', 'hot')}")
    lines.append(f"- finding_count: {state.get('findingCount', 0)}")
    summary = (state.get("lastSummary") or "").strip()
    if summary:
        lines.append("- notes: |")
        for part in summary.splitlines() or [summary]:
            lines.append(f"  {part}")
    for note in state.get("priorNotes", []):
        note = (note or "").strip()
        if note:
            lines.append("- notes: |")
            for part in note.splitlines() or [note]:
                lines.append(f"  {part}")
    return "\n".join(lines)


def render_validation_events(events, lane_letter):
    lane_events = [ev for ev in events if finding_matches_lane(ev.get("findingId", ""), lane_letter)]
    if not lane_events:
        return ""
    lines = []
    for ev in sorted(lane_events, key=lambda e: iso_sort_key(e.get("timestamp", ""))):
        header = (ev.get("header") or "").strip()
        detail = (ev.get("detail") or "").strip()
        if header:
            line = f"- **{header}**"
            if detail:
                line += f" {detail}"
            lines.append(line)
            continue
        ev_type = ev.get("type", "event")
        fid = ev.get("findingId", "(unknown finding)")
        related = ev.get("relatedFindingId")
        ts = ev.get("timestamp")
        prefix = f"- **{ev_type} {fid}**"
        if related:
            prefix += f" → `{related}`"
        if detail:
            prefix += f": {detail}"
        if ts:
            prefix += f" _(at {ts})_"
        lines.append(prefix)
    return "\n".join(lines)


def compute_overall_status(lane_states, val_events):
    all_sat = all(s.get("saturationState") == "SATURATED_FOR_NOW" for s in lane_states)
    unresolved_high = any(ev.get("type") in {"invalid", "duplicate", "superseded"} for ev in val_events)
    if all_sat and not unresolved_high:
        return "ALL_LANES_SATURATED_FOR_NOW"
    return "COLLECTING"


def latest_timestamp(*values):
    timestamps = [v for v in values if v]
    if not timestamps:
        return "never"
    return max(timestamps)


def render_report():
    lane_a_findings = read_jsonl(os.path.join(FINDINGS_DIR, "lane-a.jsonl"))
    lane_b_findings = read_jsonl(os.path.join(FINDINGS_DIR, "lane-b.jsonl"))
    lane_c_findings = read_jsonl(os.path.join(FINDINGS_DIR, "lane-c.jsonl"))

    lane_a_state = read_json(os.path.join(STATE_DIR, "lane-a.json"))
    lane_b_state = read_json(os.path.join(STATE_DIR, "lane-b.json"))
    lane_c_state = read_json(os.path.join(STATE_DIR, "lane-c.json"))
    validator_state = read_json(os.path.join(STATE_DIR, "validator.json"))

    val_events = read_jsonl(os.path.join(VALIDATION_DIR, "events.jsonl"))
    terminal = terminal_event_by_finding(val_events)

    visible_a = [f for f in lane_a_findings if f.get("id") not in terminal]
    visible_b = [f for f in lane_b_findings if f.get("id") not in terminal]
    visible_c = [f for f in lane_c_findings if f.get("id") not in terminal]

    overall = compute_overall_status([lane_a_state, lane_b_state, lane_c_state], val_events)
    last_overall_update = latest_timestamp(
        lane_a_state.get("lastScanAt"),
        lane_b_state.get("lastScanAt"),
        lane_c_state.get("lastScanAt"),
        validator_state.get("lastReportRenderAt"),
    )

    sections = []
    sections.append("""# March VPStudio Bug Fixes

This file is maintained by recurring isolated bug-scan agents.

Goal: find **valid bugs and real problems only** in VPStudio.
Do **not** fix code in this workflow.

Important honesty rule:
- \"all bugs have been found\" is treated here as **practical saturation**, not mathematical proof.
- The automation may only claim `ALL_LANES_SATURATED_FOR_NOW` after repeated passes find no new valid bugs and existing findings have been revalidated.

## Shared rules

- Read this whole file before each scan.
- Do not re-add semantically duplicate findings, even if the wording would be different.
- Only add **high-confidence** bugs/problems to the main findings sections.
- Prefer concrete evidence over vague guesses.
- Include paths, trigger/repro, impact, and why it is actually a bug/problem.
- Do not fix code, open PRs, commit, or rewrite large areas.
- If an older finding looks invalid, duplicated, stale, or superseded, append a validation note referencing the original finding ID instead of silently deleting it.
- Keep edits targeted. Prefer editing only the relevant state/file sections assigned to your job.

## Finding format

Use this exact shape for each newly added valid finding:

- `[LANE-ID-TIMESTAMP-SLUG] Short title`
  - confidence: high
  - paths: `path/one`, `path/two`
  - why_it_is_a_bug: short concrete explanation
  - trigger_or_repro: how it happens, or the exact state/flow that exposes it
  - impact: user-visible or system impact
  - evidence: code-level reason / state mismatch / missing guard / bad assumption

## Saturation rule

A lane may mark itself `SATURATED_FOR_NOW` only when all of the following are true:
- it has completed at least 3 consecutive passes with **zero** new valid findings
- it spent part of the current pass rechecking older findings in its own lane
- it does not have unresolved high-priority validation disputes in its own validation section""")

    sections.append(f"""## Overall status
<!-- OVERALL_STATUS_START -->
- overall_state: {overall}
- definition_of_done: ALL_LANES_SATURATED_FOR_NOW = all three lanes are SATURATED_FOR_NOW and there are no unresolved high-priority validation disputes remaining
- active_visible_finding_count: {len(visible_a) + len(visible_b) + len(visible_c)}
- total_recorded_finding_count: {len(lane_a_findings) + len(lane_b_findings) + len(lane_c_findings)}
- validation_event_count: {len(val_events)}
- last_overall_update: {last_overall_update}
<!-- OVERALL_STATUS_END -->""")

    for label, state, marker in [
        ("Lane A", lane_a_state, "LANE_A"),
        ("Lane B", lane_b_state, "LANE_B"),
        ("Lane C", lane_c_state, "LANE_C"),
    ]:
        sections.append(f"""## {label} status
<!-- {marker}_STATUS_START -->
{render_lane_status(state)}
<!-- {marker}_STATUS_END -->""")

    sections.append("## Findings")

    lane_render_data = [
        ("Lane A", lane_a_findings, visible_a, "A", "LANE_A"),
        ("Lane B", lane_b_findings, visible_b, "B", "LANE_B"),
        ("Lane C", lane_c_findings, visible_c, "C", "LANE_C"),
    ]
    for label, all_findings, visible_findings, lane_letter, marker in lane_render_data:
        rendered_findings = "\n\n".join(render_finding(f) for f in visible_findings)
        if not rendered_findings:
            rendered_findings = "<!-- no currently active findings in this lane -->"
        sections.append(f"""### {label} findings
<!-- {marker}_FINDINGS_START -->
{rendered_findings}
<!-- {marker}_FINDINGS_END -->""")

        validation_block = render_validation_events(val_events, lane_letter)
        comment_line = f"<!-- append {label} validation / duplicate / invalidity notes below -->"
        if validation_block:
            sections.append(f"""### {label} validation notes
<!-- {marker}_VALIDATION_START -->
{comment_line}
{validation_block}
<!-- {marker}_VALIDATION_END -->""")
        else:
            sections.append(f"""### {label} validation notes
<!-- {marker}_VALIDATION_START -->
{comment_line}
<!-- {marker}_VALIDATION_END -->""")

    return "\n\n".join(sections) + "\n"


def main():
    dry_run = "--dry-run" in sys.argv
    report = render_report()
    if dry_run:
        print(report)
        print(f"\n[dry-run] Would write {len(report)} chars to {REPORT_PATH}")
    else:
        with open(REPORT_PATH, "w", encoding="utf-8") as f:
            f.write(report)
        print(f"Wrote report ({len(report)} chars) -> {REPORT_PATH}")

    lane_a = read_jsonl(os.path.join(FINDINGS_DIR, "lane-a.jsonl"))
    lane_b = read_jsonl(os.path.join(FINDINGS_DIR, "lane-b.jsonl"))
    lane_c = read_jsonl(os.path.join(FINDINGS_DIR, "lane-c.jsonl"))
    events = read_jsonl(os.path.join(VALIDATION_DIR, "events.jsonl"))
    total = len(lane_a) + len(lane_b) + len(lane_c)
    visible = len([f for f in lane_a if f.get('id') not in terminal_event_by_finding(events)]) + len([f for f in lane_b if f.get('id') not in terminal_event_by_finding(events)]) + len([f for f in lane_c if f.get('id') not in terminal_event_by_finding(events)])
    print(f"  Findings: A={len(lane_a)}, B={len(lane_b)}, C={len(lane_c)}, total={total}, visible={visible}, events={len(events)}")


if __name__ == "__main__":
    main()
