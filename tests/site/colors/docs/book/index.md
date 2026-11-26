# Colors

A block of each language the site reads, then the generic reading, an output and a block that names no language.

java:

```java
// A record and a text block
@Override
public static int count(String s) { /* note: "not a text" */
    var t = """
        Hello, "world"
        """;
    char c = '\n';
    return s.length() + 0x1F + 1_000L + 3.5e-2; // done
}
```

kotlin:

```kotlin
/* outer /* nested */ still a comment */
fun greet(name: String) = "Hi ${name.uppercase()} and ${"inner"}"
val raw = """C:\path\${x}"""
@JvmStatic val n = 42
```

scala:

```scala
object Main { // entry
  def main(args: Array[String]): Unit =
    println(s"sum ${1 + 2} of ${args.length}")
  val t = """raw \n""" /* c */
}
```

c:

```c
#include <stdio.h>
#define MAX 10 // a macro
int main(void) {
    char *url = "http://x//y"; /* // inside */
    printf("%d\n", 'a' + MAX);
    return 0;
}
```

cpp:

```cpp
#include <vector>
template <typename T> T twice(T x) { return x * 2; }
auto s = R"json({"a": "b\n"})json";
int big = 1'000'000; // digit separators
std::vector<int> v{1, 2};
```

csharp:

```csharp
#region Main
[Serializable]
public class P { // a class
    string path = @"C:\dir\";
    string msg = $"Hi {name}, {{braces}} {x + 1}";
    string raw = """a "quoted" b""";
    char c = 'x';
}
#endregion
```

go:

```go
package main

import "fmt"

func main() {
	s := `raw \n "quoted"`
	r := 'x'
	fmt.Println("hi // not a comment", s, r, 0x2A)
}
```

rust:

```rust
// Lifetimes, chars and raw texts
#[derive(Debug, Clone)]
fn first<'a>(s: &'a str) -> char {
    let c = 'x'; let n = '\n'; let u = '\u{1F600}';
    let r = r#"a "quoted" \ text"#;
    let b = b"bytes"; let bc = b'a';
    /* outer /* nested */ still */
    println!("{} {}", s, 1_000u32);
    'outer: loop { break 'outer; }
    c
}
```

swift:

```swift
import Foundation
/* outer /* nested */ comment */
@MainActor func hi(_ n: String) -> String {
    let raw = #"a "quoted" \(n) text"#
    return "Hello, \(n.uppercased()) \("x")"
}
```

zig:

```zig
const std = @import("std");
// a comment
pub fn main() void {
    const s =
        \\a multiline "text"
        \\second line
    ;
    std.debug.print("{s} {c}\n", .{ s, 'z' });
}
```

dart:

```dart
void main() {
  var name = 'Bob'; // a comment
  print("Hi ${name.toUpperCase()} and $name");
  var raw = r'C:\path\$x';
  var multi = """three
  lines""";
}
```

typescript:

```typescript
interface User { name: string; age?: number }
const re = /a\/b[/]c/g, half = total / 2 / 3;
export function greet(u: User): string {
  return `Hi ${u.name.trim()} ${`nested ${1}`}`; // template
}
```

tsx:

```tsx
export const App = ({ items }: Props) => (
  <ul className="list" data-x={items.length > 1 ? "many" : "one"}>
    {items.map((i) => <li key={i}>Don't {i} &amp; more</li>)}
  </ul>
);
const lt = a < b;
```

php:

```php
<?php
// a comment
# another
$name = "World";
echo "Hello {$name} and ${name}\n"; /* block */
$doc = <<<EOT
  Heredoc with $name
  EOT;
function f(array $xs): int { return count($xs); }
```

ruby:

```ruby
# a comment
def greet(name = "you")
  puts "Hi #{name.upcase} #{"nested"}"
  :symbol; @ivar = 1; $global = 2
  re = /a#b/i
  text = <<~EOS
    heredoc #{name}
  EOS
  return name.empty?
end
=begin
block comment
=end
```

perl:

