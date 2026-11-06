cesia check --wrong
echo "exit $?"
cesia check nowhere.ce
echo "exit $?"
cd project/src && cesia check
