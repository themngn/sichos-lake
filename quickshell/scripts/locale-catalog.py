#!/usr/bin/env python3
# Every locale this system could use, installed or not, with English names,
# for the launcher's Language & Region pickers (TimeRegion.qml): one JSON
# list of {locale, lang, country, langName, countryName, variant, pkg,
# installed}. Fedora ships glibc's locales split into per-language
# packages (glibc-langpack-uk, ...); which locales each one holds comes
# from the repo metadata's file lists (`dnf repoquery -l`, ~0.4s from the
# cache). Picking a locale that isn't installed installs its package first
# (TimeRegion.install). Names come from iso-codes (ISO 639 / 3166), not
# glibc's own, which is in the locale's language ("українська", "Sverige").
#
# One entry per language_COUNTRY[@variant]: its UTF-8 form (".utf8", or the
# bare name where that's all there is -- those are UTF-8 only); @euro
# variants are legacy duplicates and left out. Without dnf metadata (offline,
# no cache) this still lists what `locale -a` has.
import json
import re
import subprocess

ISO = "/usr/share/iso-codes/json/"


def load(name, key, code):
    try:
        with open(ISO + name, encoding="utf-8") as f:
            return {e[code]: e for e in json.load(f)[key] if code in e}
    except OSError:
        return {}


countries = load("iso_3166-1.json", "3166-1", "alpha_2")
langs2 = load("iso_639-3.json", "639-3", "alpha_2")
langs3 = load("iso_639-3.json", "639-3", "alpha_3")
VARIANTS = {"latin": "Latin", "cyrillic": "Cyrillic", "devanagari": "Devanagari", "valencia": "Valencian",
            "saaho": "Saho", "abegede": "Abegede", "iqtelif": "IQTElif"}

pkg_of = {}
try:
    out = subprocess.run(["dnf", "repoquery", "-q", "--qf", "%{name}\t%{files}\n", "glibc-langpack-*"],
                         capture_output=True, text=True, timeout=60).stdout
    pkg = None
    for line in out.splitlines():
        m = re.match(r"(glibc-langpack-[\w-]+)", line)
        if m:
            pkg = m.group(1)
            continue
        m = re.match(r"/usr/lib/locale/([^/]+)$", line)
        if m and pkg:
            pkg_of[m.group(1)] = pkg
except (OSError, subprocess.TimeoutExpired):
    pass

installed = set(subprocess.run(["locale", "-a"], capture_output=True, text=True).stdout.split())

best = {}
for loc in set(pkg_of) | installed:
    m = re.match(r"^([a-z]{2,3})_([A-Z]{2})(\.[\w-]+)?(@\w+)?$", loc)
    if not m:
        continue
    lang, country, enc, variant = m.group(1), m.group(2), (m.group(3) or "").lower(), (m.group(4) or "")[1:]
    if variant == "euro" or (enc and enc not in (".utf8", ".utf-8")):
        continue
    key = lang + "_" + country + ("@" + variant if variant else "")
    if key not in best or enc:
        best[key] = loc

entries = []
for key, loc in best.items():
    lang, rest = key.split("_", 1)
    country, _, variant = rest.partition("@")
    l = langs2.get(lang) or langs3.get(lang) or {}
    c = countries.get(country) or {}
    entries.append({
        "locale": loc, "lang": lang, "country": country,
        "langName": l.get("common_name") or l.get("name") or lang,
        "countryName": c.get("common_name") or c.get("name") or country,
        "variant": VARIANTS.get(variant, variant.capitalize()),
        "pkg": pkg_of.get(loc) or pkg_of.get(key) or "glibc-langpack-" + lang,
        "installed": loc in installed or key in installed,
    })
entries.sort(key=lambda e: (e["langName"], e["countryName"], e["variant"]))
print(json.dumps(entries, ensure_ascii=False))
