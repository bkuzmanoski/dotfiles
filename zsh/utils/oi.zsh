oi() {
  print_help() {
    print "Usage: oi [options] <image|directory> ..."
    print "Options:"
    print "  -z, --zopfli     Use Zopfli compression for PNGs (slower but better compression)"
    print "  -q, --quality N  Set JPEG quality (0-100, lower = smaller file)"
    print "  -h, --help       Show this help message"
  }


  local missing_tools=()
  local install_instructions=()

  if ! which -s oxipng >/dev/null; then
    missing_tools+=("oxipng");
    install_instructions+=("%Boxipng%b: brew install oxipng");
  fi

  if ! which -s jpegoptim >/dev/null; then
    missing_tools+=("jpegoptim");
    install_instructions+=("%Bjpegoptim%b: brew install jpegoptim");
  fi

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    print "Required tools missing:"

    for instruction in "${install_instructions[@]}"; do
      print -u2 -P "  - ${instruction}"
    done

    return 1
  fi

  local use_zopfli=0
  local quality=""

  if ! zparseopts -D -E -F \
    "{z,-zopfli}"=flag_zopfli \
    "{q,-quality}":=option_quality \
    "{h,-help}"=flag_help \
    2>/dev/null; then
    print -u2 "Error: Invalid or incomplete options provided."
    print
    print_help

    return 1
  fi

  if (( ${#flag_help} > 0 )); then
    print_help
    return 0
  fi

  if (( ${#flag_zopfli} > 0 )); then
    use_zopfli=1
  fi

  if (( ${#option_quality} > 0 )); then
    quality="${option_quality[-1]}"
  fi

  local -a files
  for input in "$@"; do
    if [[ ! -e ${input} ]]; then
      continue
    fi

    if [[ -d ${input} ]]; then
      local dir_files=("${input}"/**/*.(jpg|jpeg|png)(N))
      files+=("${dir_files[@]}")
    elif [[ -f ${input} && ${input} == *.(jpg|jpeg|png) ]]; then
      files+=("${input}")
    fi
  done

  local image_count="${#files[@]}"

  if [[ ${image_count} -eq 0 ]]; then
    print -u2 "Didn't find any JP(E)G or PNG files to optimize."
    return 1
  fi

  print "Found ${image_count} image$([[ ${image_count} -eq 1 ]] || print "s") to optimize..."

  local processed=0
  local -A original_sizes
  local -a jpeg_opts=("--all-progressive" "--strip-exif" "--strip-com")
  local -a oxipng_opts=("--strip" "safe")

  for file in "${files[@]}"; do
    original_sizes[${file}]="$(stat -f %z "${file}")"
  done

  if [[ -n "${quality}" ]]; then
    jpeg_opts+=("--max=${quality}")
  fi

  if [[ ${use_zopfli} -eq 1 ]]; then
    oxipng_opts+=("--zopfli")
  fi

  set -e

  for file in "${files[@]}"; do
    printf "\n\033[1m%d/%d\033[0m\n" "$(( processed + 1 ))" "${image_count}"

    case "${file:l}" in
      *.jpg|*.jpeg) jpegoptim ${jpeg_opts[@]} "${file}" ;;
      *.png)        oxipng ${oxipng_opts[@]} "${file}" ;;
    esac

    (( processed++ ))
  done

  local total_size_before=0
  local total_size_after=0

  for file in "${files[@]}"; do
    (( total_size_before += "${original_sizes[${file}]}" ))
    (( total_size_after += "$(stat -f %z "${file}")" ))
  done

  local size_reduction="$(( (total_size_before - total_size_after) * 100 / total_size_before ))"

  printf "\n\033[1mProcessed %d image%s\033[0m\n" "${image_count}" "$([[ ${image_count} -eq 1 ]] || print "s")"
  printf "Total size before: %.2f MB\n" "$(print "scale=2; ${total_size_before} / 1000000" | bc)"
  printf "Total size after:  %.2f MB\n" "$(print "scale=2; ${total_size_after} / 1000000" | bc)"
  printf "Size reduction:    %d%%\n" "${size_reduction}"
}
