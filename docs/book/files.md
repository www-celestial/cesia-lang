# Files

In this chapter your program works with the machine: it reads and writes files, makes and lists folders, takes arguments from
its command line, runs other programs, and reads the clock. All of it is in [std/sys]. Each of these is a [side effect](glossary.md#side-effect), a change outside the
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
defn tasks(path)
  text = sys.Read(path)?
  Ok(Lines(text))
end
tasks("todo.txt") -->
```

For a file that comes with your program, where an `Err` would be a bug, [Unwrap] is enough:

```cesia allow=read
Len(Lines(Unwrap(sys.Read("todo.txt")))) -->
```

## Writing

[sys.Write] replaces the content of a file, and makes the file if it isn't there. [sys.Append] adds at its end. Both give
`Ok(missing)` when all went well, since there is nothing more to say:

```cesia allow=read,write
sys.Write("done.txt", "buy bread\n") -->
sys.Append("done.txt", "call Bo\n") -->
Lines(Unwrap(sys.Read("done.txt"))) -->
```

A text of several lines is written as it is: end each line with `\n`, or join them with [Join].

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
info = Unwrap(sys.Stat("todo.txt"))
info.Size -->
info.IsDir -->
```

## Arguments

[Args] holds the words written after the file on the command line, as texts:

```bash
cesia run --allow read count.ce todo.txt done.txt
```

```cesia norun
(* count.ce *)
use std/sys

for path in Args
  n = Len(Lines(Unwrap(sys.Read(path))))
  Print(path, n)
end
```

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

text = Unwrap(sys.ReadInput())
n = Len(Lines(text))
Print(n, "lines")
if n == 0
  sys.Exit(1)
end
```

## The environment

[sys.Env] reads an environment variable, or gives `missing`. It needs `--allow env`, or `env=PORT` for that one:

```cesia norun
given = sys.Env("PORT")
port = if IsMissing(given) 8080 else Number(given) end
```

## Other programs

[sys.Run] runs a program to its end and gives its exit code, what it wrote, and its errors. It needs `--allow exec`, or
`exec=git` for one program. The arguments are a list: no shell reads them, so a name with a space or a `;` stays one argument.

```cesia norun
r = Unwrap(sys.Run("git", args = ["log", "--oneline", "-3"]))
if r.Code == 0
  Print(r.Out)
else
  Print("git failed:", r.Err)
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

For dates, [std/date] has a [date.Date] struct in UTC, and the functions that go with it:

```cesia
use std/date
d = date.Date(2026, 11, 6, 14, 30)
date.Format(d) -->
date.Weekday(d) -->
date.AddDays(30, d) then date.FormatDate() -->
date.DaysBetween(d, date.Date(2026, 12, 25)) -->
date.Parse("2026-12-25") -->
```

## Next

Your programs read and write the machine's files. The next chapter, [Data](data.md), works on many values at once: lists of records,
groups, counts, tables of columns.
