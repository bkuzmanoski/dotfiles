#!/bin/zsh

###############################################################################
# Initialization
###############################################################################

SCRIPT_DIR="${0:A:h}"
TEMP_DIR="${HOME}/.dotfiles_setup"
BACKUP_DIR="${TEMP_DIR}/$(date "+%Y%m%d_%H%M%S")_backups"
LOG_FILE="${TEMP_DIR}/$(date "+%Y%m%d_%H%M%S").log"

mkdir -p "${BACKUP_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

_log() {
  local now="$(date "+%H:%M:%S")"
  case "$1" in
    --info)    local message="${now}: [INFO]    $2" ;;
    --warning) local message="${now}: [WARNING] $2" ;;
    --error)   local message="${now}: [ERROR]   $2" ;;
    *)         local message="${now}: [MESSAGE] $@" ;;
  esac
  print "${message}" | tee -a "${LOG_FILE}"
}

exec 2> >(while read -r line; do _log --error ${line}; done) # Log stderr to log file

typeset -A backups

_defaults_write() {
  local sudo currenthost

  while [[ "$1" == -* ]]; do
    case "$1" in
      --sudo)        sudo=1 ;;
      --currenthost) currenthost=1 ;;
      *)             _log --error "Unknown option: $1" && return 1 ;;
    esac
    shift
  done

  local -a cmd_prefix=(${sudo:+"sudo"} "defaults" "${currenthost:+"-currentHost"}")

  local -a export_cmd=(${cmd_prefix[@]} export "$@")
  local backup_path="${BACKUP_DIR}/${export_cmd[*]//\//_}.plist"
  if [[ -z "${backups[${backup_path}]}" ]]; then
    _log --info "Executing: ${export_cmd[*]}"
    ${export_cmd[@]}
    backups[${backup_path}]=1
  fi

  local -a write_cmd=(${cmd_prefix[@]} "write" "$@")
  _log --info "Executing: ${write_cmd[*]}"
  ${write_cmd[@]}
}

_set_system_hotkey() {
  local key="$1" enabled="$2" p1="$3" p2="$4" p3="$5"
  _defaults_write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "${key}" "<dict><key>enabled</key><${enabled}/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>${p1}</integer><integer>${p2}</integer><integer>${p3}</integer></array></dict></dict>"
}

_add_app_to_dock() {
  local app_path="$1"
  _defaults_write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${app_path}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
}

###############################################################################
# Install Homebrew, apps, and fonts
###############################################################################

if ! which -s brew >/dev/null; then
  _log --info "Installing Homebrew..."
  (
    exec 2>&1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  )

  if [[ $? -ne 0 ]]; then
    _log --error "Homebrew installation failed, exiting."
    exit 1
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

_log --info "Installing Homebrew bundle..."
if ! (
  exec 2>&1
  brew bundle --file "${SCRIPT_DIR}/Brewfile"
); then
  _log --error "Homebrew bundle installation failed, exiting."
  exit 1
fi

###############################################################################
# Link dotfiles
###############################################################################

typeset -A configs=(
  ["bat"]="${HOME}/.config/bat"
  ["eza"]="${HOME}/.config/eza"
  ["fd"]="${HOME}/.config/fd"
  ["ghostty"]="${HOME}/.config/ghostty"
  ["hammerspoon"]="${HOME}/.hammerspoon"
  ["micro"]="${HOME}/.config/micro"
  ["ripgrep"]="${HOME}/.config/ripgrep"
  ["sketchybar"]="${HOME}/.config/sketchybar"
  ["zsh"]="${HOME}/.zsh"
  [".zprofile"]="${HOME}/.zprofile"
  [".zshrc"]="${HOME}/.zshrc"
)

