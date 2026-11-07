# Cesia_v1 is frozen once released: OCaml checks every byte of cesia_v1.mli in each engine, so a comma changed in a comment
# would refuse every engine built before. What comes later goes in new modules, Cesia_v1_1 and on: this never changes.
cesia run --allow read fingerprint.ce ../../src/native/cesia_v1.mli
