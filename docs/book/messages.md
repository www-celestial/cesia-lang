# Error messages

Every message that Cesia can print, as it prints it, grouped by where it comes from. A `…` stands for what the message
fills in: a name, a value, a number. The second column is the hint that Cesia prints on the line below the message,
when it has one, then what to do, where neither says it. All of them live in one table of the source,
`src/lib/messages.ml`, so a mistake always reads the same way.

A message of a bug shows its file, line and column first, then the line with a mark under the place:

```text
shop.ce:3:9: Index 5 is outside this array of 3 elements.
  3 | io.Print(names[5])
    |         ^
```

## Reading the code

The lexer and the parser, when a file loads: nothing of it has run. `cesia check` shows them too, with their line and column.

| Message | Hint, or what to do |
|---|---|
| `This file is not valid UTF-8.` | Save the file as UTF-8 in your editor. |
| `Unexpected character ….` | Remove the character, or put it in a text. |
| `This text is not closed: a closing " is missing.` |  |
| `Two quotes in a row end a text and start another.` | `A quote inside a text is written \": "say \"hi\"".` |
| `This comment is not closed: a closing *) is missing.` |  |
| `Comments are written (* ... *).` |  |
| `--> shows a value only in an example: in a documentation comment (** *), or in a book.` | `In a program, io.Print(x) prints it.` |
| `The number … doesn't fit in 63 bits.` | `Write it as a float: ….0.` |
| `Expected …, found ….` | The parser names what the grammar wants at that place: often a missing `end`, `)` or `,`. |
| `This code is nested too deeply.` | Split the expression with names, or raise --limit nesting. |
| `A range is written with two dots, as in 1..n, which is list.Range(1, n), and a method is reached with one dot.` |  |
| `Only a variable can be assigned here.` | Assign to a name, a field `x.F`, an element `xs[i]` or a key `d[k]`. |
| `break can only be used inside a loop.` | Use break inside a for or a while. |
| `return can only be used inside a function.` | At the top of a file, the program ends at its last line: sys.Exit ends it sooner. |
| `A name can't hold a _: "…".` | `Join the words with capitals: …, or … when it is public.` |
| `? must follow its value, with no space.` | Write `x?`, the `?` against its value. |
| `Two ; in a row: an array written in the code has rows and columns only.` | `An array of more dimensions comes from matrix.Reshape: [1 3; 2 4;;; 5 7; 6 8] is matrix.Reshape([2, 2, 2], 1..8).` |
| `A struct can only be defined at the top of a file.` | Move the struct to the top level of the file. |
| `Only fields can be written inside a struct.` | `One per line: a name, its type if it has one, and = with a default. The struct ends with end.` |
| `In the block form of a struct, each field has its own line.` | Put each field of the block form on its own line. |
| `The parameters of a lambda can't have types.` | `Write the function with defn to give them some.` |
| `An interface can only be defined at the top of a file.` | Move the interface to the top level of the file. |
| `Only methods can be written inside an interface.` | `A method is a name and its parameters in parentheses, as Area() or Scaled(by Number).` |
| `A method of an interface has no body.` | `A method written apart, as (s Shape) Describe() = ..., is a method of every value that meets the interface.` |
| `In the block form of an interface, each method has its own line.` | Put each method on its own line. |
| `A parameter of an interface has no default.` | Remove the default: the method that meets the interface gives its own. |
| `A method can only be defined at the top of a file.` | Move the method to the top level of the file. |
| `Only the result of a function can end with !.` | `Int! says that a function gives an Ok of an Int, or an Err: defn Size(path) Int!.` |
| `use can only be used at the top of a file.` | Move the use to the top of the file. |
| `A use takes no quotes: it names a package of the project.` | `Write use ….` |
| `A use starts in src/ or at the root of the project, with no ./ and no ../.` | `Write the whole path: use geometry/shapes.` |
| `"it" is a reserved name and can't be assigned.` | Give the variable another name. |

## Names and packages

The resolver and the loader, when a file loads: a name that leads nowhere, a use that finds no package. Nothing has run yet.