for config in "${(k)configs[@]}"; do
  _log --info "Linking ${config}"

  source_path="${SCRIPT_DIR}/${config}"
  target_path="${configs[${config}]}"

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    relative_path="${target_path#${HOME}/}"
    backup_path="${BACKUP_DIR}/${relative_path}"
    mkdir -p "$(dirname "${backup_path}")"
    mv "${target_path}" "${backup_path}"
    _log --info "Backed up existing config at ${target_path} to ${backup_path}"
  fi

  mkdir -p "$(dirname "${target_path}")"
  ln -sfh "${source_path}" "${target_path}" || _log --error "Failed to link ${config}"
done

###############################################################################
# Set up environment
###############################################################################

# Hide "Last login" message in terminal
_log --info "Creating ~/.hushlogin"
touch "${HOME}/.hushlogin"

# Enable Touch ID for sudo
if [[ ! -f /etc/pam.d/sudo_local ]]; then
  _log --info "Enabling Touch ID for sudo."
  print "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
else
  _log --info "Touch ID for sudo already enabled."
fi

# Enable bat to use themes in config directory
_log --info "Rebuilding bat cache."
bat cache --build >/dev/null || _log --error "Failed to build bat cache"

# Start SketchyBar
_log --info "Starting SketchyBar service."
if ! (
  exec 2>&1
  brew services start sketchybar >/dev/null
); then
  _log --error "Failed to start SketchyBar service."
fi

# Set wallpaper
wallpaper_path="${SCRIPT_DIR}/wallpapers/Wallpaper.heic"

if [[ -f "${wallpaper_path}" ]]; then
  _log --info "Setting wallpaper to ${wallpaper_path}"
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${wallpaper_path}\"" || _log --error "Failed to set wallpaper."
else
  _log --error "Wallpaper image not found."
fi

###############################################################################
# Write defaults
###############################################################################

_log --info "Setting defaults..."

