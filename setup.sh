#!/bin/zsh

# --- Script setup ---

# Exit on unhandled errors and unset variables
set -e
set -u

# Get directory where script is located (not necessarily the current working directory)
SCRIPT_DIR="${0:A:h}"

# Setup log directory and logging functions
LOG_FILE="${HOME}/.dotfiles_setup/$(date +%Y%m%d_%H%M%S).log"
LOG_TIMESTAMP_FORMAT="%H:%M:%S"

mkdir -p "$(dirname "${LOG_FILE}")"
touch "${LOG_FILE}"

_log() { print "$(date +"${LOG_TIMESTAMP_FORMAT}"): $1" | tee -a "${LOG_FILE}" }
log() { _log "[INFO]    $1"; }
log_warning() { _log "[WARNING] $1"; }
log_error() { print "$1" >&2 } # Send error messages to stderr

log_stderr() { _log "[ERROR]   $1" >&2 } # Log error to file and keep on stderr
exec 2> >(while read -r line; do log_stderr "${line}"; done)

# Set up backup directory and helper functions
BACKUP_DIR="${HOME}/.dotfiles_setup/$(date +%Y%m%d_%H%M%S)_backups"
mkdir -p "${BACKUP_DIR}"

typeset -A BACKED_UP_DOMAINS

backup_plist() {
  local cmd=(defaults export)
  local use_sudo=false

  if [[ "$1" == "--sudo" ]]; then
    cmd=(sudo defaults export)
    use_sudo=true
    shift
  fi

  local domain="$1"
  local fq_domain="$1${use_sudo:+".sudo"}"

  if [[ -z "${BACKED_UP_DOMAINS[${fq_domain}]:-}" ]]; then
    local backup_path="${BACKUP_DIR}/${fq_domain//\//_}.plist"

    log "Executing: $(printf "%q " "${cmd[@]}")$*"
    ${cmd[@]} "$@" "${backup_path}"

    BACKED_UP_DOMAINS[${fq_domain}]=1
  fi
}

defaults_write() {
  local cmd=(defaults write)
  local use_sudo=false

  if [[ "$1" == "--sudo" ]]; then
    cmd=(sudo defaults write)
    use_sudo=true
    shift
  fi

  # Backup domain
  local domain="$1"
  backup_plist --sudo "${domain}"

  # Run defaults command
  log "Executing: $(printf "%q " "${cmd[@]}")$*"
  ${cmd[@]} "$@"
}

defaults_delete() {
  # Check if key exists before deleting
  if defaults read "$@" &> /dev/null; then
    # Backup domain
    local domain="$1"
    backup_plist "${domain}"

    # Run defaults command
    log "Executing: defaults delete $*"
    defaults delete "$@"
  fi
}

# --- Software Installation ---

# Install Homebrew (if not already installed)
log "Checking Homebrew installation."

if which -s brew > /dev/null; then
  log "Homebrew is already installed."
else
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Wait for Xcode Command Line Tools installation to complete
until xcode-select -p &> /dev/null; do
  log "Waiting for Xcode Command Line Tools installation..."
  sleep 5
done

# Install apps
log "Installing Brewfile bundle."

if [[ -f "${SCRIPT_DIR}/Brewfile" ]]; then
  if ! brew bundle --file="${SCRIPT_DIR}/Brewfile"; then
    log_error "brew bundle failed, exiting."
    exit 1
  fi
else
  log_error "Brewfile not found, exiting."
  exit 1
fi

# --- Settings ---

# Link dotfiles
typeset -A config_links=(
  # Source = Target
  ["bat"]="${HOME}/.config/bat"
  ["colima"]="${HOME}/.colima/default"
  ["eza"]="${HOME}/.config/eza"
  ["ghostty"]="${HOME}/.config/ghostty"
  ["hammerspoon"]="${HOME}/.hammerspoon"
  ["micro"]="${HOME}/.config/micro"
  ["karabiner"]="${HOME}/.config/karabiner"
  ["sketchybar"]="${HOME}/.config/sketchybar"
  [".zprofile"]="${HOME}/.zprofile"
  [".zshrc"]="${HOME}/.zshrc"
  ["claude/claude_desktop_config.json"]="${HOME}/Library/Application Support/Claude/claude_desktop_config.json"
)

