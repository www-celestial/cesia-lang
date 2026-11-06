cesia run $no_spec --allow ffi=sqlite3 --allow read=. denied-write.ce 2>&1 | sed -n "1s/^std[^ ]* //p"
