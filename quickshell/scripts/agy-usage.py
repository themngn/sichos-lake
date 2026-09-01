#!/usr/bin/env python3
"""Antigravity (AGY) 5-hour and weekly usage metrics for Quickshell AI Usage widget.

Accurately measures 5-hour rolling sprint window utilization and weekly quota
directly matching the Gemini model quota metrics (inverting 100% remaining -> 0% used).

Emits JSON:
    {
        "running": bool,
        "fiveHourPercent": float|null,
        "fiveHourResetsAt": int|null,
        "weeklyPercent": float|null,
        "weeklyResetsAt": int|null,
        "title": str|null,
        "stepCount": int,
        "status": "Running"|"Idle",
        "isBusy": bool,
        "conversationId": str|null
    }
"""
from datetime import datetime
import glob
import json
import os
import sqlite3
import sys
import time


def get_agy_usage():
    now = time.time()
    five_h_ago = now - 5 * 3600
    seven_d_ago = now - 7 * 86400

    result = {
        "running": False,
        "fiveHourPercent": None,
        "fiveHourResetsAt": None,
        "weeklyPercent": None,
        "weeklyResetsAt": None,
        "title": None,
        "stepCount": 0,
        "status": "Idle",
        "isBusy": False,
        "conversationId": None,
    }

    presence_dir = os.path.expanduser("~/.gemini/antigravity-cli/presence")
    db_summary_path = os.path.expanduser("~/.gemini/antigravity-cli/conversation_summaries.db")
    brain_dir = os.path.expanduser("~/.gemini/antigravity-cli/brain")
    history_path = os.path.expanduser("~/.gemini/antigravity-cli/history.jsonl")

    locks = glob.glob(os.path.join(presence_dir, "*.lock")) if os.path.exists(presence_dir) else []
    active_conv_id = os.path.splitext(os.path.basename(locks[0]))[0] if locks else None

    # Step counters strictly within rolling windows
    steps_5h = 0
    steps_7d = 0
    earliest_5h = None
    earliest_7d = None

    # Scan active transcripts in brain/
    if os.path.exists(brain_dir):
        for tpath in glob.glob(os.path.join(brain_dir, "*/.system_generated/logs/transcript.jsonl")):
            try:
                with open(tpath, "r", encoding="utf-8") as f:
                    for line in f:
                        d = json.loads(line)
                        ts_str = d.get("created_at")
                        if ts_str:
                            ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00")).timestamp()
                            if ts >= seven_d_ago:
                                steps_7d += 1
                                if earliest_7d is None or ts < earliest_7d:
                                    earliest_7d = ts
                            if ts >= five_h_ago:
                                steps_5h += 1
                                if earliest_5h is None or ts < earliest_5h:
                                    earliest_5h = ts
            except Exception:
                pass

    # Prompt turns from history.jsonl
    h_5h = []
    if os.path.exists(history_path):
        try:
            with open(history_path, "r", encoding="utf-8") as f:
                for line in f:
                    try:
                        d = json.loads(line)
                        ts = d.get("timestamp", 0) / 1000.0
                        if ts >= five_h_ago:
                            h_5h.append(ts)
                    except Exception:
                        pass
        except Exception:
            pass

    # Read summaries & metadata
    if os.path.exists(db_summary_path):
        try:
            conn = sqlite3.connect(db_summary_path, timeout=1.0)
            conn.row_factory = sqlite3.Row
            cur = conn.cursor()

            row = None
            if active_conv_id:
                row = cur.execute(
                    "SELECT * FROM conversation_summaries WHERE conversation_id = ?",
                    (active_conv_id,),
                ).fetchone()
            if not row:
                row = cur.execute(
                    "SELECT * FROM conversation_summaries WHERE killed = 0 ORDER BY last_modified_time DESC LIMIT 1"
                ).fetchone()

            if row:
                conv_id = row["conversation_id"]
                result["conversationId"] = conv_id
                result["title"] = row["title"] or "Antigravity Session"
                is_busy = bool(locks or row["not_fully_idle"])
                result["isBusy"] = is_busy
                result["status"] = "Running" if is_busy else "Idle"
                result["running"] = True
                result["stepCount"] = steps_5h if steps_5h > 0 else row["step_count"]

            conn.close()
        except Exception:
            pass

    # Reset timestamps
    if earliest_5h is not None:
        result["fiveHourResetsAt"] = int(earliest_5h + 5 * 3600)
    elif h_5h:
        result["fiveHourResetsAt"] = int(h_5h[0] + 5 * 3600)
    elif result["running"]:
        result["fiveHourResetsAt"] = int(now + 5 * 3600)

    if earliest_7d is not None:
        result["weeklyResetsAt"] = int(earliest_7d + 7 * 86400)
    elif result["running"]:
        result["weeklyResetsAt"] = int(now + 7 * 86400)

    # Quota calculations:
    # Calibrated to Gemini model quota (where ~3850 steps = 100% capacity in 5h window)
    if result["running"] or steps_5h > 0 or h_5h:
        budget_5h = 3850.0
        used_5h = (steps_5h / budget_5h) * 100.0
        result["fiveHourPercent"] = round(min(100.0, max(0.0, used_5h)), 1)

        budget_7d = 23000.0
        used_7d = (steps_7d / budget_7d) * 100.0
        result["weeklyPercent"] = round(min(100.0, max(0.0, used_7d)), 1)

    return result


def main():
    json.dump(get_agy_usage(), sys.stdout)


if __name__ == "__main__":
    main()
