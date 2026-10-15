#!/usr/bin/env python3
"""Proton VPN server list for the Control Center's VPN page (VpnPage.qml).

Reads the Proton app's own cached server list (26 MB, ~18k servers -- far too
much to JSON.parse in QML) and prints a compact summary:

    vpn-servers.py            -> {"tier", "countries": [{c, n, s, l, f, sc, cities: [[name, count]]}]}
    vpn-servers.py <CC>       -> {"c", "servers": [[name, city, load, features], ...]} fastest first,
                                 Secure Core servers exiting in <CC> last

Only servers the account can use (Tier <= MaxTier) and that are up count.
Feature bits are Proton's: 1 Secure Core, 2 Tor, 4 P2P, 8 Streaming, 16 IPv6.
"Fastest" is Proton's Score (lower is better), what `protonvpn connect` picks
by. The list is refreshed by the app/CLI (`protonvpn connect` updates it when
it's expired); this only reads it. Country names come from iso-codes.
"""
import json
import os
import sys

APP = os.path.expanduser("~/.var/app/com.protonvpn.www/cache/Proton/VPN/serverlist.json")
ISO = "/usr/share/iso-codes/json/iso_3166-1.json"

SECURE_CORE, TOR = 1, 2


def names():
    try:
        with open(ISO) as f:
            rows = json.load(f)["3166-1"]
    except (OSError, ValueError, KeyError):
        return {}
    out = {r["alpha_2"]: r.get("common_name") or r["name"] for r in rows}
    out["UK"] = out.get("GB", "United Kingdom")  # Proton's code for GB
    return out


def main():
    try:
        with open(APP) as f:
            data = json.load(f)
    except (OSError, ValueError):
        print(json.dumps({"error": "no server list"}))
        return
    tier = data.get("MaxTier", 0)
    usable = [s for s in data.get("LogicalServers", [])
              if s.get("Tier", 0) <= tier and s.get("Status")]

    if len(sys.argv) > 1:
        cc = sys.argv[1].upper()
        plain = [s for s in usable if s["ExitCountry"] == cc and not s["Features"] & (SECURE_CORE | TOR)]
        extra = [s for s in usable if s["ExitCountry"] == cc and s["Features"] & (SECURE_CORE | TOR)]
        key = lambda s: s.get("Score", 99)
        rows = sorted(plain, key=key) + sorted(extra, key=key)
        print(json.dumps({"c": cc, "servers": [
            [s["Name"], s.get("City") or "", s.get("Load", -1), s["Features"]] for s in rows]},
            separators=(",", ":")))
        return

    country_names = names()
    by = {}
    for s in usable:
        cc = s["ExitCountry"]
        e = by.setdefault(cc, {"c": cc, "n": country_names.get(cc, cc), "s": 0,
                               "_load": 0, "f": 0, "sc": 0, "_cities": {}})
        if s["Features"] & SECURE_CORE:
            e["sc"] += 1
            continue
        e["f"] |= s["Features"]
        if s["Features"] & TOR:
            continue
        e["s"] += 1
        e["_load"] += s.get("Load", 0)
        city = s.get("City") or ""
        if city:
            e["_cities"][city] = e["_cities"].get(city, 0) + 1
    countries = []
    for e in by.values():
        if e["s"] == 0 and e["sc"] == 0:
            continue
        e["l"] = round(e.pop("_load") / e["s"]) if e["s"] else -1
        e["cities"] = sorted(([k, v] for k, v in e.pop("_cities").items()), key=lambda kv: kv[0])
        countries.append(e)
    countries.sort(key=lambda e: e["n"])
    print(json.dumps({"tier": tier, "countries": countries}, separators=(",", ":")))


if __name__ == "__main__":
    main()
