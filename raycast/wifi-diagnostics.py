#!/usr/bin/env python3

# @raycast.title Wi-Fi Diagnostics
# @raycast.packageName Network
# @raycast.icon icons/wifi.png
# @raycast.mode fullOutput
# @raycast.schemaVersion 1

import json
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from typing import Any, NamedTuple, Self

EXTERNAL_HOST = "1.1.1.1"
PING_COUNT = 20
PING_INTERVAL_SECONDS = 0.2
MAX_LISTED_FAULTS = 5
MAX_PHY_RATE_PER_STREAM: dict[str, dict[int, float]] = {
  "n": {20: 72.2, 40: 150},
  "ac": {20: 86.7, 40: 200, 80: 433.3, 160: 866.7},
  "ax": {20: 143.4, 40: 286.8, 80: 600.5, 160: 1201},
}
LINK_QUALITY_CHECKS = {"Tx rate", "MCS index", "Channel busy (CCA)"}

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"

JSONObject = dict[str, Any]
PingResult = tuple[float, float | None, float | None]  # Loss %, average round-trip ms, and maximum round-trip ms


class Channel(NamedTuple):
  number: int
  band: int
  width: int

  @classmethod
  def parse(cls, text: str | None) -> Self | None:
    if channel_match := re.match(r"(\d+) \((\d)GHz, (\d+)MHz\)", text or ""):
      return cls(int(channel_match[1]), int(channel_match[2]), int(channel_match[3]))

    if channel_match := re.match(r"(\d)g(\d+)/(\d+)", text or ""):
      return cls(int(channel_match[2]), int(channel_match[1]), int(channel_match[3]))

    return None

  @property
  def span(self) -> tuple[int, int]:
    if self.band == 2:
      return self.number - 2, self.number + 2

    block_size = self.width // 5
    base = 1 if self.band == 6 else 149 if self.number >= 149 else 36
    start = base + (self.number - base) // block_size * block_size

    return start, start + block_size - 4

  def overlaps(self, other: Self) -> bool:
    start, end = self.span
    other_start, other_end = other.span

    return start <= other_end and other_start <= end


class Row(NamedTuple):
  label: str
  value: str
  passed: bool | None
  expected: str


class Report:
  def __init__(self) -> None:
    self.sections: list[list[str | Row]] = []
    self.failed_checks: set[str] = set()

  def heading(self, title: str) -> None:
    self.sections.append([f"\n{BOLD}{title}{RESET}"])

  def note(self, text: str, color: str = DIM) -> None:
    self.sections[-1].append(f"  {color}{text}{RESET}")

  def row(self, label: str, value: str, passed: bool | None = None, expected: str = "", detail: str = "") -> None:
    if passed is False:
      self.failed_checks.add(label)

    if detail:
      label = f"{label} ({detail})"

    self.sections[-1].append(Row(label, value, passed, expected))

  def print(self) -> None:
    rows = [line for section in self.sections for line in section if isinstance(line, Row)]
    label_width = max((len(row.label) for row in rows), default=0) + 2

    for section in self.sections:
      section_rows = [line for line in section if isinstance(line, Row)]
      value_width = max((len(row.value) for row in section_rows if row.expected), default=0)
      has_marks = any(row.passed is not None for row in section_rows)

      for line in section:
        print(self.format_row(line, has_marks, label_width, value_width) if isinstance(line, Row) else line)

  @staticmethod
  def format_row(row: Row, has_marks: bool, label_width: int, value_width: int) -> str:
    if row.passed is None:
      color, mark = "", " "
    else:
      color = GREEN if row.passed else RED
      mark = f"{color}{'✓' if row.passed else '✗'}{RESET}"

    if has_marks:
      prefix = f"  {mark} {row.label:<{label_width}}"
    else:
      prefix = f"  {row.label:<{label_width + 2}}"

    if not row.expected:
      return f"{prefix}{color}{row.value}{RESET}"

    return f"{prefix}{color}{row.value:<{value_width}}{RESET}  {DIM}{row.expected}{RESET}"


def run(*command: str, timeout: float = 30) -> str:
  try:
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False).stdout
  except (OSError, subprocess.TimeoutExpired):
    return ""


def parse_number(value: object) -> float | None:
  if isinstance(value, (int, float)):
    return float(value)

  if not isinstance(value, str):
    return None

  number_match = re.search(r"-?\d+(?:\.\d+)?", value)

  return float(number_match[0]) if number_match else None


def first_number(*values: object) -> float | None:
  return next((number for number in map(parse_number, values) if number is not None), None)


def wifi_is_connected() -> bool:
  hardware_ports = run("/usr/sbin/networksetup", "-listallhardwareports")
  device_match = re.search(r"Hardware Port: Wi-Fi\nDevice: (\S+)", hardware_ports)

  return device_match is not None and "status: active" in run("/sbin/ifconfig", device_match[1])