# macOS settings
_defaults_write --sudo /Library/Preferences/com.apple.commerce AutoUpdate -bool true # Enable automatic App Store updates
_defaults_write --sudo /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0 # Disable automatic brightness reduction on battery
_defaults_write --sudo /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true # Enable automatic macOS updates
_defaults_write --sudo com.apple.CoreBrightness.plist "CBUser-$(dscl . -read "/Users/$(print "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')/" GeneratedUID | awk -F': ' '{ print $2 }')" -dict-add CBColorAdaptationEnabled -bool false # Disable True Tone
_defaults_write "${HOME}/Library/Group Containers/group.com.apple.notes/Library/Preferences/group.com.apple.notes.plist" kICSettingsNoteDateHeadersTypeKey -integer 1 # Disable group notes by date
_defaults_write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 2 # Decrease click sensitivity/increase haptic feedback strength
_defaults_write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 2 # Decrease click sensitivity/increase haptic feedback strength
_defaults_write com.apple.bird com.apple.clouddocs.unshared.moveOut.suppress -bool true # Suppress warnings when moving files out of iCloud Drive
_defaults_write com.apple.dock autohide -bool true # Enable Dock auto-hide
_defaults_write com.apple.dock autohide-delay -float 0 # Remove delay before Dock shows
_defaults_write com.apple.dock autohide-time-modifier -float 0.15 # Increase Dock show/hide animation speed
_defaults_write com.apple.dock mru-spaces -bool false # Disable automatic rearranging of Spaces based on most recent use
_defaults_write com.apple.dock persistent-apps -array # Clear existing Dock items
_defaults_write com.apple.dock show-recents -bool false # Hide recent apps in Dock
_defaults_write com.apple.dock showAppExposeGestureEnabled -bool true # Enable app exposé with three finger swipe down
_defaults_write com.apple.dock wvous-br-corner -int 1 # Disable bottom-right hot corner (default is Quick Note)
_defaults_write com.apple.finder _FXSortFoldersFirst -bool true # Sort folders first
_defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf" # Set default search scope to current folder
_defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false # Disable warning when changing file extensions
_defaults_write com.apple.finder FXPreferredViewStyle -string "Nlsv" # Set default view to list view
_defaults_write com.apple.finder NewWindowTarget -string "PfHm" # Open new windows in Home folder
_defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false # Hide external drives on Desktop
_defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false # Hide internal drives on Desktop
_defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false # Hide servers on Desktop
_defaults_write com.apple.finder ShowPathbar -bool true # Show path bar
_defaults_write com.apple.finder ShowRecentTags -bool false # Hide recent tags
_defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false # Hide removable media on Desktop
_defaults_write com.apple.finder ShowStatusBar -bool true # Show status bar
_defaults_write com.apple.finder WarnOnEmptyTrash -bool false # Disable warning when emptying Trash
_defaults_write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular" # Set plain text font to JetBrains Mono
_defaults_write com.apple.TextEdit NSFixedPitchFontSize -int 13 # Set plain text font size to 13
_defaults_write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false # Open to a blank document on launch
_defaults_write com.apple.TextEdit RichText -bool false # Use plain text by default
_defaults_write com.apple.universalaccess closeViewScrollWheelToggle -bool true # Enable zoom with scroll wheel modifier (Control)
_defaults_write com.apple.universalaccess closeViewSmoothImages -bool false # Disable smooth images when zooming
_defaults_write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false # Disable click to show desktop
_defaults_write com.apple.WindowManager EnableTilingByEdgeDrag -bool false # Disable window tiling when dragging to screen edge (can still hold Option to tile)
_defaults_write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false # Disable window tiling when dragging to top edge (can still hold Option to tile)
_defaults_write NSGlobalDomain _HIHideMenuBar -bool true # Hide menu bar
_defaults_write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" # Set double-click action to zoom/fill window
_defaults_write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false # Disable swipe between pages
_defaults_write NSGlobalDomain AppleKeyboardUIMode -int 2 # Enable full keyboard access for all controls
_defaults_write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true  # Show menu bar in full screen
_defaults_write NSGlobalDomain AppleReduceDesktopTinting -bool true # Disable wallpaper tinting in windows
_defaults_write NSGlobalDomain AppleShowAllExtensions -bool true # Show all file extensions in Finder
_defaults_write NSGlobalDomain AppleShowAllFiles -bool true # Show hidden files in Finder
_defaults_write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling" # Show scroll bars when scrolling
_defaults_write NSGlobalDomain InitialKeyRepeat -int 15 # Decrease delay before key starts repeating
_defaults_write NSGlobalDomain KeyRepeat -int 2 # Increase key repeat rate
_defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false # Disable automatic capitalization
_defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true # Show expanded save dialog by default
_set_system_hotkey 64 "false" 32 49 1048576 # Disable Show Spotlight search
_set_system_hotkey 65 "false" 32 49 1572864 # Disable Show Finder search window
_set_system_hotkey 28 "false" 51 20 1179648 # Disable Save picture of screen as a file
_set_system_hotkey 29 "false" 51 20 1441792 # Disable Copy picture of screen to the clipboard
_set_system_hotkey 30 "false" 52 21 1179648 # Disable Save picture of selected area as a file
_set_system_hotkey 31 "false" 52 21 1441792 # Disable Copy picture of selected area to the clipboard
_set_system_hotkey 184 "false" 53 23 1179648 # Disable Screenshot and recording options
_add_app_to_dock "/System/Applications/Mail.app"
_add_app_to_dock "/Applications/Google Chrome.app"
_add_app_to_dock "/Applications/Figma.app"
_add_app_to_dock "/Applications/Visual Studio Code.app"
_add_app_to_dock "/Applications/Ghostty.app"

