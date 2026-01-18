export ZSH_AI_CMD_KEY='\e[CommandA'

bindkey "\e[CommandL" clear-screen-and-scrollback
bindkey "\ec" copy-buffer-to-clipboard
bindkey "\e[CommandUp" beginning-of-history
bindkey "\e[CommandDown" end-of-history
bindkey "\e[CommandZ" undo
bindkey "\e[ShiftCommandZ" redo
bindkey '\e[CommandBackspace' backward-kill-line
bindkey '\e[CommandDelete' kill-line
bindkey -s "\e[ShiftEnter" '\\\n'
bindkey "\e[CommandG" zce-custom
bindkey -s "\e[ShiftCommandG" ""
bindkey -s "\e[CommandK" ""
bindkey -s "\e[CommandO" ""
bindkey -s "\e[CommandX" ""
bindkey -s "\e[CommandMinus" ""
bindkey -s "\e[CommandEqual" ""
bindkey -s "\e[ShiftCommandLeftBracket" ""
bindkey -s "\e[ShiftCommandRightBracket" ""
