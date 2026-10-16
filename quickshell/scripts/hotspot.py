#!/usr/bin/env python3
"""Wi-Fi hotspot for the Control Center's Hotspot tile (modules/Hotspot.qml).

  hotspot.py status              one JSON line (see status())
  hotspot.py on shared|standalone
  hotspot.py off
  hotspot.py prepare             create the profile (name, password) if missing

Two ways to run it, both one NetworkManager profile ("SichOS Hotspot",
ipv4.method shared: NM's dnsmasq hands out addresses and NATs to whatever
the laptop is online through):

- shared: on the second interface udev/70-sichos-hotspot.rules creates
  (sichos-ap0), while the normal one stays connected -- the hotspot passes
  the laptop's own Wi-Fi on. Cards that can do both at once can do it on
  one channel only ("#channels <= 1" in `iw phy`), so the hotspot takes the
  Wi-Fi connection's channel -- and can't run at all when that's a DFS
  (radar) channel, 52-144, where an access point would need radar detection
  first; 6 GHz isn't attempted either. Checked here up front, so the tile
  can say why instead of showing NM's activation error.
- standalone: on the normal interface, replacing the Wi-Fi connection
  (devices on it get internet only if the laptop has another way online).

sichos-ap0 is unmanaged by NetworkManager/90-sichos-hotspot.conf and only
handed to NM ("managed yes", autoconnect off) for as long as the hotspot
runs; managed, NM would join saved networks on it as a second client.
Its QR code is wifi-share.py's, like any saved network's.
Errors go to stderr, exit 1.
"""
import json, re, secrets, socket, subprocess, sys

PROFILE = "SichOS Hotspot"
AP_PREFIX = "sichos-ap"


def run(*args, check=True):
    p = subprocess.run(args, capture_output=True, text=True)
    if check and p.returncode != 0:
        msg = (p.stderr or p.stdout).strip().splitlines()
        # nmcli: "Error: Connection activation failed: <why>" -> the why.
        fail(re.sub(r"^Error: (Connection activation failed: )?", "", msg[-1] if msg else f"{args[0]} failed"))
    return p.stdout


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def split_t(line):
    """One line of `nmcli -t` output: fields split at unescaped colons."""
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in re.split(r"(?<!\\):", line)]


def devices():
    out = []
    for line in run("nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device").splitlines():
        f = split_t(line)
        if len(f) >= 4 and f[1] == "wifi":
            out.append({"dev": f[0], "state": f[2], "conn": f[3]})
    return out


def freq_of(dev):
    m = re.search(r"freq: (\d+)", run("iw", "dev", dev, "link", check=False))
    return int(m.group(1)) if m else 0


def channel_of(freq):
    if freq == 2484:
        return 14
    if 2412 <= freq < 2484:
        return (freq - 2407) // 5
    if 5000 < freq < 5925:
        return (freq - 5000) // 5
    return 0


def share_problem(freq):
    """Why an access point can't sit on the Wi-Fi connection's channel, or ""."""
    ch = channel_of(freq)
    if freq >= 5925:
        return "Wi-Fi is on 6 GHz"
    if 5250 <= freq <= 5730:
        return f"Wi-Fi channel {ch} is a radar channel"
    if not ch:
        return "Unknown Wi-Fi channel"
    return ""


def profile_exists():
    return PROFILE in run("nmcli", "-t", "-f", "NAME", "connection", "show").splitlines()


def profile_secrets():
    if not profile_exists():
        return "", ""
    out = run("nmcli", "-s", "-t", "-f", "802-11-wireless.ssid,802-11-wireless-security.psk",
              "connection", "show", PROFILE, check=False)
    vals = {}
    for line in out.splitlines():
        k, _, v = line.partition(":")
        vals[k] = v
    return vals.get("802-11-wireless.ssid", ""), vals.get("802-11-wireless-security.psk", "")


def clients(dev):
    return len(re.findall(r"^Station ", run("iw", "dev", dev, "station", "dump", check=False), re.M))


