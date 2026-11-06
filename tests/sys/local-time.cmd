for zone in UTC Europe/Paris America/New_York Asia/Kathmandu; do
  echo "$zone"
  TZ=$zone cesia run $no_spec local-time.ce
done
