#!/bin/zsh

trap 'kill %1; exit 1' INT TERM

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
log_dir="${HOME}/.dotfiles_setup"
log_file="${log_dir}/$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${log_dir}"
touch "${log_file}"

# Helper functions
log() {
  if [[ "${VERBOSE}" -eq 1 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${1}" | tee -a "${log_file}"
  fi
}

error_log() {
  echo "[ERROR] [$(date '+%Y-%m-%d %H:%M:%S')] ${1}" | tee -a "${log_file}" >&2
}

backup_dir="${HOME}/.dotfiles_setup/$(date +%Y%m%d_%H%M%S)_backups"
mkdir -p "${backup_dir}"

backup_plist() {
  local domain="${1}"
  local use_sudo="${2:-false}"
  local use_current_host="${3:-false}"

  local sudo_cmd=""
  local current_host_flag=""
  local file_suffix=""

  if [[ "${use_sudo}" == "true" ]]; then
    sudo_cmd="sudo"
    file_suffix=".sudo"
  fi

  if [[ "${use_current_host}" == "true" ]]; then
    current_host_flag="-currentHost"
    file_suffix="${file_suffix}.currentHost"
  fi

  local backup_path="${backup_dir}/${domain//\//_}${file_suffix}.plist"

  log "Backing up defaults to ${backup_path}"
  if ! ${sudo_cmd} defaults ${current_host_flag} export "${domain}" "${backup_path}"; then
    error_log "Failed to backup ${sudo_cmd:+"${sudo_cmd} "}${current_host_flag:+"${current_host_flag} "}${domain} defaults (exiting)"
    exit 1
  fi
}

log "Starting setup script"

# Install Homebrew (if not already installed)
log "Checking Homebrew installation"
if which -s brew; then
  log "Homebrew is already installed"
else
  log "Installing Homebrew..."
  echo "Install Command Line Tools when prompted"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Wait for Xcode Command Line Tools installation to complete
until xcode-select -p &> /dev/null; do
  log "Waiting for Xcode Command Line Tools installation..."
  sleep 5
done

# Install apps
log "Installing Brewfile bundle"
if [[ -f "Brewfile" ]]; then
  if ! brew bundle; then
    error_log "brew bundle failed (exiting)"
    exit 1
  fi
else
  error_log "Brewfile not found (exiting)"
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

  touch "${HOME}/.hushlogin" # Suppress shell login message
else
  error_log "Ghostty directory not found"
fi

log "Linking bat config"
if [[ -d "$(pwd)/bat" ]]; then
  bat_config_dir="${HOME}/.config/bat"
  mkdir -p "$(dirname "${bat_config_dir}")"
  ln -sf "$(pwd)/bat" "${bat_config_dir}" || error_log "Failed to link bat directory"

  bat cache --build # Rebuild bat cache so custom theme is available
else
  error_log "bat directory not found"
fi

log "Linking colima config"
if [[ -d "$(pwd)/colima" ]]; then
  colima_config_dir="${HOME}/.colima/default"
  mkdir -p "$(dirname "${colima_config_dir}")"
  ln -sf "$(pwd)/colima" "${colima_config_dir}" || error_log "Failed to link colima directory"
else
  error_log "colima directory not found"
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
log "Configuring system defaults..."
osascript -e 'tell application "System Settings" to quit'

# Global settings
log "Configuring global defaults"
backup_plist "NSGlobalDomain"
defaults write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" # Set double-click action to zoom/fill window
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false # Disable swipe navigation in browsers
defaults write NSGlobalDomain AppleKeyboardUIMode -int 2 # Enable full keyboard access for all controls
defaults write NSGlobalDomain AppleShowAllExtensions -bool true # Show all file extensions in Finder
defaults write NSGlobalDomain AppleWindowTabbingMode -string "always" # Always use tabs when opening documents
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false # Disable automatic capitalization
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true # Show expanded save dialog by default
defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true # Click anywhere in window to move it with Control + Command
defaults write NSGlobalDomain InitialKeyRepeat -int 15 # Decrease delay before key starts repeating
defaults write NSGlobalDomain KeyRepeat -int 2 # Increase key repeat rate

# Power management
log "Configuring power management defaults"
backup_plist "/Library/Preferences/com.apple.PowerManagement" true false
sudo defaults write /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0 #  Disable automatic brightness reduction on battery

# Keyboard shortcuts
log "Configuring global keyboard shortcuts"

# backup_plist "NSGlobalDomain" false true

# modifier_mapping=$(/bin/cat << 'EOF'
# <dict>
#   <key>HIDKeyboardModifierMappingSrc</key>
#   <integer>30064771129</integer>
#   <key>HIDKeyboardModifierMappingDst</key>
#   <integer>30064771300</integer>
# </dict>
# EOF
# )

# defaults -currentHost write NSGlobalDomain com.apple.keyboard.modifiermapping.0-0-0 -array "${modifier_mapping}" # Remap modifier keys

backup_plist "com.apple.symbolichotkeys"

# These are the default params for these hotkeys
# Including them means each hotkey can be toggled on/off in System Settings without needing to re-set the keybinding
declare -A hotkey_params=(
  [64]="32 49 1048576" # Show Spotlight search
  [28]="51 20 1179648" # Save picture of screen as a file
  [29]="51 20 1441792" # Copy picture of screen to the clipboard
  [30]="52 21 1179648" # Save picture of selected area as a file
  [31]="52 21 1441792" # Copy picture of selected area to the clipboard
  [184]="53 23 1179648" # Screenshot and recording options
)

hotkey_template=$(/bin/cat << 'EOF'
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
)

for key in ${(k)hotkey_params}; do
  read -r p1 p2 p3 <<< "${hotkey_params[${key}]}"
  printf -v xml_entry "${hotkey_template}" "${p1}" "${p2}" "${p3}"
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "${key}" "${xml_entry}" # Disable hotkeys above
done

# Window Manager
log "Configuring window manager defaults"
backup_plist "com.apple.WindowManager"
defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false # Disable click to show desktop
defaults write com.apple.WindowManager EnableTilingByEdgeDrag -bool false # Disable window tiling when dragging to screen edge (can still hold Option to tile)
defaults write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false # Disable window tiling when dragging to top edge (can still hold Option to tile)

# Universal Access
log "Configuring Universal Access defaults"
backup_plist "com.apple.universalaccess"
defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true # Enable zoom with scroll wheel modifier (Control)
defaults write com.apple.universalaccess closeViewSmoothImages -bool false # Disable smooth images when zooming

# Menu Bar icons
log "Configuring Menu Bar icons"

backup_plist "com.apple.controlcenter"
defaults write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -int 0 # Hide Now Playing icon in Menu Bar
defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -int 0 # Hide Wi-Fi icon in Menu Bar

backup_plist "com.apple.Siri"
defaults write com.apple.Siri StatusMenuVisible -bool false # Hide Siri icon in Menu Bar

backup_plist "com.apple.Spotlight"
defaults read com.apple.Spotlight "NSStatusItem Visible Item-0" &> /dev/null && defaults delete com.apple.Spotlight "NSStatusItem Visible Item-0" # Hide Spotlight icon in Menu Bar

# Software Updates
log "Configuring software update settings"

backup_plist "/Library/Preferences/com.apple.SoftwareUpdate" true false
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true # Enable automatic macOS updates

backup_plist "/Library/Preferences/com.apple.commerce" true false
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true # Enable automatic App Store updates

# Set wallpaper
wallpaper_image="$(pwd)/wallpapers/raycast.heic"

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
defaults write com.apple.dock autohide -bool true # Enable Dock auto-hide
defaults write com.apple.dock autohide-delay -float 0 # Remove delay before Dock shows
defaults write com.apple.dock autohide-time-modifier -float 0.15 # Increase Dock show/hide animation speed
defaults write com.apple.dock mru-spaces -bool false # Disable automatic rearranging of Spaces based on most recent use
defaults write com.apple.dock persistent-apps -array # Clear all apps from Dock (will add custom apps below)
defaults write com.apple.dock show-recents -bool false # Hide recent applications in Dock
defaults write com.apple.dock wvous-br-corner -int 1 # Disable bottom-right hot corner (default is Quick Note)

dock_items=(
  "/System/Applications/Mail.app"
  "/Applications/Google Chrome.app"
  "/Applications/Figma.app"
  "/Applications/Visual Studio Code.app"
)

dock_item_template=$(/bin/cat << 'EOF'
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
)

for dock_item in "${dock_items[@]}"; do
  printf -v xml_entry "${dock_item_template}" "${dock_item}"
  defaults write com.apple.dock persistent-apps -array-add "${xml_entry}" # Add custom apps to Dock
done

# Finder
log "Configuring Finder"

backup_plist "com.apple.bird"
defaults write com.apple.bird com.apple.clouddocs.unshared.moveOut.suppress -bool true # Suppresse warnings when moving files out of iCloud Drive

backup_plist "com.apple.finder"
defaults write com.apple.finder _FXSortFoldersFirst -bool true # Sort folders first
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf" # Set default search scope to current folder
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false # Disable warning when changing file extensions
defaults write com.apple.finder FXPreferredViewStyle -string "clmv" # Set default view to column view
defaults write com.apple.finder NewWindowTarget -string "PfHm" # Open new windows in Home folder
defaults write com.apple.finder ShowPathbar -bool true # Show path bar
defaults write com.apple.finder ShowRecentTags -bool false # Hide recent tags
defaults write com.apple.finder ShowStatusBar -bool true # Show status bar
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false # Hide external drives on Desktop
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false # Hide internal drives on Desktop
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false # Hide servers on Desktop
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false # Hide removable media on Desktop
defaults write com.apple.finder WarnOnEmptyTrash -bool false # Disable warning when emptying Trash

# Mail
log "Configuring Mail"
backup_plist "com.apple.mail"
defaults write com.apple.mail AutoReplyFormat -int 1 # Set reply format to same as original message
defaults write com.apple.mail ConversationViewMarkAllAsRead -int 1 # Mark all messages as read when opening a conversation
defaults write com.apple.mail SendFormat -string "Plain" # Set default message format to plain text
defaults write com.apple.mail SwipeAction -int 1 # Set default action to "Archive" instead of "Delete"

# TextEdit
log "Configuring TextEdit"
backup_plist "com.apple.TextEdit"
defaults write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular" # Set plain text font to JetBrains Mono
defaults write com.apple.TextEdit NSFixedPitchFontSize -int 13 # Set plain text font size to 13
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false # Open to a blank document on launch
defaults write com.apple.TextEdit RichText -bool false # Use plain text by default

# CleanShot X
log "Configuring CleanShot X"
backup_plist "pl.maketheweb.cleanshotx"
defaults write pl.maketheweb.cleanshotx afterVideoActions -array 0 # Show Quick Access Overlay after recording
defaults write pl.maketheweb.cleanshotx afterScreenshotActions -array 1 # Copy to clipboard after taking a screenshot
defaults write pl.maketheweb.cleanshotx allowURLSchemesAPI -string "55e857c66268b59047535d6f427d1ee8" # Allow applications to control CleanShot X (for Raycast integration)
defaults write pl.maketheweb.cleanshotx crosshairMode -int 2 # Always enable crosshair mode for selection
defaults write pl.maketheweb.cleanshotx cursorHighlightStyle -int 1 # Set cursor highlight style to "Filled"
defaults write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true # Enable Do Not Disturb while recording
defaults write pl.maketheweb.cleanshotx downscaleRetinaVideos -bool true # Downscale videos to 1x
defaults write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads" # Save screenshots/recordings to Downloads folder
defaults write pl.maketheweb.cleanshotx freezeScreen -bool true # Freeze screen during selection
defaults write pl.maketheweb.cleanshotx highlightClicks -bool true # Highlight mouse clicks in recordings
defaults write pl.maketheweb.cleanshotx keyboardOverlayStyle -int 1 # Set keyboard overlay style to "Light"
defaults write pl.maketheweb.cleanshotx mergeAudioTracks -bool false # Keep audio tracks separate in recordings
defaults write pl.maketheweb.cleanshotx recordComputerAudio -bool true # Record computer audio in recordings
defaults write pl.maketheweb.cleanshotx rememberOneOverlayArea -bool false # Do not remember last selection area for recordings
defaults write pl.maketheweb.cleanshotx screenshotSound -int 3 # Set screenshot capture sound to "Subtle"
defaults write pl.maketheweb.cleanshotx showKeystrokes -bool true # Show keystrokes in recordings
defaults write pl.maketheweb.cleanshotx showMenubarIcon -bool false # Hide Menu Bar icon
defaults write pl.maketheweb.cleanshotx videoFPS -int 30 # Set video recording FPS to 30

osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/CleanShot X.app", hidden:true}'

# Google Chrome
log "Configuring Google Chrome"
backup_plist "com.google.Chrome"
defaults write com.google.Chrome NSUserKeyEquivalents -dict "New Tab" "@~t" "New Tab to the Right" "@t" # Re-map Command + T to open new tab to the right of active tab, and Option + Command + T to default open new tab behavior

# Raycast
log "Configuring Raycast"
backup_plist "com.raycast.macos"
defaults write com.raycast.macos "NSStatusItem Visible raycastIcon" 0 # Hide Menu Bar icon

echo
echo "Setup completed! Restart your computer for all changes to take effect."

log "Setup completed"

kill %1