def default_gateway() -> str | None:
  gateway_match = re.search(r"gateway: (\S+)", run("/sbin/route", "-n", "get", "default"))
  return gateway_match[1] if gateway_match else None


def system_profiler_wifi() -> tuple[JSONObject, list[JSONObject]]:
  try:
    profiler_data = json.loads(run("/usr/sbin/system_profiler", "SPAirPortDataType", "-json"))
    wifi_interfaces = profiler_data["SPAirPortDataType"][0]["spairport_airport_interfaces"]
  except (json.JSONDecodeError, KeyError, IndexError):
    return {}, []

  for wifi_interface in wifi_interfaces:
    current_network = wifi_interface.get("spairport_current_network_information", {})

    if "spairport_network_channel" in current_network:
      return current_network, wifi_interface.get("spairport_airport_other_local_wireless_networks", [])

  return {}, []


def wdutil_info() -> tuple[dict[str, str], list[str] | None]:
  wdutil_output = run("/usr/bin/sudo", "-n", "/usr/bin/wdutil", "info")

  if not wdutil_output:
    return {}, None

  lines = [line.strip() for line in wdutil_output.splitlines() if line.strip()]
  line_is_separator = [set(line) <= set("—-─") for line in lines]
  sections: dict[str, list[str]] = {}
  current_section_lines: list[str] | None = None

  for index, line in enumerate(lines):
    if line_is_separator[index]:
      continue

    if 0 < index < len(lines) - 1 and line_is_separator[index - 1] and line_is_separator[index + 1]:
      current_section_lines = sections.setdefault(line, [])
    elif current_section_lines is not None:
      current_section_lines.append(line)

  wifi_fields: dict[str, str] = {}

  for line in sections.get("WIFI", []):
    field_name, _, field_value = line.partition(":")
    wifi_fields[field_name.strip()] = field_value.strip()

  fault_events = [
    line
    for section_name, section_lines in sections.items()
    if "FAULTS" in section_name or "RECOVERIES" in section_name
    for line in section_lines
    if line.lower() != "none"
  ]

  return wifi_fields, fault_events


def ping(host: str) -> PingResult:
  ping_output = run("/sbin/ping", "-c", str(PING_COUNT), "-i", str(PING_INTERVAL_SECONDS), "-q", "-t", "15", host)
  loss_match = re.search(r"([\d.]+)% packet loss", ping_output)
  round_trip_match = re.search(r"= ([\d.]+)/([\d.]+)/([\d.]+)", ping_output)  # min/avg/max

  return (
    float(loss_match[1]) if loss_match else 100.0,
    float(round_trip_match[2]) if round_trip_match else None,
    float(round_trip_match[3]) if round_trip_match else None,
  )


def format_ping(loss_percent: float, average_ms: float | None, maximum_ms: float | None) -> str:
  if average_ms is None or maximum_ms is None:
    return f"{loss_percent:.0f}% loss"

  return f"{loss_percent:.0f}% loss, avg {average_ms:.1f} ms, max {maximum_ms:.1f} ms"


def print_wifi_link(
  report: Report, current_network: JSONObject, wdutil_fields: dict[str, str], fault_events: list[str] | None
) -> None:
  profiler_signal, _, profiler_noise = current_network.get("spairport_signal_noise", "").partition("/")
  signal_dbm = first_number(wdutil_fields.get("RSSI"), profiler_signal)
  noise_dbm = first_number(wdutil_fields.get("Noise"), profiler_noise)
  channel_busy_percent = parse_number(wdutil_fields.get("CCA"))
  channel = Channel.parse(current_network.get("spairport_network_channel"))
  phy_mode: str = current_network.get("spairport_network_phymode", "").removeprefix("802.11")
  tx_rate_mbps = first_number(wdutil_fields.get("Tx Rate"), current_network.get("spairport_network_rate"))
  mcs_index = first_number(wdutil_fields.get("MCS Index"), current_network.get("spairport_network_mcs"))
  spatial_stream_count = int(first_number(wdutil_fields.get("NSS")) or 2)
  max_phy_rate_per_stream = MAX_PHY_RATE_PER_STREAM.get(phy_mode, {}).get(channel.width) if channel else None

  report.heading("Wi-Fi link")
  report.note(f"802.11{phy_mode}, Channel {current_network.get('spairport_network_channel', '?')}")

  if signal_dbm is not None:
    report.row("Signal (RSSI)", f"{signal_dbm:.0f} dBm", signal_dbm >= -65, "≥ -65 dBm")

  if noise_dbm is not None:
    report.row("Noise", f"{noise_dbm:.0f} dBm", noise_dbm <= -90, "≤ -90 dBm")

  if signal_dbm is not None and noise_dbm is not None:
    snr_db = signal_dbm - noise_dbm
    report.row("SNR", f"{snr_db:.0f} dB", snr_db >= 25, "≥ 25 dB")

  if channel_busy_percent is not None:
    report.row("Channel busy (CCA)", f"{channel_busy_percent:.0f}%", channel_busy_percent < 20, "< 20%")

  if tx_rate_mbps is not None and max_phy_rate_per_stream:
    minimum_tx_rate_mbps = max_phy_rate_per_stream * spatial_stream_count / 2
    passed = tx_rate_mbps >= minimum_tx_rate_mbps
    report.row("Tx rate", f"{tx_rate_mbps:.0f} Mbps", passed, f"≥ {minimum_tx_rate_mbps:.0f} Mbps")
  elif tx_rate_mbps is not None:
    report.row("Tx rate", f"{tx_rate_mbps:.0f} Mbps")

  if mcs_index is not None:
    report.row("MCS index", f"{mcs_index:.0f}", mcs_index >= 7, "≥ 7")

  if fault_events is None:
    report.note("! CCA and faults need passwordless `sudo wdutil info`.", YELLOW)
    return

  report.row("Faults (last hour)", f"{len(fault_events)}", not fault_events, "0")

  for fault_event in fault_events[:MAX_LISTED_FAULTS]:
    report.note(f"    {fault_event}")