```perl
#!/usr/bin/perl
use strict;
my $name = "World"; my @xs = (1, 2); my %h = (a => 1);
print "Hello, $name\n" if $name =~ /W(or)ld/;
=pod
Documentation
=cut
sub f { return 10 % 3; }
```

elixir:

```elixir
defmodule Hi do
  @moduledoc "A module"
  def greet(name) when is_binary(name) do
    IO.puts("Hi #{String.upcase(name)}") # comment
    {:ok, name}
  end
end
```

erlang:

```erlang
-module(hi).
-export([greet/1]).
% a comment
greet(Name) ->
    C = $", D = $\n,
    io:format("Hi ~s~n", [Name]), 'quoted atom'.
```

haskell:

```haskell
{- outer {- nested -} still -}
module Main where
import qualified Data.Map as M
-- a comment
main :: IO ()
main = do
  let x' = foldl' (+) 0 [1, 2, 3] --> not a comment
  putStrLn ("sum: " ++ show x' ++ ['a'])
```

clojure:

```clojure
; a comment
(ns hi.core)
(defn greet [name]
  (println (str "Hi " name) \a \newline \")
  {:name name, :age 42})
#_(ignored form)
```

scheme:

```scheme
#| block #| nested |# comment |#
(define (square x) (* x x)) ; inline
(display #\a)
(let-values ([(q r) (floor/ 7 2)]) (list q r))
```

julia:

```julia
#= block #= nested =# comment =#
function f(x::Vector{Float64})
    A = [1 2; 3 4]'   # transpose, not a text
    c = 'a'
    @time println("sum $(sum(x)) of $x")
    return :done
end
```

fortran:

```fortran
program hi
  implicit none
  integer :: i ! a comment
  real(8) :: x = 1.5d0
  print *, 'it''s', .true.
  do i = 1, 10
  end do
end program hi
```

sql:

```sql
-- a comment
SELECT u.name, count(*) AS n FROM users u
WHERE u.note = 'it''s' AND u.id = $1 /* block /* nested */ */
GROUP BY u.name ORDER BY n DESC;
CREATE FUNCTION f() RETURNS int AS $$ SELECT 'x'; $$ LANGUAGE sql;
create table t (id serial primary key, body text default 'a', t timestamptz);
SELECT x::int, :name FROM t;
```

json:

```json
{
  "name": "cesia", "version": 1.3, "tags": ["a", "b"],
  "ok": true, "none": null, "url": "http://x//y",
  "nested": {"key": "a \"quoted\" value"} // jsonc comment
}
```

yaml:

```yaml
# a comment
name: build
on: [push]
anchors: &base
  key: "a # not a comment"
  other: 'single ''quoted'''
jobs:
  test:
    - run: |
        echo "a shell line: not yaml"
        exit 0
      shell: bash
ref: *base
url: http://example.com/#frag
---
```

html:

```html
<!DOCTYPE html>
<!-- a comment -->
<p class="note" data-x='1'>Fish &amp; chips &lt; 5 &#233;</p>
<script>const x = "</p>"; // js
</script>
<style>p { color: red; }</style>
```

xml:

```xml
<?xml version="1.0"?>
<root xmlns:a="urn:a"><a:item id="1"/><![CDATA[ <raw> & stuff ]]></root>
```

markdown:

````markdown
# A title

Some `code` and text with 2 numbers.

```python
def f(): return 1
```

```cesia
x = 1 + 2 -->
```
<!-- a comment -->
````

properties:

```properties
# a comment
! another
server.port=8080
spring.datasource.url: jdbc:postgresql://localhost/db
greeting=Hello # not a comment
```

dockerfile:

```dockerfile
# syntax=docker/dockerfile:1
FROM alpine:3.20 AS build
RUN apk add --no-cache curl && echo "done # not a comment"
ENV PATH=/app/bin:$PATH
COPY --from=build /app ${DEST}
CMD ["./app", "--port", "8080"]
```

makefile:

```makefile
# a comment
CC := gcc
CFLAGS ?= -O2
all: main.o util.o
	$(CC) $(CFLAGS) -o app $^ # recipe
.PHONY: clean
clean:
	rm -f *.o
```

cmake:

