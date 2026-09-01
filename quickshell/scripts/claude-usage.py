#!/usr/bin/env python3
"""Real Claude usage/quota percentages, for the bar's AI Model Usage widget
(AiModelUsage.qml).

Claude Code's own status line ("You've used 97% of your session limit")
comes from Anthropic's OAuth usage endpoint, not from anything ccusage or
any `claude` subcommand exposes locally (both were checked and neither
has it — see git history for that investigation). Hitting that endpoint
directly, using the OAuth token Claude Code already stores in
~/.claude/.credentials.json, gives the exact same numbers — no message
sent, no tokens spent, just a plain usage query:

    GET https://api.anthropic.com/api/oauth/usage
    Authorization: Bearer <accessToken>
    anthropic-beta: oauth-2025-04-20
    User-Agent: claude-code/<version>   <- required; without it this
                                           endpoint 429s persistently,
                                           regardless of actual usage

Emits one JSON line:
    {"fiveHourPercent": 0-100, "fiveHourResetsAt": epoch,
     "weeklyPercent": 0-100, "weeklyResetsAt": epoch}
All fields are null if the check couldn't run (offline, expired
credentials, endpoint down, etc.) — the widget treats null as "unknown"
and falls back to showing nothing rather than a wrong number.
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

CREDENTIALS_PATH = "/home/mono/.claude/.credentials.json"
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"


def access_token():
    with open(CREDENTIALS_PATH, encoding="utf-8") as f:
        return json.load(f)["claudeAiOauth"]["accessToken"]


def claude_version():
    try:
        out = subprocess.run(["claude", "--version"], capture_output=True,
                              text=True, timeout=5).stdout
        return out.split()[0]
    except (OSError, subprocess.TimeoutExpired, IndexError):
        return "2.0.0"


def to_epoch(iso_timestamp):
    if not iso_timestamp:
        return None
    return int(datetime.fromisoformat(iso_timestamp).astimezone(timezone.utc).timestamp())


def fetch():
    req = urllib.request.Request(
        USAGE_URL,
        method="GET",
        headers={
            "Authorization": f"Bearer {access_token()}",
            "anthropic-beta": "oauth-2025-04-20",
            "Content-Type": "application/json",
            "User-Agent": f"claude-code/{claude_version()}",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)


def main():
    result = {"fiveHourPercent": None, "fiveHourResetsAt": None,
              "weeklyPercent": None, "weeklyResetsAt": None}
    try:
        data = fetch()
        five_hour = data.get("five_hour") or {}
        weekly = data.get("seven_day") or {}
        result["fiveHourPercent"] = five_hour.get("utilization")
        result["fiveHourResetsAt"] = to_epoch(five_hour.get("resets_at"))
        result["weeklyPercent"] = weekly.get("utilization")
        result["weeklyResetsAt"] = to_epoch(weekly.get("resets_at"))
    except (OSError, urllib.error.URLError, urllib.error.HTTPError,
            KeyError, ValueError, TypeError):
        pass
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
