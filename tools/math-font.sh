#!/bin/sh
# Makes src/tools/math.woff2, the font of the formulas of cesia doc --site: STIX Two Math 2.13 (SIL Open Font License 1.1,
# src/tools/math-OFL.txt), cut to the characters a formula can hold: ASCII, Latin-1 and the French letters of a \text, Greek,
# the italic letters of MathML, and the symbols of the commands of src/tools/site.ce. A command added there with a new symbol
# adds it here. Needs fonttools (pyftsubset) and woff2_compress.
#   tools/math-font.sh STIXTwoMath-Regular.otf     the font of https://github.com/stipub/stixfonts, tag v2.13b171
set -eu
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
pyftsubset "$1" --layout-features='*' --no-hinting --desubroutinize --output-file="$dir/math.otf" \
  --unicodes="U+0020-007E,U+00A0-00FF,U+0152-0153,U+2013-2014,U+2018-2019,U+201C-201D,U+0391-03A9,U+03B1-03C9,\
U+1D434-1D467,U+210E,U+1D6E2-1D71B,U+2264,U+2265,U+2260,U+2248,U+2261,U+223C,U+2208,U+2209,U+220B,U+2282,U+2286,U+222A,\
U+2229,U+2192,U+00D7,U+22C5,U+00B1,U+2026,U+2308-230B,U+221E,U+2205,U+2211,U+220F,U+2212,U+2032,U+221A,U+2217,U+2218,U+2190"
woff2_compress "$dir/math.otf" > /dev/null
cp "$dir/math.woff2" "$(dirname "$0")/../src/tools/math.woff2"
