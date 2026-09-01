#!/usr/bin/env bash
# Prints one line per installed locale (from `locale -a`) as
# name|decimal_point|thousands_sep|currency_symbol.
#
# A bare locale code like "en_GB.utf8" doesn't tell a human what it
# actually produces, so the launcher's Time & Region screen (TimeRegion.qml)
# and sichos-setup.sh's installer TUI both shell out to this to show a real
# preview instead ("1,234.56", "£") — these are genuine glibc-derived facts
# about each locale, not guesses. 12-hour vs 24-hour time isn't a locale
# fact worth picking this way (see ClockWidget.qml/TimeRegion.use24Hour
# instead) — that's a plain on/off display preference, not a locale.
set -uo pipefail

locale -a | while read -r loc; do
    dp=$(LC_NUMERIC="$loc" locale -k LC_NUMERIC 2>/dev/null | sed -n 's/^decimal_point="\(.*\)"/\1/p')
    ts=$(LC_NUMERIC="$loc" locale -k LC_NUMERIC 2>/dev/null | sed -n 's/^thousands_sep="\(.*\)"/\1/p')
    cur=$(LC_MONETARY="$loc" locale -k LC_MONETARY 2>/dev/null | sed -n 's/^currency_symbol="\(.*\)"/\1/p')
    printf '%s|%s|%s|%s\n' "$loc" "$dp" "$ts" "$cur"
done
