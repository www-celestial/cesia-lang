# A slider's number set in place in a session (cells.Set): the loop whose machine code took it as a constant makes its
# code once more, which reads the number from a slot at each run, then keeps it for every next value: ten values of k
# make one unit more than the first run, not one each until the loop gives up. A set of another kind (an Int) makes it
# again. Each answer the same as with the JIT off. The time each cell took varies, and the byte that starts a message
# shows as @.
units() { CESIA_JIT_SHOW=1 cesia run --cells slider.ce < "$1" 2>&1 > /dev/null | grep -c ': module$'; }
answers() { CESIA_JIT=$1 cesia run $no_spec --cells slider.ce < slider-kinds.stdin | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' | tr '\001' '@'; }
once=$(units slider-once.stdin)
echo "ten values of k, one unit more: $([ "$(units slider-sets.stdin)" -eq $((once + 1)) ] && echo true || echo false)"
echo "an Int, a Float, an Int: three units more: $([ "$(units slider-kinds.stdin)" -eq $((once + 4)) ] && echo true || echo false)"
hot=$(answers hot)
echo "$hot"
[ "$hot" = "$(answers off)" ] && echo "the same with the JIT off"
[ "$hot" = "$(answers always)" ] && echo "the same with machine code from the first run"
