# Compress video
cv() {
  if [[ $# -eq 0 ]]; then
    print "Usage: cv [options] <video>"
    print "Use -h or --help for more information."
    return 1
  fi

  if ! which -s ffmpeg >/dev/null; then
    print -P "%Bffmpeg%b is not installed. Install with: brew install ffmpeg"
    return 1
  fi

  local preset="medium"
  local crf=28
  local fps=30
  local codec="libx265"
  local tag="hvc1"
  local audio_bitrate="128k"
  local overwrite=0
  local -a opts=()

  while [[ "$1" == -* ]]; do
    case "$1" in
      -p|--preset)
        if [[ -n "$2" ]]; then
          preset="$2"
          shift 2
        else
          print "Please specify a preset or omit the option."
          return 1
        fi
        ;;
      -q|--quality)
        if [[ -n "$2" ]]; then
          crf="$2"
          shift 2
        else
          print "Please specify a quality or omit the option."
          return 1
        fi
        ;;
      -f|--fps)
        if [[ -n "$2" ]]; then
          fps="$2"
          shift 2
        else
          print "Please specify a frame rate or omit the option."
          return 1
        fi
        ;;
      -c|--codec)
        if [[ -n "$2" ]]; then
          if [[ "$2" == "h264" ]]; then
            codec="libx264"
            tag="avc1"
          elif [[ "$2" == "h265" ]]; then
            codec="libx265"
            tag="hvc1"
          else
            print "Invalid codec: $2"
            return 1
          fi
          shift 2
        else
          print "Please specify a codec or omit the option."
          return 1
        fi
        ;;
      -a|--audio)
        if [[ -n "$2" ]]; then
          audio_bitrate="$2"
          shift 2
        else
          print "Please specify an audio bitrate or omit the option."
          return 1
        fi
        ;;
      -o|--overwrite)
        overwrite=1
        shift
        ;;
      -h|--help)
        print "Usage: cv [options] <video>"
        print "Options:"
        print "  -p, --preset VALUE   Set encoding preset (ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow) [default: medium]"
        print "  -q, --quality VALUE  Set quality (0-51, lower = better quality) [default: 28]"
        print "  -f, --fps VALUE      Set frame rate [default: 30]"
        print "  -c, --codec VALUE    Set codec (h264, h265) [default: h265]"
        print "  -a, --audio VALUE    Set audio bitrate [default: 128k]"
        print "  -o, --overwrite      Overwrite input file with compressed version"
        print "  -h, --help           Show this help message"
        return 0
        ;;
      *)
        print "Unknown option: $1"
        return 1
        ;;
    esac
  done

  local input_file="$1"
  if [[ ! -f "${input_file}" ]]; then
    print "Error: File \"${input_file}\" not found."
    return 1
  fi

  local original_size=$(stat -f %z "${input_file}")
  local output_file="${input_file%.*}_compressed.mp4"
  ffmpeg \
    -hide_banner \
    -stats \
    -i "${input_file}" \
    -r ${fps} \
    -c:v ${codec} \
    -preset ${preset} \
    -crf ${crf} \
    -pix_fmt yuv420p \
    -tag:v ${tag} \
    -c:a aac \
    -b:a ${audio_bitrate} \
    "${output_file}"

  if [[ $? -ne 0 ]]; then
    print "\nFailed to compress video."
    return 1
  fi

  local compressed_size=$(stat -f %z "${output_file}")
  local size_reduction=$(( (${original_size} - ${compressed_size}) * 100 / ${original_size} ))

  local overwrite_notice
  if [[ ${overwrite} -eq 1 ]]; then
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