| Message | Hint, or what to do |
|---|---|
| `Name "…" doesn't exist.` | Check the spelling, or define it; a name of std/ needs its use. |
| `Name "…" doesn't exist.` | `… is a package of std/: write use std/… first.` |
| `… is in std/…: write use std/… and ….….` | Add the use the message names, and write the name with its package. |
| `… is a package this file uses: choose another name here.` | Rename the variable, as `s` for a text when the file uses std/text. |
| `Module "…" has no name "…".` | Check the name in the module's page of the reference. |
| `The field or method "…" is private to the package that declares it.` | `A field or a method is public when its first letter is a capital.` |
| `There is no struct "…" here.` | `A pattern names a struct of this package, as Point(x, y), or of a package in use, as geo.Point(x, y).` |
| `A method belongs to a struct or an interface declared in the same package: this one can't be reached from here.` | Write the method in the package that declares the struct. |
| `There is no struct or interface "…" in this package.` | `A method belongs to a struct or an interface declared in the same package.` |
| `"…" is also defined at …:….` | Two files of one package define the name: rename or remove one. |
| `… has an instance method and a static method named "…".` | `A struct has one method of a name.` |
| `The method "…" has the name of a field of ….` | Rename the method or the field. |
| `The function "…" is defined twice.` | Rename one of the two functions. |
| `"…" is a function of this file and can't be assigned.` | Give the variable another name. |
| `"…" has no value yet.` | `Give it a value before reading it.` |
| `This use creates a cycle between modules.` | Two packages use each other: move what they share into a third one. |
| `The folder "…" holds no .ce file.` | A package is a folder of .ce files: check the path. |
| `"…" already names …, at line ….` | `Give one of them another name with as.` |
| `Can't read the module "…".` | Check the permissions of the file. |
| `Module "…" doesn't exist.` | Check the path from the root of the project. |
| `What comes with Cesia is used through std/: write use std/….` | Write use std/ and the name. |
| `A use is the path of a folder from the root of the project: write use ….` |  |
| `… names no package: a use of deps/ is deps/OWNER/REPO then the path of a folder from its root, as the [deps] of cesia.toml bring it.` |  |
| `Package … doesn't load: ….` | Fix the error the message gives in that package. |
| `A running program can't load a new module. Restart it to use this one.` | Restart the program. |
| `The source folder "…" doesn't exist.` | Fix src of [project], or make the folder. |
| `The source folder "…" is outside the project.` | Keep the source folders inside the project. |
| `This project needs Cesia … or later, and this is …: run cesia upgrade.` | Run cesia upgrade. |
| `… was changed by hand: run cesia pkg install.` | Run cesia pkg install: std/ and deps/ are read only. |
| `… isn't installed: run cesia pkg install.` | Run cesia pkg install. |

## Values and operations

A bug, when the line runs: an operation on a value that it can't take. The program stops at that line, or the fiber does.

