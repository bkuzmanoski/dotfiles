export ZSH_AI_CMD_KEY="\ea"

bindkey "^[[1;10A" fh
bindkey "\ec" copy-buffer-to-clipboard
bindkey "\eg" zce-themed

bindkey "^u" backward-kill-line
bindkey "^[[3;9~" kill-line
bindkey "^[[3;3~" kill-word
bindkey "^[[122;9u" undo
bindkey "^[[97;10u" redo
bindkey -s "^[[13;2u" ' \\\n'
