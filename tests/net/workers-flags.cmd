cesia run $no_spec --workers 0 workers.ce
echo "exit $?"
cesia run $no_spec --workers lots workers.ce
echo "exit $?"
cesia run $no_spec --workers 2 --watch workers.ce
