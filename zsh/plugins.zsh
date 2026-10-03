readonly -a ZSH_PLUGINS=(
  # plugin|git_url|source_file_name
  "fzf-tab|https://github.com/Aloxaf/fzf-tab|fzf-tab.plugin.zsh"
  "fzf-navigator|https://github.com/benward2301/fzf-navigator|fzf-navigator.sh"
  "zce|https://github.com/hchbaw/zce.zsh|zce.zsh"
  "zsh-ai-cmd|https://github.com/kylesnowschwartz/zsh-ai-cmd|zsh-ai-cmd.plugin.zsh"
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions|zsh-autosuggestions.zsh"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting|zsh-syntax-highlighting.zsh"
)

for plugin_entry in "${ZSH_PLUGINS[@]}"; do
  typeset parts=("${(@s:|:)plugin_entry}")
  typeset plugin="${parts[1]}"
  typeset git_repository="${parts[2]}"
  typeset source_file_name="${parts[3]}"
  typeset plugin_dir="${HOME}/.zsh/plugins/${plugin}"
  typeset source_file_path="${plugin_dir}/${source_file_name}"

  if [[ ! -d "${plugin_dir}" ]]; then
    print -P "Installing %B${plugin}%b..."

    if ! git clone "${git_repository}" "${plugin_dir}"; then
      print -u2 "\n${plugin} installation failed.\n"
      continue
    fi

    print
  fi

  if [[ -f "${source_file_path}" ]]; then
    source "${source_file_path}"
  else
    print -u2 "Warning: Source file for ${plugin} not found at \"${source_file_path}\".\n"
  fi
done

unset plugin_entry
unset parts
unset plugin
unset git_repository
unset source_file_name
unset plugin_dir
unset source_file_path
