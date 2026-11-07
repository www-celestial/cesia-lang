rm -f ../../.cesia/failures/tests-testing-exit.test.ce-*
cesia test $no_spec --seed 1 exit.test.ce
echo "exit $?"
rm -f ../../.cesia/failures/tests-testing-exit.test.ce-*
echo "== one test"
cesia test $no_spec exit.test.ce:isZ
echo "exit $?"
echo "== examples"
cesia test $no_spec exit-examples.ce
