# Options
ADAPTIVE=1                # 0: use DEFAULT_THEME, 1: use system settings
DEFAULT_THEME="dark"      # "light" or "dark"
ANIMATION_CURVE="sin"     # linear, quadratic, tanh, sin, exp, or circ
ANIMATION_DURATION=15     # n/60 seconds

# Define themes
typeset -A light=(
  [FOREGROUND_COLOR]=0xf2000000
  [FOREGROUND_WARNING_COLOR]=0xfff53126
  [BACKGROUND_COLOR]=0x80ffffff
  [BACKGROUND_HOVER_COLOR]=0xa0ffffff
  [BACKGROUND_ACTIVE_COLOR]=0x70ffffff
)

typeset -A dark=(
  [FOREGROUND_COLOR]=0xf2ffffff
  [FOREGROUND_WARNING_COLOR]=0xffff4f44
  [BACKGROUND_COLOR]=0x40ffffff
  [BACKGROUND_HOVER_COLOR]=0x4cffffff
  [BACKGROUND_ACTIVE_COLOR]=0x3affffff
)

# Determine theme
theme="${DEFAULT_THEME}"
if [[ "${ADAPTIVE}" -eq 1 ]]; then
  theme=$([[ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)" = "Dark" ]] && print "dark" || print "light")
fi

# Set color variables
for key in ${(k)${(P)theme}}; do
  eval "${key}=${${(P)theme}[${key}]}"
done
