#!/usr/bin/env python3
"""Google Calendar for the hub (GoogleCalendar.qml): events for the month
grid's dots, the day agenda and reminders.

  gcal.py auth [client_secret.json]   sign in (run in a terminal)
  gcal.py fetch                       one JSON line, see below
  gcal.py status                      {"connected": bool}
  gcal.py logout                      forget the client + token

Talks to the Calendar API directly (stdlib urllib, read-only scope) with the
user's own OAuth client: Google has no keyless/public client for a desktop
app, so `auth` needs a "Desktop app" OAuth client from Cloud Console (the
downloaded client_secret_*.json; it looks in ~/Downloads by itself). Sign-in
is the installed-app loopback flow with PKCE: a one-shot HTTP listener on
127.0.0.1 catches the redirect. The client id/secret and the refresh token
live in the login keyring (`secret-tool ... sichos gcal-client` /
`gcal-token`, like the phone PIN), never in a file or on a command line.
`fetch` touches the keyring only once signed in (MARKER, see below).
NB: while the Cloud project's consent screen is in "Testing", Google expires
refresh tokens after 7 days -- publish it ("In production"; an unverified app
is fine for your own account) and sign in again after switching, or `fetch`
drops back to needsAuth weekly.

`fetch` emits
{
  "state": "ok" | "needsAuth" | "error",
  "error": str, "fetched": epoch ms, "stale": bool (cached data after an error),
  "events": [{"id", "title", "location", "link", "calendar", "color",
              "allDay": bool, "start": ms, "end": ms,
              "days": ["YYYY-MM-DD", ...],   local days it covers
              "remind": [ms, ...]}, ...]     popup reminders (Google's own)
}
Days are computed here, in local time, so QML never parses a date string
(`new Date("2026-11-14")` is UTC midnight in JS, the previous day west of
Greenwich); an all-day event's end.date is exclusive. Range: the start of
last month to six months ahead -- the month grid can be paged that far and
still show dots. Cancelled events and ones the user declined are left out.
The last good result is cached in CACHE_FILE (0600) and returned with
"stale" when offline, so the hub keeps its events through a quickshell
restart or a spell without network.
"""
import base64
import datetime as dt
import glob
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

SCOPE = "https://www.googleapis.com/auth/calendar.readonly"
AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/calendar/v3"
CACHE_FILE = os.path.expanduser("~/.cache/sichos/gcal.json")
# Non-secret "signed in" marker. `fetch` runs from quickshell's start and
# every 5 minutes; without a sign-in it must not touch the keyring at all:
# quickshell starts beside autostart.lua's gnome-keyring unlock, and a
# secrets client that wins that race D-Bus-activates a bare daemon, which
# makes a fresh "Default keyring" (see autostart.lua / CLAUDE.md's Keyring).
MARKER = os.path.expanduser("~/.config/quickshell/gcal-connected")


# --- keyring -----------------------------------------------------------------

def secret_get(key):
    try:
        r = subprocess.run(["secret-tool", "lookup", "sichos", key],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.stdout.strip() or None


def secret_set(key, label, value):
    # On stdin, not argv: argv is world-readable in /proc.
    subprocess.run(["secret-tool", "store", f"--label={label}", "sichos", key],
                   input=value, text=True, check=True, timeout=30)


def secret_clear(key):
    subprocess.run(["secret-tool", "clear", "sichos", key], timeout=10)


# --- HTTP --------------------------------------------------------------------

class AuthError(Exception):
    pass


class KeyringError(Exception):
    """Keyring not up yet / lookup failed -- transient, keep the cache."""


def post_form(url, fields):
    data = urllib.parse.urlencode(fields).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=15) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        try:
            body = json.load(e)
        except ValueError:
            body = {}
        # invalid_grant = revoked, expired (the 7-day "Testing" limit) or
        # the password changed; invalid_client = the client was deleted.
        if body.get("error") in ("invalid_grant", "invalid_client", "unauthorized_client"):
            raise AuthError(body.get("error_description") or body["error"])
        raise


def get_json(path, token, params=None):
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise AuthError("unauthorized")
        raise


def load_client():
    raw = secret_get("gcal-client")
    if not raw:
        return None
    try:
        c = json.loads(raw)
        return c if c.get("client_id") else None
    except ValueError:
        return None


