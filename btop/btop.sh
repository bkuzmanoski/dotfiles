#!/bin/zsh

config="${HOME}/.config/btop/btop.conf"

if [[ -f ${config} ]]; then
    lines=("${(@f)$(<${config})}")

    new_config=""
    for line in "${lines[@]}"; do
        if [[ ${line} =~ "color_theme" ]]; then
            new_config+="color_theme = \"${THEME}\"\n"
        else
            new_config+="${line}\n"
        fi
    done

    print -n ${new_config} >| ${config}
fi

btop "$@"