#!/usr/bin/env bash
# tools/release-sqlite.sh BINARY: the binary of a release loads its SQLite plugin and opens SQLite from its own lib/, the version that
# tools/release-libs.sh pins, not the system's. Run by .github/workflows/release.yml on each system.
set -eu
want=$(sed -n 's/.*sqlite_version=\([0-9.]*\).*/\1/p' "$(dirname "$0")/release-libs.sh")
dir=$(mktemp -d)
printf 'use sqlite3\nuse pkg/sql\nPrint(Unwrap(sqlite3.Version()))\nPrint(Unwrap(sql.Open("sqlite::memory:") then AndThen(db -> sql.One("select 40 + 2 as x", [], db))).X)\n' > "$dir/v.ce"
have=$("$1" run "$dir/v.ce" | tr -d '\r')
rm -rf "$dir"
[ "$have" = "$want
42" ] || { echo "SQLite of the release: $have, wanted $want" >&2; exit 1; }
echo "SQLite $want"
