#!/usr/bin/env bash
# Prints one line per installed locale (from `locale -a`) as
# name|decimal_point|thousands_sep|currency_symbol|lang_name|country_name|date|currency_code
# (lang_name is glibc's own, in that language: "English", "українська";
# date is Dec 31 of this year in the locale's short date format, a day
# past 12 so the day/month order shows).
#
# A bare locale code like "en_GB.utf8" doesn't tell a human what it
# actually produces, so the launcher's Time & Region screen (TimeRegion.qml)
# and sichos-setup.sh's installer TUI both shell out to this to show a real
# preview instead ("1,234.56", "£", "31/12/26") — these are genuine
# glibc-derived facts about each locale, not guesses. 12-hour vs 24-hour time isn't a locale
# fact worth picking this way (see ClockWidget.qml/TimeRegion.use24Hour
# instead) — that's a plain on/off display preference, not a locale.
# New fields go at the end: sichos-setup.sh reads the first four.
set -uo pipefail

dec31="$(date +%Y)-12-31"
locale -a | while read -r loc; do
    declare -A k=()
    while IFS='=' read -r key val; do
        val=${val#\"}; k[$key]=${val%\"}
    done < <(LC_ALL="$loc" locale -k decimal_point thousands_sep currency_symbol lang_name country_name int_curr_symbol 2>/dev/null)
    d=$(LC_ALL="$loc" date -d "$dec31" +%x 2>/dev/null)
    cc=${k[int_curr_symbol]-}
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$loc" "${k[decimal_point]-}" "${k[thousands_sep]-}" "${k[currency_symbol]-}" \
        "${k[lang_name]-}" "${k[country_name]-}" "$d" "${cc// /}"
    unset k
done
