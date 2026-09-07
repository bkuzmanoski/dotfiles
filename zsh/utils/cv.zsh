function cv() {
  function print_usage() {
    command cat <<-"EOF"
			Usage:
			  cv [options] <video|directory> ...

			Options:
			  -p, --preset <value>     Set encoding preset (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow) [default: veryfast]
			  -q, --quality <value>    Set quality (0-51, lower = better quality) [default: 23]
			  -f, --fps <value>        Set frame rate [default: 30]
			  -c, --codec <value>      Set codec (h264, h265) [default: h264]
			  -a, --audio <value>      Set audio bitrate [default: 128k]
			  -o, --overwrite          Overwrite input file with compressed version
			  -F, --force              Re-encode even if a compressed version already exists
			  -r, --recursive          Recurse into subdirectories
			  -h, --help               Show this help message
		EOF
  }

  setopt localoptions extendedglob

  if ! command -v ffmpeg >/dev/null; then
    print -u2 -P "%Bffmpeg%b is not installed. Install with: brew install ffmpeg"
    return 1
  fi

  local preset="veryfast"
  local crf=23
  local fps=30
  local codec="libx264"
  local tag="avc1"
  local audio_bitrate="128k"

  if ! zparseopts -D -E -F \
    {p,-preset}:=option_preset \
    {q,-quality}:=option_crf \
    {f,-fps}:=option_fps \
    {c,-codec}:=option_codec \
    {a,-audio}:=option_audio \
    {o,-overwrite}=flag_overwrite \
    {F,-force}=flag_force \
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

  ((${#option_preset} > 0)) && preset="${option_preset[-1]}"
  ((${#option_crf} > 0)) && crf="${option_crf[-1]}"
  ((${#option_fps} > 0)) && fps="${option_fps[-1]}"
  ((${#option_audio} > 0)) && audio_bitrate="${option_audio[-1]}"

  if ((${#option_codec} > 0)); then
    case "${option_codec[-1]}" in
    h264)
      codec="libx264"
      tag="avc1"
      ;;
    h265)
      codec="libx265"
      tag="hvc1"
      ;;
    *)
      print -u2 "Unknown codec: ${option_codec[-1]}"
      return 1
      ;;
    esac
  fi

  if (($# == 0)); then
    print -u2 "Error: No input file(s) specified.\n"
    print_usage >&2

    return 64
  fi

  local extensions="mp4|mov|m4v|mkv|webm|avi"
  local recursive_glob=""
  local -a files
  local -i unsupported_count=0

  if ((${#flag_recursive} > 0)); then
    recursive_glob="**/"
  fi

  for input in "$@"; do
    if [[ -d ${input} ]]; then
      files+=("${input}"/${~recursive_glob}(^*_compressed).(#i)(${~extensions})(N.^D))

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

  local video_count="${#files[@]}"

  if [[ ${video_count} -eq 0 ]]; then
    if ((unsupported_count > 0)); then
      print -u2
    fi

    print -u2 "No video files found to compress."
    return 1
  fi

  local base_command

  if command -v ffpb >/dev/null; then
    base_command="ffpb"
  else
    base_command="ffmpeg"
  fi

  local result_prefix=""

  if [[ ${base_command} == "ffpb" ]]; then
    result_prefix="  "
  fi

  local -a force_opts=()

  if ((${#flag_force} > 0)); then
    force_opts=(-y)
  fi

  print "Compressing ${video_count} video$([[ ${video_count} -eq 1 ]] || print "s")..."

  local -i processed_count=0
  local -i skipped_count=0
  local -i failed_count=0
  local -i total_size_before=0
  local -i total_size_after=0

  for file in "${files[@]}"; do
    local output_file="${file:r}_compressed.mp4"
    local overwrite_notice=""
    local -i original_size="$(stat -f %z "${file}")"

    ((processed_count++))

    printf "\n\033[1m%d/%d\033[0m %s\n" "${processed_count}" "${video_count}" "${file}"

    if ((${#flag_force} == 0)) && [[ -f ${output_file} ]]; then
      print "Skipped: \"${output_file:t}\" already exists."

      ((skipped_count++))

      continue
    fi

    local -a compress_command=(
      "${base_command}"
      -hide_banner
      -stats
      -loglevel error
      ${force_opts[@]}
      -i "${file}"
      -r "${fps}"
      -c:v "${codec}"
      -preset "${preset}"
      -crf "${crf}"
      -pix_fmt yuv420p
      -tag:v "${tag}"
      -c:a aac
      -b:a "${audio_bitrate}"
      "${output_file}"
    )

    if ! "${compress_command[@]}"; then
      print -u2 "\nFailed to compress \"${file}\"."

      command rm -f "${output_file}"
      ((failed_count++))

      continue
    fi

    local -i compressed_size="$(stat -f %z "${output_file}")"

    if ((${#flag_overwrite} > 0)); then
      if ((compressed_size < original_size)); then
        command mv "${output_file}" "${file}"
        overwrite_notice="Replaced original file with compressed version."
      else
        command rm "${output_file}"
        compressed_size="${original_size}"
        overwrite_notice="Compression did not reduce file size. Original file left unchanged."
      fi

      output_file="${file}"
    fi

    printf "\n%s%s  %.2f MB → %.2f MB (%d%% smaller)\n" "${result_prefix}" "${output_file:t}" $((original_size / 1000000.0)) $((compressed_size / 1000000.0)) "$(((original_size - compressed_size) * 100 / original_size))"

    if [[ -n "${overwrite_notice}" ]]; then
      print "${result_prefix}${overwrite_notice}"
    fi

    ((total_size_before += original_size))
    ((total_size_after += compressed_size))
  done

  local compressed_count="$((video_count - skipped_count - failed_count))"

  if [[ ${compressed_count} -eq 0 ]]; then
    if [[ ${failed_count} -gt 0 ]]; then
      if [[ ${video_count} -gt 1 ]]; then
        print -u2 "\nFailed to compress any videos."
      fi

      return 1
    fi

    print "\nEvery video already has a compressed version (use --force to re-encode)."

    return 0
  fi

  local summary_suffix=""
  local -a summary_notes=()
  local size_reduction="$((total_size_before - total_size_after))"
  local size_reduction_percent="$((size_reduction * 100 / total_size_before))"

  if [[ ${failed_count} -gt 0 ]]; then
    summary_notes+=("${failed_count} failed")
  fi

  if [[ ${skipped_count} -gt 0 ]]; then
    summary_notes+=("${skipped_count} skipped")
  fi

  if [[ ${#summary_notes[@]} -gt 0 ]]; then
    summary_suffix=" (${(j:, :)summary_notes})"
  fi

  printf "\n\033[1mCompressed %d video%s\033[0m%s\n" "${compressed_count}" "$([[ ${compressed_count} -eq 1 ]] || print "s")" "${summary_suffix}"
  printf "Total size before: %.2f MB\n" $((total_size_before / 1000000.0))
  printf "Total size after:  %.2f MB\n" $((total_size_after / 1000000.0))
  printf "Size reduction:    %.2f MB (%d%%)\n" $((size_reduction / 1000000.0)) "${size_reduction_percent}"

  if [[ ${failed_count} -gt 0 ]]; then
    return 1
  fi
}
