# A function that a session defines again with the same code keeps the machine code made for the one before: spring of
# twins.ce defined again four times makes no unit more than the first time; with another body, or in a cell that declares
# an interface, through which a method is found from the module of the cell, it is made again (units of the typed path,
# where the JIT has its candidates). A loop whose machine code took k of a cell run again makes it again for each new k,
# never giving up for good, though its short runs never paid for its making. Each answer the same as with the JIT off:
# the same body, another, k of another cell given again as a Float then an Int, a helper spring calls defined again, a
# recursion, a closure, an error in a function defined again. The time each cell took varies, and the byte that starts a
# message shows as @.
units() { CESIA_JIT_SHOW=1 cesia run --cells twins.ce < "$1" 2>&1 > /dev/null | grep -c ': module$'; }
answers() { CESIA_JIT=$1 cesia run $no_spec --cells twins.ce < twins-edits.stdin | sed -e 's/"Seconds":[^,}]*/"Seconds":0/' | tr '\001' '@'; }
once=$(units twins-once.stdin)
echo "units the same after four runs again: $([ "$(units twins-again.stdin)" = "$once" ] && echo true || echo false)"
echo "units made again for another body: $([ "$(units twins-edit.stdin)" -gt "$once" ] && echo true || echo false)"
echo "units made again when the cell declares an interface: $([ "$(units twins-iface.stdin)" -gt "$once" ] && echo true || echo false)"
echo "a unit made again for each of ten new values of k, short runs: $([ "$(units twins-params.stdin)" -ge 10 ] && echo true || echo false)"
hot=$(answers hot)
echo "$hot"
[ "$hot" = "$(answers off)" ] && echo "the same with the JIT off"
