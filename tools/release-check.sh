#!/usr/bin/env bash
# tools/release-check.sh BINARY: the binary of a release loads the C libraries of its own lib/, those tools/release-libs.sh
# puts there, not the system's: its SQLite plugin and the SQLite version that script pins, libsodium, which hashes a text, and
# OpenSSL, which makes a client's context (on Linux OpenSSL stays the system's). Run by .github/workflows/release.yml on each
# system, before the archive is made.
set -eu
want=$(sed -n 's/.*sqlite_version=\([0-9.]*\).*/\1/p' "$(dirname "$0")/release-libs.sh")
dir=$(mktemp -d)
cat > "$dir/v.ce" << 'EOF'
use std/sqlite3
use std/sql
use std/io
use std/result
use std/crypto
use std/encode
use std/tls
io.Print(result.Unwrap(sqlite3.Version()))
io.Print(result.Unwrap(sql.Open("sqlite::memory:") then result.AndThen(db -> sql.One("select 40 + 2 as x", [], db))).X)
io.Print(encode.Hex(crypto.Blake2b("abc", result.Unwrap(crypto.Open()))))
tls.Client(result.Unwrap(tls.Open()))
io.Print("tls")
EOF
# On Windows the binary reads Windows paths, not those of the shell it runs in, and finds no DLL on the PATH but Windows's
# own: those of Git, MSYS2 or the compiler, which a user's machine lacks, would hide one that lib/ or bin/ misses.
file="$dir/v.ce"
path=$PATH
if command -v cygpath > /dev/null; then
  file=$(cygpath -w "$file")
  path="$(cygpath -u "$SYSTEMROOT")/System32:$(cygpath -u "$SYSTEMROOT")"
fi
have=$(PATH=$path "$1" run --allow ffi=sodium,ffi=ssl,ffi=crypto "$file" | tr -d '\r')
rm -rf "$dir"
[ "$have" = "$want
42
bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319
tls" ] || { echo "Libraries of the release: $have, wanted SQLite $want, 42, the BLAKE2b of abc and tls" >&2; exit 1; }
echo "SQLite $want, libsodium and OpenSSL"
