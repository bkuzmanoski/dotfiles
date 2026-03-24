readonly -a ZSH_PLUGINS=(
  # plugin|git_url|source_file
  "fzf-tab|https://github.com/Aloxaf/fzf-tab|fzf-tab.plugin.zsh"
  "zce|https://github.com/hchbaw/zce.zsh|zce.zsh"
  "zsh-ai-cmd|https://github.com/kylesnowschwartz/zsh-ai-cmd|zsh-ai-cmd.plugin.zsh"
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions|zsh-autosuggestions.zsh"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting|zsh-syntax-highlighting.zsh"
)

for plugin_entry in "${ZSH_PLUGINS[@]}"; do
  local parts=("${(@s:|:)plugin_entry}")
  local plugin="${parts[1]}"
  local git_repository="${parts[2]}"
  local source_file="${parts[3]}"
  local plugin_dir="${HOME}/.zsh/plugins/${plugin}"

  if [[ ! -d "${plugin_dir}" ]]; then
    print -P "Installing %B${plugin}%b..."
    git clone "${git_repository}" "${plugin_dir}"

    if [[ $? -ne 0 ]]; then
      print -u2 "\n${plugin} installation failed.\n"
      continue
    fi

    print
  fi

  if [[ -f "${plugin_dir}/${source_file}" ]]; then
    source "${plugin_dir}/${source_file}"
  else
    print "Warning: Plugin file ${source_file} not found for ${plugin}\n"
  fi
done

