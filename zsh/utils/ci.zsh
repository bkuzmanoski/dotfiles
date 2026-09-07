function ci() {
  function print_usage() {
    command cat <<-"EOF"
			Usage:
			  ci [options] <image|directory> ...

			Options:
			  -a, --avif-quality <value>    Set AVIF quality (0-100, lower = smaller file) [default: 80]
			  -w, --webp-quality <value>    Set WebP quality (0-100, lower = smaller file) [default: 90]
			  -r, --recursive               Recurse into subdirectories
			  -h, --help                    Show this help message
		EOF
  }

  setopt localoptions extendedglob

  function dissimilarity() {
    local score="$(magick compare -metric DSSIM "$1" "$2" null: 2>&1)"

    if [[ "${score}" =~ '\(([0-9.]+)\)' ]]; then
      print -- "${match[1]}"
    else
      print -- "?"
    fi
  }

  local missing_tools=()
  local install_instructions=()

  if ! command -v magick >/dev/null; then
    missing_tools+=("magick")
    install_instructions+=("%Bmagick%b: brew install imagemagick")
  fi

  if ! command -v cwebp >/dev/null; then
    missing_tools+=("cwebp")
    install_instructions+=("%Bcwebp%b: brew install webp")
  fi

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    print -u2 "Required tools missing:"

    for instruction in "${install_instructions[@]}"; do
      print -u2 -P "  - ${instruction}"
    done

    return 1
  fi

  local avif_quality=80
  local webp_quality=90

  if ! zparseopts -D -E -F \
    {a,-avif-quality}:=option_avif_quality \
    {w,-webp-quality}:=option_webp_quality \
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

  ((${#option_avif_quality} > 0)) && avif_quality="${option_avif_quality[-1]}"
  ((${#option_webp_quality} > 0)) && webp_quality="${option_webp_quality[-1]}"

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

    print -u2 "No JP(E)G or PNG files found to convert."

    return 1
  fi

  print "Converting ${image_count} image$([[ ${image_count} -eq 1 ]] || print "s")..."

  local -i processed_count=0
  local -i total_size_source=0
  local -i total_size_avif=0
  local -i total_size_webp=0

  for file in "${files[@]}"; do
    local avif_file="${file:r}.avif"
    local webp_file="${file:r}.webp"
    local -i source_size="$(stat -f %z "${file}")"

    printf "\n\033[1m%d/%d\033[0m %s (%.0f KB)\n" "$((processed_count + 1))" "${image_count}" "${file}" $((source_size / 1000.0))

    if ! magick "${file}" -quality "${avif_quality}" "${avif_file}"; then
      print -u2 "Failed to convert \"${file}\" to AVIF."
      return 1
    fi

    if ! cwebp -q "${webp_quality}" -m 6 -sharp_yuv -alpha_q 100 -metadata none "${file}" -o "${webp_file}" -quiet; then
      print -u2 "Failed to convert \"${file}\" to WebP."
      return 1
    fi

    local -i avif_size="$(stat -f %z "${avif_file}")"
    local -i webp_size="$(stat -f %z "${webp_file}")"

    printf "%s → %.0f KB (dssim %s)\n" "${avif_file:t}" $((avif_size / 1000.0)) "$(dissimilarity "${file}" "${avif_file}")"
    printf "%s → %.0f KB (dssim %s)\n" "${webp_file:t}" $((webp_size / 1000.0)) "$(dissimilarity "${file}" "${webp_file}")"

    ((total_size_source += source_size))
    ((total_size_avif += avif_size))
    ((total_size_webp += webp_size))
    ((processed_count++))
  done

  local avif_reduction_percent="$(((total_size_source - total_size_avif) * 100 / total_size_source))"
  local webp_reduction_percent="$(((total_size_source - total_size_webp) * 100 / total_size_source))"

  printf "\n\033[1mConverted %d image%s\033[0m\n" "${image_count}" "$([[ ${image_count} -eq 1 ]] || print "s")"
  printf "Total source size: %.2f MB\n" $((total_size_source / 1000000.0))
  printf "Total AVIF size:   %.2f MB (%d%% smaller)\n" $((total_size_avif / 1000000.0)) "${avif_reduction_percent}"
  printf "Total WebP size:   %.2f MB (%d%% smaller)\n" $((total_size_webp / 1000000.0)) "${webp_reduction_percent}"
}
