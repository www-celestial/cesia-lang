#!/usr/bin/env bash
# Builds the C libraries a release holds beside its binary, so that nothing has to be installed by hand:
# tools/release-libs.sh SYSTEM FOLDER puts them in FOLDER/lib, their licenses in FOLDER/lib/licenses. Run from the root of the
# repository by the release job of the CI, which keeps FOLDER in its cache: a version changed here builds them again.
#   linux-x86_64     OpenBLAS (BLAS and LAPACK, the kernels of every processor, no Fortran), libsodium, SDL3, SDL3_ttf
#                    (FreeType and HarfBuzz inside); OpenSSL stays the system's, which gets its security fixes.
#   macos-arm64      libsodium, SDL3, SDL3_ttf, OpenSSL 3; BLAS and LAPACK are macOS's own, Accelerate.
#   windows-x86_64   OpenBLAS, libsodium, SDL3 and SDL3_ttf as their projects publish them for Windows, and OpenSSL 3 as
#                    MSYS2 builds it.
# All three hold SQLite: built from its amalgamation, the DLL that sqlite.org publishes on Windows.
# The names are those c.Open and the BLAS search ask for: see src/sys/c.ml and src/sys/linalg.ml.
set -eu
system=$1
root=$PWD
out=$(mkdir -p "$2" && cd "$2" && pwd)
openblas=0.3.28 sodium=1.0.20 sdl=3.2.24 ttf=3.2.2 openssl=3.5.4
# SQLite: its release, and the SHA3-256 of its files that sqlite.org publishes.
sqlite=3540100 sqlite_year=2026 sqlite_version=3.54.1
sqlite_sha3=92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30
sqlite_dll_sha3=c2d09c8babb9399277055c057c97a53f1ffd7c5f11d0c1f2118ffdfa39f2daa4
work=$(mktemp -d)
lib="$out/lib"
mkdir -p "$lib/licenses"
cd "$work"
get() { curl -fsSL --retry 3 -o "$2" "$1"; }
jobs=$(getconf _NPROCESSORS_ONLN 2> /dev/null || echo 4)

# A download of SQLite, checked against the fingerprint above before anything reads it.
get_sqlite() {  # file, sha3
  get "https://www.sqlite.org/$sqlite_year/$1" "$1"
  have=$(python3 -I -c 'import hashlib, sys; print(hashlib.sha3_256(open(sys.argv[1], "rb").read()).hexdigest())' "$1")
  [ "$have" = "$2" ] || { echo "$1: SHA3-256 $have, not $2." >&2; exit 1; }
  printf 'The author disclaims copyright to this source code. In place of a legal notice, here is a blessing:\n\n    May you do good and not evil.\n    May you find forgiveness for yourself and forgive others.\n    May you share freely, never taking more than you give.\n' > "$lib/licenses/SQLite.txt"
}

# The amalgamation, with what Cesia doesn't use left out: no extension loading, no shared cache, no double-quoted texts.
build_sqlite() {  # output file, then the flags that name it
  get_sqlite "sqlite-amalgamation-$sqlite.zip" "$sqlite_sha3"
  unzip -q "sqlite-amalgamation-$sqlite.zip"
  cc -O2 -fPIC -shared -DSQLITE_DQS=0 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
    -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_THREADSAFE=1 \
    "sqlite-amalgamation-$sqlite/sqlite3.c" -o "$lib/$1" "${@:2}" -lpthread -lm
}

build_openblas() {
  get "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$openblas/OpenBLAS-$openblas.tar.gz" openblas.tgz
  tar -xzf openblas.tgz
  make -C "OpenBLAS-$openblas" -j"$jobs" DYNAMIC_ARCH=1 NOFORTRAN=1 C_LAPACK=1 USE_OPENMP=0 NUM_THREADS=64 libs shared > /dev/null
  cp -L "OpenBLAS-$openblas/libopenblas.so.0" "$lib/"
  cp "OpenBLAS-$openblas/LICENSE" "$lib/licenses/OpenBLAS.txt"
}

build_sodium() {
  get "https://download.libsodium.org/libsodium/releases/libsodium-$sodium.tar.gz" sodium.tgz
  tar -xzf sodium.tgz
  (cd "libsodium-$sodium" && ./configure --disable-static --prefix="$work/prefix" > /dev/null && make -j"$jobs" install > /dev/null)
  cp "libsodium-$sodium/LICENSE" "$lib/licenses/libsodium.txt"
}

