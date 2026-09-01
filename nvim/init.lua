-- Transparent background: kitty itself already shows the wallpaper through
-- (background_opacity in kitty.conf), but nvim's default colorscheme paints
-- an opaque bg on top of that, hiding it. Clearing these highlight groups
-- to "none" lets kitty's alpha show through nvim exactly like a bare shell
-- prompt. Must run on ColorScheme too, since loading any colorscheme
-- (:colorscheme, plugins, etc.) repaints these groups and would undo it.
local function transparent_bg()
  for _, group in ipairs({
    "Normal",
    "NormalNC",
    "NormalFloat",
    "SignColumn",
    "EndOfBuffer",
    "LineNr",
    "FoldColumn",
    "VertSplit",
    "WinSeparator",
  }) do
    vim.api.nvim_set_hl(0, group, { bg = "none" })
  end
end

transparent_bg()
vim.api.nvim_create_autocmd("ColorScheme", { callback = transparent_bg })
