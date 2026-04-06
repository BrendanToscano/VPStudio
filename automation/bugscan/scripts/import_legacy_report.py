#!/usr/bin/env python3
"""
import_legacy_report.py — Bootstrap JSONL + lane state from the existing
marchVPStudioBugFixes.md markdown report.

Best-effort: preserves finding IDs, fields, lane metadata, and validation
events. Long-form notes are stored in lane state summary fields.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BUGSCAN_DIR = os.path.dirname(SCRIPT_DIR)
PROJECT_ROOT = os.path.dirname(os.path.dirname(BUGSCAN_DIR))
REPORT_PATH = os.path.join(PROJECT_ROOT, "marchVPStudioBugFixes.md")

FINDINGS_DIR = os.path.join(BUGSCAN_DIR, "findings")
STATE_DIR = os.path.join(BUGSCAN_DIR, "state")
VALIDATION_DIR = os.path.join(BUGSCAN_DIR, "validation")


def read_report(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------------------
# Lane status parsing
# ---------------------------------------------------------------------------

def extract_between(text, start_marker, end_marker):
    """Return content between HTML comment markers (exclusive)."""
    s = text.find(start_marker)
    e = text.find(end_marker)
    if s == -1 or e == -1:
        return ""
    return text[s + len(start_marker):e].strip()


def parse_lane_status(block):
    """Parse a lane status block into a dict."""
    state = {}

    def grab(key, line):
        m = re.match(rf"^-\s+{key}:\s*(.+)$", line)
        if m:
            state[key] = m.group(1).strip()
            return True
        return False

    lines = block.split("\n")
    i = 0
    notes_blocks = []
    current_notes = []
    in_notes = False

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("- notes: |"):
            if in_notes and current_notes:
                notes_blocks.append("\n".join(current_notes).strip())
            in_notes = True
            current_notes = []
            i += 1
            continue

        if in_notes:
            if stripped.startswith("- ") and not stripped.startswith("- `"):
                # Could be a new YAML key or a new notes block
                if re.match(r"^-\s+\w+:", stripped):
                    notes_blocks.append("\n".join(current_notes).strip())
                    in_notes = False
                    # Fall through to parse this line as a key
                else:
                    current_notes.append(stripped)
                    i += 1
                    continue
            else:
                current_notes.append(stripped)
                i += 1
                continue

        if not in_notes:
            for key in ["scope", "owner_model", "last_scan",
                        "no_new_valid_bug_streak", "saturation_state"]:
                if grab(key, stripped):
                    break
            else:
                # paths list
                if stripped.startswith("- `") and "paths" not in state:
                    pass  # handled below
                if stripped == "- paths:":
                    paths = []
                    i += 1
                    while i < len(lines):
                        pl = lines[i].strip()
                        m = re.match(r"^-\s+`(.+?)`", pl)
                        if m:
                            paths.append(m.group(1))
                            i += 1
                        else:
                            break
                    state["paths"] = paths
                    continue
        i += 1

    if in_notes and current_notes:
        notes_blocks.append("\n".join(current_notes).strip())

    state["notes"] = notes_blocks
    return state


# ---------------------------------------------------------------------------
# Finding parsing
# ---------------------------------------------------------------------------

def parse_findings(block):
    """Parse a findings block into a list of finding dicts."""
    findings = []
    lines = block.split("\n")
    i = 0

    while i < len(lines):
        line = lines[i].strip()

        # Match finding header: - `[LANE-X-YYYY-MM-DD-X-NNN] Title`
        m = re.match(r'^-\s+`\[([^\]]+)\]\s+(.+?)`\s*$', line)
        if m:
            finding = {
                "id": m.group(1),
                "title": m.group(2),
                "confidence": "",
                "paths": [],
                "why_it_is_a_bug": "",
                "trigger_or_repro": "",
                "impact": "",
                "evidence": "",
            }
            i += 1

            # Parse indented fields
            while i < len(lines):
                fl = lines[i].strip()
                if not fl or (fl.startswith("- `[") and re.match(r'^-\s+`\[', fl)):
                    break

                for field in ["confidence", "why_it_is_a_bug",
                              "trigger_or_repro", "impact", "evidence"]:
                    fm = re.match(rf"^-\s+{field}:\s*(.+)$", fl)
                    if fm:
                        val = fm.group(1).strip()
                        # Collect continuation lines
                        i += 1
                        while i < len(lines):
                            cont = lines[i].strip()
                            if not cont or cont.startswith("- "):
                                break
                            val += " " + cont
                            i += 1
                        finding[field] = val
                        break
                else:
                    # paths field
                    pm = re.match(r"^-\s+paths:\s*(.+)$", fl)
                    if pm:
                        raw = pm.group(1).strip()
                        finding["paths"] = [
                            p.strip().strip("`").strip(",").strip()
                            for p in re.split(r"`,\s*`|`\s*,\s*`", raw)
                            if p.strip().strip("`").strip()
                        ]
                        i += 1
                    else:
                        i += 1

            findings.append(finding)
        else:
            i += 1

    return findings


# ---------------------------------------------------------------------------
# Validation notes parsing
# ---------------------------------------------------------------------------

def parse_validation_notes(block):
    """Parse validation notes into a list of event dicts."""
    events = []
    lines = block.split("\n")
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("- **") or stripped.startswith("**"):
            # e.g. - **C-003 validation (2026-03-31 Run 3):** ...
            m = re.match(
                r'^-?\s*\*\*(.+?)\*\*:?\s*(.*)$', stripped
            )
            if m:
                header = m.group(1).strip()
                body = m.group(2).strip()
                # Try to extract finding ID
                fid_m = re.match(r'^([A-C]-\d{3})', header)
                finding_id = fid_m.group(1) if fid_m else None
                events.append({
                    "type": "revalidated",
                    "findingId": finding_id,
                    "header": header,
                    "detail": body,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "source": "legacy_import",
                })
    return events


# ---------------------------------------------------------------------------
# State construction
# ---------------------------------------------------------------------------

def build_lane_state(lane_id, status_dict, finding_count):
    """Build a lane state JSON object."""
    streak = 0
    try:
        streak = int(status_dict.get("no_new_valid_bug_streak", "0"))
    except (ValueError, TypeError):
        pass

    scan_mode = "cool" if status_dict.get("saturation_state") == "SATURATED_FOR_NOW" else "hot"

    # Combine notes into a summary (most recent first)
    notes = status_dict.get("notes", [])
    summary = notes[0] if notes else ""

    return {
        "laneId": lane_id,
        "scope": status_dict.get("scope", ""),
        "relevantPaths": status_dict.get("paths", []),
        "lastScanAt": status_dict.get("last_scan", None),
        "lastScannedCommit": None,
        "noNewValidBugStreak": streak,
        "saturationState": status_dict.get("saturation_state", "ACTIVE"),
        "scanMode": scan_mode,
        "findingCount": finding_count,
        "ownerModel": status_dict.get("owner_model", "minimax"),
        "lastSummary": summary,
        "priorNotes": notes[1:] if len(notes) > 1 else [],
    }


def build_validator_state():
    return {
        "lastRunAt": None,
        "totalEventsProcessed": 0,
        "lastReportRenderAt": None,
    }


def build_manager_state():
    return {
        "lastRunAt": None,
        "lastInspectedCommit": None,
        "lanesReactivated": [],
    }


# ---------------------------------------------------------------------------
# Write helpers
# ---------------------------------------------------------------------------

def write_jsonl(path, items):
    with open(path, "w", encoding="utf-8") as f:
        for item in items:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")


def write_json(path, obj):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    report_path = sys.argv[1] if len(sys.argv) > 1 else REPORT_PATH
    if not os.path.exists(report_path):
        print(f"ERROR: Report not found at {report_path}")
        sys.exit(1)

    print(f"Reading report from {report_path}")
    text = read_report(report_path)

    # --- Parse lane statuses ---
    lane_a_status_block = extract_between(text, "<!-- LANE_A_STATUS_START -->", "<!-- LANE_A_STATUS_END -->")
    lane_b_status_block = extract_between(text, "<!-- LANE_B_STATUS_START -->", "<!-- LANE_B_STATUS_END -->")
    lane_c_status_block = extract_between(text, "<!-- LANE_C_STATUS_START -->", "<!-- LANE_C_STATUS_END -->")

    lane_a_status = parse_lane_status(lane_a_status_block)
    lane_b_status = parse_lane_status(lane_b_status_block)
    lane_c_status = parse_lane_status(lane_c_status_block)

    # --- Parse findings ---
    lane_a_findings_block = extract_between(text, "<!-- LANE_A_FINDINGS_START -->", "<!-- LANE_A_FINDINGS_END -->")
    lane_b_findings_block = extract_between(text, "<!-- LANE_B_FINDINGS_START -->", "<!-- LANE_B_FINDINGS_END -->")
    lane_c_findings_block = extract_between(text, "<!-- LANE_C_FINDINGS_START -->", "<!-- LANE_C_FINDINGS_END -->")

    lane_a_findings = parse_findings(lane_a_findings_block)
    lane_b_findings = parse_findings(lane_b_findings_block)
    lane_c_findings = parse_findings(lane_c_findings_block)

    # --- Parse validation notes ---
    lane_a_val_block = extract_between(text, "<!-- LANE_A_VALIDATION_START -->", "<!-- LANE_A_VALIDATION_END -->")
    lane_b_val_block = extract_between(text, "<!-- LANE_B_VALIDATION_START -->", "<!-- LANE_B_VALIDATION_END -->")
    lane_c_val_block = extract_between(text, "<!-- LANE_C_VALIDATION_START -->", "<!-- LANE_C_VALIDATION_END -->")

    val_events = []
    for block in [lane_a_val_block, lane_b_val_block, lane_c_val_block]:
        val_events.extend(parse_validation_notes(block))

    # --- Write findings JSONL ---
    for findings, lane_file in [
        (lane_a_findings, "lane-a.jsonl"),
        (lane_b_findings, "lane-b.jsonl"),
        (lane_c_findings, "lane-c.jsonl"),
    ]:
        path = os.path.join(FINDINGS_DIR, lane_file)
        write_jsonl(path, findings)
        print(f"  Wrote {len(findings)} findings -> {lane_file}")

    # --- Write validation events ---
    val_path = os.path.join(VALIDATION_DIR, "events.jsonl")
    write_jsonl(val_path, val_events)
    print(f"  Wrote {len(val_events)} validation events -> events.jsonl")

    # --- Write lane states ---
    for lane_id, status, findings, fname in [
        ("a", lane_a_status, lane_a_findings, "lane-a.json"),
        ("b", lane_b_status, lane_b_findings, "lane-b.json"),
        ("c", lane_c_status, lane_c_findings, "lane-c.json"),
    ]:
        state = build_lane_state(lane_id, status, len(findings))
        path = os.path.join(STATE_DIR, fname)
        write_json(path, state)
        print(f"  Wrote lane state -> {fname}")

    # --- Write validator/manager states ---
    write_json(os.path.join(STATE_DIR, "validator.json"), build_validator_state())
    print("  Wrote validator.json")
    write_json(os.path.join(STATE_DIR, "manager.json"), build_manager_state())
    print("  Wrote manager.json")

    # --- Summary ---
    total = len(lane_a_findings) + len(lane_b_findings) + len(lane_c_findings)
    print(f"\nImport complete: {total} findings, {len(val_events)} validation events")
    print(f"  Lane A: {len(lane_a_findings)} findings, streak={lane_a_status.get('no_new_valid_bug_streak')}, state={lane_a_status.get('saturation_state')}")
    print(f"  Lane B: {len(lane_b_findings)} findings, streak={lane_b_status.get('no_new_valid_bug_streak')}, state={lane_b_status.get('saturation_state')}")
    print(f"  Lane C: {len(lane_c_findings)} findings, streak={lane_c_status.get('no_new_valid_bug_streak')}, state={lane_c_status.get('saturation_state')}")


if __name__ == "__main__":
    main()