| Message | Hint, or what to do |
|---|---|
| `Can't … … … ….` | `To put a value in a text, write "...$x" or value.Text(x).` |
| `The integer result of … … … doesn't fit in 63 bits.` | `Integers have 63 bits. To go further, use a float: 1.0 * x.` |
| `The integer result of -(…) doesn't fit in 63 bits.` | `Integers have 63 bits. To go further, use a float: 1.0 * x.` |
| `…: division by zero.` | Check the divisor before the division; float division by zero gives an infinity instead. |
| `Can't take the opposite of ….` | `-` takes a number or an array of numbers. |
| `Can't compare … … ….` | `<` and `>` take two numbers or two texts; `==` takes any two values. |
| `A condition must be true or false, not ….` | `if`, `while` and `and`/`or` take true or false: compare with `==`, or ask value.IsMissing. |
| `Can't call …: it is not a function.` | The value called is no function: check the name, or a missing `.` before a method. |
| `… takes …, not ….` | Give the arguments the function takes; its page in the reference lists them. |
| `… takes … arguments, not ….` | Give fewer arguments; its page in the reference lists them. |
| `… needs the argument "…".` | Give that argument, by position or by name. |
| `… has no argument named "…".` | Check the name of the argument in the function's page. |
| `… received the argument "…" twice.` | Give the argument once. |
| `… needs a whole number, not ….` | Round the float first, with math.Floor, math.Ceil or math.Round. |
| `… needs numbers, not ….` | `When the value is "function <anonymous>": "it" belongs to the nearest call. Write x -> ... to use it further out.` |
| `… needs a count of 0 or more, not ….` | Give a whole number of 0 or more. |
| `… needs a text, not ….` | Give a text; value.Text makes one of any value. |
| `… needs true or false, not ….` | An optional parameter, as `fold` of text.ByteFind or `sync` of sys.Write, takes true or false; leaving it out means false. |
| `… needs an array, not ….` | Give a list or an array. |
| `… needs a dictionary, not ….` | Give a dictionary. |
| `… needs a dictionary, not ….` | `dict.Fields(x) gives the public fields of a struct as a dictionary.` |
| `… needs a text that isn't empty.` | Give a text with at least one character. |
| `… of an empty array.` |  |
| `A range needs whole numbers, not ….` | `To get a whole number, use math.Floor(...), math.Ceil(...) or math.Round(...).` |
| `This range has too many elements.` | A range is held in memory when it isn't the range of a for: make it shorter, or loop over it. |
| `An index must be a whole number, not ….` | `To get a whole number, use math.Floor(...), math.Ceil(...) or math.Round(...).` |
| `Index … is outside this array of … elements.` | Positions count from 1 to value.Len(xs); list.First and list.Last give missing for an empty list. |
| `Index […, …] is outside this array of … rows and … columns.` | Check the row and the column against value.Size. |
| `Index […] is outside this array of … by ….` | Check each position against value.Size. |
| `An array of … dimensions takes a whole number for each index, not a slice.` | Give a whole number for each index of an array of three dimensions or more. |
| `This array has … dimensions: use … indexes, or one.` | Give one index per dimension, or one for the order of the elements. |
| `Only one element can be written at a time.` | Write the elements one by one, in a loop. |
| `Can't index ….` | Only arrays, texts and dictionaries take brackets. |
| `This mask has … elements, the array has ….` | Make the mask from the same array, as `xs > 0`. |
| `Can't loop over ….` | `for` goes over an array, a range or a channel; for a dictionary, dict.Keys, dict.Values or dict.Pairs. |
| `Can't look inside … with "in".` | `in` looks in an array, a dictionary or a text. |
| `The rows of this array have different lengths.` | Give each row of the matrix the same number of elements. |
| `… needs a size, not ….` | Give a whole number of 0 or more. |
| `The method len of … must give an integer for value.Len, not ….` | Make the method len give an integer. |
| `Can't reshape … elements into ….` | The product of the sizes must equal the number of elements. |
| `Reshape needs its shape as a list of sizes, not ….` | `Write the sizes in a list: matrix.Reshape([2, 3], xs).` |
| `…'s dimension must be 1 or 2, not ….` | Give a dimension the array has. |
| `An array has at most 32 dimensions, not ….` | Use 32 dimensions at most. |
| `… works on arrays of 2 dimensions, not ….` | Give a matrix; matrix.Reshape makes one. |
| `Can't combine an array of … with an array of ….` | Give arrays of the same sizes, or a number and an array. |
| `Matmul can't multiply … by … with … by …: the columns of the first must equal the rows of the second.` | Transpose one, or check the sizes with value.Size. |
| `text.Decimals needs a count of decimals from 0 to 20, not ….` | Give 0 to 20 decimals. |
| `value.Text needs a count of 1 or more characters as most, not ….` | Give a whole number of 1 or more. |
| `Can't sort … with ….` | Sort numbers or texts, or give list.SortBy a function that gives one. |
| `… needs a text with a character.` | Give a text with at least one character. |
| `FromBytes needs integers from 0 to 255, not ….` | Give integers from 0 to 255. |
| `Char needs a code point, not ….` | Give a code point from 0 to 1,114,111, not a surrogate. |
| `… needs a number of bytes within the text, not ….` | Give a number of bytes within the text. |
| `A dictionary key is a number or a text, not ….` | Use a number or a text as a key. |
| `This dictionary has no key: ….` | Ask dict.Has first, or read with dict.Get or dict.GetOr, which give missing or a default. |
| `A dictionary takes one key between its brackets.` | Give one key: d[k]. |
| `Dict needs structs with a Key and a Value, not ….` | Give dict.Dict a list of {Key, Value}. |
| `No branch of this match accepts ….` | Add the missing case, or an else. |
| `This pattern takes … elements, the value has ….` | Give the pattern as many names as the list has elements. |
| `This pattern needs a struct, not ….` | The value is no struct: match it first. |
| `This pattern needs an array, not ….` | The value is no array: match it first. |
| `This pattern needs …, not ….` | The value doesn't have the shape of the pattern: use match, with an else. |
| `? can only be used inside a function, which it leaves with the Err.` | `At the top of a file, write result.Unwrap(...) where an Err would be a bug, or match on the result.` |
| `? needs an Ok or an Err, not ….` | `Return a result from the function you call.` |
| `Assertion failed.` | The condition of bug.Assert was false. |
| `date.Local can't place … seconds since 1970: it takes a time less than 10^15 seconds from 1970, about 31 million years.` | Give a time within about 31 million years of 1970. |
| `random.Int needs a low that is at most its high, and a range that fits in 63 bits: … to ….` | Give random.Int a low at most its high. |
| `sys.Exit takes a code from 0 to 255, not ….` | Give a code from 0 to 255. |
| `Near needs … to be a number of 0 or more, not ….` | Give rel and abs of 0 or more. |
| `JSON can't hold ….` | JSON holds numbers, texts, booleans, missing, lists and dictionaries: dict.Fields turns a struct into a dictionary. |

