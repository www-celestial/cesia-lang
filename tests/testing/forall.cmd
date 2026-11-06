rm -f ../../.cesia/failures/tests-testing-forall.test.ce-*
cesia test $no_spec --seed 1 forall.test.ce
echo "exit $?"
echo "== the failures were saved, and come first"
ls ../../.cesia/failures/ | grep tests-testing-forall | sort
cesia test $no_spec --seed 2 forall.test.ce:isSortAgrees
echo "exit $?"
echo "== --cases 5, one test"
cesia test $no_spec --seed 3 --cases 5 forall.test.ce:isHolds
echo "exit $?"
rm -f ../../.cesia/failures/tests-testing-forall.test.ce-*