```cmake
cmake_minimum_required(VERSION 3.20)
project(Hi LANGUAGES C)
#[[ a block
comment ]]
add_executable(hi main.c) # inline
if(NOT DEFINED X)
  set(X "${CMAKE_SOURCE_DIR}/x")
endif()
```

nginx:

```nginx
server {
    listen 80;  # a comment
    server_name example.com;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
    }
}
```

http:

```http
POST /api/users HTTP/1.1
Host: example.com
Content-Type: application/json

{"name": "Ana", "age": 31}
```

graphql:

```graphql
# a comment
query User($id: ID!) {
  user(id: $id) @include(if: true) {
    name
    friends(first: 10) { name }
  }
}
```

protobuf:

```protobuf
syntax = "proto3";
package hi;
// a comment
message User {
  string name = 1;
  repeated int32 ids = 2 [packed = true];
}
```

nix:

```nix
{ pkgs ? import <nixpkgs> {} }:
# a comment
let
  name = "hi-${pkgs.lib.version}";
  script = ''
    echo "in ${name}"
  '';
in pkgs.mkShell { buildInputs = [ pkgs.hello ]; }
```

latex:

```latex
\documentclass{article}
% a comment
\begin{document}
Price: 50\% off, $x^2 + y^2$ and
$$\frac{1}{2}$$
\end{document}
```

diff:

```diff
diff --git a/x.ce b/x.ce
index 1a2b3c4..5d6e7f8 100644
--- a/x.ce
+++ b/x.ce
@@ -1,3 +1,3 @@
 x = 1
-y = 2
+y = 3
\ No newline at end of file
```

console:

```console
$ cesia run hello.ce
Hello, world!
ana@box:~/shop$ curl -s https://x.com/#a | jq '.name' # a comment
"shop"
$ echo "a long \
>   line"
total 42
```

bash:

```bash
#!/bin/sh
# a comment
url=https://x.com/#not-a-comment
echo "Hi $USER, today is $(date +%A) and ${HOME}" # yes
cat > notes.txt <<'EOF'
Text with $no expansion # and no comment
EOF
for f in *.ce; do echo "$f"; done
```

lua:

```lua
-- a comment
--[==[ a long
comment ]==]
local s = [[a long
text]] .. "x"
print(string.format("%d", 10))
```

ocaml:

```ocaml
(* outer (* nested *) comment *)
let rec map f = function [] -> [] | x :: xs -> f x :: map f xs
type 'a tree = Leaf | Node of 'a tree * 'a * 'a tree
let c = 'x' and n = '\n' and x' = 1
```

css:

```css
/* a comment */
@media (max-width: 600px) {
  a:hover { font-size: 1.5em; color: #fff; }
  .note::before { content: "a: b"; --main-color: red; }
}
```

powershell:

```powershell
# a comment
<# a block #>
$name = "World"
Write-Host "Hello $name, $($name.Length)"
$doc = @"
here string $name
"@
```

r:

```r
# a comment
x <- c(1, 2, 3.5e2)
f <- function(n) paste0("n = ", n, '!')
if (TRUE) print(f(x[1]))
```

matlab:

```matlab
% a comment
A = [1 2; 3 4]';
s = 'it''s';
disp(sprintf("%d", A(1)))
```

toml:

```toml norun
# a comment
[project]
name = "shop"
"quoted key" = 1
[[peer]]
path = 'C:\raw'
when = 1979-05-27T07:32:00Z
```

ini:

```ini
; a comment
[section]
key=value ; inline
path: /usr/bin
```

python:

```python
@app.route("/x")
def f(x, y="a # b"):  # a comment
    return f"{d["k"]:>3} {{x}}" + r"\d" + b"\x00" + """doc "string" """
```

brainfudge:

```brainfudge
# a comment line
x = "a text" + 'b' // not here
// a comment
don't stop: 42 /* closed */ path/*.c
```

Aliases:

```py
print(f"{x!r}")
```

```yml
a: 1
```

```c++
int x = 1;
```

An output:

```text
3 passed, 0 failed
```

```output
x = 1 # not a comment
```

No language:

```
x = 1
```
