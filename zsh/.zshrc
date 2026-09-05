# Created by newuser for 5.9

# zsh ships with HISTSIZE=30/SAVEHIST=0 and no HISTFILE by default, so
# without this block history is an in-memory-only 30-entry buffer that's
# discarded on shell exit — nothing is ever written to disk.
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY       # record timestamp + duration per entry
setopt HIST_EXPIRE_DUPS_FIRST # trim dupes first when HISTFILE hits HISTSIZE
setopt HIST_IGNORE_DUPS       # don't record a line dup of the previous one
setopt HIST_IGNORE_ALL_DUPS   # remove earlier dupe when a new one is added
setopt HIST_IGNORE_SPACE      # don't record lines starting with a space
setopt HIST_FIND_NO_DUPS      # skip dupes when searching history
setopt HIST_SAVE_NO_DUPS      # don't write dupes to HISTFILE
setopt SHARE_HISTORY          # share history live across concurrent shells
setopt APPEND_HISTORY         # append instead of overwrite on exit

# Must come before anything below that shells out to a ~/.local/bin binary
# (oh-my-posh) — antidote/omp don't add this themselves, so on a shell
# where nothing else already put ~/.local/bin on PATH first (i.e. not
# inherited from a parent process/session), the oh-my-posh eval below fails
# with "command not found: oh-my-posh".
export PATH="$HOME/.local/bin:$PATH"

source ${ZDOTDIR:-~}/.antidote/antidote.zsh

antidote load

# Absolute path, not the original relative "--config .config/prompt.toml":
# that only resolved because a fresh terminal's cwd happens to start at
# $HOME — a new kitty window/tab opened with an inherited cwd elsewhere
# would silently fail to find the config. Verified this form parses and
# renders under both `zsh -c` and a login shell.
eval "$(oh-my-posh init zsh --config "$HOME/.config/prompt.toml")"

# Fedora's fzf package installs completion + key-bindings but leaves both
# disabled by default (see /usr/share/doc/fzf/README.Fedora) — this is the
# package's own recommended embedded-script method (`fzf --zsh`) rather than
# sourcing /usr/share/fzf/shell/*.zsh directly, so it keeps working even if
# a future fzf update reorganizes those file paths. Gives CTRL-T (paste
# selected file), CTRL-R (search shell history), ALT-C (cd into selected dir).
source <(fzf --zsh)
