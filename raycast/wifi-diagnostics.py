#!/usr/bin/env python3

# @raycast.title Wi-Fi Diagnostics
# @raycast.packageName Network
# @raycast.icon icons/wifi.png
# @raycast.mode fullOutput
# @raycast.schemaVersion 1

import ipaddress
import json
import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from enum import StrEnum
from typing import Any, NamedTuple, Self

EXTERNAL_HOST = "1.1.1.1"
PING_COUNT = 20
PING_INTERVAL_SECONDS = 0.2
MAX_LISTED_FAULTS = 5
MAX_PHY_RATE_PER_STREAM: dict[str, dict[int, float]] = {
  "n": {20: 72.2, 40: 150},
  "ac": {20: 86.7, 40: 200, 80: 433.3, 160: 866.7},
  "ax": {20: 143.4, 40: 286.8, 80: 600.5, 160: 1201},
  "be": {20: 172.1, 40: 344.1, 80: 720.6, 160: 1441.2, 320: 2882.4},
}
PHY_RATE_HEADROOM = 1.5  # Real throughput is roughly two-thirds of the PHY rate.
INTERNET_PLAN_MBPS = 500

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"

JSONObject = dict[str, Any]
PingResult = tuple[float, float | None, float | None]  # Loss %, average round-trip ms, and maximum round-trip ms.


class Check(StrEnum):
  RSSI = "Signal (RSSI)"
  NOISE = "Noise"
  SNR = "SNR"
  CCA = "Channel busy (CCA)"
  TX_RATE = "Tx rate"
  MCS = "MCS index"
  FAULTS = "Faults / recoveries"
  GATEWAY = "Gateway"
  EXTERNAL = "External"


class WdutilResult(NamedTuple):
  fields: dict[str, str]
  faults: list[str]
  recoveries: list[str]


