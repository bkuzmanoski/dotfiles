function oi() {
  function print_usage() {
    command cat <<-"EOF"
			Usage:
			  oi [options] <image|directory> ...

			Options:
			  -q, --quality <value>    Set JPEG quality (0-100, lower = smaller file)
			  -z, --zopfli             Use Zopfli compression for PNGs (slower but better compression)
			  -r, --recursive          Recurse into subdirectories
			  -h, --help               Show this help message
		EOF
  }

  setopt localoptions extendedglob

  local missing_tools=()
  local install_instructions=()

  if ! command -v jpegoptim >/dev/null; then
    missing_tools+=("jpegoptim")
    install_instructions+=("%Bjpegoptim%b: brew install jpegoptim")
  fi

  if ! command -v oxipng >/dev/null; then
    missing_tools+=("oxipng")
    install_instructions+=("%Boxipng%b: brew install oxipng")
  fi

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    print -u2 "Required tools missing:"

    for instruction in "${install_instructions[@]}"; do
      print -u2 -P "  - ${instruction}"
    done

    return 1
  fi

  local use_zopfli=0
  local quality=""

  if ! zparseopts -D -E -F \
    {q,-quality}:=option_quality \
    {z,-zopfli}=flag_zopfli \
    {r,-recursive}=flag_recursive \
    {h,-help}=flag_help \
    2>/dev/null; then
    print -u2 "Error: Invalid or missing option(s).\n"
    print_usage >&2

    return 64
  fi

  if ((${#flag_help} > 0)); then
    print_usage
    return 0
  fi

  if ((${#option_quality} > 0)); then
    quality="${option_quality[-1]}"
  fi

  if ((${#flag_zopfli} > 0)); then
    use_zopfli=1
  fi

  if (($# == 0)); then
    print -u2 "Error: No input file(s) specified.\n"
    print_usage >&2

    return 64
  fi

  local extensions="jpg|jpeg|png"
  local recursive_glob=""
  local -a files
  local -i unsupported_count=0

  if ((${#flag_recursive} > 0)); then
    recursive_glob="**/"
  fi

  for input in "$@"; do
    if [[ -d ${input} ]]; then
      files+=("${input}"/${~recursive_glob}*.(#i)(${~extensions})(N.^D))

    elif [[ -f ${input} ]]; then
      if [[ ${input:l} != *.(${~extensions}) ]]; then
        print -u2 "Skipping unsupported file: \"${input}\""

        ((unsupported_count++))

        continue
      fi

      files+=("${input}")

    else
      print -u2 "Error: File \"${input}\" not found."
      return 1
    fi
  done

  files=("${(u)files[@]}")

  local image_count="${#files[@]}"

  if [[ ${image_count} -eq 0 ]]; then
    if ((unsupported_count > 0)); then
      print -u2
    fi

    print -u2 "No JP(E)G or PNG files found to optimize."
    return 1
  fi

  print "Found ${image_count} image$([[ ${image_count} -eq 1 ]] || print "s") to optimize..."

  local -i processed_count=0
  local -i failed_count=0
  local -i total_size_before=0
  local -i total_size_after=0

  local -a jpeg_opts=("--all-progressive" "--strip-exif" "--strip-com")

  if [[ -n "${quality}" ]]; then
    jpeg_opts+=("--max=${quality}")
  fi

  local -a oxipng_opts=("--strip" "safe")

  if [[ ${use_zopfli} -eq 1 ]]; then
    oxipng_opts+=("--zopfli")
  fi

  for file in "${files[@]}"; do
    local -i original_size="$(stat -f %z "${file}")"
    local -a optimize_command=()

    ((processed_count++))

    printf "\n\033[1m%d/%d\033[0m %s\n" "${processed_count}" "${image_count}" "${file}"

    case "${file:l}" in
    *.jpg | *.jpeg) optimize_command=(jpegoptim ${jpeg_opts[@]} "${file}") ;;
    *.png) optimize_command=(oxipng ${oxipng_opts[@]} "${file}") ;;
    esac

    if ! "${optimize_command[@]}"; then
      print -u2 "Failed to optimize \"${file}\"."

      ((failed_count++))

      continue
    fi

    local -i optimized_size="$(stat -f %z "${file}")"

    ((total_size_before += original_size))
    ((total_size_after += optimized_size))
  done

  local optimized_count="$((image_count - failed_count))"

  if [[ ${optimized_count} -eq 0 ]]; then
    if [[ ${image_count} -gt 1 ]]; then
      print -u2 "\nFailed to optimize any images."
    fi

    return 1
  fi

  local summary_suffix=""
  local size_reduction="$((total_size_before - total_size_after))"
  local size_reduction_percent="$((size_reduction * 100 / total_size_before))"

  if [[ ${failed_count} -gt 0 ]]; then
    summary_suffix=" (${failed_count} failed)"
  fi

  printf "\n\033[1mProcessed %d image%s\033[0m%s\n" "${optimized_count}" "$([[ ${optimized_count} -eq 1 ]] || print "s")" "${summary_suffix}"
  printf "Total size before: %.2f MB\n" $((total_size_before / 1000000.0))
  printf "Total size after:  %.2f MB\n" $((total_size_after / 1000000.0))
  printf "Size reduction:    %.2f MB (%d%%)\n" $((size_reduction / 1000000.0)) "${size_reduction_percent}"

  if [[ ${failed_count} -gt 0 ]]; then
    return 1
  fi
}
