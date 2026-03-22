function fnm_use_on_cd() {
  if [[ -f .node-version || -f .nvmrc || -f package.json ]]; then
    fnm use --silent-if-unchanged
  fi
}

add-zsh-hook -D chpwd fnm_use_on_cd
add-zsh-hook chpwd fnm_use_on_cd
