#!/usr/bin/env python3
# Polls dnf and Flatpak for pending updates and caches the result to disk for
# the System Update bar widget (SystemUpdate.qml) -- same fetch-then-cache-
# to-JSON pattern as claude-usage.py/weather.py, so the widget can show the
# last known state instantly on quickshell startup instead of blanking out
# while this (network-bound, occasionally multi-second) script is still
# running.
import json
import os
import shutil
import subprocess
import time

CACHE_PATH = os.path.expanduser("~/.config/quickshell/system-update-cache.json")


def dnf_pending_count():
    # `dnf -q check-update` exit codes: 0 = no updates, 100 = updates
    # available, anything else = a real error (no network, broken repo,
    # metadata lock held by another dnf/rpm run, ...) -- only the first two
    # are a trustworthy count, so callers must treat everything else as
    # "unknown" rather than "zero".
    try:
        result = subprocess.run(
            ["dnf", "-q", "check-update"],
            capture_output=True, text=True, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None

    if result.returncode not in (0, 100):
        return None

    count = 0
    for line in result.stdout.splitlines():
        parts = line.split()
        # A real update line is "name.arch  version  repo" (3 fields, dotted
        # first field). The blank separator line and an "Obsoleting
        # Packages" section header/body never match that shape.
        if len(parts) == 3 and "." in parts[0]:
            count += 1
    return count


def flatpak_pending_count():
    # install.sh always installs the flatpak package itself (only individual
    # apps are optional), but this script also runs unmodified against
    # whatever's actually on disk, so a machine without it just reports zero
    # flatpak updates rather than an error.
    if shutil.which("flatpak") is None:
        return 0

    # `flatpak remote-ls --updates` looked like the obvious tool for this but
    # is unreliable: confirmed live it kept reporting several refs (e.g.
    # org.kde.kdenlive) as updatable purely because their remote commit hash
    # had changed, even right after `flatpak update --appstream` refreshed
    # the local summary cache -- while the real `flatpak update` (both
    # interactively and --noninteractive) consistently said "Nothing to
    # update" for the same refs. list_installed_refs_for_update() is the
    # actual libflatpak call `flatpak update`/GNOME Software use internally
    # to decide what's updatable, so it's the only thing guaranteed to agree
    # with what "Update All" (system-update-run.sh) will actually do.
    try:
        import gi
        gi.require_version("Flatpak", "1.0")
        from gi.repository import Flatpak, GLib
    except (ImportError, ValueError):
        return None

    total = 0
    try:
        for installation in (Flatpak.Installation.new_system(),
                              Flatpak.Installation.new_user()):
            total += len(installation.list_installed_refs_for_update())
    except GLib.Error:
        return None
    return total


def last_update_epoch():
    # Newest INSTALLTIME across every installed package -- a real epoch
    # straight from the rpm db, so no locale-dependent parsing of
    # `rpm -qa --last`'s human-readable date column is needed. Flatpak
    # updates aren't folded into this -- they don't touch the rpm db, and
    # dnf/rpm is what this figure is meant to track ("last updated" reads as
    # "last time the base system was patched").
    try:
        result = subprocess.run(
            ["rpm", "-qa", "--queryformat", "%{INSTALLTIME}\n"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    times = [int(line) for line in result.stdout.split() if line.isdigit()]
    return max(times) if times else None


def main():
    # On a transient failure (no wifi at boot, a repo hiccup), keep whatever
    # counts were last known good rather than flashing the widget to
    # "hidden" and back -- only a successful run for that source replaces
    # its count, independently of the other source.
    previous = {}
    try:
        with open(CACHE_PATH) as f:
            previous = json.load(f)
    except (OSError, json.JSONDecodeError):
        pass

    dnf_count = dnf_pending_count()
    flatpak_count = flatpak_pending_count()

    resolved_dnf = dnf_count if dnf_count is not None else previous.get("dnfCount")
    resolved_flatpak = flatpak_count if flatpak_count is not None else previous.get("flatpakCount")

    data = {
        "dnfCount": resolved_dnf,
        "flatpakCount": resolved_flatpak,
        "count": (resolved_dnf or 0) + (resolved_flatpak or 0),
        "lastCheckOk": dnf_count is not None and flatpak_count is not None,
        "lastUpdateEpoch": last_update_epoch(),
        "checkedAt": time.time(),
    }
    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    with open(CACHE_PATH, "w") as f:
        json.dump(data, f)
    print(json.dumps(data))


if __name__ == "__main__":
    main()
