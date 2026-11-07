cesia test $no_spec passing.test.ce:isSun
echo "exit $?"
echo "== a function that is no test"
cesia test $no_spec only.test.ce:isTwice
echo "exit $?"
echo "== the test that is there"
cesia test $no_spec passing.test.ce:isSum
