# Updating SichOS

How a machine running SichOS gets config changes after the first install, how to see a change live
while working on it, and how to move between versions. Everything here goes through
[`update.sh`](update.sh) — the one place that knows where each repo file is deployed.

## Install once, update forever

| Script | When |
| --- | --- |
| `./sichos-setup.sh` / `./install.sh` | **First install of a machine only**: packages, repos, services, system files, your choices (`--vm`, `--alt`, browser, apps...). Don't re-run them to pick up config changes. |
| `update.sh` (via git hooks) | **Every change after that**: deploys what changed in the repo onto the running session. |

`install.sh` needs a git checkout (`git clone git@github.com:themngn/sichos-lake.git`). At the end it
deploys every config through `update.sh install`, turns on the git hooks, and records the deployed
version — from then on the machine updates itself.

## How updates happen

The hooks in [`githooks/`](githooks) (enabled with `git config core.hooksPath githooks`, which
`install.sh` does) run `update.sh` after every

- `git pull` / `git merge`
- `git commit` and `git commit --amend`
- `git rebase` / `git pull --rebase`
- `git checkout <branch>` / `git switch`

`update.sh` remembers which commit is deployed (`~/.local/state/sichos/deployed-rev`) and deploys only
the files that changed between that commit and the new one. Hyprland and quickshell pick the new files
up on their own (hot reload) — no restart, no re-login.

So on any SichOS machine, **updating is just `git pull`** in the checkout.

Only **committed** files are ever deployed — uncommitted edits in the repo stay where they are until you
commit them (or deploy them by hand, see below).

### What it will and won't touch

- **Your local edits are never overwritten.** If a deployed file was changed by hand (a fix you're
  testing, a deliberate local tweak), it's kept, and the new repo version is parked in
  `~/.local/state/sichos/update-conflicts/<repo path>` for you to merge. `./update.sh status` lists
  them; the parked copy disappears once the deployed file matches.
- **Settings stay yours.** Things the shell's own UI saves inside config files are carried over into
  each new version: terminal transparency (`kitty.conf`), the Night Light schedule
  (`hyprsunset.conf`), idle timeouts (`hypridle.conf`) — and `install.sh`'s per-machine choices
  (`--alt`, `--vm`, the default browser).
- **`monitors.lua` is per-machine** and never replaced once it exists.
- **Files removed from the repo** are removed from `~/.config` too — but only if you never edited them.
- **System files** (SDDM, Plymouth, polkit, kernel-install, firewalld, root's zsh, new `packages.txt`
  entries) need `sudo`, which a hook can't ask for. The hook only tells you (and shows a notification);
  apply them with `./update.sh system` — see below.
- Each file is replaced atomically, so a hot reload never sees a half-written file. If a file can't be
  written, the deployed version stays where it was and the next run retries.

## Seeing a change live while you work

Committing deploys a change — but you don't have to commit to try something out:

```sh
./update.sh try                      # deploy every uncommitted change to a config file, now
./update.sh try quickshell/modules   # ...or only under some paths
```

`try` takes the repo's **working tree** — edited files, new (untracked) files, deleted files — and deploys
them the same careful way a normal update does: new files first and `Theme.qml` before the rest (so
quickshell's hot reload sees a complete tree), your UI settings carried over, and a check that
quickshell really reloaded. Edit more, run `try` again; a file you reverted in the repo goes back to its
committed version on the next `try`. The Version tile shows `N uncommitted live` meanwhile, and
`./update.sh status` lists the files.

When you're done:

- **Keep it — commit.** The hook sees the deployed files already match and just stops counting them as
  live. Files you haven't committed yet stay live through commits and pulls (the hook prints
  `kept live`, it doesn't treat them as conflicts).
- **Drop it — `./update.sh undo`.** Puts every file `try` deployed back to the deployed commit's
  version (restores deleted files, removes new ones). `./update.sh undo <path>` for just some.

Safety:

- `try` only replaces a deployed file that's untouched or that an earlier `try` put there. One with
  local edits that didn't come from the repo is kept and reported; `try --force <path>` replaces it
  (backup as `<name>.bak`).
- `undo` keeps a file you edited by hand *after* trying it; `undo --force <path>` replaces it
  (with a `.bak`).
- `./update.sh undo --all` also puts back every *other* deployed file that differs from the deployed
  commit — leftovers from hand-copying or old experiments. It lists them and asks first (`--yes` to
  skip the question); each gets a `.bak`.
- System files are never tried (they need sudo): commit them, then `./update.sh system`.
- While anything is live, `./update.sh switch` refuses — commit or undo first.

Copying a file by hand (`cp quickshell/modules/Bar.qml ~/.config/quickshell/modules/`) still works, and
so does editing the deployed file directly. Just know that `update.sh` can't tell those from local edits:
`status` lists them as `modified`, updates keep them, and `undo --all` is how to put them back.

Tips:

- quickshell only watches files it has already loaded: a brand-new `.qml` file copied by hand reloads
  nothing (`try` handles this). Force a reload with `quickshell ipc call shell reload` — touching
  `shell.qml` does **not** reload; quickshell reacts to content changes only.
- Did it load? `quickshell log --pid "$(pgrep -xo quickshell)" | tail` — look for
  `Configuration Loaded` after the last `Reloading configuration...`.

## Commands

```sh
./update.sh                 # deploy HEAD (what the hooks run); also un-pins
./update.sh status          # what's deployed, pending system changes, parked edits, drift
./update.sh list [n]        # recent commits: * = deployed, H = HEAD
./update.sh switch <rev>    # deploy any commit / tag / branch, without checking it out (pins it)
./update.sh back            # go back to the version deployed before this one
./update.sh latest          # follow HEAD again
./update.sh try [paths]     # deploy uncommitted changes now, to see them live (--force: over local edits)
./update.sh undo [paths]    # put back what try deployed (--all: every differing file, asks; --yes)
./update.sh system          # apply pending system-level changes (asks for sudo)
./update.sh info            # one JSON line about the deployed version (the Version tile uses it)
./update.sh install         # first install: deploy every config (install.sh runs this)
./update.sh mark [rev]      # record <rev> as deployed without copying anything
./update.sh system mark [rev]   # same, for the system files
```

`./update.sh --help` prints the full description from the script itself.

## Switching versions

`./update.sh switch <rev>` deploys any version — a commit hash, a tag, another branch — onto the running
session without touching your checkout. The same rules apply (local edits kept, settings carried over).

While a switched-to version is live, it's **pinned**: the hooks stop following HEAD, so a commit or pull
doesn't silently move you off it (the hook just prints that you're pinned). Then:

- `./update.sh back` — the version before this one (each deploy is logged in
  `~/.local/state/sichos/deploy-history`)
- `./update.sh latest` — back to HEAD, hooks follow it again

Example — try what the config looked like before a change, then come back:

```sh
./update.sh list            # find the commit
./update.sh switch 9c7c8fb
./update.sh latest
```

## System files

```sh
./update.sh system
```

Applies the system-level files that changed since they were last applied (tracked separately in
`~/.local/state/sichos/system-rev`), with the same rules as user files — a system file you edited by
hand is kept and its new version parked. It also runs what `install.sh` would run after copying them:

- Plymouth theme → `plymouth-set-default-theme -R unlock` (rebuilds the initramfs)
- kernel-install drop-in → retitles the existing boot entries
- firewalld service → `firewall-cmd --reload`
- new `packages.txt` entries → `dnf install` (packages dropped from the list are left installed)
- SDDM theme/config → takes effect at the next login (or `sudo systemctl restart sddm`)
- `cage/` (the patched SDDM compositor) → comes from the `mdukhota/test1` COPR; rebuild it there

Run it from your own terminal — it prompts for your `sudo` password. If nothing system-level changed it
just says so, without asking for sudo.

## The Version tile

The Control Center's **Version** tile (add it with the pencil → "Add tiles") shows which SichOS
version this machine runs:

- the deployed **commit hash**, with the **branch** (or tag, or pin) and how long ago it was deployed
- underneath, what needs a look — `pinned`, `N behind HEAD`, `N uncommitted live`, `N to pull`, `N to push`,
  `N parked edits`, `N system`, `auto-update off` — or else the commit message
- at 2 rows, the commit message in full and one status line
- lit when the deployed version isn't HEAD

Tap it for `update.sh status` and the recent commits in a terminal. It refreshes after every deploy and
every 30 s while the Control Center is open (fetching origin at most every 10 minutes, for the
"to pull" count).

## More than one machine

Each machine has its own checkout and its own deployed state. Push from one, `git pull` on the others —
the pull deploys. Per-machine things (`monitors.lua`, the Control Center tile layout, settings saved
from the UI) are never synced or overwritten.

## Turning it off, and other details

- **Turn auto-deploy off** on a machine: `git config sichos.autodeploy false` (back on: `true`). The
  commands still work by hand.
- **`git worktree`s** never deploy — working on a side branch in one doesn't swap your live config.
- **`git bisect`** steps don't deploy; `git bisect reset` brings you back.
- **Log**: everything `update.sh` deploys is appended to `~/.local/state/sichos/update.log`.
  Notifications only appear when something needs a look (parked edits, system changes, a failed
  quickshell reload).
- **"No deployed version recorded"**: the machine predates `update.sh`. If `~/.config` matches some
  commit, `./update.sh mark <that commit>`, then `./update.sh` to bring it to HEAD. `./update.sh status`
  shows how the deployed files compare.
- **quickshell failed to reload**: the bar keeps running the previous config; `update.sh` retries once
  and reports the error (`file[line:col]: why`) in its output and the notification.

## Working on `update.sh` itself

- Repo path → deployed path lives in `dest_for` (user files) and `sys_dest_for` (system files). A new
  file under an already-mapped directory needs nothing; a new location needs a case there (plus the
  matching `install.sh` system step for system files).
- A new deploy-time patch, or a setting the UI writes into a deployed file, needs a
  `patch_like_deployed` case — otherwise every later update reports that file as a local edit.
- Test it in a sandbox, never against the real session: point both `HOME` **and** `XDG_STATE_HOME` at
  a scratch directory (`XDG_STATE_HOME` is set on these machines, so overriding `HOME` alone writes the
  real state), and use `SICHOS_SYSROOT=<dir> SICHOS_SUDO=` for `system`.
