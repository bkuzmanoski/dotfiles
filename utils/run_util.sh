#!/bin/zsh

readonly SCRIPT_NAME="${RUN_UTIL_COMMAND_NAME:-${0:t}}"
readonly SCRIPT_DIR="${0:A:h}"
readonly SOURCES_DIR="${SCRIPT_DIR}/sources"
readonly BIN_DIR="${SCRIPT_DIR}/bin"

readonly SWIFT_COMPILE_COMMANDS_JSON_PATH="${SCRIPT_DIR}/compile_commands.json"
readonly SWIFT_SHARED_DIRECTIVE_PREFIX="// Shared:"
readonly SWIFT_SHARED_SOURCES_DIR="${SOURCES_DIR}/Shared"
readonly -a SWIFT_FLAGS=(
  -O
  -wmo
  -parse-as-library
  -swift-version 6
  -strict-concurrency=complete
  -enable-upcoming-feature ExistentialAny
  -enable-upcoming-feature MemberImportVisibility
)

# =============================================================================
# Helper functions
# =============================================================================

function print_usage() {
  cat <<-EOF
		Usage:
		  ${SCRIPT_NAME} [options] <command_or_source_file> [command_args...]

		Options:
		  -b, --background        Run the command in the background (no output to terminal)
		  -B, --build-only        Only compile the command if needed, do not execute it
		  -c, --compile-commands  Regenerate compile_commands.json and exit
		  -h, --help              Show this help message
	EOF
}

function exit_with_error() {
  print -u2 "Error: $1"
  exit ${2:-1}
}

function exit_with_usage_error() {
  print -u2 "Error: $1\n"
  print_usage >&2
  exit 64
}