## Structs, interfaces and types

Most when a value comes in: a struct built, a field written, a call, a result. A type that names nothing is found when the file loads.

| Message | Hint, or what to do |
|---|---|
| `This struct has no field "…".` | Check the spelling against the fields of the struct. |
| `… has no field "…".` | Check the spelling against the fields of the struct. |
| `Can't read the field "…" of ….` | Only structs and dictionaries have fields: check the value. |
| `"…" is a method of …: it must be called.` | `Write x.…(). On an array: list.Map(it.…(), xs).` |
| `"…" is a static method of ….` | `Write ….…(...).` |
| `"…" needs a ….` | `Write x.…(), with x a ….` |
| `… has no static method "…".` | Check the name, or write it as a function of the package. |
| `… has no field or method "…".` | Check the spelling against the struct's fields and methods. |
| `….From is a static method of every struct: it can't be defined.` | `Another name, as FromRow, can build a struct its own way.` |
| `… needs a field that is private to its package.` | From fills public fields only: give the private one a default, or build the struct in its package. |
| `Fields needs a struct, not ….` | Give dict.Fields a struct. |
| `… needs the field "…".` | Give the key in the dictionary, or a default to the field. |
| `… gets its field "…" from two keys: "…" and "…".` | Keep one of the two keys. |
| `There is no type "…".` | `A type is Int, Float, Number, Bool, Text, Array, Dict, Function, a struct or an interface.` |
| `… is an interface: it can't be called.` | `A value meets it by having its methods. To check one, write the interface after a parameter or a field: s ….` |
| `Both … and … have a method "…", and … meets both.` | `A field or a method of the value itself would win over theirs.` |
| `…: … must be …, found ….` | Give a value of the type written, or change the type. |
| `… needs a struct, not ….` | Give a struct. |

## Warnings of cesia check

Not errors: `cesia check` shows them, and they don't change its exit code.

| Message | Hint, or what to do |
|---|---|
| `… gives a result, used here as a plain value.` | `An Err would pass for a value: add ?, match it, or Unwrap it.` |
| `… gives a result, which is dropped here.` | `Its Err would go unseen: add ?, match it, or write _ = before it to drop it on purpose.` |
| `… can give an Err, which … doesn't say: write …!.` | Write the `!` after the result type the message names. |

## Permissions and limits

When the program asks for what its command line didn't give, or goes past a limit: see [Permissions](permissions.md).

