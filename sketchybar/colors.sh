# Options
ADAPTIVE=0                # 0: use DEFAULT_THEME, 1: use system settings
PALETTE="NEUTRAL"         # "NEUTRAL" or "BLUE"
DEFAULT_THEME="DARK"      # "LIGHT" or "DARK"

# Determine theme
THEME="${DEFAULT_THEME}"
if [[ "${ADAPTIVE}" -eq 1 ]]; then
  THEME=$([[ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)" = "Dark" ]] && echo "DARK" || echo "LIGHT")
fi

# Define palettes
typeset -A NEUTRAL_LIGHT NEUTRAL_DARK BLUE_LIGHT BLUE_DARK

NEUTRAL_LIGHT=(
  [ICON_COLOR]=0x99000000
  [LABEL_COLOR]=0xf2000000
  [ICON_WARNING_COLOR]=0xffff3b30
  [LABEL_WARNING_COLOR]=0xffff3b30
  [BACKGROUND_COLOR]=0x80ffffff
  [BACKGROUND_HOVER_COLOR]=0xa0ffffff
  [BACKGROUND_ACTIVE_COLOR]=0x70ffffff
  [BORDER_COLOR]=0x20000000
)

NEUTRAL_DARK=(
  [ICON_COLOR]=0xd9ffffff
  [LABEL_COLOR]=0xf2ffffff
  [ICON_WARNING_COLOR]=0xffff453a
  [LABEL_WARNING_COLOR]=0xffff453a
  [BACKGROUND_COLOR]=0x20ffffff
  [BACKGROUND_HOVER_COLOR]=0x2affffff
  [BACKGROUND_ACTIVE_COLOR]=0x1effffff
  [BORDER_COLOR]=0x10ffffff
)

BLUE_LIGHT=(
  [ICON_COLOR]=0x99000000
  [LABEL_COLOR]=0xf2000000
  [ICON_WARNING_COLOR]=0xffb03645
  [LABEL_WARNING_COLOR]=0xffb03645
  [BACKGROUND_COLOR]=0xffdde1e3
  [BACKGROUND_HOVER_COLOR]=0xffe6e9eb
  [BACKGROUND_ACTIVE_COLOR]=0xffd5d9dc
  [BORDER_COLOR]=0xffa9aeb2
)

BLUE_DARK=(
  [ICON_COLOR]=0xd9ffffff
  [LABEL_COLOR]=0xf2ffffff
  [ICON_WARNING_COLOR]=0xffde6e7c
  [LABEL_WARNING_COLOR]=0xffde6e7c
  [BACKGROUND_COLOR]=0xff2f363b
  [BACKGROUND_HOVER_COLOR]=0xff343c41
  [BACKGROUND_ACTIVE_COLOR]=0xff2a3237
  [BORDER_COLOR]=0xff394046
)

# Set colors
set_colors() {
  local palette="$1_$2"

  for key in ${(k)${(P)palette}}; do
    eval "${key}=${${(P)palette}[${key}]}"
  done
}

set_colors "${PALETTE}" "${THEME}"
