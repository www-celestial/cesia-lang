# A stop in the middle of a long loop typed at a prompt, which gives a variable and that of its for in place: both as the
# loop left them at the checkpoint where the stop came, n equal to i, with the interpreter and with machine code from hot
# loops and from the first run. The stop comes a while after the loop started; a forget of no name waits for the run
# after it.
for mode in off hot always; do
  printf '%s\n' "$mode:"
  {
    printf '%s\n' '{"Do":"run","Code":"n = 0\ni = 0","Line":0,"Path":"cells-loops.ce"}'
    printf '%s\n' '{"Do":"run","Code":"for i in 1..4000000000\n  n = n + 1\nend","Line":0,"Path":"cells-loops.ce"}'
    sleep 0.3
    printf '%s\n' '{"Do":"stop"}'
    printf '%s\n' '{"Do":"run","Code":"[n == i, n > 0]","Line":0,"Path":"cells-loops.ce"}'
    printf '%s\n' '{"Do":"forget","Names":[]}'
    printf '%s\n' '{"Do":"stop"}'
  } | CESIA_JIT=$mode cesia run $no_spec --cells cells-loops.ce | tr '\001' '@' | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' -e 's/"Mark":"[0-9a-f]*"/"Mark":"TOKEN"/' -e '/^@token [0-9a-f]*$/d'
done
