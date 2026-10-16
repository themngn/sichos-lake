#!/usr/bin/env python3
"""A saved Wi-Fi network's password and "join this network" QR code, for the
Wi-Fi page's network details (modules/WifiMenu.qml) and the Hotspot page (the
hotspot is a saved network too).

  wifi-share.py password <ssid>    the password on stdout ("" = open network)
  wifi-share.py qr <ssid> <png>    the QR code (qrencode)

Found by SSID, not by profile name: NetworkManager names a profile after the
SSID, but "TP-Link 1"-style duplicates and renamed ones exist. The secret
comes from NetworkManager (`nmcli -s`; an active local session may read
system profiles' secrets without a prompt). Errors go to stderr, exit 1.
"""
import re, subprocess, sys


def fail(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def nmcli(*args):
    p = subprocess.run(["nmcli", *args], capture_output=True, text=True)
    if p.returncode != 0:
        fail((p.stderr or p.stdout).strip().splitlines()[-1] if (p.stderr or p.stdout).strip() else "nmcli failed")
    return p.stdout


def profile(ssid):
    """(key-mgmt, psk) of the saved profile for `ssid`, most recently used first."""
    best = None
    for line in nmcli("-t", "-f", "UUID,TYPE,TIMESTAMP", "connection", "show").splitlines():
        uuid, typ, ts = (line.split(":") + ["", "", ""])[:3]
        if typ != "802-11-wireless":
            continue
        if nmcli("-g", "802-11-wireless.ssid", "connection", "show", "uuid", uuid).strip() != ssid:
            continue
        if not best or int(ts or 0) > best[1]:
            best = (uuid, int(ts or 0))
    if not best:
        fail("Not a saved network")
    vals = nmcli("-s", "-g", "802-11-wireless-security.key-mgmt,802-11-wireless-security.psk",
                 "connection", "show", "uuid", best[0]).splitlines()
    # -g with two fields: one line each ("" when unset, e.g. an open network).
    vals += ["", ""]
    # nmcli -g escapes ":" and "\" in values.
    return vals[0], re.sub(r"\\(.)", r"\1", vals[1])


def password(ssid):
    mgmt, psk = profile(ssid)
    if mgmt in ("wpa-eap", "wpa-eap-suite-b-192", "ieee8021x"):
        fail("Signs in with an account, not a password")
    print(psk)


def qr(ssid, path):
    mgmt, psk = profile(ssid)
    if mgmt in ("wpa-eap", "wpa-eap-suite-b-192", "ieee8021x"):
        fail("Signs in with an account, can't be shared")
    # The de-facto Wi-Fi QR format (ZXing's; what phone cameras read), with
    # \ ; , : " escaped. WPA3-only (SAE) networks as "SAE", which is how
    # Android's own "Share" encodes them (a phone told "WPA" would try
    # WPA2 and fail); owe/none are open.
    esc = lambda v: re.sub(r'([\\;,:"])', r"\\\1", v)
    kind = "SAE" if mgmt == "sae" else "WPA" if psk else "nopass"
    data = f"WIFI:T:{kind};S:{esc(ssid)};" + (f"P:{esc(psk)};" if psk else "") + ";"
    # On stdin, so the password isn't in any process's argv.
    try:
        p = subprocess.run(["qrencode", "-o", path, "-s", "10", "-m", "2", "-l", "M"],
                           input=data, capture_output=True, text=True)
    except FileNotFoundError:
        fail("qrencode isn't installed")
    if p.returncode != 0:
        fail(p.stderr.strip() or "qrencode failed")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 2 and a[0] == "password":
        password(a[1])
    elif len(a) == 3 and a[0] == "qr":
        qr(a[1], a[2])
    else:
        fail(__doc__)