run_config_tasks() {
  local config_name="$1"
  case "${config_name}" in
    "bat")
      which -s bat > /dev/null && bat cache --build > /dev/null # Rebuild bat cache so custom themes are available
      ;;
    "claude/claude_desktop_config.json")
      [[ -f "${SCRIPT_DIR}/claude/claude_desktop_config.json" ]] && sed -i '' "s|{{HOME}}|${HOME}|g" "${SCRIPT_DIR}/claude/claude_desktop_config.json"
      [[ -f "${SCRIPT_DIR}/claude/npx_launcher.sh" ]] && chmod +x "${SCRIPT_DIR}/claude/npx_launcher.sh" # Make npx_launcher.sh executable
      ;;
    "sketchybar")
      # Make sketchybar scripts executable
      scripts=(
        # "file" path or "dir/*" path
        "${SCRIPT_DIR}/sketchybar/helpers/*"
        "${SCRIPT_DIR}/sketchybar/plugins/*"
        "${SCRIPT_DIR}/sketchybar/sketchybarrc"
      )

      for script_path in "${scripts[@]}"; do
        for file in "${script_path}"*(N); do
          chmod +x "${file}"
        done
      done

      brew services start sketchybar > /dev/null # Start sketchybar service
      ;;
  esac
}

for config_name in "${(k)config_links[@]}"; do
  source_path="${SCRIPT_DIR}/${config_name}"
  target_path="${config_links[${config_name}]}"

  log "Linking ${config_name}"

  if [[ -e "${source_path}" ]]; then
    # Backup existing file or directory if it exists and is not a symlink
    if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
      relative_path="${target_path#${HOME}/}"
      backup_path="${BACKUP_DIR}/${relative_path}"
      mkdir -p "$(dirname "${backup_path}")"
      mv "${target_path}" "${backup_path}"

      log "Backed up existing ${target_path} to ${backup_path}"
    fi

    # Link configuration files
    mkdir -p "$(dirname "${target_path}")"
    if ln -sfh "${source_path}" "${target_path}"; then
      run_config_tasks "${config_name}"
    else
      log_error "Failed to link ${config_name}. Skipping config tasks."
    fi
  else
    log_error "${config_name} not found in ${SCRIPT_DIR}, skipping."
  fi
done

# Suppress shell login message
touch "${HOME}/.hushlogin"

# Enable Touch ID for sudo
if [[ ! -f /etc/pam.d/sudo_local ]]; then
  log "Enabling Touch ID for sudo."
  print "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local > /dev/null
else
  log_warning "sudo_local already exists, skipping Touch ID for sudo configuration."
fi

# Set wallpaper
wallpaper_image="${SCRIPT_DIR}/wallpapers/loupe-mono-dynamic.heic"

if [[ -f "${wallpaper_image}" ]]; then
  log "Setting wallpaper to ${wallpaper_image}"

  escaped_path="$(print "${wallpaper_image}" | sed 's/"/\\"/g')"
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${escaped_path}\"" || log_error "Failed to set wallpaper."
else
  log_error "Wallpaper file not found."
fi

log "Setting defaults..."

# System and global settings
defaults_write NSGlobalDomain _HIHideMenuBar -bool true # Hide menu bar
defaults_write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" # Set double-click action to zoom/fill window
defaults_write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false # Disable swipe between pages
defaults_write NSGlobalDomain AppleKeyboardUIMode -int 2 # Enable full keyboard access for all controls
defaults_write NSGlobalDomain AppleReduceDesktopTinting -bool true # Disable wallpaper tinting in windows
defaults_write NSGlobalDomain AppleShowAllExtensions -bool true # Show all file extensions in Finder
defaults_write NSGlobalDomain AppleShowAllFiles -bool true # Show hidden files in Finder
defaults_write NSGlobalDomain com.apple.sound.beep.volume -float 0 # Mute alert sounds
defaults_write NSGlobalDomain InitialKeyRepeat -int 15 # Decrease delay before key starts repeating
defaults_write NSGlobalDomain KeyRepeat -int 2 # Increase key repeat rate
defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false # Disable automatic capitalization
defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true # Show expanded save dialog by default
defaults_write NSGlobalDomain NSWindowShouldDragOnGesture -bool true # Click anywhere in window to move it with Control + Command
defaults_write --sudo /Library/Preferences/com.apple.commerce AutoUpdate -bool true # Enable automatic App Store updates
defaults_write --sudo /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0 # Disable automatic brightness reduction on battery
defaults_write --sudo /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true # Enable automatic macOS updates

# Disable "Automatically adjust brightness" in Displays settings
corebrightness_plist_content=$(sudo defaults read com.apple.CoreBrightness.plist)
display_key=$(print "${corebrightness_plist_content}" | jq -r ".DisplayPreferences | to_entries[] | select(.value | has(\"AutoBrightnessEnable\")) | .key" 2> /dev/null)

