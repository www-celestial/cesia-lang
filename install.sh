#!/bin/sh
# Installs Cesia on Linux and macOS, from its releases:
#   curl -fsSL https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.sh | sh
# The archive of this system (bin/cesia and lib/, every C library it uses) goes into ~/.cesia once its fingerprint is checked,
# and cesia and ce into ~/.local/bin. Then cesia upgrade keeps it up to date. Downloaded this way, macOS doesn't hold the
# binary back, as it does for a file taken through a browser.
# CESIA_HOME and CESIA_BIN change the two folders; CESIA_RELEASES=file:///folder reads a folder instead of GitHub.
set -eu
case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) echo "Cesia has no release for $(uname -s): build it from its sources." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) echo "Cesia has no release for $(uname -m): build it from its sources." >&2; exit 1 ;;
esac
archive="cesia-$os-$arch.tar.gz"
releases=${CESIA_RELEASES:-https://github.com/www-celestial/cesia-lang/releases/latest/download}
home=${CESIA_HOME:-$HOME/.cesia}
bin=${CESIA_BIN:-$HOME/.local/bin}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch() {
  case "$1" in
    file://*) cp "${1#file://}" "$2" ;;
    *) curl -fsSL --retry 3 -o "$2" "$1" ;;
  esac
}
fetch "$releases/$archive" "$tmp/$archive"
fetch "$releases/$archive.sha256" "$tmp/$archive.sha256"
if command -v sha256sum > /dev/null; then
  have=$(sha256sum "$tmp/$archive" | cut -d' ' -f1)
else
  have=$(shasum -a 256 "$tmp/$archive" | cut -d' ' -f1)
fi
if [ "$have" != "$(cut -d' ' -f1 < "$tmp/$archive.sha256")" ]; then
  echo "The download of $archive doesn't match its fingerprint: nothing installed." >&2
  exit 1
fi
mkdir "$tmp/new"
tar -xzf "$tmp/$archive" -C "$tmp/new"
version=$("$tmp/new/bin/cesia" version)
mkdir -p "$home" "$bin"
for part in bin lib; do
  rm -rf "$home/$part.old"
  if [ -e "$home/$part" ]; then mv "$home/$part" "$home/$part.old"; fi
  mv "$tmp/new/$part" "$home/$part"
  rm -rf "$home/$part.old"
done
ln -sf "$home/bin/cesia" "$bin/cesia"
ln -sf "$home/bin/cesia" "$bin/ce"
echo "Installed $version in $home: cesia and ce are in $bin."
case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "Add $bin to your PATH." ;;
esac