def status():
    devs = devices()
    ap = next((d for d in devs if d["dev"].startswith(AP_PREFIX)), None)
    # The normal interface: the first other Wi-Fi device (p2p-dev-* is type wifi-p2p).
    sta = next((d for d in devs if not d["dev"].startswith(AP_PREFIX)), None)
    on = next((d for d in devs if d["conn"] == PROFILE and d["state"].startswith("connected")), None)
    starting = next((d for d in devs if d["conn"] == PROFILE and not d["state"].startswith("connected")), None)
    online = bool(sta and sta["state"].startswith("connected") and sta["conn"] != PROFILE)
    freq = freq_of(sta["dev"]) if online else 0
    ssid, psk = profile_secrets()
    problem = "" if not ap else "Wi-Fi isn't connected" if not online else share_problem(freq)
    print(json.dumps({
        "active": bool(on),
        "starting": bool(starting),
        "mode": "" if not on else "shared" if on["dev"].startswith(AP_PREFIX) else "standalone",
        "ssid": ssid,
        "password": psk,
        "clients": clients(on["dev"]) if on else 0,
        "wifiDevice": sta["dev"] if sta else "",
        "wifiConnected": online,
        "wifiName": sta["conn"] if online else "",
        "channel": channel_of(freq),
        # Sharing needs the extra interface (a card that can do both) and a
        # Wi-Fi connection on a channel an access point may use.
        "canShare": bool(ap) and online and not problem,
        "shareProblem": "This Wi-Fi card can't share" if not ap else problem,
    }))


def ensure_profile(dev):
    if profile_exists():
        return
    host = socket.gethostname().split(".")[0] or "sichos"
    # 12 characters, no look-alikes (0/O, 1/l/I): typed on a phone.
    psk = "".join(secrets.choice("abcdefghijkmnpqrstuvwxyz23456789") for _ in range(12))
    run("nmcli", "connection", "add", "type", "wifi", "con-name", PROFILE, "ifname", dev,
        "autoconnect", "no", "ssid", f"{host}-hotspot",
        "802-11-wireless.mode", "ap",
        # Its own MAC: sichos-ap0 is created with the card's address, the
        # same one the Wi-Fi connection uses.
        "802-11-wireless.cloned-mac-address", "stable",
        "ipv4.method", "shared", "ipv6.method", "ignore",
        "wifi-sec.key-mgmt", "wpa-psk", "wifi-sec.psk", psk,
        "wifi-sec.proto", "rsn", "wifi-sec.pairwise", "ccmp", "wifi-sec.group", "ccmp")


def turn_on(mode):
    devs = devices()
    ap = next((d for d in devs if d["dev"].startswith(AP_PREFIX)), None)
    sta = next((d for d in devs if not d["dev"].startswith(AP_PREFIX)), None)
    if not sta:
        fail("No Wi-Fi adapter")
    if mode == "shared":
        if not ap:
            fail("This Wi-Fi card can't share")
        if not (sta["state"].startswith("connected") and sta["conn"] != PROFILE):
            fail("Wi-Fi isn't connected")
        freq = freq_of(sta["dev"])
        problem = share_problem(freq)
        if problem:
            fail(problem)
        dev, ch = ap["dev"], channel_of(freq)
        band = "bg" if freq < 3000 else "a"
        run("nmcli", "device", "set", dev, "autoconnect", "no", "managed", "yes")
    else:
        # 5 GHz channel 36: fast, never a radar channel, allowed for an
        # access point almost everywhere.
        dev, band, ch = sta["dev"], "a", 36
    ensure_profile(dev)
    run("nmcli", "connection", "modify", PROFILE, "connection.interface-name", dev,
        "802-11-wireless.band", band, "802-11-wireless.channel", str(ch))
    p = subprocess.run(["nmcli", "--wait", "25", "connection", "up", PROFILE, "ifname", dev],
                       capture_output=True, text=True)
    if p.returncode != 0:
        if mode == "shared":
            run("nmcli", "device", "set", dev, "managed", "no", check=False)
        msg = (p.stderr or p.stdout).strip().splitlines()
        fail(re.sub(r"^Error: (Connection activation failed: )?", "", msg[-1] if msg else "Couldn't start"))


def turn_off():
    run("nmcli", "connection", "down", PROFILE, check=False)
    for d in devices():
        if d["dev"].startswith(AP_PREFIX) and d["state"] != "unmanaged":
            run("nmcli", "device", "set", d["dev"], "managed", "no", check=False)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        status()
    elif cmd == "on" and len(sys.argv) > 2 and sys.argv[2] in ("shared", "standalone"):
        turn_on(sys.argv[2])
    elif cmd == "off":
        turn_off()
    elif cmd == "prepare":
        sta = next((d for d in devices() if not d["dev"].startswith(AP_PREFIX)), None)
        if not sta:
            fail("No Wi-Fi adapter")
        ensure_profile(sta["dev"])
    else:
        fail(__doc__)
