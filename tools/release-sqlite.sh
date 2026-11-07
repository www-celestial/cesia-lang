#!/usr/bin/env bash
# tools/release-sqlite.sh BINARY: the binary of a release loads its SQLite plugin and opens SQLite from its own lib/, the version that
# tools/release-libs.sh pins, not the system's. Run by .github/workflows/release.yml on each system.
set -eu
want=$(sed -n 's/.*sqlite_version=\([0-9.]*\).*/\1/p' "$(dirname "$0")/release-libs.sh")
dir=$(mktemp -d)
printf 'use std/sqlite3\nuse std/sql\nuse std/io\nuse std/result\nio.Print(result.Unwrap(sqlite3.Version()))\nio.Print(result.Unwrap(sql.Open("sqlite::memory:") then result.AndThen(db -> sql.One("select 40 + 2 as x", [], db))).X)\n' > "$dir/v.ce"
# On Windows the binary reads Windows paths, not those of the shell it runs in.
file="$dir/v.ce"
command -v cygpath > /dev/null && file=$(cygpath -w "$file")
have=$("$1" run "$file" | tr -d '\r')
rm -rf "$dir"
[ "$have" = "$want
42" ] || { echo "SQLite of the release: $have, wanted $want" >&2; exit 1; }
echo "SQLite $want"
