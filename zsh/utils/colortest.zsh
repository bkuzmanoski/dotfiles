function colortest() {
  local sample_text="gYw"
  local -a foregrounds=("" "1")
  local -a backgrounds=({40..47})
  local -i code

  for code in {30..37}; do
    foregrounds+=("${code}" "1;${code}")
  done

  printf "\n%12s" ""

  for background in "${backgrounds[@]}"; do
    printf "%8s" "${background}m"
  done

  print

  for foreground in "${foregrounds[@]}"; do
    printf " %5s \e[%sm  %s  " "${foreground}m" "${foreground}" "${sample_text}"

    for background in "${backgrounds[@]}"; do
      printf " \e[%sm\e[%sm  %s  \e[0m" "${foreground}" "${background}" "${sample_text}"
    done

    print
  done

  print
}