| Message | Hint, or what to do |
|---|---|
| `Permission "…" denied. Run again with --allow ….` |  |
| `Permission "…" denied for ….` | `Run again with --allow …=…, or a folder that holds it.` The narrowest permission that would do: the file, the port, the host, the command, the variable or the library; ", or a folder that holds it" for read and write only. |
| `Permission "net" denied for listening on …, which other machines can reach.` | `Run again with --allow net=…; net=:… listens on this machine only.` |
| `Permission "net" denied for …: net=own reaches only the listeners this program has open, at an address of this machine written out or localhost.` | `Run again with --allow net=…; for cesia test, "net=…" in allow of [test] in cesia.toml does it too.` |
| `Limit "…" reached.` | Find the loop or the data that grows; raise the limit with --limit if the program is right. |

## Fibers and channels

From std/fiber. Those with a kind are not bugs but the `Err` of a result, as `"timeout"`; the others stop the fiber.

| Message | Hint, or what to do |
|---|---|
| `… needs a task, not ….` | Give fiber.Wait or fiber.Cancel what fiber.Spawn gave. |
| `All fibers are waiting and nothing can wake them.` | Some fiber must send, close or end: look for a channel that nobody closes. |
| `… needs a channel, not ….` | Give what fiber.Channel gave. |
| `Select needs a list of channels, not ….` | Give a list of channels. |
| `The size of a channel is a whole number, 0 or more, not ….` | Give a size of 0 or more, or none. |
| `A timeout is a number of seconds, 0 or more, not ….` | Give a number of seconds, 0 or more. |
| `Nothing came on the channel before the timeout.` | An Err of kind "timeout": nothing came in time. |
| `The task didn't end before the timeout.` | An Err of kind "timeout": the task runs on. |
| `Nothing came on the channels before the timeout.` | An Err of kind "timeout". |
| `The fiber was cancelled here.` | An Err of kind "cancelled": fiber.Cancel stopped it. |
| `The channel is closed, and nothing is left in it.` | An Err of kind "closed": everything sent was taken. |
| `Send to a closed channel: Close said that nothing more comes.` | Send before Close, or don't send after it. |
| `This channel is closed already.` | Close a channel once. |

## Files, processes and the network

From std/sys and std/net, and from the supervisor of `--workers`, which prints its lines on the standard error.

| Message | Hint, or what to do |
|---|---|
| `Can't … …: ….` | The system's own reason ends the message: a file missing, a folder not empty, no space left. |
| `… needs a finite duration of 0 or more, not ….` | Give a number of seconds, 0 or more. |
| `This process has ended.` | Start the program again with sys.Start. |
| `… needs a process, not ….` | Give what sys.Start gave. |
| `The input of this process is closed.` | Nothing more can be written to it after sys.CloseInput. |
| `… needs a socket, not ….` | Give what net.Listen, net.Accept or net.Connect gave. |
| `A port is a number from 0 to 65535, not ….` | Give a port from 0 to 65535; 0 lets the system choose one. |
| `This socket is closed.` | Open a new connection. |
| `This system can't watch more sockets.` | On macOS and Windows, a program watches at most 1,000 sockets: close some, or serve on Linux. |
| `The server is stopping.` | The program got a stop signal: nothing to do. |
| `Worker … ended with code …: another starts.` | The supervisor starts another worker; look at its output for why it ended. |
| `A worker ended with code … before it could accept: the program can't start, the workers stop.` | Run the program without --workers to see its error. |
| `A new worker ended with code … before it could accept: the running workers stay.` | The new version has a bug: the old workers serve on; fix it and send HUP again. |
| `The new workers didn't accept in time: the running workers stay.` | The new version took more than 30 seconds to accept: the old workers serve on. |

## Logs and metrics

From std/log and std/metrics.

| Message | Hint, or what to do |
|---|---|
| `The fields of a log line are a struct or a dictionary, not ….` | Give a struct or a dictionary, as {Order: 7}. |
| `The labels of a metric are a struct or a dictionary, not ….` | Give a struct or a dictionary, as {method: "GET"}. |
| `"…" isn't a name Prometheus takes: letters, digits and _, not first a digit.` | Use letters, digits and _, not a digit first. |
| `The metric … is a …: it can't be another kind too.` | Give the histogram another name than the counter. |
| `A counter only grows: metrics.Add takes 0 or more, not ….` | A counter counts up: use a histogram for a value that can fall. |

