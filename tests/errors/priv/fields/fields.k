-- A struct with a small field, for the tests of private fields.
struct Secret { key, Label }

New() = Secret("k", "public")
Record() = {size: 1}
