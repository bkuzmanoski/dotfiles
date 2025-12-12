aichat-enhance-inline() {
    if [[ -n "${BUFFER}" ]]; then
        local input="${BUFFER}"

        BUFFER+=" Generating…"

        zle -I
        zle redisplay

        BUFFER=$(aichat -e "$input")

        zle end-of-line
    fi
}

zle -N aichat-enhance-inline
