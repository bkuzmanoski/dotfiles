#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
TEMP_DIR="${HOME}/.dotfiles_setup"
BACKUP_DIR="${TEMP_DIR}/$(date +%Y%m%d_%H%M%S)_backups"
LOG_FILE="${TEMP_DIR}/$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${BACKUP_DIR}"
mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

log() {
  local now="$(date +"%H:%M:%S")"

  case "${1}" in
    "--info")     local message="${now}: [INFO]    ${2}" ;;
    "--warning")  local message="${now}: [WARNING] ${2}" ;;
    "--error")    local message="${now}: [ERROR]   ${2}" ;;
    *)            local message="${now}: [MESSAGE] ${@}" ;;
  esac

  print "${message}" | tee -a "${LOG_FILE}"
}

exec 2> >(while read -r line; do log --error "${line}"; done) # Log stderr to log file

### Install Homebrew
if ! which -s brew > /dev/null; then
  log --info "Installing Homebrew..."
  (
    exec 2>&1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  )

  if [[ ${?} -ne 0 ]]; then
    log --error "Homebrew installation failed, exiting."
    exit 1
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

### Install apps and fonts
log --info "Installing Brewfile bundle."
if ! (
  exec 2>&1
  brew bundle --file "${SCRIPT_DIR}/Brewfile"
); then
  log --error "brew bundle failed, exiting."
  exit 1
fi

### Link dotfiles
typeset -A configs=(
  ["bat"]="${HOME}/.config/bat"
  ["eza"]="${HOME}/.config/eza"
  ["fd"]="${HOME}/.config/fd"
  ["ghostty"]="${HOME}/.config/ghostty"
  ["hammerspoon"]="${HOME}/.hammerspoon"
  ["micro"]="${HOME}/.config/micro"
  ["sketchybar"]="${HOME}/.config/sketchybar"
  ["zsh"]="${HOME}/.zsh"
  [".zprofile"]="${HOME}/.zprofile"
  [".zshrc"]="${HOME}/.zshrc"
)

for config in "${(k)configs[@]}"; do
  log --info "Linking ${config}"

  source_path="${SCRIPT_DIR}/${config}"
  target_path="${configs[${config}]}"

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    relative_path="${target_path#${HOME}/}"
    backup_path="${BACKUP_DIR}/${relative_path}"
    mkdir -p "$(dirname "${backup_path}")"
    mv "${target_path}" "${backup_path}"
    log --info "Backed up existing config at ${target_path} to ${backup_path}"
  fi

  mkdir -p "$(dirname "${target_path}")"
  ln -sfh "${source_path}" "${target_path}" || log --error "Failed to link ${config}"
done

# Hide "Last login" message in terminal
log --info "Creating ~/.hushlogin"
touch "${HOME}/.hushlogin"

# Enable Touch ID for sudo
if [[ ! -f /etc/pam.d/sudo_local ]]; then
  log --info "Enabling Touch ID for sudo."
  print "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local > /dev/null
fi

# Enable bat to use themes in config directory
log --info "Rebuilding bat cache."
bat cache --build > /dev/null || log --error "Failed to build bat cache"

# Start SketchyBar
if ! (
  exec 2>&1
  brew services start sketchybar > /dev/null
); then
  log --error "Failed to start SketchyBar."
fi

### Set defaults
log --info "Setting defaults..."

typeset -A backed_up_domains

backup_plist() {
  local cmd=(defaults export)
  local use_sudo=false

  if [[ "${1}" == "--sudo" ]]; then
    cmd=(sudo defaults export)
    use_sudo=true
    shift
  fi

  local domain="${1}"
  local fq_domain="${1}${use_sudo:+".sudo"}"

  if [[ -z "${backed_up_domains[${fq_domain}]:-}" ]]; then
    local backup_path="${BACKUP_DIR}/${fq_domain//\//_}.plist"
    log --info "Executing: $(printf "%q " "${cmd[@]}")$*"
    ${cmd[@]} "$@" "${backup_path}"
    backed_up_domains[${fq_domain}]=1
  fi
}

