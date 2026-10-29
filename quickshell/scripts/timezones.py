#!/usr/bin/env python3
# Every time zone a person would pick, for the launcher's Date & Time
# screen (TimeRegion.qml), one JSON list: [{id, city, country, note,
# offset ("+02:00"), abbr ("EET")}], sorted by current UTC offset, then
# city. zone.tab gives each canonical zone its country (and a note like
# "most of Spain"); zones only in `timedatectl list-timezones` -- legacy
# aliases such as Europe/Kiev or US/Eastern, and Etc/* -- are left out,
# except UTC, so every city shows once.
import datetime
import json
import zoneinfo

ZI = "/usr/share/zoneinfo/"
countries = {}
with open(ZI + "iso3166.tab", encoding="utf-8") as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        code, name = line.rstrip("\n").split("\t")[:2]
        countries[code] = name

now = datetime.datetime.now(datetime.timezone.utc)


def entry(tz, city, country, note):
    local = now.astimezone(zoneinfo.ZoneInfo(tz))
    off = local.utcoffset()
    mins = int(off.total_seconds() // 60)
    sign = "+" if mins >= 0 else "-"
    mins = abs(mins)
    abbr = local.tzname() or ""
    # Zones with no abbreviation of their own report the offset ("+04").
    if abbr[:1] in "+-":
        abbr = ""
    return {"id": tz, "city": city, "country": country, "note": note,
            "offset": "%s%02d:%02d" % (sign, mins // 60, mins % 60),
            "minutes": (1 if sign == "+" else -1) * mins, "abbr": abbr}


zones = [entry("UTC", "UTC", "Coordinated Universal Time", "")]
with open(ZI + "zone.tab", encoding="utf-8") as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        code, tz = parts[0], parts[2]
        note = parts[3] if len(parts) > 3 else ""
        try:
            zones.append(entry(tz, tz.split("/")[-1].replace("_", " "), countries.get(code, code), note))
        except (zoneinfo.ZoneInfoNotFoundError, ValueError):
            pass
zones.sort(key=lambda z: (z["minutes"], z["city"]))
print(json.dumps(zones, ensure_ascii=False))