build_sdl() {
  get "https://github.com/libsdl-org/SDL/releases/download/release-$sdl/SDL3-$sdl.tar.gz" sdl.tgz
  tar -xzf sdl.tgz
  cmake -S "SDL3-$sdl" -B sdl-build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/prefix" -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF > /dev/null
  cmake --build sdl-build -j"$jobs" > /dev/null
  cmake --install sdl-build > /dev/null
  cp "SDL3-$sdl/LICENSE.txt" "$lib/licenses/SDL3.txt"
  # SDL3_ttf with its FreeType and HarfBuzz inside: the sources with their submodules.
  git clone -q --depth 1 --recursive --branch "release-$ttf" https://github.com/libsdl-org/SDL_ttf.git ttf
  cmake -S ttf -B ttf-build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$work/prefix" -DCMAKE_PREFIX_PATH="$work/prefix" \
    -DSDLTTF_VENDORED=ON -DSDLTTF_SAMPLES=OFF > /dev/null
  cmake --build ttf-build -j"$jobs" > /dev/null
  cmake --install ttf-build > /dev/null
  cp ttf/LICENSE.txt "$lib/licenses/SDL3_ttf.txt"
}

build_openssl() {
  get "https://github.com/openssl/openssl/releases/download/openssl-$openssl/openssl-$openssl.tar.gz" openssl.tgz
  tar -xzf openssl.tgz
  (cd "openssl-$openssl" && ./Configure "$1" shared no-tests --prefix="$work/prefix" --libdir=lib > /dev/null &&
    make -j"$jobs" > /dev/null && make install_sw > /dev/null)
  cp "openssl-$openssl/LICENSE.txt" "$lib/licenses/OpenSSL.txt"
}

case "$system" in
  linux-x86_64)
    build_openblas
    build_sodium
    build_sdl
    cp -L "$work/prefix/lib/libsodium.so.26" "$work/prefix/lib/libSDL3.so.0" "$work/prefix/lib/libSDL3_ttf.so.0" "$lib/"
    build_sqlite libsqlite3.so.0 -Wl,-soname,libsqlite3.so.0
    # A library finds the others beside it.
    for f in "$lib"/*.so*; do patchelf --set-rpath '$ORIGIN' "$f"; done
    ;;
  macos-arm64)
    build_sodium
    build_sdl
    build_openssl darwin64-arm64-cc
    build_sqlite libsqlite3.0.dylib -Wl,-install_name,@loader_path/libsqlite3.0.dylib
    for name in libsodium.26.dylib libSDL3.0.dylib libSDL3_ttf.0.dylib libssl.3.dylib libcrypto.3.dylib; do
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
    get "https://github.com/OpenMathLib/OpenBLAS/releases/download/v$openblas/OpenBLAS-$openblas-x64.zip" openblas.zip
    unzip -q openblas.zip -d openblas
    cp openblas/bin/libopenblas.dll "$lib/"
    cp openblas/LICENSE "$lib/licenses/OpenBLAS.txt" 2> /dev/null || true
    get "https://download.libsodium.org/libsodium/releases/libsodium-$sodium-mingw.tar.gz" sodium.tgz
    tar -xzf sodium.tgz
    cp libsodium-win64/bin/libsodium-26.dll "$lib/libsodium.dll"
    get "https://github.com/libsdl-org/SDL/releases/download/release-$sdl/SDL3-devel-$sdl-mingw.zip" sdl.zip
    unzip -q sdl.zip -d sdl
    cp "sdl/SDL3-$sdl/x86_64-w64-mingw32/bin/SDL3.dll" "$lib/"
    cp "sdl/SDL3-$sdl/LICENSE.txt" "$lib/licenses/SDL3.txt"
    get "https://github.com/libsdl-org/SDL_ttf/releases/download/release-$ttf/SDL3_ttf-devel-$ttf-mingw.zip" ttf.zip
    unzip -q ttf.zip -d ttf
    cp "ttf/SDL3_ttf-$ttf/x86_64-w64-mingw32/bin/SDL3_ttf.dll" "$lib/"
    cp "ttf/SDL3_ttf-$ttf/LICENSE.txt" "$lib/licenses/SDL3_ttf.txt"
    # OpenSSL publishes no binaries: MSYS2's, which need only the DLLs of Windows itself. MSYS2_ROOT is where the release job
    # installed it, apart from the /mingw64 of Git's own shell; else C:\msys64.
    msys=$(cygpath -u "${MSYS2_ROOT:-C:\\msys64}")
    if [ ! -f "$msys/mingw64/bin/libssl-3-x64.dll" ]; then
      "$msys/usr/bin/pacman" --noconfirm -S --needed mingw-w64-x86_64-openssl > /dev/null
    fi
    cp "$msys/mingw64/bin/libssl-3-x64.dll" "$msys/mingw64/bin/libcrypto-3-x64.dll" "$lib/"
    cp "$msys"/mingw64/share/licenses/openssl/LICENSE* "$lib/licenses/OpenSSL.txt" 2> /dev/null || true
    get_sqlite "sqlite-dll-win-x64-$sqlite.zip" "$sqlite_dll_sha3"
    unzip -q "sqlite-dll-win-x64-$sqlite.zip" -d sqlite
    cp sqlite/sqlite3.dll "$lib/"
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
