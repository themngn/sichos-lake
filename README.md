# SichOS

A personal Hyprland desktop for Fedora: Lua-configured Hyprland, a quickshell bar / launcher / Control
Center, SDDM and Plymouth themes, and the scripts that put it all in place.

## Install (once per machine)

```sh
git clone git@github.com:themngn/sichos-lake.git
cd sichos-lake
./sichos-setup.sh      # interactive: pick options, then it runs install.sh
# or: ./install.sh [--vm] [--alt]
```

The install scripts are for the **first install only**.

## Update

```sh
git pull
```

Git hooks deploy whatever changed onto the running session — no re-install, no restart. Your local
edits and UI settings are never overwritten. Seeing a change live before committing, switching between
versions, system files (`./update.sh system`) and the Control Center's Version tile:
**[UPDATING.md](UPDATING.md)**.

## More

- [CLAUDE.md](CLAUDE.md) — architecture and conventions (written for AI coding agents, useful for anyone)
- [TODO.md](TODO.md) — known workarounds that aren't real fixes yet
