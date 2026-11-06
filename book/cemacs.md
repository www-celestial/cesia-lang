# Cemacs

In this chapter you meet Cemacs, the editor written in Cesia, for Cesia. It has the keys of Emacs, the colours of Cesia's code,
and a band that shows what a key can lead to, so you don't need to learn its keys before you start. You change it in Cesia,
and it reloads while it runs.

## Starting it

Cemacs needs Cesia and two libraries for its window: SDL3 and SDL3_ttf. From the folder of Cemacs, `bin/cemacs` opens the
files it is given:

```bash
bin/cemacs src/main.ce
```

`bin/cemacs` gives Cemacs the permissions it needs, as a task of `cesia.toml` would: read and write files, run `cesia`, read a
few environment variables, and load its two libraries. Link it into a folder of your `PATH` to start it from anywhere.

## Moving and editing

The keys are those of Emacs. A few to start with:

| Keys | What they do |
|---|---|
| `C-f`, `C-b`, `C-n`, `C-p`, or the arrows | a character forward or back, a line down or up |
| `M-f`, `M-b` | a word forward or back |
| `C-a`, `C-e` | the start and the end of the line |
| `C-space`, then a move | select from there |
| `C-w`, `M-w`, `C-y` | cut, copy, paste |
| `C-k` | cut the end of the line |
| `C-/` | undo |
| `C-g` | stop what the keys started |

`C-` is the Control key, and `M-` the Alt key: `C-x C-s` is Control and `x`, then Control and `s`.

## Files, buffers and panes

| Keys | What they do |
|---|---|
| `C-x C-f` | open a file |
| `C-x C-s` | save |
| `C-x b`, `C-x C-b` | the next buffer, the list of buffers |
| `C-x d` | the file manager of the current folder |
| `C-x 2`, `C-x 3` | split the pane below, or to the right |
| `C-x o`, `C-x 0`, `C-x 1` | the next pane, close this one, keep only this one |
| `C-x C-c` | quit |

## The band of hints

Under `C-c`, the keys are in groups, as in Doom Emacs: `f` for files, `b` buffers, `w` windows, `c` code, `q` quit. Press
`C-c` and wait: a band at the bottom shows each group. Press `f` and wait again: it shows the keys of the files, `C-c f f` to
open one, `C-c f s` to save. `?` after a first key lists everything that can follow it.

So you can always find a key from its group, without knowing it: `C-c`, then look.

## Writing Cesia in it

Cemacs colours Cesia's code with [std/syntax], the same colours as this book. To run your program while you write it, keep a
terminal beside Cemacs with `--watch`: Cesia reloads the code each time you save, and runs it again.

```bash
cesia run --watch src/main.ce
```

The keys of the group `c`, `C-c c r` to run the file and `C-c c o` for its output, are in place. For now they only say that
running from Cemacs is not there yet: until it is, the terminal does that work.

## Changing Cemacs

Cemacs is a Cesia project, and its settings are Cesia code. `C-c f c` opens `src/cemacs.ce`, where the keys of each part are
joined, and `src/emacs/emacs.ce` holds the keys and the settings: `FontSize`, `TabText`, `HintDelay` for the band. A key runs
any function from the state of the editor to a new state:

```cesia norun
(* in src/emacs/emacs.ce: a size for the font, and the wait before the band shows *)
FontSize() = 15
HintDelay() = 0.5
```

Start Cemacs with `cesia do dev` from its folder, and each save of one of its files reloads it, without closing the window.

## Next

You know the tools. The last chapter, A real program, puts the chapters together: a small web service on SQLite, with its
tests, from `cesia new` to a server that runs.