function format_compilation_error() {
  setopt localoptions extendedglob

  local -a output_lines=("${(@f)1}")
  local -a error_lines=("${(@M)output_lines:#*error:*}")
  local -a non_blank_lines=("${(@)output_lines:#[[:space:]]#}")
  local summary_line="${error_lines[1]:-${non_blank_lines[1]-}}"

  print -r -- "${summary_line#"${SOURCES_DIR}/"}"
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

# Populates `reply` with shared sources referenced directly or transitively by `// Shared: <Name>...` directives.
function resolve_shared_sources() {
  setopt localoptions extendedglob

  local -a files_to_scan=("$1")
  local -a shared_sources=()

  while ((${#files_to_scan[@]} > 0)); do
    local scanned_file="${files_to_scan[1]}"
    shift files_to_scan

    local -a scanned_file_lines=("${(@f)$(<"${scanned_file}")}")
    local -a leading_comment_block=("${(@)scanned_file_lines[1,${scanned_file_lines[(i)^(//*|)]}-1]}")
    local -a shared_directives=("${(@M)leading_comment_block:#"${SWIFT_SHARED_DIRECTIVE_PREFIX}"*}")
    # shellcheck disable=SC2086,SC2206 # Intentionally split the directives into names
    local -a shared_source_names=(${=shared_directives#"${SWIFT_SHARED_DIRECTIVE_PREFIX}"})

    for shared_source_name in "${shared_source_names[@]}"; do
      local shared_source="${SWIFT_SHARED_SOURCES_DIR}/${shared_source_name}.swift"

      if [[ ! -f "${shared_source}" ]]; then
        print -u2 "Error: Shared source file required by ${scanned_file:t} not found at \"${shared_source#"${SOURCES_DIR}/"}\"."
        return 1
      fi

      if ((! ${shared_sources[(Ie)${shared_source}]})); then
        shared_sources+=("${shared_source}")
        files_to_scan+=("${shared_source}")
      fi
    done
  done

  reply=("${shared_sources[@]}")
}

function write_compile_commands_json() {
  local sdk_path
  sdk_path="$(xcrun --show-sdk-path 2>/dev/null)"

  local -a sdk_flags=()

  if [[ -n "${sdk_path}" ]]; then
    sdk_flags=(-sdk "${sdk_path}")
  fi

  local -a compile_command_entries=()
  local -a files_with_entries=()

  for source_file in "${SOURCES_DIR}"/*.swift(N.); do
    local util_name="${source_file:t:r}"

    if ! resolve_shared_sources "${source_file}"; then
      return 1
    fi

    local -a shared_sources=("${reply[@]}")
    local -a arguments=(
      swiftc
      "${sdk_flags[@]}"
      "${SWIFT_FLAGS[@]}"
      -module-name "${util_name}"
      -o "${BIN_DIR}/${util_name}"
      "${source_file}"
      "${shared_sources[@]}"
    )
    local -a quoted_arguments=("\"${^arguments[@]}\"")

    for entry_file in "${source_file}" "${shared_sources[@]}"; do
      if ((${files_with_entries[(Ie)${entry_file}]})); then
        continue # Skip adding an entry for shared files that have already been added.
      fi

      files_with_entries+=("${entry_file}")
      compile_command_entries+=("$(
        cat <<-EOF
				  {
				    "directory": "${SCRIPT_DIR}",
				    "file": "${entry_file}",
				    "output": "${BIN_DIR}/${util_name}",
				    "arguments": [${(j:, :)quoted_arguments}]
				  }
			EOF
      )")
    done
  done

  print -r -- $'[\n'"${(pj:,\n:)compile_command_entries}"$'\n]' >"${SWIFT_COMPILE_COMMANDS_JSON_PATH}"
}

function needs_compilation() {
  local bin_path="$1"
  shift

  if [[ ! -e "${bin_path}" ]]; then
    return 0
  fi

  for source_file in "$@"; do
    if [[ "${source_file}" -nt "${bin_path}" ]]; then
      return 0
    fi
  done

  return 1
}

function compile_util() {
  local util_name="$1"
  local source_file="$2"
  local source_file_extension="$3"
  local bin_path="$4"
  shift 4

  local -a shared_sources=("$@")

  local -a compile_command
  local compile_output

  rm -rf "${bin_path}"
  mkdir -p "${bin_path:h}"

  case "${source_file_extension}" in
  swift)
    compile_command=(
      swiftc "${SWIFT_FLAGS[@]}" -module-name "${util_name}" -o "${bin_path}" "${source_file}" "${shared_sources[@]}"
    )
    ;;
  applescript)
    compile_command=(osacompile -o "${bin_path}" "${source_file}")
    ;;
  *)
    exit_with_error "Unsupported source file type: .${source_file_extension}"
    ;;
  esac

  if ! compile_output="$("${compile_command[@]}" 2>&1)"; then
    if [[ -n "${compile_output}" ]]; then
      print -r -u2 -- "${compile_output}"
    fi

    notify_compilation_failure "${util_name} failed to compile" "$(format_compilation_error "${compile_output}")"
    exit_with_error "Compilation failed."
  fi

  if [[ -n "${compile_output}" ]]; then
    print -r -u2 -- "${compile_output}"
  fi

  if [[ "${source_file_extension}" == "swift" ]] && ! write_compile_commands_json; then
    print -u2 "Warning: Failed to write ${SWIFT_COMPILE_COMMANDS_JSON_PATH}."
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
# Parse options
# =============================================================================

# shellcheck disable=SC2034
if ! zparseopts -D -F \
  {b,-background}=flag_background \
  {B,-build-only}=flag_build_only \
  {c,-compile-commands}=flag_compile_commands \
  {h,-help}=flag_help \
  2>/dev/null; then
  exit_with_usage_error "Invalid option(s)."
fi

if ((${#flag_help} > 0)); then
  print_usage
  exit 0
fi

if ((${#flag_compile_commands} > 0)); then
  if ((${#flag_background} > 0 || ${#flag_build_only} > 0)); then
    exit_with_usage_error "--compile-commands cannot be combined with --background or --build-only."
  fi

  if (($# > 0)); then
    exit_with_usage_error "--compile-commands takes no arguments (got '$1')."
  fi

  if ! write_compile_commands_json; then
    exit_with_error "Failed to write to ${SWIFT_COMPILE_COMMANDS_JSON_PATH}"
  fi

  print "Wrote to ${SWIFT_COMPILE_COMMANDS_JSON_PATH}"
  exit 0
fi

if ((${#flag_background} > 0 && ${#flag_build_only} > 0)); then
  exit_with_usage_error "--background cannot be combined with --build-only."
fi

if (($# == 0)); then
  exit_with_usage_error "No command specified."
fi

# =============================================================================
# Resolve source files
# =============================================================================

set -u

readonly UTIL_NAME="${1:t:r}"
shift

readonly -a CANDIDATE_SOURCE_FILES=("${SOURCES_DIR}/${UTIL_NAME}".*(N.))

if ((${#CANDIDATE_SOURCE_FILES[@]} == 0)); then
  exit_with_error "Missing source file for utility."
elif ((${#CANDIDATE_SOURCE_FILES[@]} > 1)); then
  print -u2 "Warning: Multiple source files found for '${UTIL_NAME}'. Using \"${CANDIDATE_SOURCE_FILES[1]:t}\"."
fi

readonly SOURCE_FILE="${CANDIDATE_SOURCE_FILES[1]}"
readonly SOURCE_FILE_EXTENSION="${SOURCE_FILE:e}"

if [[ "${SOURCE_FILE_EXTENSION}" == "applescript" ]]; then
  readonly BIN_PATH="${BIN_DIR}/${UTIL_NAME}.scpt"
  readonly -a SHARED_SOURCE_FILES=()
else
  readonly BIN_PATH="${BIN_DIR}/${UTIL_NAME}"

  if ! resolve_shared_sources "${SOURCE_FILE}"; then
    exit 1
  fi

  readonly -a SHARED_SOURCE_FILES=("${reply[@]}")
fi

# =============================================================================
# Build and run
# =============================================================================

if needs_compilation "${BIN_PATH}" "${SOURCE_FILE}" "${SHARED_SOURCE_FILES[@]}"; then
  compile_util "${UTIL_NAME}" "${SOURCE_FILE}" "${SOURCE_FILE_EXTENSION}" "${BIN_PATH}" "${SHARED_SOURCE_FILES[@]}"
fi

if ((${#flag_build_only} > 0)); then
  exit 0
fi

if [[ "${SOURCE_FILE_EXTENSION}" == "swift" && -x "${BIN_PATH}" ]]; then
  run_and_exit "${#flag_background}" "${BIN_PATH}" "$@"

elif [[ "${SOURCE_FILE_EXTENSION}" == "applescript" && -e "${BIN_PATH}" ]]; then
  run_and_exit "${#flag_background}" osascript "${BIN_PATH}" "$@"

else
  exit_with_error "Failed to locate executable."
fi