## JSON

The `Message` of the `Err` of [json.Parse]: each ends with the byte where the text goes wrong, as `Expected a value, at byte 7`.

| Message | Hint, or what to do |
|---|---|
| `Unexpected text` |  |
| `A \u escape is too short` |  |
| `A \u escape needs four hex digits` |  |
| `A surrogate is alone` |  |
| `A text is not closed` |  |
| `A bad escape` |  |
| `A control character in a text` |  |
| `A number needs digits` |  |
| `A number is too large` |  |
| `Too deep` |  |
| `Expected a value` |  |
| `Expected a comma or ]` |  |
| `A key needs a text` |  |
| `Expected a colon` |  |
| `Expected a comma or }` |  |
| `Text after the value` |  |

## Regular expressions

From std/regex, when a pattern is compiled.

| Message | Hint, or what to do |
|---|---|
| `Bad pattern: ….` | Fix the pattern at the place the message says; see the table of patterns in Texts. |

## SQL and columns

From std/sql, std/sqlite3 and std/columns. The errors of SQLite itself are `Err`s with the code SQL gives them, as [SQLite](sqlite.md) shows.

| Message | Hint, or what to do |
|---|---|
| `SQLite can't take … with a zero byte.` | Remove the zero byte. |
| `… needs a …, not ….` | Give what sql.Open or a transaction gave. |
| `This connection or cursor is closed.` | Open the database again. |
| `This database is closed.` | Open it again. |
| `SQLite's pragmas temp_store_directory and data_store_directory are refused: they would put its files where read= and write= don't reach.` | Keep SQLite's files where the permissions reach. |
| `Can't load SQLite's plugin cesia_sqlite.cmxs: ….` | The release is incomplete: install it again. |
| `The text holds no statement.` | Give one SQL statement. |
| `One statement per call: sql.Script runs several, without parameters.` | Split the text into calls, or use sql.Script for a schema. |
| `Parameter … is …: SQL takes missing, a Bool, an Int, a Float or a Text.` | Give missing, a Bool, an Int, a Float or a Text: json.Text for a list or a dictionary. |
| `The statement has … placeholders, given … values: one value for each ?.` | Give one value for each ?. |
| `A batch needs a count of rows above 0, not ….` | Give a count above 0. |
| `The column … holds an integer past 63 bits: read it with cast(… as text).` | Read it as a text, as the message says. |
| `No connection was free for … seconds. Inside a transaction, use its tx, not db.` | Raise max of sql.Open, or keep transactions short. |
| `A pool holds 1 connection or more, not ….` | Give max of 1 or more. |
| `… is a URI: SQLite takes the path of a file here, or :memory:.` | Give the path of the file. |
| `The columns … and … both give the key …: rename one with as.` | Rename one of the columns with as in the SQL. |
| `… cells don't make whole rows of … names.` | Give as many cells as names times rows. |
| `These columns have … and … rows.` | Give columns of the same length. |
| `Split needs the result of Groups, not ….` | Give Split what columns.Groups gave. |
| `… is SQLite, which programs reach through std/sql only.` | Use std/sql. |

## C

From std/c: see [C and C++](c.md).

