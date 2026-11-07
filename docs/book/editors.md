# Editors

Any editor works, since a program is a text file. An editor that speaks the
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/) does more with
[cesia lsp](commands.md#cesia-lsp), a language server that comes in the binary:

- what [cesia check](commands.md#cesia-check) finds, under the code, as you type: a name that doesn't exist, a call with the
  wrong arguments, a result left unhandled;
- the documentation of the name under the cursor, `list.Map` or a function of your own;
- where a name is defined, in your project;
- the names of a package after its dot: `list.` lists `Map`, `Filter` and the others.

The editor starts `cesia lsp` in the folder of the project, the one that holds `cesia.toml`, and talks to it on its input and
output. The server reads the files and never writes one. Below, each editor's few lines of configuration.

## Neovim

The sources of Cesia hold `tools/editors/nvim/`: copy it into `~/.config/nvim/`. It gives Neovim the file type, the colours,
and `lsp/cesia.lua`, the configuration of the server. Then one line in `init.lua` starts the server on each `.ce` file, from
Neovim 0.11:

```lua
vim.lsp.enable('cesia')
```

Without the copy, the same in `init.lua`:

```lua
vim.filetype.add({ extension = { ce = 'cesia' } })
vim.lsp.config('cesia', { cmd = { 'cesia', 'lsp' }, filetypes = { 'cesia' }, root_markers = { 'cesia.toml', '.git' } })
vim.lsp.enable('cesia')
```

`K` shows the documentation under the cursor, `Ctrl-]` goes to a definition, and `Ctrl-X Ctrl-O` completes after a dot.

## Helix

In `~/.config/helix/languages.toml`:

```text
[language-server.cesia]
command = "cesia"
args = ["lsp"]

[[language]]
name = "cesia"
scope = "source.cesia"
file-types = ["ce"]
roots = ["cesia.toml"]
block-comment-tokens = { start = "(*", end = "*)" }
indent = { tab-width = 2, unit = "  " }
language-servers = ["cesia"]
```

Helix has no grammar of Cesia, so it doesn't colour the code; the errors, `Space k` for the documentation and `g d` for a
definition work.

## Emacs

`tools/editors/cesia-mode.el` is the mode of Cesia: add `(load "/path/to/cesia/tools/editors/cesia-mode.el")` to `init.el`.
It tells Eglot, the client that comes with Emacs, how to start the server: `M-x eglot` in a `.ce` file starts it.

## Zed and VS Code

Both start a language server only through an extension of their own, and Cesia has none yet. Zed's also needs a grammar of
Cesia, which doesn't exist. Until there is one, use one of the editors above.
