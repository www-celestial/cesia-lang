cesia run $no_spec --allow read=shop.db,write=shop.db denied-wal.ce 2>&1 | sed -n "1s/^[^ ]* //p"
