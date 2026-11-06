cesia run $no_spec --allow read find.ce -i -n alpha sample.txt
cesia run $no_spec --allow read find.ce --max 1 line sample.txt
cesia run $no_spec --allow read find.ce -x alpha sample.txt
echo "exit $?"
cesia run $no_spec --allow read find.ce alpha 2> /dev/null
echo "exit $?"
cesia run $no_spec --allow read find.ce alpha nothing.txt
