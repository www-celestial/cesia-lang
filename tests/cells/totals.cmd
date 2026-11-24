# The side of the session for totals: for each column of a table, by name or by the key of a table a run showed, the count
# of its values that aren't missing, NaN being one, the missing ones, and for a column of numbers their sum, mean, least
# and greatest; over every row, or over the rows a filter keeps, as rows filters them; and what can't be totaled. The time
# each cell took varies, and so does the token of the session, told first and held by each message; the byte that starts a
# message shows as @.
cesia run $no_spec --cells totals.ce | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'