| Message | Hint, or what to do |
|---|---|
| `Can't load …: ….` | Install the library, or give its exact path; the system's reason ends the message. |
| `This library has no function ….` | Check the name in the library's header. |
| `… isn't a C type.` | Use a type of the table of C and C++. |
| `void can't be an argument.` | A function of no argument takes []. |
| `slow takes a function of at most 6 numbers, pointers or texts, which doesn't call back.` | Bind it without slow. |
| `… slow C calls already wait for a place: this one can't wait too.` | Too many at once: refuse sooner, as by a limit of sign-ins by client. |
| `A C function takes at most 60 arguments, not ….` | A C function takes 60 arguments at most here. |
| `This needs libffi, which isn't installed.` | Install libffi, for more than 6 arguments, structures by value, variadic functions and callbacks. |
| `libffi refuses this signature.` | Check the types against the C header. |
| `A structure needs a block, not ….` | Give a block of c.Alloc. |
| `This block has … bytes, and the structure takes ….` | Allocate the size of the structure. |
| `callback needs a callback, not ….` | Give what c.Callback made. |
| `c.Callback needs a function, not ….` | Give a function. |
| `c.Struct needs at least one field.` | Give c.Struct at least one field. |
| `… can't be a field of a structure.` | Use a number type or ptr. |
| `Field … is outside this structure of … fields.` | Count the fields from 1. |
| `… needs a structure type, not ….` | Give what c.Struct made. |
| `… can't be a variadic argument: C promotes it. Use i32 or f64.` |  |
| `… can't go through a callback.` | Use numbers and ptr in a callback. |
| `c.Fn needs a library, not ….` | Give what c.Open gave. |
| `c.Open needs a version as an integer or a text, not ….` | Give a version as 6 or "1.2". |
| `… doesn't fit in ….` | Give a value within the range of the C type. |
| `This … doesn't fit in an integer.` | Use a smaller type, or read it as two halves. |
| `… needs an integer, not ….` | Give an integer. |
| `… needs a number, not ….` | Give a number. |
| `bool needs true or false, not ….` | Give true or false. |
| `ptr needs a pointer, a block or missing, not ….` | Give a block, a pointer or missing. |
| `text needs a text or missing, not ….` | Give a text or missing. |
| `c.Alloc needs a size of 1 or more, not ….` | Give a size of 1 or more. |
| `Offset … is outside this block of … bytes for … ….` | Keep the offset inside the block. |
| `An offset is an integer, not ….` | Give an integer. |
| `… can't be … a block.` | Read or write the type the block holds. |
| `c.… needs a block, not ….` | Give what c.Alloc gave. |
| `c.Text needs a pointer, not ….` | Give a pointer. |
| `This block was freed.` | Don't use a block after c.Free. |
| `Nothing of C runs before a library is open: structures, pointers and calls wait for c.Open.` | `Call c.Open first: it checks the ffi permission for the whole of std/c.` |
| `This text has a zero byte, which C would read as its end.` | Remove the zero byte, or pass bytes in a block. |

## Native packages

The `[native]` table of a package's `cesia.toml`, and the engine Cesia loads at a native's first call: see
[Native packages](native.md).

