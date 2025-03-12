# fzf helpers
fdir() {
  _select_paths "fd --type d" "$@"
}

ff() {
  _select_paths "fd --type f" "$@"
}

fif() {
  if [[ $# -eq 0 ]]; then
    print "Usage: fif <search_pattern> [output_command]"
    return 1
  fi

  local pattern="$1" && shift
  _select_paths "rg --files-with-matches --no-messages -- \"${pattern}\"" "$@"
}

fh() {
  local selected_command="$(fc -nl 1 | tail -r | fzf --scheme history)"
  print -rz -- "${selected_command}"
}

fk() {
  local selected_processes="$(ps -eo pid,comm | sed -E "1d; s/^([[:space:]]*)([0-9]+)/\2\1/" | fzf --multi)"
  if [[ -z "${selected_processes}" ]]; then
    return
  fi

  local pids="$(print "${selected_processes}" | awk '{print $1}' | xargs echo)"
  print -rz -- "kill ${pids}"
}

_select_paths() {
  local find_command="$1" && shift
  local selected_paths=("${(@f)$(eval "${find_command}" | fzf --multi)}")
  [[ -z "${selected_paths[@]}" ]] && return

  if [[ $# -gt 0 ]]; then
    print -rz -- "$@ ${(@q)selected_paths}"
  else
    print -r -- "${(@q)selected_paths}" | pbcopy
    print "Copied to clipboard."
  fi
}

# Compress video
cv() {
  if [[ $# -eq 0 ]]; then
    print "Usage: cv <video>"
    return 1
  fi

  local input_file="$1"
  if [[ ! -f "${input_file}" ]]; then
    print "Error: File \"${input_file}\" not found."
    return 1
  fi

  local original_size=$(stat -f %z "${input_file}")
  local output_file="${input_file%.*}_compressed.mp4"

  ffmpeg \
    -hide_banner \
    -i "${input_file}" \
    -r 30 \
    -c:v libx265 \
    -preset medium \
    -tune animation \
    -crf 28 \
    -pix_fmt yuv420p \
    -tag:v hvc1 \
    -c:a aac \
    -ac 1 \
    -b:a 64k \
    "${output_file}"

  if [[ $? -ne 0 ]]; then
    print "\nFailed to compress video."
    return 1
  fi

  local compressed_size=$(stat -f %z "${output_file}")
  local size_reduction=$(( (${original_size} - ${compressed_size}) * 100 / ${original_size} ))
  print -P "\n%B${output_file}%b"
  printf "Original size:   %.2f MB\n" $(print "${original_size} / 1000000" | bc -l)
  printf "Compressed size: %.2f MB\n" $(print "${compressed_size} / 1000000" | bc -l)
  printf "Size reduction:  %d%%\n" ${size_reduction}
}

# Optimize images
oi() {
  if [[ $# -eq 0 ]]; then
    print "Usage: oi <image|directory> ..."
    return 1
  fi

  if ! which -s imageoptim >/dev/null; then
    print "ImageOptim is not installed."
    return 1
  fi

  local -a files
  for input in "$@"; do
    [[ ! -e ${input} ]] && continue
    if [[ -d ${input} ]]; then
      local dir_files=("${input}"/**/*.(gif|jpg|jpeg|png|svg)(N))
      files+=("${dir_files[@]}")
    elif [[ -f ${input} ]]; then
      [[ ${input} = *.(gif|jpg|jpeg|png|svg) ]] && files+=("${input}")
    fi
  done

  local image_count=${#files[@]}
  if [[ ${image_count} -eq 0 ]]; then
    print "Error: Didn't find any valid image files to optimize."
    return 1
  fi

  local -A original_sizes
  for file in "${files[@]}"; do
    original_sizes[${file}]=$(stat -f %z "${file}")
  done

  imageoptim "${files[@]}"
  if [[ $? -ne 0 ]]; then
    return 1
  fi

  local total_size_original=0
  local total_size_optimized=0
  for file in "${files[@]}"; do
    (( total_size_original += ${original_sizes[${file}]} ))
    (( total_size_optimized += $(stat -f %z "${file}") ))
  done

  printf "\n\033[1mOptimized %d image%s\033[0m\n" "${image_count}" "$([[ ${image_count} -eq 1 ]] || print "s")"
  if [[ ${total_size_original} -eq 0 ]]; then
    print "There was a problem calculating optimization statistics."
  else
    local size_reduction=$(((total_size_original - total_size_optimized) * 100 / total_size_original))
    printf "Original size:  %.2f MB\n" $(print "${total_size_original} / 1000000" | bc -l)
    printf "Optimized size: %.2f MB\n" $(print "${total_size_optimized} / 1000000" | bc -l)
    printf "Size reduction: %d%%\n" ${size_reduction}
  fi
}