defaults_write() {
  local cmd=(defaults write)
  local use_sudo=false

  if [[ "${1}" == "--sudo" ]]; then
    cmd=(sudo defaults write)
    use_sudo=true
    shift
  fi

  local domain="${1}"
  backup_plist --sudo "${domain}"
  log --info "Executing: $(printf "%q " "${cmd[@]}")$*"
  ${cmd[@]} "$@"
}

defaults_delete() {
  if defaults read "$@" &> /dev/null; then
    local domain="${1}"
    backup_plist "${domain}"
    log --info "Executing: defaults delete $*"
    defaults delete "$@"
  fi
}

# macOS settings
defaults_write --sudo /Library/Preferences/com.apple.commerce AutoUpdate -bool true # Enable automatic App Store updates
defaults_write --sudo /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0 # Disable automatic brightness reduction on battery
defaults_write --sudo /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true # Enable automatic macOS updates
defaults_write "${HOME}/Library/Group Containers/group.com.apple.notes/Library/Preferences/group.com.apple.notes.plist" kICSettingsNoteDateHeadersTypeKey -integer 1 # Disable group notes by date
defaults_write com.apple.ActivityMonitor UpdatePeriod -int 1 # Set update frequency to 1 second
defaults_write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 2 # Decrease click sensitivity/increase haptic feedback strength
defaults_write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 2 # Decrease click sensitivity/increase haptic feedback strength
defaults_write com.apple.bird com.apple.clouddocs.unshared.moveOut.suppress -bool true # Suppress warnings when moving files out of iCloud Drive
defaults_write com.apple.dock autohide -bool true # Enable Dock auto-hide
defaults_write com.apple.dock autohide-delay -float 0 # Remove delay before Dock shows
defaults_write com.apple.dock autohide-time-modifier -float 0.15 # Increase Dock show/hide animation speed
defaults_write com.apple.dock mru-spaces -bool false # Disable automatic rearranging of Spaces based on most recent use
defaults_write com.apple.dock persistent-apps -array # Clear existing Dock items
defaults_write com.apple.dock show-recents -bool false # Hide recent applications in Dock
defaults_write com.apple.dock wvous-br-corner -int 1 # Disable bottom-right hot corner (default is Quick Note)
defaults_write com.apple.finder _FXSortFoldersFirst -bool true # Sort folders first
defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf" # Set default search scope to current folder
defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false # Disable warning when changing file extensions
defaults_write com.apple.finder FXPreferredViewStyle -string "Nlsv" # Set default view to list view
defaults_write com.apple.finder NewWindowTarget -string "PfHm" # Open new windows in Home folder
defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false # Hide external drives on Desktop
defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false # Hide internal drives on Desktop
defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false # Hide servers on Desktop
defaults_write com.apple.finder ShowPathbar -bool true # Show path bar
defaults_write com.apple.finder ShowRecentTags -bool false # Hide recent tags
defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false # Hide removable media on Desktop
defaults_write com.apple.finder ShowStatusBar -bool true # Show status bar
defaults_write com.apple.finder WarnOnEmptyTrash -bool false # Disable warning when emptying Trash
defaults_write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular" # Set plain text font to JetBrains Mono
defaults_write com.apple.TextEdit NSFixedPitchFontSize -int 13 # Set plain text font size to 13
defaults_write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false # Open to a blank document on launch
defaults_write com.apple.TextEdit RichText -bool false # Use plain text by default
defaults_write com.apple.universalaccess closeViewScrollWheelToggle -bool true # Enable zoom with scroll wheel modifier (Control)
defaults_write com.apple.universalaccess closeViewSmoothImages -bool false # Disable smooth images when zooming
defaults_write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false # Disable click to show desktop
defaults_write com.apple.WindowManager EnableTilingByEdgeDrag -bool false # Disable window tiling when dragging to screen edge (can still hold Option to tile)
defaults_write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false # Disable window tiling when dragging to top edge (can still hold Option to tile)
defaults_write NSGlobalDomain _HIHideMenuBar -bool true # Hide menu bar
defaults_write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" # Set double-click action to zoom/fill window
defaults_write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false # Disable swipe between pages
defaults_write NSGlobalDomain AppleKeyboardUIMode -int 2 # Enable full keyboard access for all controls
defaults_write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true  # Show menu bar in full screen
defaults_write NSGlobalDomain AppleReduceDesktopTinting -bool true # Disable wallpaper tinting in windows
defaults_write NSGlobalDomain AppleShowAllExtensions -bool true # Show all file extensions in Finder
defaults_write NSGlobalDomain AppleShowAllFiles -bool true # Show hidden files in Finder
defaults_write NSGlobalDomain InitialKeyRepeat -int 15 # Decrease delay before key starts repeating
defaults_write NSGlobalDomain KeyRepeat -int 2 # Increase key repeat rate
defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false # Disable automatic capitalization
defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true # Show expanded save dialog by default

