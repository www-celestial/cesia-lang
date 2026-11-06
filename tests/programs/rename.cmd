dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cp rename.ce "$dir"
cd "$dir"
mkdir -p photos/2025/trip photos/2026
touch photos/IMG_001.JPG photos/2025/IMG_002.JPG photos/2025/trip/Notes.TXT photos/2026/IMG_003.jpeg photos/2026/a.png photos/2026/b.jpg
cesia run $no_spec --allow read,write rename.ce --dry photos
cesia run $no_spec --allow read,write rename.ce photos
find photos -type f | LC_ALL=C sort
