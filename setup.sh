#!/bin/zsh

# Default to non-verbose
VERBOSE=0

# Parse flags
while getopts "v" opt; do
  case "${opt}" in
    v) VERBOSE=1 ;;
    *) echo "Usage: ${0} [-v]" >&2; exit 1 ;;
  esac
done

# Maintain sudo timestamp
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Exit on error
set -e

# Setup logging
log_file="${HOME}/.dotfiles_setup/$(date +%Y%m%d_%H%M%S).log"
touch "${log_file}"

# Helper functions
log() {
  if [[ "${VERBOSE}" -eq 1 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${1}" | tee -a "${log_file}"
  fi
}

error_log() {
  echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') ${1}" | tee -a "${log_file}" >&2
}

backup_dir="${HOME}/.dotfiles_setup/$(date +%Y%m%d_%H%M%S)_backups"
mkdir -p "${backup_dir}"

backup_plist() {
  local domain="${1}"
  local backup_path="${backup_dir}/${domain//\//_}.plist"
  log "Backing up ${domain} defaults to ${backup_path}"
  if ! sudo defaults export "${domain}" "${backup_path}" 2>/dev/null; then
    error_log "Failed to backup ${domain} defaults"
    exit 1
  fi
}

log "Starting setup script"

# # Install Homebrew and apps
# log "Checking Homebrew installation"
# if which -s brew; then
#   log "Homebrew is already installed"
# else
#   log "Installing Homebrew..."
#   echo "Install Command Line Tools when prompted"
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# fi

# # Wait for Xcode Command Line Tools
# until xcode-select -p &> /dev/null; do
#   log "Waiting for Xcode Command Line Tools installation..."
#   sleep 5
# done

log "Installing Brewfile bundle"
if ! brew bundle; then
  error_log "brew bundle failed"
  exit 1
fi

# Setup dotfiles
log "Linking .zprofile"
if [[ -f ".zprofile" ]]; then
  ln -sf "$(pwd)/.zprofile" ~/.zprofile || error_log "Failed to link .zprofile"
else
  error_log ".zprofile not found in current directory"
fi

log "Linking .zshrc"
if [[ -f ".zshrc" ]]; then
  ln -sf "$(pwd)/.zshrc" ~/.zshrc || error_log "Failed to link .zshrc"
else
  error_log ".zshrc not found in current directory"
fi

log "Linking Ghostty config"
if [[ -d "$(pwd)/ghostty" ]]; then
  ghostty_config_dir="${HOME}/.config/ghostty"
  mkdir -p "$(dirname "${ghostty_config_dir}")"
  ln -sf "$(pwd)/ghostty" "${ghostty_config_dir}" || error_log "Failed to link Ghostty directory"

  touch "${HOME}/.hushlogin"
else
  error_log "Ghostty directory not found"
fi

log "Linking bat config"
if [[ -d "$(pwd)/bat" ]]; then
  bat_config_dir="${HOME}/.config/bat"
  mkdir -p "$(dirname "${bat_config_dir}")"
  ln -sf "$(pwd)/bat" "${bat_config_dir}" || error_log "Failed to link bat directory"

  bat cache --build
else
  error_log "bat directory not found"
fi

log "Linking eza config"
if [[ -d "$(pwd)/eza" ]]; then
  eza_config_dir="${HOME}/.config/eza"
  mkdir -p "$(dirname "${eza_config_dir}")"
  ln -sf "$(pwd)/eza" "${eza_config_dir}" || error_log "Failed to link eza directory"
else
  error_log "eza directory not found"
fi

log "Linking micro config"
if [[ -d "$(pwd)/micro" ]]; then
  micro_config_dir="${HOME}/.config/micro"
  mkdir -p "$(dirname "${micro_config_dir}")"
  ln -sf "$(pwd)/micro" "${micro_config_dir}" || error_log "Failed to link micro directory"
else
  error_log "micro directory not found"
fi

# System settings
log "Setting system defaults..."
osascript -e 'tell application "System Settings" to quit'

# Global settings
log "Configuring global settings"
backup_plist "NSGlobalDomain"
defaults write NSGlobalDomain AppleActionOnDoubleClick -string "Fill"
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
defaults write NSGlobalDomain AppleKeyboardUIMode -int 2
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain AppleWindowTabbingMode -string "always"
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2

# Power management
log "Configuring power management"
backup_plist "/Library/Preferences/com.apple.PowerManagement"
sudo defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0

# Keyboard shortcuts
log "Configuring keyboard shortcuts"
backup_plist "com.apple.symbolichotkeys"

read -r -d "" hotkey_template << 'EOF'
<dict>
  <key>enabled</key><false/>
  <key>value</key><dict>
    <key>type</key><string>standard</string>
    <key>parameters</key>
    <array>
      <integer>%d</integer>
      <integer>%d</integer>
      <integer>%d</integer>
    </array>
  </dict>
</dict>
EOF

declare -A hotkey_params=(
  [28]="51 20 1179648"
  [29]="51 20 1441792"
  [30]="52 21 1179648"
  [31]="52 21 1441792"
  [64]="32 49 1048576"
  [184]="53 23 1179648"
)

for key in "${!hotkey_params[@]}"; do
  read -r p1 p2 p3 <<< "${hotkey_params[${key}]}"
  printf -v xml_entry "${hotkey_template}" "${p1}" "${p2}" "${p3}"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "${key}" "${xml_entry}"
done

# Window Manager
log "Configuring window manager"
backup_plist "com.apple.WindowManager"
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false

# Universal Access
log "Configuring Universal Access"
backup_plist "com.apple.universalaccess"
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
defaults write com.apple.universalaccess closeViewSmoothImages -bool false

# Menu Bar icons
log "Configuring Menu Bar icons"

log "Hiding Now Playing and Wi-Fi"
backup_plist "com.apple.controlcenter"
defaults write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -int 0
defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -int 0

log "Hiding Siri"
backup_plist "com.apple.Siri"
defaults write com.apple.Siri StatusMenuVisible -bool false

log "Hiding Spotlight"
backup_plist "com.apple.Spotlight"
defaults delete com.apple.Spotlight "NSStatusItem Visible Item-0"

# Software Updates
log "Configuring software update settings"

log "Enabling automatic macOS updates"
backup_plist "/Library/Preferences/com.apple.SoftwareUpdate"
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true

log "Enabling automatic App Store updates"
backup_plist "/Library/Preferences/com.apple.commerce"
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true

# Set wallpaper
wallpaper_image="${HOME}/.dotfiles/wallpapers/raycast.heic"

if [[ -f "${wallpaper_image}" ]]; then
  log "Setting wallpaper to ${wallpaper_image}"

  escaped_path="$(echo "${wallpaper_image}" | sed 's/"/\\"/g')"
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${escaped_path}\"" || error_log "Failed to set wallpaper"
else
  error_log "Wallpaper file not found"
fi

# Dock
log "Configuring Dock"
backup_plist "com.apple.dock"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.15
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock wvous-br-corner -int 1

dock_items=(
  "/System/Applications/Mail.app"
  "/Applications/Google Chrome.app"
  "/Applications/Figma.app"
  "/Applications/Visual Studio Code.app"
)

read -r -d "" dock_item_template << 'EOF'
<dict>
  <key>tile-data</key>
  <dict>
    <key>file-data</key>
    <dict>
      <key>_CFURLString</key>
      <string>%s</string>
      <key>_CFURLStringType</key>
      <integer>0</integer>
    </dict>
  </dict>
</dict>
EOF

for dock_item in "${dock_items[@]}"; do
  printf -v xml_entry "${dock_item_template}" "${dock_item}"
  defaults write com.apple.dock persistent-apps -array-add "${xml_entry}"
done

# Finder
log "Configuring Finder"
backup_plist "com.apple.bird"
defaults write com.apple.bird com.apple.clouddocs.unshared.moveOut.suppress -bool true
backup_plist "com.apple.finder"
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"
defaults write com.apple.finder downscaleRetinaVideos -bool true
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowRecentTags -bool false
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false
defaults write com.apple.finder WarnOnEmptyTrash -bool false

# Mail
log "Configuring Mail"
backup_plist "com.apple.mail"
defaults write com.apple.mail AutoReplyFormat -int 1
defaults write com.apple.mail ConversationViewMarkAllAsRead -int 1
defaults write com.apple.mail SendFormat -string "Plain"
defaults write com.apple.mail SwipeAction -int 1

# TextEdit
log "Configuring TextEdit"
backup_plist "com.apple.TextEdit"
defaults write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular"
defaults write com.apple.TextEdit NSFixedPitchFontSize -int 13
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
defaults write com.apple.TextEdit RichText -bool false

# CleanShot X
log "Configuring CleanShot X"
backup_plist "pl.maketheweb.cleanshotx"
defaults write pl.maketheweb.cleanshotx afterVideoActions -array 0
defaults write pl.maketheweb.cleanshotx afterScreenshotActions -array 1
defaults write pl.maketheweb.cleanshotx allowURLSchemesAPI -string "55e857c66268b59047535d6f427d1ee8"
defaults write pl.maketheweb.cleanshotx crosshairMode -int 2
defaults write pl.maketheweb.cleanshotx cursorHighlightStyle -int 1
defaults write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true
defaults write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads"
defaults write pl.maketheweb.cleanshotx freezeScreen -bool true
defaults write pl.maketheweb.cleanshotx highlightClicks -bool true
defaults write pl.maketheweb.cleanshotx keyboardOverlayStyle -int 1
defaults write pl.maketheweb.cleanshotx mergeAudioTracks -bool false
defaults write pl.maketheweb.cleanshotx recordComputerAudio -bool true
defaults write pl.maketheweb.cleanshotx rememberOneOverlayArea -bool false
defaults write pl.maketheweb.cleanshotx screenshotSound -int 3
defaults write pl.maketheweb.cleanshotx showKeystrokes -bool true
defaults write pl.maketheweb.cleanshotx showMenubarIcon -bool false
defaults write pl.maketheweb.cleanshotx videoFPS -int 30
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/CleanShot X.app", hidden:true}'

# Google Chrome
log "Configuring Google Chrome"
backup_plist "com.google.Chrome"
defaults write com.google.Chrome NSUserKeyEquivalents -dict "New Tab" "@~t" "New Tab to the Right" "@t"

# Raycast
log "Configuring Raycast"
backup_plist "com.raycast.macos"
defaults write com.raycast.macos "NSStatusItem Visible raycastIcon" 0

echo
echo "Setup completed! Restart your computer for all changes to take effect."

log "Setup completed"