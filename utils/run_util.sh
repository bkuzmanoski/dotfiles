#!/bin/zsh

readonly SCRIPT_NAME="${RUN_UTIL_COMMAND_NAME:-${0:t}}"
readonly SCRIPT_DIR="${0:A:h}"
readonly SOURCES_DIR="${SCRIPT_DIR}/sources"
readonly BIN_DIR="${SCRIPT_DIR}/bin"
readonly COMPILE_COMMANDS_JSON_PATH="${SCRIPT_DIR}/compile_commands.json"

readonly -a SWIFT_FLAGS=(
  -O
  -swift-version 6
  -strict-concurrency=complete
  -enable-upcoming-feature ExistentialAny
  -enable-upcoming-feature MemberImportVisibility
)

# =============================================================================
# Functions
# =============================================================================

function print_usage() {
  cat <<-EOF
		Usage:
		  ${SCRIPT_NAME} [options] <command_or_source_file> [command_args...]

		Options:
		  -b, --background          Run the command in the background (no output to terminal)
		  -B, --build-only          Only compile the command if needed, do not execute it
		  -c, --compile-commands    Regenerate compile_commands.json and exit
		  -h, --help                Show this help message
	EOF
}

function die() {
  print -u2 "Error: $1"
  exit ${2:-1}
}

function die_usage() {
  print -u2 "Error: $1\n"
  print_usage >&2
  exit 64
}

function format_compilation_error() {
  local output="$1"

  {
    print -r -- "${output}" \
      | grep -m1 "error:" \
      || print -r -- "${output}" | grep -m1 -v '^[[:space:]]*$'
  } | sed -E "s|^${SOURCES_DIR}/||"
}

function notify_compilation_failure() {
  local title="$1"
  local message="$2"

  if [[ -t 2 ]]; then
    return 0
  fi

  osascript - "${title}" "${message}" >/dev/null 2>&1 <<-'EOF'
		on run {notification_title, notification_message}
		  display notification notification_message with title notification_title
		end run
	EOF
}

