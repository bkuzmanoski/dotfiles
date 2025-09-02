cv() {
  _help() {
    print "Usage: cv [options] <video>"
    print "Options:"
    print "  -p, --preset VALUE   Set encoding preset (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow) [default: veryfast]"
    print "  -q, --quality VALUE  Set quality (0-51, lower = better quality) [default: 23]"
    print "  -f, --fps VALUE      Set frame rate [default: 30]"
    print "  -c, --codec VALUE    Set codec (h264, h265) [default: h264]"
    print "  -a, --audio VALUE    Set audio bitrate [default: 128k]"
    print "  -o, --overwrite      Overwrite input file with compressed version"
    print "  -h, --help           Show this help message"
  }

  if ! which -s ffmpeg >/dev/null; then
    print -u2 -P "%Bffmpeg%b is not installed. Install with: brew install ffmpeg"
    return 1
  fi

  local preset="veryfast"
  local crf=23
  local fps=30
  local codec="libx264"
  local tag="avc1"
  local audio_bitrate="128k"

  if ! zparseopts -D -E -F -- \
    {p,-preset}:=opt_preset \
    {q,-quality}:=opt_crf \
    {f,-fps}:=opt_fps \
    {c,-codec}:=opt_codec \
    {a,-audio}:=opt_audio \
    {o,-overwrite}=flag_overwrite \
    {h,-help}=flag_help \
    2>/dev/null; then
    print -u2 "Error: Invalid or incomplete options provided.\n"
    _help
    return 1
  fi

  if (( ${#flag_help} > 0 )); then
    _help
    return 0
  fi

  if (( ${#opt_preset} > 0 )); then preset=${opt_preset[-1]}; fi
  if (( ${#opt_crf} > 0 )); then crf=${opt_crf[-1]}; fi
  if (( ${#opt_fps} > 0 )); then fps=${opt_fps[-1]}; fi
  if (( ${#opt_audio} > 0 )); then audio_bitrate=${opt_audio[-1]}; fi
  if (( ${#opt_codec} > 0 )); then
    case "${opt_codec[-1]}" in
      h264) codec="libx264"; tag="avc1" ;;
      h265) codec="libx265"; tag="hvc1" ;;
      *) print -u2 "Unknown codec: ${opt_codec[-1]}"; return 1 ;;
    esac
  fi

  local input_file="$1"
  if [[ ! -f "${input_file}" ]]; then
    print -u2 "Error: File \"${input_file}\" not found."
    return 1
  fi

  local original_size=$(stat -f %z "${input_file}")
  local output_file="${input_file%.*}_compressed.mp4"
  ffmpeg \
    -hide_banner \
    -stats \
    -loglevel error \
    -i "${input_file}" \
    -r "${fps}" \
    -c:v "${codec}" \
    -preset "${preset}" \
    -crf "${crf}" \
    -pix_fmt yuv420p \
    -tag:v "${tag}" \
    -c:a aac \
    -b:a "${audio_bitrate}" \
    "${output_file}"

  if [[ $? -ne 0 ]]; then
    print -u2 "\nFailed to compress video."
    return 1
  fi

  local compressed_size=$(stat -f %z "${output_file}")
  local size_reduction=$(( (${original_size} - ${compressed_size}) * 100 / ${original_size} ))

  local overwrite_notice
  if (( ${#flag_overwrite} > 0 )); then
    if [[ ${compressed_size} -lt ${original_size} ]]; then
      command mv "${output_file}" "${input_file}"
      overwrite_notice="Replaced original file with compressed version."
    else
      command rm "${output_file}"
      overwrite_notice="Compression did not reduce file size. Original file kept unchanged."
    fi
    output_file="${input_file}"
  fi

  printf "\n\033[1m%s\033[0m\n" "${output_file}"
  [[ -n "${overwrite_notice}" ]] && printf "%s\n\n" "${overwrite_notice}"
  printf "Original size:   %.2f MB\n" "$(print "scale=2; ${original_size} / 1000000" | bc)"
  printf "Compressed size: %.2f MB\n" "$(print "scale=2; ${compressed_size} / 1000000" | bc)"
  printf "Size reduction:  %d%%\n" "${size_reduction}"
}
