#!/bin/zsh

# @raycast.title NextDNS Status
# @raycast.packageName NextDNS
# @raycast.icon icons/nextdns-status.png

# @raycast.argument1 { "type": "dropdown", "placeholder": "Action", "data": [{"title": "Enable", "value": "activate"}, {"title": "Disable", "value": "deactivate"}] }
# @raycast.mode silent

# @raycast.schemaVersion 1

nextdns "$@"

sleep 0.5

if [[ "$(scutil --dns | grep "nameserver\[0\]" | head -1 | awk '{print $3}')" == "127.0.0.1" ]]; then
  print "NextDNS is enabled"
else
  print "NextDNS is disabled"
fi