# App settings
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Developer Tools" "\$@i" # Map Developer Tools to ⌥⌘I
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Email Link" "\U0000" # Remove shortcut for Email Link (conflicts with ⌥⌘I)
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab to the Right" "@t" # Map New Tab to the Right to ⌘T
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab" "\U0000" # Remove shortcut for New Tab (conflicts with ⌘T)
_defaults_write com.lwouis.alt-tab-macos appearanceStyle -int 2 # Set appearance to "Titles"
_defaults_write com.lwouis.alt-tab-macos appearanceVisibility -int 1 # Set appearance visibility to "High"
_defaults_write com.lwouis.alt-tab-macos holdShortcut -string $'\U2318' # Set hold key for shortcut 1 to ⌘
_defaults_write com.lwouis.alt-tab-macos holdShortcut2 -string $'\U2318' # Set hold key for shortcut 2 to ⌘
_defaults_write com.lwouis.alt-tab-macos windowDisplayDelay -int 0 # Set window display delay to 0 ms
_defaults_write com.pixelmatorteam.pixelmator.x appearanceAutomaticMode -bool true # Set appearance to auto
_defaults_write com.pixelmatorteam.pixelmator.x showWelcomeWindow -bool false # Don't show welcome window on launch
_defaults_write com.raycast.macos "NSStatusItem Visible raycastIcon" 0 # Hide menu bar icon
_defaults_write com.raycast.macos raycastGlobalHotkey -string "Command-49"; # Set hotkey to ⌘␣
_defaults_write com.sindresorhus.Scratchpad KeyboardShortcuts_toggleWindow -string '{"carbonModifiers":768,"carbonKeyCode":49}' # Set keyboard shortcut to ⌘⌥␣
_defaults_write com.sindresorhus.Scratchpad lineSpacing -string "0.3" # Set line spacing to 0.3
_defaults_write com.sindresorhus.Scratchpad showCloseButton -bool false # Hide close button
_defaults_write com.sindresorhus.Scratchpad showMenuBarIcon -bool false # Hide menu bar icon
_defaults_write com.sindresorhus.Scratchpad showOnAllSpaces -bool true # Show on all spaces
_defaults_write com.sindresorhus.Scratchpad SS_NSStatusItem_ensureVisibility_shouldNotShowAgain -bool true # Disable warning about menu bar item visibility
_defaults_write com.sindresorhus.Scratchpad SS_Tooltip_statusBarButtonWelcomePopover -bool true # Disable menu bar item welcome popover
_defaults_write com.sindresorhus.Scratchpad textSize -int 13 # Set font size to 13
_defaults_write net.pornel.ImageOptim PngCrush2Enabled -bool true # Enable PNG Crush 2
_defaults_write net.pornel.ImageOptim PngOutEnabled -bool false # Disable PNG Out (doesn't work on arm64)
_defaults_write org.hammerspoon.Hammerspoon HSUploadCrashData -bool false # Don't send crash data
_defaults_write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false # Hide menu bar icon
_defaults_write org.hammerspoon.Hammerspoon SUAutomaticallyUpdate -bool true # Enable automatic updates
_defaults_write org.hammerspoon.Hammerspoon SUEnableAutomaticChecks -bool true # Enable automatic update checks
_defaults_write pl.maketheweb.cleanshotx dimScreenWhileRecording -bool false # Do not dim screen while recording
_defaults_write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true # Enable Do Not Disturb while recording
_defaults_write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads" # Save screenshots/recordings to Downloads folder
_defaults_write pl.maketheweb.cleanshotx freezeScreen -bool true # Freeze screen during selection
_defaults_write pl.maketheweb.cleanshotx screenshotSound -int 3 # Set screenshot capture sound to "Subtle"
_defaults_write pl.maketheweb.cleanshotx showKeystrokes -bool true # Show keystrokes in recordings
_defaults_write pl.maketheweb.cleanshotx showMenubarIcon -bool false # Hide menu bar icon
_defaults_write pl.maketheweb.cleanshotx videoFPS -int 30 # Set video recording FPS to 30

###############################################################################
# The end
###############################################################################

_log --info "Setup completed."
print "\nIf there were no errors, you can remove the temporary setup directory by running:"
print -P "%Brm -rf ${TEMP_DIR}%b"
print "\nRestart your computer for all changes to take effect."
