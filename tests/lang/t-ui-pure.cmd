! grep "^use " "$root/src/std/ui.ce" | grep -qvE "^use std/(list|math|value|text|dict)$" && "$root/_build/default/src/bin/main.exe" run $no_spec t-ui-pure.ce