def access_token():
    if not os.path.exists(MARKER):
        raise AuthError("not signed in")
    # The unlocked daemon's control socket; not there yet = still starting.
    if not os.path.exists(os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), "keyring", "control")):
        raise KeyringError("keyring not ready")
    client = load_client()
    refresh = secret_get("gcal-token")
    if not client or not refresh:
        # Signed in (marker) but nothing came back: a locked/slow keyring
        # more likely than a deleted secret -- logout removes the marker.
        raise KeyringError("keyring lookup failed")
    tok = post_form(TOKEN_URL, {
        "client_id": client["client_id"],
        "client_secret": client.get("client_secret", ""),
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    })
    return tok["access_token"]


# --- fetch -------------------------------------------------------------------

def parse_when(w):
    """(datetime aware local, all_day) from an event's start/end object."""
    if "date" in w:
        d = dt.date.fromisoformat(w["date"])
        return dt.datetime(d.year, d.month, d.day).astimezone(), True
    return dt.datetime.fromisoformat(w["dateTime"].replace("Z", "+00:00")).astimezone(), False


def day_keys(start, end, all_day):
    first = start.date()
    # The end is exclusive for both kinds; a timed event ending exactly at
    # midnight doesn't touch the next day.
    last = (end - dt.timedelta(microseconds=1)).date() if end > start else first
    out, d = [], first
    while d <= last and len(out) < 62:
        out.append(d.isoformat())
        d += dt.timedelta(days=1)
    return out


def ms(t):
    return int(t.timestamp() * 1000)


def fetch_live():
    token = access_token()
    colors = get_json("/colors", token).get("event", {})
    cals = []
    page = None
    while True:
        p = {"minAccessRole": "reader", "maxResults": 250}
        if page:
            p["pageToken"] = page
        res = get_json("/users/me/calendarList", token, p)
        cals += res.get("items", [])
        page = res.get("nextPageToken")
        if not page:
            break
    # The calendars ticked in Google Calendar's own sidebar.
    cals = [c for c in cals if c.get("selected") and not c.get("hidden")]

    now = dt.datetime.now().astimezone()
    lo = (now.replace(day=1, hour=0, minute=0, second=0, microsecond=0) - dt.timedelta(days=1)).replace(day=1)
    hi = lo + dt.timedelta(days=220)
    events = []
    for cal in cals:
        defaults = [r["minutes"] for r in cal.get("defaultReminders", []) if r.get("method") == "popup"]
        page = None
        while True:
            p = {"singleEvents": "true", "orderBy": "startTime", "maxResults": 2500,
                 "timeMin": lo.isoformat(), "timeMax": hi.isoformat()}
            if page:
                p["pageToken"] = page
            res = get_json("/calendars/" + urllib.parse.quote(cal["id"], safe="") + "/events", token, p)
            for ev in res.get("items", []):
                if ev.get("status") == "cancelled" or "start" not in ev:
                    continue
                if any(a.get("self") and a.get("responseStatus") == "declined"
                       for a in ev.get("attendees", [])):
                    continue
                start, all_day = parse_when(ev["start"])
                end, _ = parse_when(ev.get("end", ev["start"]))
                rem = ev.get("reminders", {})
                # The calendar's defaultReminders are for timed events; on an
                # all-day one they'd fire just before the previous midnight.
                if rem.get("useDefault", True):
                    mins = [] if all_day else defaults
                else:
                    mins = [r["minutes"] for r in rem.get("overrides", []) if r.get("method") == "popup"]
                events.append({
                    "id": cal["id"] + "/" + ev["id"],
                    "title": ev.get("summary") or "(No title)",
                    "location": ev.get("location", ""),
                    "link": ev.get("htmlLink", ""),
                    "calendar": cal.get("summaryOverride") or cal.get("summary", ""),
                    "color": colors.get(ev.get("colorId"), {}).get("background") or cal.get("backgroundColor", ""),
                    "allDay": all_day,
                    "start": ms(start),
                    "end": ms(end),
                    "days": day_keys(start, end, all_day),
                    "remind": sorted(ms(start - dt.timedelta(minutes=m)) for m in mins),
                })
            page = res.get("nextPageToken")
            if not page:
                break
    events.sort(key=lambda e: (e["start"], not e["allDay"], e["title"]))
    return events


def save_cache(result):
    try:
        os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
        tmp = CACHE_FILE + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(result, f)
        os.replace(tmp, CACHE_FILE)
    except OSError:
        pass


