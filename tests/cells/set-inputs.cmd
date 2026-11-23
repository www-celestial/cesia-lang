# The side of the session for the inputs other than sliders: set with a Kind gives a name the value of its text, read as a
# file writes it and never run, in place, when the name holds a value of the same kind: a text for a text, true or false
# for true or false, a date for a date, a number for a number. It refuses a text with $(...) or $name in it, a text not
# written as a value, a value of another kind, a day that is none, a function and a name that holds nothing. The time each
# cell took varies, and so does the token of the session, told first and held by each message; the byte that starts a
# message shows as @.
cesia run $no_spec --cells form.ce | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e 's/^@token [0-9a-f]*$/@token TOKEN/'
