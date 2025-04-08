# Options
DEFAULT_THEME="dark"                        # "light" or "dark"
FOLLOW_SYSTEM_THEME=1                       # 0: use DEFAULT_THEME, 1: switch according to system appearance
UNLOCK_SOUND=1                              # 0: no sound, 1: play sound
ANIMATION_CURVE="circ"                      # linear, quadratic, tanh, sin, exp, or circ
ANIMATION_DURATION=10                        # n/60 seconds
UPDATE_FREQUENCY="$((60 - $(date "+%-S")))" # Update frequency in seconds for non-event-based items

# Themes
typeset -A light=(
  [TEXT_DEFAULT_COLOR]=0xf2000000
  [TEXT_INVERSE_COLOR]=0xf2ffffff
  [TEXT_WARNING_COLOR]=0xffff3b30
  [BACKGROUND_WARNING_COLOR]=0xffff3b30
  [BACKGROUND_HOVER_COLOR]=0xa0ffffff
  [BACKGROUND_ACTIVE_COLOR]=0x70ffffff
)
typeset -A dark=(
  [TEXT_DEFAULT_COLOR]=0xf2ffffff
  [TEXT_INVERSE_COLOR]=0xf2ffffff
  [TEXT_WARNING_COLOR]=0xffff453a
  [BACKGROUND_WARNING_COLOR]=0xffff453a
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