def load_cache():
    try:
        with open(CACHE_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def cmd_fetch():
    try:
        result = {"state": "ok", "error": "", "stale": False,
                  "fetched": ms(dt.datetime.now().astimezone()), "events": fetch_live()}
        save_cache(result)
    except AuthError as e:
        result = {"state": "needsAuth", "error": str(e), "stale": False, "fetched": 0, "events": []}
        # Signed out / revoked: the old events would be a lie from here on.
        try:
            os.remove(CACHE_FILE)
        except OSError:
            pass
    except Exception as e:  # offline, 5xx, rate limit...
        cached = load_cache()
        result = dict(cached or {"fetched": 0, "events": []},
                      state="ok" if cached else "error", error=str(e), stale=bool(cached))
    print(json.dumps(result))


# --- auth --------------------------------------------------------------------

def find_client_file(arg):
    if arg:
        return os.path.expanduser(arg)
    files = sorted(glob.glob(os.path.expanduser("~/Downloads/client_secret_*.json")),
                   key=os.path.getmtime, reverse=True)
    return files[0] if files else None


def read_client(path):
    with open(path, encoding="utf-8") as f:
        j = json.load(f)
    c = j.get("installed") or j.get("web") or {}
    if not c.get("client_id"):
        raise ValueError(f"{path}: no client_id (expected a Desktop app OAuth client)")
    return {"client_id": c["client_id"], "client_secret": c.get("client_secret", "")}


def cmd_auth(arg):
    path = find_client_file(arg)
    if path:
        print(f"Using OAuth client from {path}")
        client = read_client(path)
    else:
        client = load_client()
        if client:
            print("Using the OAuth client saved in the keyring.")
        else:
            print("No client_secret_*.json in ~/Downloads. Paste the Desktop app client's values:")
            import getpass
            cid = input("Client ID: ").strip()
            csec = getpass.getpass("Client secret: ").strip()
            client = {"client_id": cid, "client_secret": csec}

    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    got = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if "code" not in q and "error" not in q:
                self.send_response(404)
                self.end_headers()
                return
            got.update({k: v[0] for k, v in q.items()})
            ok = "code" in q and q.get("state", [""])[0] == state
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "SichOS is connected to Google Calendar. You can close this tab." if ok \
                else "Sign-in failed: " + q.get("error", ["state mismatch"])[0]
            self.wfile.write(f"<html><body style='font-family:sans-serif'><h2>{msg}</h2></body></html>".encode())

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    srv.timeout = 300
    redirect = f"http://127.0.0.1:{srv.server_port}"
    url = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": client["client_id"], "redirect_uri": redirect, "response_type": "code",
        "scope": SCOPE, "access_type": "offline", "prompt": "consent",
        "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
    })
    print("\nOpening the browser to sign in. If it doesn't open, visit:\n\n" + url + "\n")
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # handle_request() also returns for stray requests (a favicon) and on
    # srv.timeout, so loop on a deadline rather than one call.
    import time
    deadline = time.monotonic() + 300
    while not got and time.monotonic() < deadline:
        srv.handle_request()
    if not got:
        print("Timed out waiting for the browser.")
        return 1
    srv.server_close()
    if got.get("state") != state or "code" not in got:
        print("Sign-in failed:", got.get("error", "state mismatch"))
        return 1

    tok = post_form(TOKEN_URL, {
        "client_id": client["client_id"], "client_secret": client["client_secret"],
        "code": got["code"], "code_verifier": verifier, "redirect_uri": redirect,
        "grant_type": "authorization_code",
    })
    if not tok.get("refresh_token"):
        print("Google returned no refresh token; try again.")
        return 1
    secret_set("gcal-client", "SichOS Google Calendar client", json.dumps(client))
    secret_set("gcal-token", "SichOS Google Calendar token", tok["refresh_token"])
    open(MARKER, "w").close()
    try:
        events = fetch_live()
    except urllib.error.HTTPError as e:
        # Most likely 403 accessNotConfigured: the Calendar API isn't
        # enabled in the Cloud project. The sign-in itself is kept.
        print(f"Signed in, but the Calendar API answered {e.code}:\n{e.read().decode(errors='replace')}")
        print("Enable the Google Calendar API for this project in Cloud Console, then the hub picks it up.")
        return 1
    save_cache({"state": "ok", "error": "", "stale": False,
                "fetched": ms(dt.datetime.now().astimezone()), "events": events})
    print(f"Connected: {len(events)} events loaded.")
    subprocess.run(["quickshell", "ipc", "call", "calendar", "refresh"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "fetch"
    if cmd == "fetch":
        cmd_fetch()
    elif cmd == "auth":
        sys.exit(cmd_auth(sys.argv[2] if len(sys.argv) > 2 else None))
    elif cmd == "status":
        print(json.dumps({"connected": os.path.exists(MARKER)}))
    elif cmd == "logout":
        secret_clear("gcal-token")
        secret_clear("gcal-client")
        for f in (CACHE_FILE, MARKER):
            try:
                os.remove(f)
            except OSError:
                pass
        subprocess.run(["quickshell", "ipc", "call", "calendar", "refresh"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
