function mitm() {
  local keychain="/Library/Keychains/System.keychain"
  local certificate="${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"

  if [[ ! -f "${certificate}" ]]; then
    print "mitmproxy certificate not found at '${certificate}'. Run mitmproxy once to generate it."
    return 1
  fi

  print "Trusting mitmproxy certificate..."
  sudo security add-trusted-cert -d -p ssl -p basic -k "${keychain}" "${certificate}"

  print "Starting mitmproxy..."
  sudo mitmproxy --mode local

  print "Removing mitmproxy certificate..."
  sudo security delete-certificate -c "mitmproxy" "${keychain}"

  print "Session ended."
}
