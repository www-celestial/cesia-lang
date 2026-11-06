# A call nested in the next one, 10,000 times: compiling it stays linear.
(echo 'use std/io'; echo 'f(x) = x + 1'; printf 'io.Print(1'; printf ' then f(it)%.0s' $(seq 1 10000); echo ')') > "$tmp/long-pipeline.ce"
timeout 3 "$cesia" run $no_spec "$tmp/long-pipeline.ce"
