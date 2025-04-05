# Options
FOLLOW_SYSTEM_THEME=1                       # 0: use DEFAULT_THEME, 1: switch according to system appearance
DEFAULT_THEME="dark"                        # "light" or "dark"
THEME_ANIMATION_CURVE="quadratic"           # linear, quadratic, tanh, sin, exp, or circ
THEME_ANIMATION_DURATION=12                 # n/60 seconds
UNLOCK_SOUND=1                              # 0: no sound, 1: play sound
UNLOCK_ANIMATION_CURVE="circ"               # linear, quadratic, tanh, sin, exp, or circ
UNLOCK_ANIMATION_DURATION=9                 # n/60 seconds
UPDATE_FREQUENCY="$((60 - $(date "+%-S")))" # Update frequency in seconds for non-event-based items

# Themes
typeset -A light=(
  [TEXT_DEFAULT_COLOR]=0xf2000000
  [TEXT_INVERSE_COLOR]=0xf2000000
  [TEXT_WARNING_COLOR]=0xfff53126
  [BACKGROUND_DEFAULT_COLOR]=0x80ffffff
  [BACKGROUND_HOVER_COLOR]=0xa0ffffff
  [BACKGROUND_ACTIVE_COLOR]=0x70ffffff
)
typeset -A dark=(
  [TEXT_DEFAULT_COLOR]=0xf2ffffff
  [TEXT_INVERSE_COLOR]=0xf2ffffff
  [TEXT_WARNING_COLOR]=0xffff4f44
  [BACKGROUND_DEFAULT_COLOR]=0x40ffffff
  [BACKGROUND_HOVER_COLOR]=0x4cffffff
  [BACKGROUND_ACTIVE_COLOR]=0x3affffff
)

theme="${DEFAULT_THEME}"
if [[ ${FOLLOW_SYSTEM_THEME} -eq 1 ]]; then
  theme="$([[ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)" == "Dark" ]] && print "dark" || print "light")"
fi

for key in ${(k)${(P)theme}}; do
  eval "${key}=${${(P)theme}[${key}]}"
done
