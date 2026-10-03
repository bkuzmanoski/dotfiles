function mitm() {
  local keychain="/Library/Keychains/System.keychain"
  local certificate_path="${HOME}/.mitmproxy/mitmproxy-ca-cert.pem"

  if [[ ! -f "${certificate_path}" ]]; then
    print -u2 "mitmproxy certificate not found at \"${certificate_path}\". Run mitmproxy once to generate it."
    return 1
  fi

  print "Trusting mitmproxy certificate..."
  sudo security add-trusted-cert -d -p ssl -p basic -k "${keychain}" "${certificate_path}"

  print "Starting mitmproxy..."
  sudo mitmproxy --mode local

  print "Removing mitmproxy certificate..."
  sudo security delete-certificate -c "mitmproxy" "${keychain}"

  print "Session ended."
}