| Message | Hint, or what to do |
|---|---|
| `[native] needs package, the folder of a package of the project, and natives, an array of the names of its natives.` | Give both keys in the `[native]` table. |
| `[native] natives: … isn't a private name, as a native of a package is: a small first letter, no _.` | Rename the native; the package's public function wraps it. |
| `native/ has no engine for …: build the engine of this project.` | Build the engine for this system and this Cesia; the parenthesis lists the engines the folder has. |
| `… has no engine for …: run cesia pkg install.` | The dependency has no engine for this system and this Cesia: install it again, or ask its author for one. |
| `The engine … didn't load: ….` | The reason after the colon says what failed: the file, its fingerprint or a check. |
| `it needs …, which this Cesia doesn't hold` | A reason of the message above: the engine uses an OCaml module that this Cesia's binary doesn't link, as `Stdlib__Dynarray`. Its author rebuilds it without that module. |
| `… changed since this Cesia loaded it: run the program again.` | The engine's file was replaced while the program ran: start the program again. |
| `The engine … doesn't give the natives of its cesia.toml: it lacks …; it adds ….` | The engine and the `natives` list of `[native]` must name the same natives. |
| `Cesia_v1.…, by a native package.` | The engine called a function of `Cesia_v1` the wrong way (as `register` twice, or off Cesia's domain): a bug of the package. |
| `… raised …: a bug of its native package.` | The native raised an OCaml exception: report it to the package's author. |
| `… needs …, not ….` | A native was given a value of the wrong kind: give the kind the message names. |

## The debugger and tools

From std/debug and the tools that `cesia` runs.

| Message | Hint, or what to do |
|---|---|
| `The debugger has no function OnStop(stop).` | A debugger given to --debugger defines OnStop(stop). |
| `This tool has no function Main().` | A tool defines Main(). |
| `The debugger's engine didn't load: ….` |  |
| `Eval needs a frame of a stop, as stop.Frames[1], not ….` | Give Eval a frame of the stop, as stop.Frames[1]. |
| `OnStop must return "continue", "step", "next" or "out", not ….` | Return one of the four words. |

## Tests

What `cesia test` prints, and the bugs of std/test: see [Tests](tests.md).

| Message | Hint, or what to do |
|---|---|
| `std/test and std/gen work under cesia test, in a test function of a .test.ce file or a tests folder.` | Move the code into a test function of a .test.ce file. |
| `at case … of …` |  |
| `on the case an earlier run saved` |  |
| `, shrunk from … draws to …:` |  |
| `it stopped: …` |  |
| `…: no test is named …; its tests are ….` |  |
| `it called sys.Exit(…), which would end the whole run.` |  |
| `saved, tried first next time; these cases again: cesia test … --seed …` |  |
| `… passed, … failed, seed …` |  |
| `…, part … of …` |  |
| `… at the ? of line …` |  |
| `the same float but for its last bits: math.Near(…, …)?` |  |
| `rel can't help at 0: give abs` |  |
| `== compares element by element: value.Equal(a, b)?` |  |
| `The test ran past its … s.` | `timeout of [test] in cesia.toml gives a test more time.` |
| `Its Temp folder is kept: …` |  |
| `new snapshot …: review it, then cesia test --update` |  |
| `snapshot … changed: cesia test --update keeps the new text` |  |
| `cesia test needs its plugin, cesia_testing.cmxs, beside the binary: …` |  |

## The command line

From `cesia` itself, before a program runs: the command ends with the code 2, or 3 for an internal error.

| Message | Hint, or what to do |
|---|---|
| `cesia: can't read …` |  |
| `cesia: unknown permission: …` |  |
| `cesia: invalid permission: …` |  |
| `cesia: invalid size: …` |  |
| `cesia: invalid limit: …` |  |
| `cesia: unknown limit: …` |  |
| `invalid seed: …, a whole number` |  |
| `invalid number of workers: …, a whole number from 1, or cores` |  |
| `--workers and --watch don't go together: --watch reloads one process` |  |
| `--workers needs Linux or macOS: on Windows, a program serves on one core` |  |
| `cesia: nothing is documented under …` |  |
| `cesia: … is in std/…: cesia doc ….….` |  |
| `Internal error: …` |  |

## cesia.toml, cesia do and cesia new

From the reader of `cesia.toml`, each with `cesia.toml:LINE:` in front, and from `cesia do` and `cesia new`.

| Message | Hint, or what to do |
|---|---|
| `This line is not valid UTF-8.` |  |
| `Control characters aren't allowed here.` |  |
| `… aren't supported in this file.` |  |
| `Arrays hold strings only in this file.` |  |
| `Expected ….` |  |
| `This string is not closed.` |  |
| `This array is not closed.` |  |
| `The escape \… isn't supported in this file.` |  |
| `… is defined twice.` |  |
| `No cesia.toml in this folder.` |  |
| `cesia.toml has no name in [project].` |  |
| `cesia.toml has no task.` |  |
| `Unknown table […].` |  |
| `Unknown field … outside any table.` |  |
| `… has an unknown field ….` |  |
| `…: … needs ….` |  |
| `Task …: run needs at least one word.` |  |
| `Task … has both run and file.` |  |
| `Task … has … without file.` |  |
| `Task … needs …, which doesn't exist.` |  |
| `Task … needs itself, through ….` |  |
| `(needs …)` |  |
| `A project name holds letters, digits, - and _, not ….` |  |
| `… already exists.` |  |
| `Created …. Run it: cd … && cesia do run` |  |
| `No task named ….` |  |
| `Task … runs no program of its own, so it takes no words after its name.` | Give the words to a task that has run or file. |
| `Can't start …: ….` |  |

## Next

The [Commands](commands.md) give the exit code of each kind of error.
