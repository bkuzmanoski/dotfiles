clear-screen-and-scrollback() {
  echoti civis >"${TTY}"
  printf "%b" "\e[H\e[2J\e[3J" >"${TTY}"
  echoti cnorm >"${TTY}"
  zle redisplay
}

zle -N clear-screen-and-scrollback
