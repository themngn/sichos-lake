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


def dnf_pending_updates():
    # `dnf -q check-update` exit codes: 0 = no updates, 100 = updates
    # available, anything else = a real error (no network, broken repo,
    # metadata lock held by another dnf/rpm run, ...) -- only the first two
    # are a trustworthy list, so callers must treat everything else as
    # "unknown" rather than "nothing pending". Returns (name.arch, version)
    # pairs, one per update line.
    try:
        result = subprocess.run(
            ["dnf", "-q", "check-update"],
            capture_output=True, text=True, timeout=180,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None

    if result.returncode not in (0, 100):
        return None

    updates = []
    for line in result.stdout.splitlines():
        parts = line.split()
        # A real update line is "name.arch  version  repo" (3 fields, dotted
        # first field). The blank separator line, dnf5's "Upgrades" header
        # and an "Obsoleting Packages" section header/body never match that
        # shape.
        if len(parts) == 3 and "." in parts[0]:
            updates.append((parts[0], parts[1]))

    # check-update lists every newer build in the repos, including ones the
    # upgrade can't install -- seen live: an RPM Fusion
    # mesa-va-drivers-freeworld built against a mesa Fedora hadn't shipped
    # yet, a testing-repo telegram-desktop needing a library nothing
    # provided. `dnf upgrade` skips those ("Skipping packages with broken
    # dependencies"), so the widget showed "2 updates" that Update All
    # never applied. A dry run (no root needed) names exactly what it would
    # skip.
    skipped = dnf_skipped_upgrades() if updates else set()
    return [u for u in updates if u[0].rsplit(".", 1)[0] not in skipped]


def dnf_skipped_upgrades():
    try:
        result = subprocess.run(
            ["dnf", "upgrade", "--assumeno"],
            capture_output=True, text=True, timeout=180,
            env={**os.environ, "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return set()
    # dnf5's transaction table: a section header ("Skipping packages with
    # broken dependencies:", "... with conflicts:", "Upgrading:", ...), then
    # one " name arch version repo size" row per package.
    skipped = set()
    in_skip = False
    for line in (result.stdout + result.stderr).splitlines():
        if line.rstrip().endswith(":") and not line.startswith(" "):
            in_skip = line.startswith("Skipping packages")
        elif in_skip and line.startswith(" ") and line.split():
            skipped.add(line.split()[0])
        elif not line.strip():
            in_skip = False
    return skipped


def flatpak_pending_updates():
    # install.sh always installs the flatpak package itself (only individual
    # apps are optional), but this script also runs unmodified against
    # whatever's actually on disk, so a machine without it just reports zero
    # flatpak updates rather than an error.
    if shutil.which("flatpak") is None:
        return []

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

    refs = []
    try:
        for installation in (Flatpak.Installation.new_system(),
                              Flatpak.Installation.new_user()):
            refs.extend(installation.list_installed_refs_for_update())
    except GLib.Error:
        return None

    updates = []
    for ref in refs:
        # Runtimes/extensions (and some apps) ship no appdata, so the ref
        # name is the only label there is. The version column is the branch,
        # not a release number: the installed appdata version is the *old*
        # one, and the pending one isn't known without fetching the remote's
        # appstream data -- the branch at least tells "stable" apps apart
        # from runtime branches like "24.08".
        updates.append((ref.get_appdata_name() or ref.get_name(),
                        ref.get_branch() or ""))
    return updates


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


def reboot_needed():
    # `dnf needs-restarting -r` exit codes: 0 = nothing core changed since
    # boot, 1 = reboot needed. Anything else (plugin missing, a metadata
    # lock, ...) falls through to the kernel comparison below rather than
    # failing the whole check -- this is an extra hint, not the widget's
    # main job.
    try:
        result = subprocess.run(
            ["dnf", "needs-restarting", "-r"],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode in (0, 1):
            return result.returncode == 1
    except (OSError, subprocess.TimeoutExpired):
        pass

    # Fallback: only catches kernel updates (not glibc/systemd/...), but
    # that's the one that matters most. kernel-core carries the actual
    # vmlinuz, and its version-release.arch is exactly what `uname -r`
    # reports for it.
    try:
        result = subprocess.run(
            ["rpm", "-q", "kernel-core", "--last"],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    lines = result.stdout.split("\n")
    if result.returncode != 0 or not lines[0].startswith("kernel-core-"):
        return None
    newest = lines[0].split()[0][len("kernel-core-"):]
    return newest != os.uname().release


def dnf_rows(updates):
    # Dropping `.arch` makes multilib pairs (foo.i686 + foo.x86_64) identical
    # rows, so those collapse to one -- dnfCount still counts every update
    # line, matching what dnf itself reports.
    rows = []
    seen = set()
    for name_arch, version in sorted(updates, key=lambda u: u[0].lower()):
        name = name_arch.rsplit(".", 1)[0]
        if (name, version) not in seen:
            seen.add((name, version))
            rows.append({"name": name, "version": version, "kind": "dnf"})
    return rows


def flatpak_rows(updates):
    return [{"name": name, "version": version, "kind": "flatpak"}
            for name, version in sorted(updates, key=lambda u: u[0].lower())]


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

    dnf_updates = dnf_pending_updates()
    flatpak_updates = flatpak_pending_updates()
    dnf_count = len(dnf_updates) if dnf_updates is not None else None
    flatpak_count = len(flatpak_updates) if flatpak_updates is not None else None

    resolved_dnf = dnf_count if dnf_count is not None else previous.get("dnfCount")
    resolved_flatpak = flatpak_count if flatpak_count is not None else previous.get("flatpakCount")

    # Same per-source keep-last-known-good rule for the popup's package
    # list (absent in caches written before it existed -- then a failed
    # source just contributes no rows). dnf first; capped so a fresh
    # install's thousand-package backlog doesn't bloat the cache file and
    # every QML reload of it.
    previous_packages = previous.get("packages") or []
    packages = (
        (dnf_rows(dnf_updates) if dnf_updates is not None
         else [p for p in previous_packages if p.get("kind") == "dnf"])
        + (flatpak_rows(flatpak_updates) if flatpak_updates is not None
           else [p for p in previous_packages if p.get("kind") == "flatpak"])
    )[:200]

    reboot = reboot_needed()
    if reboot is None:
        reboot = bool(previous.get("rebootNeeded", False))

    data = {
        "dnfCount": resolved_dnf,
        "flatpakCount": resolved_flatpak,
        "count": (resolved_dnf or 0) + (resolved_flatpak or 0),
        "packages": packages,
        "rebootNeeded": reboot,
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
