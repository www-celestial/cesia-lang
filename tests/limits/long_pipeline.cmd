# A call nested in the next one, 10,000 times: compiling it stays linear.
(echo 'f(x) = x + 1'; printf 'Print(1'; printf ' then f(it)%.0s' $(seq 1 10000); echo ')') > "$tmp/long_pipeline.k"
timeout 3 "$kepler" run $no_spec "$tmp/long_pipeline.k"
