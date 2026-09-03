# Created by newuser for 5.9
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
