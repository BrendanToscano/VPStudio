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

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BUGSCAN_DIR = os.path.dirname(SCRIPT_DIR)
PROJECT_ROOT = os.path.dirname(os.path.dirname(BUGSCAN_DIR))
REPORT_PATH = os.path.join(PROJECT_ROOT, "marchVPStudioBugFixes.md")

FINDINGS_DIR = os.path.join(BUGSCAN_DIR, "findings")
STATE_DIR = os.path.join(BUGSCAN_DIR, "state")
VALIDATION_DIR = os.path.join(BUGSCAN_DIR, "validation")

TERMINAL_STATES = {"duplicate", "invalid", "stale", "superseded"}


def warn(message):
    print(f"[render_report] {message}", file=sys.stderr)


def read_jsonl(path):
    records = []
    issues = {"path": path, "malformed": [], "non_object": []}
    if not os.path.exists(path):
        return records, issues

    with open(path, "r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError as error:
                issues["malformed"].append({"line": line_number, "error": str(error)})
                warn(f"Skipping malformed JSONL in {os.path.basename(path)}:{line_number}: {error}")
                continue
            if not isinstance(parsed, dict):
                record_type = type(parsed).__name__
                issues["non_object"].append({"line": line_number, "type": record_type})
                warn(f"Skipping non-object JSONL record in {os.path.basename(path)}:{line_number}: {record_type}")
                continue
            records.append(parsed)
    return records, issues


def read_json(path):
    issues = {"path": path, "malformed": None, "non_object": None}
    if not os.path.exists(path):
        return {}, issues

    try:
        with open(path, "r", encoding="utf-8") as handle:
            parsed = json.load(handle)
    except json.JSONDecodeError as error:
        issues["malformed"] = str(error)
        warn(f"Skipping malformed JSON in {os.path.basename(path)}: {error}")
        return {}, issues

    if not isinstance(parsed, dict):
        issues["non_object"] = type(parsed).__name__
        warn(f"Skipping non-object JSON in {os.path.basename(path)}: {issues['non_object']}")
        return {}, issues

    return parsed, issues


def iso_sort_key(timestamp):
    return timestamp or ""


def finding_matches_lane(finding_id, lane_letter):
    if not finding_id:
        return False
    return finding_id.startswith(f"LANE-{lane_letter}-") or finding_id.startswith(f"{lane_letter}-")


def split_paths(raw_value):
    if isinstance(raw_value, list):
        return [str(part).strip() for part in raw_value if str(part).strip()]
    if isinstance(raw_value, str):
        return [part.strip() for part in raw_value.split(",") if part.strip()]
    return []


def summarize_record(record):
    parts = []
    for key in ("id", "findingId", "type", "action", "classification", "title"):
        value = record.get(key)
        if value:
            parts.append(f"{key}={value}")
        if len(parts) == 4:
            break
    return ", ".join(parts) if parts else "unclassified record"


def text_value(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, list):
        return "; ".join(text_value(item) for item in value if text_value(item))
    if isinstance(value, dict):
        return json.dumps(value, sort_keys=True)
    return str(value).strip()


def normalize_finding_record(record):
    finding_id = str(record.get("id") or "").strip()
    title = str(record.get("title") or "").strip()
    if not finding_id or not title:
        return None

    normalized = dict(record)
    normalized["id"] = finding_id
    normalized["title"] = title
    normalized["paths"] = split_paths(record.get("paths"))
    if not normalized["paths"]:
        normalized["paths"] = split_paths(record.get("evidenceFile"))
    return normalized


def load_findings_file(path):
    raw_records, issues = read_jsonl(path)
    findings = []
    ignored = []
    for record in raw_records:
        normalized = normalize_finding_record(record)
        if normalized is None:
            ignored.append(record)
            continue
        findings.append(normalized)

    return findings, {
        "path": path,
        "malformed": issues["malformed"],
        "non_object": issues["non_object"],
        "ignored_non_finding": ignored,
    }


def load_validation_events(path):
    events, issues = read_jsonl(path)
    return events, {
        "path": path,
        "malformed": issues["malformed"],
        "non_object": issues["non_object"],
    }


def is_terminal_validation_event(event):
    event_type = str(event.get("type") or "").lower()
    classification = str(event.get("classification") or "").lower()
    action = str(event.get("action") or "").lower()

    if event_type in {"duplicate", "invalid", "superseded"}:
        return True
    if classification in TERMINAL_STATES:
        return True
    if action.startswith("classified_as_"):
        classified_state = action.removeprefix("classified_as_")
        return classified_state in TERMINAL_STATES
    return False


def terminal_event_by_finding(events):
    terminal = {}
    for event in sorted(events, key=lambda current: iso_sort_key(current.get("timestamp", ""))):
        finding_id = event.get("findingId")
        if finding_id and is_terminal_validation_event(event):
            terminal[finding_id] = event
    return terminal


def is_visible_finding(finding, terminal_events):
    if finding.get("id") in terminal_events:
        return False
    finding_type = str(finding.get("type") or "").lower()
    classification = str(finding.get("classification") or "").lower()
    return finding_type not in TERMINAL_STATES and classification not in TERMINAL_STATES


def render_finding(finding):
    lines = [f"- `[{finding['id']}] {finding['title']}`"]
    lines.append(f"  - confidence: {finding.get('confidence', 'high')}")
    paths = finding.get("paths") or []
    paths_str = ", ".join(f"`{path}`" for path in paths) if paths else "(none recorded)"
    lines.append(f"  - paths: {paths_str}")
    for field in ["why_it_is_a_bug", "trigger_or_repro", "impact", "evidence", "details"]:
        value = text_value(finding.get(field))
        if value:
            lines.append(f"  - {field}: {value}")
    return "\n".join(lines)


def render_lane_status(state):
    lines = [f"- scope: {state.get('scope', '')}", "- paths:"]
    for path in state.get("relevantPaths", []):
        lines.append(f"  - `{path}`")
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
    lane_events = [
        event for event in events
        if finding_matches_lane(event.get("findingId", ""), lane_letter)
        or str(event.get("lane") or "").upper() == lane_letter
    ]
    if not lane_events:
        return ""

    lines = []
    for event in sorted(lane_events, key=lambda current: iso_sort_key(current.get("timestamp", ""))):
        header = text_value(event.get("header"))
        detail = text_value(event.get("detail"))
        if header:
            line = f"- **{header}**"
            if detail:
                line += f" {detail}"
            lines.append(line)
            continue

        event_type = event.get("type") or event.get("action") or "event"
        finding_id = event.get("findingId") or f"lane-{lane_letter}"
        related = event.get("relatedFindingId")
        timestamp = event.get("timestamp")
        line = f"- **{event_type} {finding_id}**"
        if related:
            line += f" → `{related}`"
        if detail:
            line += f": {detail}"
        if timestamp:
            line += f" _(at {timestamp})_"
        lines.append(line)
    return "\n".join(lines)


def has_unresolved_high_priority_validation_disputes(events):
    dispute_types = {"dispute", "needs_revalidation", "reopen", "reopened"}
    for event in events:
        event_type = str(event.get("type") or "").lower()
        priority = str(event.get("priority") or "").lower()
        if event_type in dispute_types and (not priority or priority == "high"):
            return True
    return False


def latest_timestamp(*values):
    timestamps = [value for value in values if value]
    return max(timestamps) if timestamps else "never"


def load_report_data():
    lane_a_findings, lane_a_input = load_findings_file(os.path.join(FINDINGS_DIR, "lane-a.jsonl"))
    lane_b_findings, lane_b_input = load_findings_file(os.path.join(FINDINGS_DIR, "lane-b.jsonl"))
    lane_c_findings, lane_c_input = load_findings_file(os.path.join(FINDINGS_DIR, "lane-c.jsonl"))

    lane_a_state, lane_a_state_issues = read_json(os.path.join(STATE_DIR, "lane-a.json"))
    lane_b_state, lane_b_state_issues = read_json(os.path.join(STATE_DIR, "lane-b.json"))
    lane_c_state, lane_c_state_issues = read_json(os.path.join(STATE_DIR, "lane-c.json"))
    validator_state, validator_state_issues = read_json(os.path.join(STATE_DIR, "validator.json"))

    validation_events, validation_input = load_validation_events(os.path.join(VALIDATION_DIR, "events.jsonl"))

    return {
        "findings": {
            "A": lane_a_findings,
            "B": lane_b_findings,
            "C": lane_c_findings,
        },
        "finding_inputs": [lane_a_input, lane_b_input, lane_c_input],
        "states": {
            "A": lane_a_state,
            "B": lane_b_state,
            "C": lane_c_state,
            "validator": validator_state,
        },
        "state_issues": [lane_a_state_issues, lane_b_state_issues, lane_c_state_issues, validator_state_issues],
        "validation_events": validation_events,
        "validation_input": validation_input,
    }


def compute_input_integrity(data):
    malformed_count = 0
    non_object_count = 0
    ignored_non_finding_count = 0
    notes = []

    for item in data["finding_inputs"]:
        malformed = len(item["malformed"])
        non_object = len(item["non_object"])
        ignored = len(item["ignored_non_finding"])
        malformed_count += malformed
        non_object_count += non_object
        ignored_non_finding_count += ignored
        if malformed or non_object or ignored:
            notes.append(
                f"`{os.path.basename(item['path'])}`: malformed={malformed}, non_object={non_object}, ignored_non_finding={ignored}"
            )

    validation_input = data["validation_input"]
    validation_malformed = len(validation_input["malformed"])
    validation_non_object = len(validation_input["non_object"])
    malformed_count += validation_malformed
    non_object_count += validation_non_object
    if validation_malformed or validation_non_object:
        notes.append(
            f"`{os.path.basename(validation_input['path'])}`: malformed={validation_malformed}, non_object={validation_non_object}"
        )

    for issue in data["state_issues"]:
        malformed = 1 if issue["malformed"] else 0
        non_object = 1 if issue["non_object"] else 0
        malformed_count += malformed
        non_object_count += non_object
        if malformed or non_object:
            notes.append(
                f"`{os.path.basename(issue['path'])}`: malformed={malformed}, non_object={non_object}"
            )

    status = "DEGRADED" if (malformed_count or non_object_count or ignored_non_finding_count) else "CLEAN"
    return {
        "status": status,
        "malformed_count": malformed_count,
        "non_object_count": non_object_count,
        "ignored_non_finding_count": ignored_non_finding_count,
        "notes": notes,
    }


def compute_overall_status(lane_states, val_events, input_integrity):
    if input_integrity["status"] != "CLEAN":
        return "DEGRADED_INPUT"
    all_saturated = all(state.get("saturationState") == "SATURATED_FOR_NOW" for state in lane_states)
    if all_saturated and not has_unresolved_high_priority_validation_disputes(val_events):
        return "ALL_LANES_SATURATED_FOR_NOW"
    return "COLLECTING"


def render_input_integrity(integrity):
    lines = [
        "## Input integrity",
        "<!-- INPUT_INTEGRITY_START -->",
        f"- status: {integrity['status']}",
        f"- malformed_input_record_count: {integrity['malformed_count']}",
        f"- non_object_input_record_count: {integrity['non_object_count']}",
        f"- ignored_non_finding_record_count: {integrity['ignored_non_finding_count']}",
    ]
    if integrity["status"] != "CLEAN":
        lines.append("- note: malformed or non-object input was skipped, so this report is degraded")
    if integrity["notes"]:
        lines.append("- notes:")
        for note in integrity["notes"]:
            lines.append(f"  - {note}")
    lines.append("<!-- INPUT_INTEGRITY_END -->")
    return "\n".join(lines)


def render_report(data=None):
    data = data or load_report_data()
    validation_events = data["validation_events"]
    terminal = terminal_event_by_finding(validation_events)
    integrity = compute_input_integrity(data)

    visible = {
        lane: [finding for finding in findings if is_visible_finding(finding, terminal)]
        for lane, findings in data["findings"].items()
    }

    lane_states = [data["states"]["A"], data["states"]["B"], data["states"]["C"]]
    overall = compute_overall_status(lane_states, validation_events, integrity)
    last_overall_update = latest_timestamp(
        data["states"]["A"].get("lastScanAt"),
        data["states"]["B"].get("lastScanAt"),
        data["states"]["C"].get("lastScanAt"),
        data["states"]["validator"].get("lastReportRenderAt"),
    )

    sections = ["""# March VPStudio Bug Fixes

This file is maintained by recurring isolated bug-scan agents.

Goal: find **valid bugs and real problems only** in VPStudio.
Do **not** fix code in this workflow.

Important honesty rule:
- "all bugs have been found" is treated here as **practical saturation**, not mathematical proof.
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
- it does not have unresolved high-priority validation disputes in its own validation section"""]

    sections.append(f"""## Overall status
<!-- OVERALL_STATUS_START -->
- overall_state: {overall}
- definition_of_done: ALL_LANES_SATURATED_FOR_NOW = all three lanes are SATURATED_FOR_NOW and there are no unresolved high-priority validation disputes remaining
- active_visible_finding_count: {sum(len(findings) for findings in visible.values())}
- total_recorded_finding_count: {sum(len(findings) for findings in data['findings'].values())}
- validation_event_count: {len(validation_events)}
- last_overall_update: {last_overall_update}
<!-- OVERALL_STATUS_END -->""")

    sections.append(render_input_integrity(integrity))

    for label, marker in [("Lane A", "A"), ("Lane B", "B"), ("Lane C", "C")]:
        sections.append(f"""## {label} status
<!-- LANE_{marker}_STATUS_START -->
{render_lane_status(data['states'][marker])}
<!-- LANE_{marker}_STATUS_END -->""")

    sections.append("## Findings")

    for label, lane_letter in [("Lane A", "A"), ("Lane B", "B"), ("Lane C", "C")]:
        rendered_findings = "\n\n".join(render_finding(finding) for finding in visible[lane_letter])
        if not rendered_findings:
            rendered_findings = "<!-- no currently active findings in this lane -->"
        sections.append(f"""### {label} findings
<!-- LANE_{lane_letter}_FINDINGS_START -->
{rendered_findings}
<!-- LANE_{lane_letter}_FINDINGS_END -->""")

        validation_block = render_validation_events(validation_events, lane_letter)
        comment_line = f"<!-- append {label} validation / duplicate / invalidity notes below -->"
        if validation_block:
            sections.append(f"""### {label} validation notes
<!-- LANE_{lane_letter}_VALIDATION_START -->
{comment_line}
{validation_block}
<!-- LANE_{lane_letter}_VALIDATION_END -->""")
        else:
            sections.append(f"""### {label} validation notes
<!-- LANE_{lane_letter}_VALIDATION_START -->
{comment_line}
<!-- LANE_{lane_letter}_VALIDATION_END -->""")

    return "\n\n".join(sections) + "\n"


def main():
    dry_run = "--dry-run" in sys.argv
    data = load_report_data()
    report = render_report(data)
    integrity = compute_input_integrity(data)
    if integrity["status"] != "CLEAN":
        warn(
            "Input integrity degraded: "
            f"malformed={integrity['malformed_count']}, "
            f"non_object={integrity['non_object_count']}, "
            f"ignored_non_finding={integrity['ignored_non_finding_count']}; "
            "report marked DEGRADED_INPUT"
        )
    terminal = terminal_event_by_finding(data["validation_events"])
    visible_count = sum(
        1
        for findings in data["findings"].values()
        for finding in findings
        if is_visible_finding(finding, terminal)
    )

    if dry_run:
        print(report)
        print(f"\n[dry-run] Would write {len(report)} chars to {REPORT_PATH}")
    else:
        with open(REPORT_PATH, "w", encoding="utf-8") as handle:
            handle.write(report)
        print(f"Wrote report ({len(report)} chars) -> {REPORT_PATH}")

    print(
        "  Findings: "
        f"A={len(data['findings']['A'])}, "
        f"B={len(data['findings']['B'])}, "
        f"C={len(data['findings']['C'])}, "
        f"total={sum(len(findings) for findings in data['findings'].values())}, "
        f"visible={visible_count}, "
        f"events={len(data['validation_events'])}, "
        f"input_status={integrity['status']}, "
        f"ignored_non_finding={integrity['ignored_non_finding_count']}, "
        f"malformed={integrity['malformed_count']}"
    )


if __name__ == "__main__":
    main()