# Disable True Tone
current_user=$(print "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
user_id=$(dscl . -read "/Users/${current_user}/" GeneratedUID | awk -F': ' '{print $2}')
defaults_write --sudo com.apple.CoreBrightness.plist "CBUser-${user_id}" -dict-add CBColorAdaptationEnabled -bool false

# Set keyboard shortcuts
set_system_hotkey() {
  local key="${1}"
  local enabled="${2}"
  local p1="${3}" p2="${4}" p3="${5}"
  defaults_write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "${key}" "<dict><key>enabled</key><${enabled}/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>${p1}</integer><integer>${p2}</integer><integer>${p3}</integer></array></dict></dict>"
}

set_system_hotkey 64 "false" 32 49 1048576 # Disable Show Spotlight search
set_system_hotkey 65 "false" 32 49 1572864 # Disable Show Finder search window
set_system_hotkey 28 "false" 51 20 1179648 # Disable Save picture of screen as a file
set_system_hotkey 29 "false" 51 20 1441792 # Disable Copy picture of screen to the clipboard
set_system_hotkey 30 "false" 52 21 1179648 # Disable Save picture of selected area as a file
set_system_hotkey 31 "false" 52 21 1441792 # Disable Copy picture of selected area to the clipboard
set_system_hotkey 184 "false" 53 23 1179648 # Disable Screenshot and recording options

# Set Dock apps
add_dock_app() {
  local app_path="${1}"
  defaults_write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${app_path}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
}

add_dock_app "/System/Applications/Mail.app"
add_dock_app "/Applications/Google Chrome.app"
add_dock_app "/Applications/Figma.app"
add_dock_app "/Applications/Visual Studio Code.app"
add_dock_app "/Applications/Ghostty.app"

# Set wallpaper
wallpaper_image_path="${SCRIPT_DIR}/wallpapers/loupe-mono-dynamic.heic"

if [[ -f "${wallpaper_image_path}" ]]; then
  log --info "Setting wallpaper to ${wallpaper_image_path}"
  escaped_wallpaper_image_path="$(print "${wallpaper_image_path}" | sed 's/"/\\"/g')"
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${escaped_wallpaper_image_path}\"" || log --error "Failed to set wallpaper."
else
  log --error "Wallpaper image not found."
fi

### App settings
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab to the Right" "@t" # Map New Tab to the Right to ⌘T
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab" "\U0000" # Remove shortcut for New Tab
defaults_write com.henrikruscon.Alcove enableBattery -bool false # Disable battery notifications
defaults_write com.henrikruscon.Alcove enableQuickPeek -bool false # Disable now playing preview when media changes
defaults_write com.henrikruscon.Alcove hideMenuBarIcon -bool true # Hide menu bar icon
defaults_write com.henrikruscon.Alcove showOnDisplay -string "builtInDisplay" # Show on built-in display only
defaults_write com.manytricks.Menuwhere "Application Mode" -int 2 # Run in faceless mode
defaults_write com.manytricks.Menuwhere "Stealth Mode" -bool true # Don't show settings on launch
defaults_write com.manytricks.Menuwhere Blacklist -string "Apple,Menuwhere" # Disable menu items for Apple and Menuwhere
defaults_write com.manytricks.Menuwhere SUEnableAutomaticChecks -bool true # Enable automatic updates
defaults_write com.raycast.macos "NSStatusItem Visible raycastIcon" 0 # Hide Menu Bar icon
defaults_write com.raycast.macos raycastGlobalHotkey -string "Command-49"; # Set hotkey to ⌘␣
defaults_write com.sindresorhus.Scratchpad isSyncEnabled -bool true # Enable iCloud sync
defaults_write com.sindresorhus.Scratchpad KeyboardShortcuts_toggleWindow -string '{"carbonModifiers":768,"carbonKeyCode":49}' # Set keyboard shortcut to ⌘⌥␣
defaults_write com.sindresorhus.Scratchpad lineSpacing -string "0.3" # Set line spacing to 0.3
defaults_write com.sindresorhus.Scratchpad linkifyURLs -bool true # Make URLs clickable
defaults_write com.sindresorhus.Scratchpad showCloseButton -bool false # Hide close button
defaults_write com.sindresorhus.Scratchpad showMenuBarIcon -bool false # Hide menu bar icon
defaults_write com.sindresorhus.Scratchpad showOnAllSpaces -bool true # Show on all spaces
defaults_write com.sindresorhus.Scratchpad SS_NSStatusItem_ensureVisibility_shouldNotShowAgain -bool true # Disable warning about menu bar item visibility
defaults_write com.sindresorhus.Scratchpad SS_Tooltip_statusBarButtonWelcomePopover -bool true # Disable menu bar item welcome popover
defaults_write com.sindresorhus.Scratchpad textSize -int 13 # Set font size to 13
defaults_write net.pornel.ImageOptim PngCrush2Enabled -bool true # Enable PNG Crush 2
defaults_write net.pornel.ImageOptim PngOutEnabled -bool false # Disable PNG Out (doesn't work on arm64)
defaults_write org.hammerspoon.Hammerspoon HSUploadCrashData -bool false # Don't send crash data
defaults_write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false # Hide menu bar icon
defaults_write org.hammerspoon.Hammerspoon SUAutomaticallyUpdate -bool true # Enable automatic updates
defaults_write org.hammerspoon.Hammerspoon SUEnableAutomaticChecks -bool true # Enable automatic update checks
defaults_write pl.maketheweb.cleanshotx afterScreenshotActions -array 1 # Copy to clipboard after taking a screenshot
defaults_write pl.maketheweb.cleanshotx afterVideoActions -array 0 # Show Quick Access Overlay after recording
defaults_write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true # Enable Do Not Disturb while recording
defaults_write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads" # Save screenshots/recordings to Downloads folder
defaults_write pl.maketheweb.cleanshotx freezeScreen -bool true # Freeze screen during selection
defaults_write pl.maketheweb.cleanshotx rememberOneOverlayArea -bool false # Do not remember last selection area for recordings
defaults_write pl.maketheweb.cleanshotx screenshotSound -int 3 # Set screenshot capture sound to "Subtle"
defaults_write pl.maketheweb.cleanshotx showMenubarIcon -bool false # Hide menu bar icon

### Finish
log --info "Setup completed."
print
print "If there were no errors, you can remove the temporary setup directory by running:"
print -P "%Brm -rf ${TEMP_DIR}%b"
print
print "Restart your computer for all changes to take effect."
