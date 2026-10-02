#!/usr/bin/env -S uv run --quiet --script

# @raycast.title Restart Wi-Fi Network
# @raycast.packageName Network
# @raycast.icon icons/wifi.png
# @raycast.mode silent
# @raycast.schemaVersion 1

# /// script
# requires-python = ">=3.12"
# dependencies = ["gpsoauth", "requests"]
# ///

import json
import os
import secrets
import subprocess
import sys
from pathlib import Path
from typing import Any, TypedDict

import gpsoauth
import requests

KEYCHAIN_SERVICE = "restart-wifi-network"
FOYER_URL = "https://googlehomefoyer-pa.googleapis.com/v2"
GOOGLE_HOME_APP_PACKAGE = "com.google.android.apps.chromecast.app"
GOOGLE_HOME_APP_SIGNATURE = "24bb24c05e47e0aefa68a58a766179d9b613a600"

JSONObject = dict[str, Any]

USAGE = f"""Usage:
  {Path(__file__).name} [options]

Options:
  --setup     Sign in and choose the Wi-Fi network to restart
  -h, --help  Show this help message"""


class Credentials(TypedDict):
  email_address: str
  android_id: str
  master_token: str


class Config(Credentials):
  group_id: str


def load_config() -> Config:
  result = subprocess.run(
    ["/usr/bin/security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
    capture_output=True,
    text=True,
    check=False,
  )

  if result.returncode != 0:
    sys.exit("Run with --setup to sign in and choose the Wi-Fi network to restart.")

  return json.loads(result.stdout)


def save_config(config: Config) -> None:
  password_hex = json.dumps(config).encode().hex()
  command = f'add-generic-password -U -s {KEYCHAIN_SERVICE} -a "{config["email_address"]}" -X {password_hex}\n'
  result = subprocess.run(["/usr/bin/security", "-i"], input=command, capture_output=True, text=True, check=False)

  if result.returncode != 0:
    sys.exit(f"Failed to save configuration to Keychain: {result.stderr.strip()}")


def get_access_token(credentials: Credentials) -> str:
  response = gpsoauth.perform_oauth(
    credentials["email_address"],
    credentials["master_token"],
    credentials["android_id"],
    service="oauth2:https://www.google.com/accounts/OAuthLogin",
    app=GOOGLE_HOME_APP_PACKAGE,
    client_sig=GOOGLE_HOME_APP_SIGNATURE,
  )

  if "Auth" not in response:
    error = response.get("Error", response)
    sys.exit(f"Failed to get access token: {error}")

  return response["Auth"]


def foyer_request(method: str, path: str, access_token: str) -> requests.Response:
  return requests.request(
    method,
    f"{FOYER_URL}{path}",
    params={"prettyPrint": "false"},
    headers={"Authorization": f"Bearer {access_token}"},
    json={} if method == "POST" else None,
    timeout=30,
  )


def setup() -> None:
  email_address = input("Google account email address (Wi-Fi network owner): ").strip()

  print(
    f"\n1. Open https://accounts.google.com/EmbeddedSetup in a browser and sign in as {email_address}",
    '2. Click "I agree" (the page will not redirect, which is expected)',
    "3. Copy the value of `oauth_token` from Developer Tools → Application → Cookies → accounts.google.com\n",
    sep="\n",
  )

  oauth_token = input("oauth_token: ").strip().removeprefix("oauth_token=")
  android_id = secrets.token_hex(8)
  response = gpsoauth.exchange_token(email_address, oauth_token, android_id)

  if "Token" not in response:
    sys.exit(f"Token exchange failed: {response.get('Error', response)}")

  credentials: Credentials = {
    "email_address": email_address,
    "android_id": android_id,
    "master_token": response["Token"],
  }
  groups_response = foyer_request("GET", "/groups", get_access_token(credentials))
  groups: list[JSONObject] = groups_response.json().get("groups", []) if groups_response.ok else []

  if not groups:
    status_code, body = groups_response.status_code, groups_response.text[:200]
    sys.exit(f"No Wi-Fi network found for this account (HTTP {status_code}: {body}).")

  network_names: list[str] = [
    group.get("groupSettings", {}).get("lanSettings", {}).get("networkName", "Unknown") for group in groups
  ]

  print()

  for number, (group, network_name) in enumerate(zip(groups, network_names), 1):
    point_count = len(group.get("accessPoints", []))
    print(f"[{number}] {network_name} ({point_count} Wi-Fi point{'' if point_count == 1 else 's'})")

  selected_index = 0

  if len(groups) > 1:
    selected_index = prompt_for_selection(len(groups)) - 1

  save_config({**credentials, "group_id": groups[selected_index]["id"]})

  print(f"Saved “{network_names[selected_index]}” to Keychain (service: {KEYCHAIN_SERVICE}).")


def prompt_for_selection(count: int) -> int:
  while True:
    answer = input(f"Network [1–{count}]: ").strip()

    if answer.isdigit() and 1 <= int(answer) <= count:
      return int(answer)


def restart() -> None:
  config = load_config()
  response = foyer_request("POST", f"/groups/{config['group_id']}/reboot", get_access_token(config))

  if not response.ok:
    sys.exit(f"Restart failed (HTTP {response.status_code}: {response.text[:200]}).")

  print("Restarting Wi-Fi network…")


def main() -> None:
  arguments = sys.argv[1:]

  if arguments in (["-h"], ["--help"]):
    print(USAGE)
    return

  if arguments not in ([], ["--setup"]):
    print(f"Unknown arguments: {' '.join(arguments)}\n\n{USAGE}", file=sys.stderr)
    sys.exit(os.EX_USAGE)

  try:
    if arguments == ["--setup"]:
      setup()
    else:
      restart()
  except (EOFError, KeyboardInterrupt):
    print()
    sys.exit(1)


if __name__ == "__main__":
  main()
