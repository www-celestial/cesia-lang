-- cesia lsp for Neovim 0.11 and later: with vim.lsp.enable('cesia') in init.lua, it starts on each .ce file, in the folder
-- of its project.
return {
  cmd = { 'cesia', 'lsp' },
  filetypes = { 'cesia' },
  root_markers = { 'cesia.toml', '.git' },
}
