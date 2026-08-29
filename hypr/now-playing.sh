#!/usr/bin/env bash
# hyprlock.conf's own config parser treats "{{ }}" as its template-variable
# syntax (same family as $TIME/$LAYOUT), so a playerctl --format string
# with literal double braces embedded directly in a `cmd[...]` value gets
# mangled before playerctl ever runs — hence this wrapper script instead.
playerctl metadata --format "{{ artist }} - {{ title }}" 2>/dev/null
