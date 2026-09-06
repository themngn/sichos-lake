# Known issues / possible improvements

Things that are worked around rather than properly fixed, kept here so the workaround doesn't
get mistaken for the real fix later.

## Bar goes fully opaque under HDR (workaround, not a real fix)

**Priority:** low. **Complexity:** medium (needs isolating which layer — Hyprland, Qt Quick, or
the driver — actually owns the bug before a real fix is possible).

**Where:** `quickshell/Bar.qml`, `hdrActiveHere` / the `color:` binding.

**Symptom:** on a `bitdepth=10` (HDR, see `HdrSettings.apply()`) output, the bar's Wayland
surface bands/noises constantly whenever it isn't fully opaque. Confirmed live:
- `alpha=0` ("transparent", the bar's normal empty-workspace state) — bands.
- `alpha=1/255` (tried as a "still see-through" compromise) — bands *worse* than `alpha=0`.
- `alpha=0.8` (the normal "workspace has windows" state) — not explicitly confirmed clean or
  banding, just never reported as a problem.
- `alpha=1.0` — clean, no banding.

**Current workaround:** whenever HDR is active and selected for a monitor, the bar is forced
fully opaque on that monitor regardless of workspace state — same as the existing
`ShellState.transparencyOpaque` toggle. This gives up the "floats over the wallpaper on an
empty workspace" look, but only on HDR-enabled monitors.

**Why this isn't a real fix:** it never identified the actual mechanism. Open questions:
- Is this a Hyprland/wlroots bug (its GPU composition/blend path mishandling alpha blending
  into a 10-bit framebuffer), a Mesa/driver issue, or something Qt Quick's renderer does
  wrong when targeting a 10-bit surface?
- Does the same banding happen with *any* other semi-transparent layer-shell client under HDR
  on this machine (e.g. a test with `alacritty --opacity`), or is it specific to Quickshell/Qt
  Quick's rendering path? That test would tell us whether to report this upstream to Hyprland
  or to Quickshell/Qt.
- Was `alpha=0.8` actually verified banding-free under HDR, or just assumed because it was
  never reported as a problem before this bug was noticed? Worth explicitly testing.
- If this does turn out to be a wlroots/driver blending precision bug, is there a Hyprland
  render setting (dithering, color management mode) that fixes it globally instead of
  papering over it per-surface in this repo?

**How to properly fix:** once the actual layer (Hyprland vs. Qt vs. driver) is identified,
either report/patch it upstream, or find a real Hyprland-side setting instead of forcing bar
opacity. Remove the `hdrActiveHere` workaround from `Bar.qml` once that's done.
