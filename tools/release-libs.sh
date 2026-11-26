#!/usr/bin/env bash
# Builds the C libraries a release holds beside its binary, so that nothing has to be installed by hand:
# tools/release-libs.sh SYSTEM FOLDER puts them in FOLDER/lib, their licenses in FOLDER/lib/licenses. Run from the root of the
# repository by the release job of the CI, which keeps FOLDER in its cache: a version changed here builds them again.
#   linux-x86_64     OpenBLAS (BLAS and LAPACK, the kernels of every processor, no Fortran) and libsodium; OpenSSL stays
#                    the system's, which gets its security fixes.
#   macos-arm64      libsodium and OpenSSL 3.5, its long-term version; BLAS and LAPACK are macOS's own, Accelerate.
#   windows-x86_64   OpenBLAS as its project publishes it for Windows, libsodium and OpenSSL 3.5 as on macOS, built in the
#                    shell of MSYS2 for UCRT64 (msys2 -c), whose make, perl, python and gcc it needs.
# All three hold SQLite: built from its amalgamation, the DLL that sqlite.org publishes on Windows.
# The names are those c.Open and the BLAS search ask for: see src/sys/c.ml and src/sys/linalg.ml.
set -eu
system=$1
root=$PWD
out=$(mkdir -p "$2" && cd "$2" && pwd)
openblas=0.3.28 sodium=1.0.20 openssl=3.5.9
openblas_sha256=f1003466ad074e9b0c8d421a204121100b0751c96fc6fcf3d1456bd12f8a00a1
openblas_win_sha256=4cbd0e5daa3fb083b18f5e5fa6eefe79e2f2c51a6d539f98a3c6309a21160042
sodium_sha256=ebb65ef6ca439333c2bb41a0c1990587288da07f6c7fd07cb3a18cc18d30ce19
openssl_sha256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
# SQLite: its release, and the SHA3-256 of its files that sqlite.org publishes.
sqlite=3540100 sqlite_year=2026 sqlite_version=3.54.1
sqlite_sha3=92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30
sqlite_dll_sha3=c2d09c8babb9399277055c057c97a53f1ffd7c5f11d0c1f2118ffdfa39f2daa4
work=$(mktemp -d)
lib="$out/lib"
mkdir -p "$lib/licenses"
cd "$work"
fetch() { curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$2" "$1"; }
# A download checked against its SHA-256 before anything reads it. The fingerprints were checked by hand at each change of
# version: OpenSSL's against the .sha256 it publishes, libsodium's against its minisign signatures, OpenBLAS's source
# against the archive of its git tag; OpenBLAS publishes none for its Windows zip, so that one is the file as fetched then.
get() {  # url, file, sha256
  fetch "$1" "$2"
  have=$(python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$2")
  [ "$have" = "$3" ] || { echo "$2: SHA-256 $have, not $3." >&2; exit 1; }
}
jobs=$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)

# A download of SQLite, checked against the fingerprint above before anything reads it.
get_sqlite() {  # file, sha3
  fetch "https://www.sqlite.org/$sqlite_year/$1" "$1"
  have=$(python3 -I -c 'import hashlib, sys; print(hashlib.sha3_256(open(sys.argv[1], "rb").read()).hexdigest())' "$1")
  [ "$have" = "$2" ] || { echo "$1: SHA3-256 $have, not $2." >&2; exit 1; }
  printf 'The author disclaims copyright to this source code. In place of a legal notice, here is a blessing:\n\n    May you do good and not evil.\n    May you find forgiveness for yourself and forgive others.\n    May you share freely, never taking more than you give.\n' > "$lib/licenses/SQLite.txt"
}

# The amalgamation, with what Cesia doesn't use left out: no extension loading, no shared cache, no double-quoted texts.
# -ffp-contract=off, as for Cesia's own C (the file dune): no product fused with an add into one rounding, which GCC on
# arm64 and Clang on macOS do by default, so that its floats, read from a text, written or computed, have the same bits
# on every system. Cesia reads no float from libsodium or OpenSSL; OpenBLAS picks its kernels, in assembly, by processor
# at run time, so that its sums follow the processor whatever the flags of its C.
build_sqlite() {  # output file, then the flags that name it
  get_sqlite "sqlite-amalgamation-$sqlite.zip" "$sqlite_sha3"
  unzip -q "sqlite-amalgamation-$sqlite.zip"
  cc -O2 -ffp-contract=off -fPIC -shared -DSQLITE_DQS=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
    -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_THREADSAFE=1 \
    "sqlite-amalgamation-$sqlite/sqlite3.c" -o "$lib/$1" "${@:2}" -lpthread -lm
}

build_openblas() {
  get "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$openblas/OpenBLAS-$openblas.tar.gz" openblas.tgz "$openblas_sha256"
  tar -xzf openblas.tgz
  # TARGET=GENERIC: the code common to every processor is built for any x86-64, as Debian builds it, and not for the
  # processor of the machine that builds, which OpenBLAS may not know (a runner newer than this version stopped the build
  # in getarch_2nd); with DYNAMIC_ARCH the kernels of each processor are still all built and picked at run time.
  make -C "OpenBLAS-$openblas" -j"$jobs" TARGET=GENERIC DYNAMIC_ARCH=1 NOFORTRAN=1 C_LAPACK=1 USE_OPENMP=0 NUM_THREADS=64 \
    libs shared > /dev/null
  cp -L "OpenBLAS-$openblas/libopenblas.so.0" "$lib/"
  cp "OpenBLAS-$openblas/LICENSE" "$lib/licenses/OpenBLAS.txt"
}

build_sodium() {
  get "https://download.libsodium.org/libsodium/releases/libsodium-$sodium.tar.gz" sodium.tgz "$sodium_sha256"
  tar -xzf sodium.tgz
  (cd "libsodium-$sodium" && ./configure --disable-static --prefix="$work/prefix" > /dev/null && make -j"$jobs" install > /dev/null)
  cp "libsodium-$sodium/LICENSE" "$lib/licenses/libsodium.txt"
}

build_openssl() {
  get "https://github.com/openssl/openssl/releases/download/openssl-$openssl/openssl-$openssl.tar.gz" openssl.tgz "$openssl_sha256"
  tar -xzf openssl.tgz
  (cd "openssl-$openssl" && ./Configure "$1" shared no-tests --prefix="$work/prefix" --libdir=lib > /dev/null &&
    make -j"$jobs" > /dev/null && make install_sw > /dev/null)
  cp "openssl-$openssl/LICENSE.txt" "$lib/licenses/OpenSSL.txt"
}

case "$system" in
  linux-x86_64)
    build_openblas
    build_sodium
    cp -L "$work/prefix/lib/libsodium.so.26" "$lib/"
    build_sqlite libsqlite3.so.0 -Wl,-soname,libsqlite3.so.0
    # A library finds the others beside it.
    for f in "$lib"/*.so*; do patchelf --set-rpath '$ORIGIN' "$f"; done
    ;;
  macos-arm64)
    build_sodium
    build_openssl darwin64-arm64-cc
    build_sqlite libsqlite3.0.dylib -Wl,-install_name,@loader_path/libsqlite3.0.dylib
    for name in libsodium.26.dylib libssl.3.dylib libcrypto.3.dylib; do
      cp -L "$work/prefix/lib/$name" "$lib/"
    done
    # Each one names itself, and the others it needs, as beside it: their build folder is gone on the user's machine.
    for f in "$lib"/*.dylib; do
      [ "$(basename "$f")" = libsqlite3.0.dylib ] && { codesign --force --sign - "$f"; continue; }
      install_name_tool -id "@loader_path/$(basename "$f")" "$f"
      otool -L "$f" | awk 'NR > 1 { print $1 }' | grep "^$work/prefix/" | while read -r dep; do
        install_name_tool -change "$dep" "@loader_path/$(basename "$dep")" "$f"
      done
      codesign --force --sign - "$f"
    done
    ;;
  windows-x86_64)
    get "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$openblas/OpenBLAS-$openblas-x64.zip" openblas.zip "$openblas_win_sha256"
    unzip -q openblas.zip -d openblas
    cp openblas/bin/libopenblas.dll "$lib/"
    cp openblas/LICENSE "$lib/licenses/OpenBLAS.txt" 2> /dev/null || true
    # libsodium and OpenSSL built here as on macOS, by the compiler of MSYS2 for UCRT64, in whose shell release.yml runs
    # this script on Windows; libgcc goes inside them, so that they need no DLL of that compiler on the user's machine.
    export LDFLAGS=-static-libgcc
    build_sodium
    cp "$work/prefix/bin/libsodium-26.dll" "$lib/libsodium.dll"
    build_openssl mingw64
    cp "$work/prefix/bin/libssl-3-x64.dll" "$work/prefix/bin/libcrypto-3-x64.dll" "$lib/"
    get_sqlite "sqlite-dll-win-x64-$sqlite.zip" "$sqlite_dll_sha3"
    unzip -q "sqlite-dll-win-x64-$sqlite.zip" -d sqlite
    cp sqlite/sqlite3.dll "$lib/"
    # Each DLL needs only the others of lib/ and those of Windows itself, never one that only the build machine holds: on a
    # user's machine it would not load. Windows names its DLLs in any case of letters.
    system32=$(cygpath -u "$SYSTEMROOT")/System32
    for f in "$lib"/*.dll; do
      for dll in $(objdump -p "$f" | awk '/DLL Name/ { print $3 }'); do
        case "${dll,,}" in api-ms-win-* | ext-ms-win-*) continue ;; esac
        ls "$lib" "$system32" 2> /dev/null | grep -qixF "$dll" || { echo "$(basename "$f") needs $dll, which Windows lacks." >&2; exit 1; }
      done
    done
    ;;
  *)
    echo "No libraries for $system." >&2
    exit 2
    ;;
esac
cp "$root/LICENSE" "$lib/licenses/Cesia.txt"
# MIR is in the JIT's plugin, lib/cesia_jit.cmxs: its licence goes with it.
cp "$root/src/sys/mir/LICENSE" "$lib/licenses/MIR.txt"
cd "$root"
rm -rf "$work"
ls "$lib"
