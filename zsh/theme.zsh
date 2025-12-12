# fzf
FZF_BASE_COLORS="gutter:-1,fg:-1,fg+:-1,bg:-1,hl:4,hl+:4,marker:4"
FZF_DARK_COLORS="bg+:#395263,info:8,spinner:8,border:8,scrollbar:8"
FZF_LIGHT_COLORS="bg+:#b2c9d8,info:15,spinner:15,border:15,scrollbar:15"

# zsh-syntax-highlighting
ZSH_HIGHLIGHT_STYLES[alias]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[arg0]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[autodirectory]="fg=7,underline"
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=5"
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=5"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=5,bold"
ZSH_HIGHLIGHT_STYLES[command]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[comment]="fg=8"
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=5"
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg=3"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=2"
ZSH_HIGHLIGHT_STYLES[function]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[global-alias]="fg=3"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=15"
ZSH_HIGHLIGHT_STYLES[path]="none"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=5"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=5"
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=5"
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg=3"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=2"
ZSH_HIGHLIGHT_STYLES[suffix-alias]="fg=7,underline"
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=1,bold"

update_theme() {
  local macos_mode="$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)"

  if [[ "${macos_mode}" == "Dark" ]]; then
    export THEME="dark"
    export FZF_THEME="${FZF_BASE_COLORS},${FZF_DARK_COLORS}"

    zstyle ":zce:*" fg "fg=7,bold"
    zstyle ":zce:*" bg "fg=15"
  else
    export THEME="light"
    export FZF_THEME="${FZF_BASE_COLORS},${FZF_LIGHT_COLORS}"

    zstyle ":zce:*" fg "fg=0,bold"
    zstyle ":zce:*" bg "fg=8"
  fi
}
