# The side of the session for tables: rows of a name or of the key of a table a run showed, sorted by a column, increasing
# or decreasing, numbers as numbers, NaN and missing last, equal values in their order; filtered by words in any column,
# ASCII letters in either case; the place of a row found; and what a sort or a filter can't be. The time each cell took
# varies, and so does the token of the session, told first and held by each message; the byte that starts a message shows
# as @.
cesia run $no_spec --cells tables.ce | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'