def print_neighbouring_networks(
  report: Report, current_network: JSONObject, neighbouring_networks: list[JSONObject]
) -> None:
  channel = Channel.parse(current_network.get("spairport_network_channel"))

  if not channel:
    return

  span_start, span_end = channel.span
  neighbour_channels = [
    Channel.parse(neighbouring_network.get("spairport_network_channel"))
    for neighbouring_network in neighbouring_networks
  ]
  same_band_channels = [
    neighbour_channel
    for neighbour_channel in neighbour_channels
    if neighbour_channel and neighbour_channel.band == channel.band
  ]
  same_primary_channel_count = sum(1 for other in same_band_channels if other.number == channel.number)
  overlapping_channel_count = sum(1 for other in same_band_channels if channel.overlaps(other))

  report.heading("Neighbouring networks")
  report.row(f"On channel {channel.number}", f"{same_primary_channel_count}")
  report.row(f"Visible on {channel.band} GHz", f"{len(same_band_channels)}", None, f"{len(neighbour_channels)} total")
  report.row(
    f"Overlapping {channel.width} MHz", f"{overlapping_channel_count}", None, f"Channels {span_start}–{span_end}"
  )


def print_connectivity(
  report: Report, gateway_address: str | None, gateway_ping: PingResult | None, external_ping: PingResult
) -> None:
  report.heading("Connectivity")

  if gateway_address and gateway_ping:
    loss_percent, average_ms, _ = gateway_ping
    passed = loss_percent == 0 and average_ms is not None and average_ms < 10
    report.row("Gateway", format_ping(*gateway_ping), passed, "0% loss, avg < 10 ms", gateway_address)
  else:
    report.row("Gateway", "No default route", False)

  report.row("External", format_ping(*external_ping), external_ping[0] == 0, "0% loss", EXTERNAL_HOST)


def print_summary(report: Report) -> None:
  failed_checks = report.failed_checks
  diagnoses: list[str] = []

  report.heading("Summary")

  if not failed_checks:
    report.note("All metrics in range.", GREEN)
    return

  if "Signal (RSSI)" in failed_checks:
    diagnoses.append("Weak signal.")
  elif failed_checks & LINK_QUALITY_CHECKS:
    diagnoses.append("Strong signal but degraded link (likely airtime contention).")

  if "Gateway" in failed_checks:
    diagnoses.append("Loss or latency to the gateway (Wi-Fi/router fault).")
  elif "External" in failed_checks:
    diagnoses.append("Gateway clean but external loss (ISP/WAN fault).")

  if not diagnoses:
    report.note(f"Out of range: {', '.join(sorted(failed_checks))}.", YELLOW)
    return

  for diagnosis in diagnoses:
    report.note(diagnosis, RED)


def print_not_connected(report: Report) -> None:
  report.heading("Wi-Fi link")
  report.note("Not connected to Wi-Fi.", RED)
  report.print()


def main() -> None:
  report = Report()

  if not wifi_is_connected():
    print_not_connected(report)
    return

  gateway_address = default_gateway()

  with ThreadPoolExecutor() as executor:
    wdutil_job = executor.submit(wdutil_info)
    gateway_ping_job = executor.submit(ping, gateway_address) if gateway_address else None
    external_ping_job = executor.submit(ping, EXTERNAL_HOST)

  current_network, neighbouring_networks = system_profiler_wifi()
  gateway_ping = gateway_ping_job.result() if gateway_ping_job else None

  if not current_network:
    print_not_connected(report)
    return

  print_wifi_link(report, current_network, *wdutil_job.result())
  print_neighbouring_networks(report, current_network, neighbouring_networks)
  print_connectivity(report, gateway_address, gateway_ping, external_ping_job.result())
  print_summary(report)
  report.print()


if __name__ == "__main__":
  main()
