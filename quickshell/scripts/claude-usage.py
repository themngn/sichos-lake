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
On a successful fetch this also overwrites CACHE_FILE, and a failed fetch
(offline, expired credentials, endpoint down, rate limited, etc.) falls
back to reading it instead of emitting nulls — mirrors weather.py's own
cache fallback, for the same reason: this re-runs from scratch on every
quickshell (re)start with no memory of its own, and the 180s poll interval
means a transient failure would otherwise blank the pill for a while.
Only emit all-null if there's truly nothing cached yet (e.g. first run
ever, never successfully reached the endpoint).
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

CREDENTIALS_PATH = os.path.expanduser("~/.claude/.credentials.json")
USAGE_URL = "https://api.anthropic.com/api/oauth/usage"
CACHE_FILE = os.path.expanduser("~/.config/quickshell/claude-usage-cache.json")
EMPTY_RESULT = {"fiveHourPercent": None, "fiveHourResetsAt": None,
                "weeklyPercent": None, "weeklyResetsAt": None}


def load_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            cached = json.load(f)
        if cached.get("fiveHourPercent") is not None:
            return cached
    except (OSError, ValueError, TypeError):
        pass
    return None


def save_cache(result):
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(result, f)
    except OSError:
        pass


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
    try:
        data = fetch()
        five_hour = data.get("five_hour") or {}
        weekly = data.get("seven_day") or {}
        result = {
            "fiveHourPercent": five_hour.get("utilization"),
            "fiveHourResetsAt": to_epoch(five_hour.get("resets_at")),
            "weeklyPercent": weekly.get("utilization"),
            "weeklyResetsAt": to_epoch(weekly.get("resets_at")),
        }
        save_cache(result)
    except (OSError, urllib.error.URLError, urllib.error.HTTPError,
            KeyError, ValueError, TypeError):
        result = load_cache() or dict(EMPTY_RESULT)
    json.dump(result, sys.stdout)


if __name__ == "__main__":
    main()
