# Files

In this chapter your program works with the machine: it reads and writes files, makes and lists folders, takes apart their
paths, takes arguments and flags from its command line, runs other programs, and reads the clock. Most of it is in [std/sys]. Each of these is a [side effect](glossary.md#side-effect), a change outside the
program, so each function says the permission it needs. The examples run with `--allow read,write`, in a folder that holds
`todo.txt`:

```text
buy bread
call Bo
water the plants
```

## Reading a file

[sys.Read] gives the text of a file in an `Ok`, or an `Err` if it can't: the file isn't there, or it is a folder.

```cesia allow=read
use std/sys
sys.Read("todo.txt") -->
sys.Read("nothing.txt") -->
```

### Inside a function

A script at the top of its file can't use `?`, which leaves a function. Inside a function, `?` passes the error on, as the
chapter [Errors](errors.md) showed:

```cesia allow=read
use std/result
use std/text
defn tasks(path)
  body = sys.Read(path)?
  result.Ok(text.Lines(body))
end
tasks("todo.txt") -->
```

For a file that comes with your program, where an `Err` would be a bug, [result.Unwrap] is enough:

```cesia allow=read
use std/value
value.Len(text.Lines(result.Unwrap(sys.Read("todo.txt")))) -->
```

## Writing

[sys.Write] replaces the content of a file, and makes the file if it isn't there. [sys.Append] adds at its end. Both give
`Ok(missing)` when all went well, since there is nothing more to say:

```cesia allow=read,write
sys.Write("done.txt", "buy bread\n") -->
sys.Append("done.txt", "call Bo\n") -->
text.Lines(result.Unwrap(sys.Read("done.txt"))) -->
```

A text of several lines is written as it is: end each line with `\n`, or join them with [text.Join].

## Folders

[sys.Mkdir] makes a folder and the folders above it. [sys.List] gives the names in a folder, sorted. [sys.Rename] moves a file
or a folder, and [sys.Remove] deletes a file or an empty folder:

```cesia allow=read,write
sys.Mkdir("archive/2026") -->
sys.Rename("done.txt", "archive/2026/done.txt") -->
sys.List(".") -->
sys.List("archive/2026") -->
sys.Remove("archive/2026/done.txt") -->
```

### Exists and Stat

[sys.Exists] asks whether a path is there, and [sys.Stat] tells more: the size in bytes, the time of the last change, and
whether it is a folder, a file or a link.

```cesia allow=read
sys.Exists("todo.txt") -->
info = result.Unwrap(sys.Stat("todo.txt"))
info.Size -->
info.IsDir -->
```

## Paths

[std/path] takes a path apart without touching the disk: [path.Base] is its last part, [path.Dir] the folder that holds it,
[path.Ext] the extension with its dot, [path.Stem] the last part without it. [path.Join] puts a name after a folder:

```cesia
use std/path
path.Base("photos/2026/beach.JPG") -->
path.Dir("photos/2026/beach.JPG") -->
path.Ext("photos/2026/beach.JPG") -->
path.Stem("photos/2026/beach.JPG") -->
path.Join("photos/2026", "beach.jpg") -->
```

A path is written with `/`, on Windows too, which takes it as well as `\`.

### Every file under a folder

[sys.List] gives the names of one folder. [sys.Walk] goes down into the folders inside it, and gives the path of every file,
in order. A symbolic link is listed, never followed, so a link can't make it loop:

```cesia allow=read,write
use std/list
sys.Write("archive/2026/june.txt", "sold 3\n") -->
sys.Walk("archive") -->
list.Filter(p -> path.Ext(p) == ".txt", result.Unwrap(sys.Walk("."))) -->
```

Together they rename a whole tree. This one gives every photo of a folder the extension `.jpg`, in lower case:

```cesia norun
use std/path
use std/sys
use std/text
use std/list
defn renamePhotos(folder)
  for p in list.Filter(p -> text.Lower(path.Ext(p)) == ".jpeg", sys.Walk(folder)?)
    sys.Rename(p, path.Join(path.Dir(p), "$(path.Stem(p)).jpg"))?
  end
  result.Ok(missing)
end
```

## Arguments

[sys.Args] holds the words written after the file on the command line, as texts:

```bash
cesia run --allow read count.ce todo.txt done.txt
```

```cesia norun
(* count.ce *)
use std/sys
use std/io
use std/result
use std/text
use std/value

for path in sys.Args
  n = value.Len(text.Lines(result.Unwrap(sys.Read(path))))
  io.Print(path, n)
end
```

### Flags

The flags of a command line, `-v` or `--max 5`, are read by [flags.Parse]. It takes the defaults, which say what each flag
takes, and the words; it gives the flags and the other words. `false` makes a switch, a number or a text takes a value, and
a flag that the defaults don't name is an `Err` that says which flags there are:

```cesia
use std/flags
args = ["-i", "--max", "2", "bread", "todo.txt"]
a = result.Unwrap(flags.Parse({i: false, max: 0}, args))
a.Flags -->
a.Words -->
flags.Parse({i: false, max: 0}, ["--min", "2"]) -->
```

A name of one letter is written with one dash, a longer one with two: `maxCount` is `--max-count`. In a program, the words
are [sys.Args]: `flags.Parse({i: false, max: 0}, sys.Args)`.

## Standard input and the exit code

[sys.ReadInput] gives all that the program receives on its
[standard input](glossary.md#standard-input-and-output), so that it can sit in a pipe of the shell. [sys.Exit] ends the
program at once with an [exit code](glossary.md#exit-code): 0 says that all went well, another number that something failed,
for the shell or the script that ran it.

```bash
cat sales.csv | cesia run lines.ce
```

```cesia norun
(* lines.ce: how many lines came in, and code 1 when none did *)
use std/sys
use std/io
use std/result
use std/text
use std/value

input = result.Unwrap(sys.ReadInput())
n = value.Len(text.Lines(input))
io.Print(n, "lines")
if n == 0
  io.PrintError("lines: nothing came in")
  sys.Exit(1)
end
```

[io.PrintError] writes as [io.Print] does, on the
[standard error](glossary.md#standard-input-and-output): what went wrong reaches the screen even when the output goes to a
file or a pipe, as in `cesia run lines.ce < sales.csv > count.txt`.

## The environment

[sys.Env] reads an environment variable, or gives `missing`. It needs `--allow env`, or `env=PORT` for that one:

```cesia norun
use std/text
use std/value
given = sys.Env("PORT")
port = if value.IsMissing(given) 8080 else text.Number(given) end
```

## Other programs

[sys.Run] runs a program to its end and gives its exit code, what it wrote, and its errors. It needs `--allow exec`, or
`exec=git` for one program. The arguments are a list: no shell reads them, so a name with a space or a `;` stays one argument.

```cesia norun
use std/io
use std/result
r = result.Unwrap(sys.Run("git", args = ["log", "--oneline", "-3"]))
if r.Code == 0
  io.Print(r.Out)
else
  io.Print("git failed:", r.Err)
end
```

### Programs that keep running

`input` gives the program a text to read, `dir` the folder it runs in, and `timeout` stops it after a number of seconds. For a
program that keeps running, a server or a shell, [sys.Start] gives a process to write to and read from while it runs, with
[sys.WriteInput], [sys.ReadOutput] and [sys.WaitExit].

## The clock

[sys.Now] gives the time in seconds since 1970, as a float. The difference of two of them times a piece of code. [sys.Sleep]
waits:

```cesia
start = sys.Now()
sys.Sleep(0.05)
sys.Now() - start >= 0.05 -->
```

### Dates

For dates, [std/date] has a [date.Date] struct, in UTC unless its `Offset` says otherwise, and the functions that go with it:

```cesia
use std/date
d = date.Date(2026, 11, 6, 14, 30)
date.Format(d) -->
date.Weekday(d) -->
date.AddDays(30, d) then date.FormatDate() -->
date.DaysBetween(d, date.Date(2026, 12, 25)) -->
date.Parse("2026-12-25") -->
```

### Here and now

[date.Local] gives the date of an instant on the clock of this machine, with the `Offset` of its time zone, in seconds ahead
of UTC; [date.Format] writes it, and [date.Parse] reads it back. [date.Utc] gives the same instant in UTC, and [date.ToUnix] of
both is the same:

```cesia
here = date.Local(sys.Now())
date.Format(here) -->
date.ToUnix(here) == date.ToUnix(date.Utc(here)) -->
date.Parse("2026-11-06T14:30:00+03:00") then result.MapOk(date.Utc) then result.MapOk(date.Format) -->
```

The time zone is the system's: `TZ=Asia/Tokyo cesia run app.ce` runs a program on the clock of Tokyo.

## Next

Your programs read and write the machine's files. The next chapter, [Data](data.md), works on many values at once: lists of records,
groups, counts, tables of columns.