function write_compile_commands_json() {
  local sdk_path
  sdk_path="$(xcrun --show-sdk-path 2>/dev/null)"

  local -a sdk_flags=()

  if [[ -n "${sdk_path}" ]]; then
    sdk_flags=(-sdk "${sdk_path}")
  fi

  local -a entries=()
  local -a arguments=()

  for source_file in "${SOURCES_DIR}"/*.swift(N.); do
    local util_name="${source_file:t:r}"

    arguments=(
      swiftc
      "${sdk_flags[@]}"
      "${SWIFT_FLAGS[@]}"
      -module-name "${util_name}"
      -o "${BIN_DIR}/${util_name}"
      "${source_file}"
    )

    local arguments_json=""

    for argument in "${arguments[@]}"; do
      arguments_json+="${arguments_json:+, }\"${argument}\""
    done

    entries+=("$(
      cat <<-EOF
			  {
			    "directory": "${SCRIPT_DIR}",
			    "file": "${source_file}",
			    "output": "${BIN_DIR}/${util_name}",
			    "arguments": [${arguments_json}]
			  }
		EOF
    )")
  done

  local compile_commands_json=$'[\n'"${(pj:,\n:)entries}"$'\n]'

  if ! print -r -- "${compile_commands_json}" >"${COMPILE_COMMANDS_JSON_PATH}"; then
    return 1
  fi

  return 0
}

function compile_util() {
  local util_name="$1"
  local source_file="$2"
  local source_file_extension="$3"
  local bin_path="$4"

  local -a compile_command
  local compile_output

  rm -rf "${bin_path}"
  mkdir -p "${bin_path:h}"

  case "${source_file_extension}" in
  swift)
    compile_command=(swiftc "${SWIFT_FLAGS[@]}" -module-name "${util_name}" -o "${bin_path}" "${source_file}")
    ;;
  applescript)
    compile_command=(osacompile -o "${bin_path}" "${source_file}")
    ;;
  *)
    die "Unsupported source file type: .${source_file_extension}"
    ;;
  esac

  if ! compile_output="$("${compile_command[@]}" 2>&1)"; then
    if [[ -n "${compile_output}" ]]; then
      print -u2 -- "${compile_output}"
    fi

    notify_compilation_failure "${util_name} failed to compile" "$(format_compilation_error "${compile_output}")"
    die "Compilation failed."
  fi

  if [[ -n "${compile_output}" ]]; then
    print -u2 -- "${compile_output}"
  fi

  if [[ "${source_file_extension}" == "swift" ]]; then
    if ! write_compile_commands_json; then
      print -u2 "Warning: Failed to write ${COMPILE_COMMANDS_JSON_PATH}."
    fi
  fi

  return 0
}

function run_and_exit() {
  local in_background="$1"
  shift

  if ((in_background)); then
    nohup "$@" >/dev/null 2>&1 &
    exit 0
  else
    exec "$@"
  fi
}

# =============================================================================
# Parse options and arguments
# =============================================================================

# shellcheck disable=SC2034
if ! zparseopts -D -F \
  {b,-background}=flag_background \
  {B,-build-only}=flag_build_only \
  {c,-compile-commands}=flag_compile_commands \
  {h,-help}=flag_help \
  2>/dev/null; then
  die_usage "Invalid option(s)."
fi

if (($#flag_help)); then
  print_usage
  exit 0
fi

if (($#flag_compile_commands)); then
  if (($#flag_background || $#flag_build_only)); then
    die_usage "--compile-commands cannot be combined with --background or --build-only."
  fi

  if (($# > 0)); then
    die_usage "--compile-commands takes no arguments (got '$1')."
  fi

  if write_compile_commands_json; then
    print "Wrote to ${COMPILE_COMMANDS_JSON_PATH}"
    exit 0
  else
    die "Failed to write to ${COMPILE_COMMANDS_JSON_PATH}"
  fi
fi

if (($#flag_background && $#flag_build_only)); then
  die_usage "--background cannot be combined with --build-only."
fi

if (($# < 1)); then
  die_usage "No command specified."
fi

# =============================================================================
# Resolve the utility
# =============================================================================

set -u

readonly UTIL_NAME="${1:t:r}"
shift

readonly -a CANDIDATE_SOURCE_FILES=("${SOURCES_DIR}/${UTIL_NAME}".*(N.))

if ((${#CANDIDATE_SOURCE_FILES[@]} == 0)); then
  die "Missing source file for utility."
elif ((${#CANDIDATE_SOURCE_FILES[@]} > 1)); then
  print -u2 "Warning: Multiple source files found for '${UTIL_NAME}'. Using \"${CANDIDATE_SOURCE_FILES[1]:t}\"."
fi

readonly SOURCE_FILE="${CANDIDATE_SOURCE_FILES[1]}"
readonly SOURCE_FILE_EXTENSION="${SOURCE_FILE##*.}"

if [[ "${SOURCE_FILE_EXTENSION}" == "applescript" ]]; then
  readonly BIN_PATH="${BIN_DIR}/${UTIL_NAME}.scpt"
else
  readonly BIN_PATH="${BIN_DIR}/${UTIL_NAME}"
fi

# =============================================================================
# Build and run
# =============================================================================

if [[ ! -e "${BIN_PATH}" || "${SOURCE_FILE}" -nt "${BIN_PATH}" ]]; then
  compile_util "${UTIL_NAME}" "${SOURCE_FILE}" "${SOURCE_FILE_EXTENSION}" "${BIN_PATH}"
fi

if (($#flag_build_only)); then
  exit 0
fi

if [[ "${SOURCE_FILE_EXTENSION}" == "swift" && -x "${BIN_PATH}" ]]; then
  run_and_exit "${#flag_background}" "${BIN_PATH}" "$@"

elif [[ "${SOURCE_FILE_EXTENSION}" == "applescript" && -e "${BIN_PATH}" ]]; then
  run_and_exit "${#flag_background}" osascript "${BIN_PATH}" "$@"

else
  die "Failed to locate executable."
fi