class Channel(NamedTuple):
  number: int
  band: int
  width: int

  @classmethod
  def parse(cls, text: str | None) -> Self | None:
    if channel_match := re.match(r"(\d+) \((\d)GHz, (\d+)MHz\)", text or ""):
      number, band, width = int(channel_match[1]), int(channel_match[2]), int(channel_match[3])
      return cls(number, band, width) if width >= 5 else None

    if channel_match := re.match(r"(\d)g(\d+)(?:/(\d+))?", text or ""):
      band, number = int(channel_match[1]), int(channel_match[2])
      width = int(channel_match[3]) if channel_match[3] else 20
      return cls(number, band, width) if width >= 5 else None

    return None

  @property
  def band_label(self) -> str:
    return "2.4 GHz" if self.band == 2 else f"{self.band} GHz"

  @property
  def span(self) -> tuple[int, int]:
    if self.band == 2:
      half_width = max(2, self.width // 10)
      return max(1, self.number - half_width), min(14, self.number + half_width)

    block_size = self.width // 5
    # Assumes the 320-1 layout (starting at ch 1) for 6 GHz 320 MHz; macOS does not report 320-1 vs 320-2.
    base = 1 if self.band == 6 else 149 if self.number >= 149 else 36
    start = base + (self.number - base) // block_size * block_size

    return start, start + block_size - 4

  @property
  def span_label(self) -> str:
    start, end = self.span
    return f"Channel {start}" if start == end else f"Channels {start}–{end}"

  def overlaps(self, other: Self) -> bool:
    if self.band != other.band:
      return False

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
    self.checks: dict[Check, bool] = {}

  def heading(self, title: str) -> None:
    self.sections.append([f"\n{BOLD}{title}{RESET}"])

  def note(self, text: str, color: str = DIM) -> None:
    self.sections[-1].append(f"  {color}{text}{RESET}")

  def row(
    self, label: Check | str, value: str, passed: bool | None = None, expected: str = "", detail: str = ""
  ) -> None:
    if isinstance(label, Check) and passed is not None:
      self.checks[label] = passed

    display_label = f"{label} ({detail})" if detail else str(label)
    self.sections[-1].append(Row(display_label, value, passed, expected))

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
      color, mark = "", f"{DIM}–{RESET}"
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


def run(*command: str, timeout: float = 30, require_ok: bool = False) -> str:
  try:
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
  except (OSError, subprocess.TimeoutExpired):
    return ""

  if require_ok and result.returncode != 0:
    return ""

  return result.stdout


def parse_number(value: object) -> float | None:
  if isinstance(value, bool):
    return None

  if isinstance(value, (int, float)):
    return float(value)

  if not isinstance(value, str):
    return None

  number_match = re.search(r"-?\d+(?:\.\d+)?", value)

  return float(number_match[0]) if number_match else None


def first_number(*values: object) -> float | None:
  return next((number for number in map(parse_number, values) if number is not None), None)


def active_wifi_device() -> str | None:
  hardware_ports = run("/usr/sbin/networksetup", "-listallhardwareports", require_ok=True)
  device_match = re.search(r"Hardware Port: Wi-Fi\nDevice: (\S+)", hardware_ports)

  if device_match and "status: active" in run("/sbin/ifconfig", device_match[1], require_ok=True):
    return device_match[1]

  return None


def default_route() -> tuple[str | None, str | None]:
  route_output = run("/sbin/route", "-n", "get", "default", require_ok=True)
  gateway_match = re.search(r"gateway: (\S+)", route_output)
  interface_match = re.search(r"interface: (\S+)", route_output)
  gateway = gateway_match[1] if gateway_match else None
  interface = interface_match[1] if interface_match else None

  if gateway:
    try:
      ipaddress.IPv4Address(gateway)
    except ValueError:
      gateway = None

  return gateway, interface


def system_profiler_wifi() -> tuple[JSONObject, list[JSONObject]]:
  try:
    profiler_data = json.loads(run("/usr/sbin/system_profiler", "SPAirPortDataType", "-json", require_ok=True))
    wifi_interfaces: list[JSONObject] = profiler_data["SPAirPortDataType"][0]["spairport_airport_interfaces"] or []
  except (json.JSONDecodeError, KeyError, IndexError, TypeError):
    return {}, []

  for wifi_interface in wifi_interfaces:
    current_network: JSONObject = wifi_interface.get("spairport_current_network_information") or {}

    if "spairport_network_channel" in current_network:
      other_networks: list[JSONObject] = wifi_interface.get("spairport_airport_other_local_wireless_networks") or []
      return current_network, other_networks

  return {}, []


def wdutil_info() -> WdutilResult | None:
  wdutil_output = run("/usr/bin/sudo", "-n", "/usr/bin/wdutil", "info", require_ok=True)

  if not wdutil_output:
    return None

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

  if not sections:
    return None

  wifi_fields: dict[str, str] = {}

  for line in sections.get("WIFI", []):
    if ":" not in line:
      continue

    field_name, _, field_value = line.partition(":")
    wifi_fields[field_name.strip()] = field_value.strip()

  fault_events = [
    line
    for section_name, section_lines in sections.items()
    if "FAULTS" in section_name
    for line in section_lines
    if line.lower() != "none"
  ]
  recovery_events = [
    line
    for section_name, section_lines in sections.items()
    if "RECOVERIES" in section_name
    for line in section_lines
    if line.lower() != "none"
  ]

  return WdutilResult(wifi_fields, fault_events, recovery_events)


def ping(host: str) -> PingResult:
  ping_output = run("/sbin/ping", "-c", str(PING_COUNT), "-i", str(PING_INTERVAL_SECONDS), "-q", "-t", "15", host)
  loss_match = re.search(r"([\d.]+)% packet loss", ping_output)
  round_trip_match = re.search(r"= ([\d.]+)/([\d.]+)/([\d.]+)", ping_output)  # min/avg/max

  return (
    float(loss_match[1]) if loss_match else 100.0,
    float(round_trip_match[2]) if round_trip_match else None,
    float(round_trip_match[3]) if round_trip_match else None,
  )


def format_loss(loss_percent: float) -> str:
  if loss_percent == 0:
    return "0%"

  if loss_percent < 0.1:
    return "<0.1%"

  return f"{loss_percent:.0f}%" if loss_percent.is_integer() else f"{loss_percent:.1f}%"


def format_ping(loss_percent: float, average_ms: float | None, maximum_ms: float | None) -> str:
  loss_text = format_loss(loss_percent)

  if average_ms is None or maximum_ms is None:
    return f"{loss_text} loss"

  return f"{loss_text} loss, avg {average_ms:.1f} ms, max {maximum_ms:.1f} ms"


def append_event_notes(report: Report, events: list[str]) -> None:
  for event in events[:MAX_LISTED_FAULTS]:
    report.note(f"    {event}")

  remaining = len(events) - MAX_LISTED_FAULTS

  if remaining > 0:
    report.note(f"    … and {remaining} more")


def print_wifi_link(report: Report, current_network: JSONObject, wdutil_result: WdutilResult | None) -> None:
  wdutil_fields = wdutil_result.fields if wdutil_result else {}
  profiler_signal, _, profiler_noise = current_network.get("spairport_signal_noise", "").partition("/")
  signal_dbm = first_number(wdutil_fields.get("RSSI"), profiler_signal)
  noise_dbm = first_number(wdutil_fields.get("Noise"), profiler_noise)
  channel_busy_percent = parse_number(wdutil_fields.get("CCA"))
  channel = Channel.parse(current_network.get("spairport_network_channel")) or Channel.parse(
    wdutil_fields.get("Channel")
  )
  raw_phy_mode = current_network.get("spairport_network_phymode") or wdutil_fields.get("PHY Mode", "")
  phy_mode = re.sub(r"^(?:802\.)?11", "", raw_phy_mode)
  tx_rate_mbps = first_number(wdutil_fields.get("Tx Rate"), current_network.get("spairport_network_rate"))
  mcs_index = first_number(wdutil_fields.get("MCS Index"), current_network.get("spairport_network_mcs"))
  spatial_stream_count = int(first_number(wdutil_fields.get("NSS")) or 2)
  max_phy_rate_per_stream = MAX_PHY_RATE_PER_STREAM.get(phy_mode, {}).get(channel.width) if channel else None

  phy_label = f"802.11{phy_mode}" if phy_mode else "Unknown PHY"
  channel_label = current_network.get("spairport_network_channel") or (
    f"{channel.number} ({channel.band_label}, {channel.width}MHz)" if channel else "?"
  )

  report.heading("Wi-Fi link")
  report.note(f"{phy_label}, Channel {channel_label}")

  if signal_dbm is not None:
    report.row(Check.RSSI, f"{signal_dbm:.0f} dBm", signal_dbm >= -65, "≥ -65 dBm")

  if noise_dbm is not None:
    report.row(Check.NOISE, f"{noise_dbm:.0f} dBm", noise_dbm <= -90, "≤ -90 dBm")

  if signal_dbm is not None and noise_dbm is not None:
    snr_db = signal_dbm - noise_dbm
    report.row(Check.SNR, f"{snr_db:.0f} dB", snr_db >= 25, "≥ 25 dB")

  if channel_busy_percent is not None:
    report.row(Check.CCA, f"{channel_busy_percent:.0f}%", channel_busy_percent < 20, "< 20%")

  if tx_rate_mbps is not None and max_phy_rate_per_stream:
    # Half the link's peak rate, or enough headroom over the internet plan, whichever is lower.
    minimum_tx_rate_mbps = min(
      max_phy_rate_per_stream * spatial_stream_count / 2, INTERNET_PLAN_MBPS * PHY_RATE_HEADROOM
    )
    passed = tx_rate_mbps >= minimum_tx_rate_mbps
    report.row(Check.TX_RATE, f"{tx_rate_mbps:.0f} Mbps", passed, f"≥ {minimum_tx_rate_mbps:.0f} Mbps")
  else:
    if tx_rate_mbps is not None:
      report.row(Check.TX_RATE, f"{tx_rate_mbps:.0f} Mbps")

    # Tx rate already reflects MCS, channel width and streams, so MCS is only judged when Tx rate can't be.
    if mcs_index is not None:
      mcs_int = int(mcs_index)
      if phy_mode == "n":
        minimum_mcs = (mcs_int // 8) * 8 + 7
        report.row(Check.MCS, f"{mcs_int}", mcs_int >= minimum_mcs, f"≥ {minimum_mcs}")
      else:
        report.row(Check.MCS, f"{mcs_int}", mcs_index >= 7, "≥ 7")

  if wdutil_result is None:
    report.note("! CCA and faults need passwordless `sudo wdutil info`.", YELLOW)
    return

  fault_count = len(wdutil_result.faults)
  recovery_count = len(wdutil_result.recoveries)
  event_parts: list[str] = []

  if fault_count:
    event_parts.append(f"{fault_count} {'fault' if fault_count == 1 else 'faults'}")

  if recovery_count:
    event_parts.append(f"{recovery_count} {'recovery' if recovery_count == 1 else 'recoveries'}")

  fault_value = ", ".join(event_parts) if event_parts else "0"
  report.row(Check.FAULTS, fault_value, not event_parts, "0 in last hour")
  append_event_notes(report, wdutil_result.faults)
  append_event_notes(report, [f"Recovery: {event}" for event in wdutil_result.recoveries])


def print_neighbouring_networks(
  report: Report, current_network: JSONObject, neighbouring_networks: list[JSONObject]
) -> None:
  channel = Channel.parse(current_network.get("spairport_network_channel"))

  if not channel:
    return

  same_band_channels = [
    neighbour_channel
    for neighbouring_network in neighbouring_networks
    if (neighbour_channel := Channel.parse(neighbouring_network.get("spairport_network_channel")))
    and neighbour_channel.band == channel.band
  ]
  same_primary_channel_count = sum(1 for other in same_band_channels if other.number == channel.number)
  overlapping_channel_count = sum(1 for other in same_band_channels if channel.overlaps(other))

  report.heading("Neighbouring networks")
  report.row(f"On channel {channel.number}", f"{same_primary_channel_count}")
  report.row(
    f"Visible on {channel.band_label}", f"{len(same_band_channels)}", None, f"{len(neighbouring_networks)} total"
  )
  report.row(f"Overlapping {channel.width} MHz", f"{overlapping_channel_count}", None, channel.span_label)


def print_connectivity(
  report: Report,
  wifi_device: str,
  gateway_address: str | None,
  route_interface: str | None,
  gateway_ping: PingResult | None,
  external_ping: PingResult,
) -> None:
  report.heading("Connectivity")

  if route_interface and route_interface != wifi_device:
    report.note(f"! Default route is via {route_interface}, not {wifi_device} (Wi-Fi).", YELLOW)

  if gateway_address and gateway_ping:
    loss_percent, average_ms, _ = gateway_ping
    passed = loss_percent == 0 and average_ms is not None and average_ms < 10
    report.row(Check.GATEWAY, format_ping(*gateway_ping), passed, "0% loss, avg < 10 ms", gateway_address)
  elif route_interface:
    report.row(Check.GATEWAY, f"Point-to-point ({route_interface})")
  else:
    report.row(Check.GATEWAY, "No default route", False)

  report.row(Check.EXTERNAL, format_ping(*external_ping), external_ping[0] == 0, "0% loss", EXTERNAL_HOST)


def print_summary(report: Report, *, has_default_route: bool) -> None:
  checks = report.checks
  failed_checks = {check for check, passed in checks.items() if not passed}
  diagnoses: list[str] = []
  explained_checks: set[Check] = set()

  report.heading("Summary")

  if not failed_checks:
    report.note("All metrics in range.", GREEN)
    return

  if Check.RSSI in failed_checks:
    diagnoses.append("Weak signal.")
    explained_checks |= {Check.RSSI, Check.SNR, Check.TX_RATE, Check.MCS}

  if Check.NOISE in failed_checks:
    diagnoses.append("High noise floor (non-Wi-Fi interference nearby).")
    explained_checks |= {Check.NOISE, Check.SNR, Check.TX_RATE, Check.MCS}

  if Check.CCA in failed_checks:
    diagnoses.append("Busy channel (likely airtime contention).")
    explained_checks |= {Check.CCA, Check.TX_RATE, Check.MCS}

  if not (failed_checks & {Check.RSSI, Check.NOISE, Check.CCA}) and (failed_checks & {Check.TX_RATE, Check.MCS}):
    if Check.CCA in checks:
      diagnoses.append("Low link rate on a quiet channel (interference or power-save scaling).")
    else:
      diagnoses.append("Low link rate (contention, interference, or power-save scaling; CCA unavailable).")
    explained_checks |= {Check.TX_RATE, Check.MCS}

  if Check.FAULTS in failed_checks:
    diagnoses.append("Recent Wi-Fi faults or recoveries logged (possible dropouts).")
    explained_checks.add(Check.FAULTS)

  if Check.GATEWAY in failed_checks:
    if has_default_route:
      diagnoses.append("Loss or latency to the gateway (Wi-Fi/router fault).")
    else:
      diagnoses.append("No default route (DHCP or router configuration fault).")
    explained_checks |= {Check.GATEWAY, Check.EXTERNAL}
  elif Check.EXTERNAL in failed_checks:
    if checks.get(Check.GATEWAY):
      diagnoses.append("Gateway clean but external loss (ISP/WAN fault).")
    else:
      diagnoses.append("External packet loss (gateway not tested).")
    explained_checks.add(Check.EXTERNAL)

  for diagnosis in diagnoses:
    report.note(diagnosis, RED)

  unexplained_checks = failed_checks - explained_checks

  if unexplained_checks:
    report.note(f"Out of range: {', '.join(sorted(unexplained_checks))}.", YELLOW)


def print_not_connected(report: Report) -> None:
  report.heading("Wi-Fi link")
  report.note("Not connected to Wi-Fi.", RED)
  report.print()


def main() -> None:
  report = Report()
  wifi_device = active_wifi_device()

  if not wifi_device:
    print_not_connected(report)
    return

  gateway_address, route_interface = default_route()

  with ThreadPoolExecutor() as executor:
    wdutil_job = executor.submit(wdutil_info)
    gateway_ping_job = executor.submit(ping, gateway_address) if gateway_address else None
    external_ping_job = executor.submit(ping, EXTERNAL_HOST)

  # Run after pings finish: system_profiler triggers an off-channel Wi-Fi scan that would otherwise inject latency
  # spikes and packet loss into concurrent pings.
  current_network, neighbouring_networks = system_profiler_wifi()
  wdutil_result = wdutil_job.result()
  gateway_ping = gateway_ping_job.result() if gateway_ping_job else None

  if current_network or wdutil_result is not None:
    print_wifi_link(report, current_network, wdutil_result)
    if current_network:
      print_neighbouring_networks(report, current_network, neighbouring_networks)
  else:
    report.heading("Wi-Fi link")
    report.note("Connected to Wi-Fi, but could not read link details from system_profiler.", RED)

  print_connectivity(report, wifi_device, gateway_address, route_interface, gateway_ping, external_ping_job.result())
  print_summary(report, has_default_route=route_interface is not None)
  report.print()


if __name__ == "__main__":
  main()