if [[ -z "${display_key}" ]]; then
  log_warning "No key containing AutoBrightnessEnable found in com.apple.CoreBrightness.plist. Please disable \"Automatically adjust brightness\" manually."
else
  existing_display_values=$(print "${corebrightness_plist_content}" | jq -r --arg key "${display_key}" '.DisplayPreferences."\( $key )"')

  if [[ -n "${existing_display_values}" ]]; then
    updated_display_values=$(print "${existing_display_values}" | jq ".AutoBrightnessEnable = 0")
    defaults_write --sudo com.apple.CoreBrightness.plist DisplayPreferences -dict "${display_key}" "${updated_display_values}"
  else
    log_warning "Could not retrieve values for key \"${display_key}\" in com.apple.CoreBrightness.plist. Please disable \"Automatically adjust brightness\" manually."
  fi
fi

# Disable "True Tone" in Displays settings
current_user=$(print "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')
user_id=$(dscl . -read "/Users/${current_user}/" GeneratedUID | awk -F': ' '{print $2}')

defaults_write --sudo com.apple.CoreBrightness.plist "CBUser-${user_id}" -dict-add CBColorAdaptationEnabled -bool false

# Set system hotkeys
set_system_hotkey() {
  local key="$1"
  local enabled="$2"
  local p1="$3" p2="$4" p3="$5"

  defaults_write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "${key}" "<dict><key>enabled</key><${enabled}/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>${p1}</integer><integer>${p2}</integer><integer>${p3}</integer></array></dict></dict>"
}

# Default params for disabled hotkeys included below so they can be toggled on/off in System Settings without needing to re-set the keybinding
set_system_hotkey 64 "false" 32 49 1048576 # Disable Show Spotlight search
set_system_hotkey 65 "false" 32 49 1572864 # Disable Show Finder search window
set_system_hotkey 28 "false" 51 20 1179648 # Disable Save picture of screen as a file
set_system_hotkey 29 "false" 51 20 1441792 # Disable Copy picture of screen to the clipboard
set_system_hotkey 30 "false" 52 21 1179648 # Disable Save picture of selected area as a file
set_system_hotkey 31 "false" 52 21 1441792 # Disable Copy picture of selected area to the clipboard
set_system_hotkey 184 "false" 53 23 1179648 # Disable Screenshot and recording options

# Universal Access
defaults_write com.apple.universalaccess closeViewScrollWheelToggle -bool true # Enable zoom with scroll wheel modifier (Control)
defaults_write com.apple.universalaccess closeViewSmoothImages -bool false # Disable smooth images when zooming

# Trackpad
defaults_write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 2 # Decrease click sensitivity/increase haptic feedback strength
defaults_write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 2 # Decrease click sensitivity/increase haptic feedback strength

# Window Manager
defaults_write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false # Disable click to show desktop
defaults_write com.apple.WindowManager EnableTilingByEdgeDrag -bool false # Disable window tiling when dragging to screen edge (can still hold Option to tile)
defaults_write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false # Disable window tiling when dragging to top edge (can still hold Option to tile)

# Menu Bar icons
defaults_write com.apple.controlcenter "NSStatusItem Visible NowPlaying" -int 0 # Hide Now Playing icon in Menu Bar
defaults_write com.apple.controlcenter "NSStatusItem Visible WiFi" -int 0 # Hide Wi-Fi icon in Menu Bar
defaults_write com.apple.controlcenter "NSStatusItem Visible Display" -int 0 # Hide Display icon in Menu Bar
defaults_write com.apple.Siri StatusMenuVisible -bool false # Hide Siri icon in Menu Bar
defaults_delete com.apple.Spotlight "NSStatusItem Visible Item-0" # Hide Spotlight icon in Menu Bar

# Dock
defaults_write com.apple.dock autohide -bool true # Enable Dock auto-hide
defaults_write com.apple.dock autohide-delay -float 0 # Remove delay before Dock shows
defaults_write com.apple.dock autohide-time-modifier -float 0.15 # Increase Dock show/hide animation speed
defaults_write com.apple.dock mru-spaces -bool false # Disable automatic rearranging of Spaces based on most recent use
defaults_write com.apple.dock show-recents -bool false # Hide recent applications in Dock
defaults_write com.apple.dock wvous-br-corner -int 1 # Disable bottom-right hot corner (default is Quick Note)
defaults_write com.apple.dock persistent-apps -array # Clear existing Dock items

add_dock_app() {
  local app_path="$1"
  defaults_write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${app_path}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
}

add_dock_app "/System/Applications/Mail.app"
add_dock_app "/Applications/Google Chrome.app"
add_dock_app "/Applications/Figma.app"
add_dock_app "/Applications/Visual Studio Code.app"
add_dock_app "/Applications/Ghostty.app"

# Finder
defaults_write com.apple.bird com.apple.clouddocs.unshared.moveOut.suppress -bool true # Suppress warnings when moving files out of iCloud Drive
defaults_write com.apple.finder _FXSortFoldersFirst -bool true # Sort folders first
defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf" # Set default search scope to current folder
defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false # Disable warning when changing file extensions
defaults_write com.apple.finder FXPreferredViewStyle -string "Nlsv" # Set default view to list view
defaults_write com.apple.finder NewWindowTarget -string "PfHm" # Open new windows in Home folder
defaults_write com.apple.finder ShowPathbar -bool true # Show path bar
defaults_write com.apple.finder ShowRecentTags -bool false # Hide recent tags
defaults_write com.apple.finder ShowStatusBar -bool true # Show status bar
defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false # Hide external drives on Desktop
defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false # Hide internal drives on Desktop
defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false # Hide servers on Desktop
defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false # Hide removable media on Desktop
defaults_write com.apple.finder WarnOnEmptyTrash -bool false # Disable warning when emptying Trash

# Mail
defaults_write com.apple.mail AutoReplyFormat -int 1 # Set reply format to same as original message
defaults_write com.apple.mail ConversationViewMarkAllAsRead -int 1 # Mark all messages as read when opening a conversation
defaults_write com.apple.mail SendFormat -string "Plain" # Set default message format to plain text
defaults_write com.apple.mail SwipeAction -int 1 # Set default action to "Archive" instead of "Delete"

# Notes
defaults_write "${HOME}/Library/Group Containers/group.com.apple.notes/Library/Preferences/group.com.apple.notes.plist" kICSettingsNoteDateHeadersTypeKey -integer 1 # Disable group notes by date

# TextEdit
defaults_write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular" # Set plain text font to JetBrains Mono
defaults_write com.apple.TextEdit NSFixedPitchFontSize -int 13 # Set plain text font size to 13
defaults_write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false # Open to a blank document on launch
defaults_write com.apple.TextEdit RichText -bool false # Use plain text by default

# Alcove
defaults_write com.henrikruscon.Alcove enableHaptics -bool false # Disable haptic feedback
defaults_write com.henrikruscon.Alcove enableQuickPeek -bool false # Disable now playing preview when media changes
defaults_write com.henrikruscon.Alcove hideMenuBarIcon -bool true # Hide menu bar icon
defaults_write com.henrikruscon.Alcove launchAtLogin -bool true # Launch at login
defaults_write com.henrikruscon.Alcove lowBatteryThreshold -int 10 # Set low battery threshold to 10%
defaults_write com.henrikruscon.Alcove showOnDisplay -string "builtInDisplay" # Always show on built-in display
defaults_write com.henrikruscon.Alcove warnOnLowBattery -bool false # Disable low battery warning

# AltTab
defaults_write com.lwouis.alt-tab-macos appearanceSize -int 1 # Set appearance size to "Medium"
defaults_write com.lwouis.alt-tab-macos appearanceVisibility -int 1 # Set appearance visibility to "High"
defaults_write com.lwouis.alt-tab-macos hideSpaceNumberLabels -bool true # Hide space number labels
defaults_write com.lwouis.alt-tab-macos hideStatusIcons -bool true # Hide window status icons
defaults_write com.lwouis.alt-tab-macos holdShortcut -string "\\U2318" # Set hold key for shortcut 1 to "Command"
defaults_write com.lwouis.alt-tab-macos holdShortcut2 -string "\\U2318" # Set hold key for shortcut 2 to "Command"
defaults_write com.lwouis.alt-tab-macos menubarIconShown -bool false # Hide menu bar icon
defaults_write com.lwouis.alt-tab-macos mouseHoverEnabled -bool true # Enable mouse hover
defaults_write com.lwouis.alt-tab-macos showOnScreen -string "builtInDisplay" # Show on built in display only
defaults_write com.lwouis.alt-tab-macos windowDisplayDelay -int 0 # Set window display delay to 0 ms
defaults_write com.lwouis.alt-tab-macos updatePolicy -int 2 # Install updates automatically

# CleanShot X
defaults_write pl.maketheweb.cleanshotx afterVideoActions -array 0 # Show Quick Access Overlay after recording
defaults_write pl.maketheweb.cleanshotx afterScreenshotActions -array 1 # Copy to clipboard after taking a screenshot
defaults_write pl.maketheweb.cleanshotx allowURLSchemesAPI -string "55e857c66268b59047535d6f427d1ee8" # Allow applications to control CleanShot X (for Raycast integration)
defaults_write pl.maketheweb.cleanshotx crosshairMode -int 2 # Always enable crosshair mode for selection
defaults_write pl.maketheweb.cleanshotx cursorHighlightStyle -int 1 # Set cursor highlight style to "Filled"
defaults_write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true # Enable Do Not Disturb while recording
defaults_write pl.maketheweb.cleanshotx downscaleRetinaVideos -bool true # Downscale videos to 1x
defaults_write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads" # Save screenshots/recordings to Downloads folder
defaults_write pl.maketheweb.cleanshotx freezeScreen -bool true # Freeze screen during selection
defaults_write pl.maketheweb.cleanshotx highlightClicks -bool true # Highlight mouse clicks in recordings
defaults_write pl.maketheweb.cleanshotx keyboardOverlayStyle -int 1 # Set keyboard overlay style to "Light"
defaults_write pl.maketheweb.cleanshotx mergeAudioTracks -bool false # Keep audio tracks separate in recordings
defaults_write pl.maketheweb.cleanshotx recordComputerAudio -bool true # Record computer audio in recordings
defaults_write pl.maketheweb.cleanshotx rememberOneOverlayArea -bool false # Do not remember last selection area for recordings
defaults_write pl.maketheweb.cleanshotx screenshotSound -int 3 # Set screenshot capture sound to "Subtle"
defaults_write pl.maketheweb.cleanshotx showKeystrokes -bool true # Show keystrokes in recordings
defaults_write pl.maketheweb.cleanshotx showMenubarIcon -bool false # Hide Menu Bar icon
defaults_write pl.maketheweb.cleanshotx videoFPS -int 30 # Set video recording FPS to 30

log "Configuring CleanShot X login item." # Run CleanShot X on login
osascript -e "tell application \"System Events\" to make login item at end with properties { path:\"/Applications/CleanShot X.app\", hidden:true }" > /dev/null || log_error "Failed to configure CleanShot X login item."

# ImageOptim
defaults_write net.pornel.ImageOptim PngCrush2Enabled -bool true # Enable PNG Crush 2
defaults_write net.pornel.ImageOptim PngOutEnabled -bool false # Disable PNG Out (doesn't work on arm64)

# Google Chrome
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab to the Right" "@t" # Re-map New Tab to the Right to ⌘T
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab" "~\$@t" # Re-map New Tab to ⌥⇧⌘T
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Bookmark This Tab…" "\$@d" # Re-map Bookmark This Tab… to ⇧⌘D
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Bookmark All Tabs…" "~\$@d" # Re-map Bookmark All Tabs… to ⌥⇧⌘D

# Hammerspoon
defaults write org.hammerspoon.Hammerspoon HSUploadCrashData -bool false # Don't send crash data
defaults write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false # Hide menu bar icon
defaults write org.hammerspoon.Hammerspoon SUAutomaticallyUpdate -bool true # Enable automatic updates
defaults write org.hammerspoon.Hammerspoon SUEnableAutomaticChecks -bool true # Enable automatic update checks

log "Configuring Hammerspoon login item." # Run Hammerspoon on login
osascript -e "tell application \"System Events\" to make login item at end with properties { path:\"/Applications/Hammerspoon.app\", hidden:true }" > /dev/null || log_error "Failed to configure Hammerspoon login item."

# Menuwhere
defaults_write com.manytricks.Menuwhere "Application Mode" -int 2 # Run in faceless mode
defaults_write com.manytricks.Menuwhere "Stealth Mode" -bool true # Don't show settings on launch
defaults_write com.manytricks.Menuwhere Blacklist -string "Apple,Menuwhere" # Disable menu items for Apple and Menuwhere
defaults_write com.manytricks.Menuwhere SUEnableAutomaticChecks -bool true # Enable automatic updates

log "Configuring Menuwhere login item." # Run Menuwhere on login
osascript -e "tell application \"System Events\" to make login item at end with properties { path:\"/Applications/Menuwhere.app\", hidden:true }" > /dev/null || log_error "Failed to configure Menuwhere login item."

# Raycast
defaults_write com.raycast.macos "NSStatusItem Visible raycastIcon" 0 # Hide Menu Bar icon
defaults_write com.raycast.macos raycast_hyperKey_state -dict allowShortCapsLockPresses 0 enabled 1 keyCode 57 # Set Hyper Key to Caps Lock

log "Setup completed."
print
print "Restart your computer for all changes to take effect."
