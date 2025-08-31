#!/bin/zsh

SCRIPT_DIR="${0:A:h}"

# =============================================================================
# Logging and Utility Functions
# =============================================================================

_log() {
  case "$1" in
    "--info")    print "[INFO]    $2" ;;
    "--warning") print "[WARNING] $2" ;;
    "--error")   print "[ERROR]   $2" ;;
    *).          print "[MESSAGE] $@" ;;
  esac
}

_defaults_write() {
  if ! zparseopts -D -E options -- "-sudo"=use_sudo "-currenthost"=use_currenthost; then
    _log --error "Invalid options provided for _defaults_write."
    return 1
  fi

  local -a write_cmd=(${use_sudo:+"sudo "}"defaults""${use_currenthost:+" -currentHost"}"" write" "$@")
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

# =============================================================================
# Install Homebrew, apps, and fonts
# =============================================================================

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

# =============================================================================
# Link dotfiles
# =============================================================================

typeset -A configs=(
  ["bat"]="${HOME}/.config/bat"
  ["eza"]="${HOME}/.config/eza"
  ["fd"]="${HOME}/.config/fd"
  ["ghostty"]="${HOME}/.config/ghostty"
  ["hammerspoon"]="${HOME}/.hammerspoon"
  ["micro"]="${HOME}/.config/micro"
  ["ripgrep"]="${HOME}/.config/ripgrep"
  ["zsh"]="${HOME}/.zsh"
  [".zprofile"]="${HOME}/.zprofile"
  [".zshrc"]="${HOME}/.zshrc"
)

for config in "${(k)configs[@]}"; do
  _log --info "Linking ${config}"

  source_path="${SCRIPT_DIR}/${config}"
  target_path="${configs[${config}]}"

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    mv "${target_path}" "${target_path}.backup"
    _log --info "Backed up existing config at ${target_path} to ${target_path}.backup"
  fi

  mkdir -p "$(dirname "${target_path}")"
  ln -sfh "${source_path}" "${target_path}" || _log --error "Failed to link ${config}"
done

# =============================================================================
# Set up environment
# =============================================================================

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

# =============================================================================
# Write defaults
# =============================================================================

_log --info "Setting defaults..."

# macOS settings
_defaults_write --sudo /Library/Preferences/com.apple.commerce AutoUpdate -bool true # Enable automatic App Store updates
_defaults_write --sudo /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0 # Disable automatic brightness reduction on battery
_defaults_write --sudo /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true # Enable automatic macOS updates
_defaults_write --sudo com.apple.CoreBrightness.plist "CBUser-$(dscl . -read "/Users/$(print "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')/" GeneratedUID | awk -F': ' '{ print $2 }')" -dict-add CBColorAdaptationEnabled -bool false # Disable True Tone
_defaults_write "${HOME}/Library/Group Containers/group.com.apple.notes/Library/Preferences/group.com.apple.notes.plist" kICSettingsNoteDateHeadersTypeKey -integer 1 # Disable group notes by date
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
_defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
_defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false
_defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false
_defaults_write com.apple.finder ShowPathbar -bool true
_defaults_write com.apple.finder ShowRecentTags -bool false
_defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false
_defaults_write com.apple.finder ShowStatusBar -bool true
_defaults_write com.apple.finder WarnOnEmptyTrash -bool false
_defaults_write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular"
_defaults_write com.apple.TextEdit NSFixedPitchFontSize -int 13
_defaults_write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false # Open to a blank document on launch
_defaults_write com.apple.TextEdit RichText -bool false
_defaults_write com.apple.universalaccess closeViewPanningMode -int 0 # Set zoomed image to move continuously with pointer
_defaults_write com.apple.universalaccess closeViewScrollWheelToggle -bool true # Enable zoom with scroll wheel modifier (Control)
_defaults_write com.apple.universalaccess closeViewSmoothImages -bool false # Disable smooth images when zooming
_defaults_write com.apple.universalaccess closeViewZoomScreenShareEnabledKey -bool true # Show zoomed image while screen sharing
_defaults_write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
_defaults_write com.apple.WindowManager EnableTilingByEdgeDrag -bool false # Disable window tiling when dragging to screen edge (can still hold Option to tile)
_defaults_write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false # Disable window tiling when dragging to top edge (can still hold Option to tile)
_defaults_write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" # Set double-click action to maximize window
_defaults_write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false # Disable swipe between pages
_defaults_write NSGlobalDomain AppleKeyboardUIMode -int 2 # Enable full keyboard access for all controls
_defaults_write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true  # Show menu bar in full screen
_defaults_write NSGlobalDomain AppleShowAllExtensions -bool true # Show all file extensions in Finder
_defaults_write NSGlobalDomain AppleShowAllFiles -bool true # Show hidden files in Finder
_defaults_write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling" # Show scroll bars when scrolling
_defaults_write NSGlobalDomain InitialKeyRepeat -int 15 # Decrease delay before key starts repeating
_defaults_write NSGlobalDomain KeyRepeat -int 2 # Increase key repeat rate
_defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false # Disable automatic capitalization of text
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
_add_app_to_dock "/Applications/Xcode.app"
_add_app_to_dock "/Applications/Ghostty.app"

# App settings
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Developer Tools" "\$@i" # Map Developer Tools keyboard shortcut to ⇧⌘I
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Email Link" "\U0000" # Remove keyboard shortcut for Email Link (conflicts with ⇧⌘I)
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab to the Right" "@t" # Map New Tab to the Right keyboard shortcut to ⌘T
_defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New tab" "\U0000" # Remove keyboard shortcut for New Tab (conflicts with ⌘T)
_defaults_write com.lwouis.alt-tab-macos "NSStatusItem Visible Item-0" -int 0 # Hide menu bar icon
_defaults_write com.lwouis.alt-tab-macos appearanceStyle -int 2 # Set appearance to "Titles"
_defaults_write com.lwouis.alt-tab-macos appearanceVisibility -int 1 # Set appearance visibility to "High"
_defaults_write com.lwouis.alt-tab-macos hideAppBadges -bool true
_defaults_write com.lwouis.alt-tab-macos hideSpaceNumberLabels -bool true
_defaults_write com.lwouis.alt-tab-macos hideStatusIcons -bool true
_defaults_write com.lwouis.alt-tab-macos holdShortcut -string $'\U2318' # Set hold key for keyboard shortcut 1 to ⌘
_defaults_write com.lwouis.alt-tab-macos holdShortcut2 -string $'\U2318' # Set hold key for keyboard shortcut 2 to ⌘
_defaults_write com.lwouis.alt-tab-macos windowDisplayDelay -int 0 # Set window display delay to 0 ms
_defaults_write com.raycast.macos "NSStatusItem Visible raycastIcon" -int 0 # Hide menu bar icon
_defaults_write com.raycast.macos raycastGlobalHotkey -string "Command-49" # Set hotkey to ⌘␣
_defaults_write org.hammerspoon.Hammerspoon HSUploadCrashData -bool false # Don't send crash data
_defaults_write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false # Hide menu bar icon
_defaults_write org.hammerspoon.Hammerspoon SUAutomaticallyUpdate -bool true # Enable automatic updates
_defaults_write org.hammerspoon.Hammerspoon SUEnableAutomaticChecks -bool true # Enable automatic update checks
_defaults_write pl.maketheweb.cleanshotx dimScreenWhileRecording -bool false # Do not dim screen while recording
_defaults_write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true # Enable Do Not Disturb while recording
_defaults_write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads" # Save screenshots/recordings to Downloads folder
_defaults_write pl.maketheweb.cleanshotx freezeScreen -bool true # Freeze screen during selection
_defaults_write pl.maketheweb.cleanshotx rememberRecordingArea -bool false # Disable remember last recording area selection
_defaults_write pl.maketheweb.cleanshotx screenshotSound -int 3 # Set screenshot capture sound to "Subtle"
_defaults_write pl.maketheweb.cleanshotx showKeystrokes -bool true # Show keystrokes in recordings
_defaults_write pl.maketheweb.cleanshotx showMenubarIcon -bool false
_defaults_write pl.maketheweb.cleanshotx videoFPS -int 30

# =============================================================================
# The end
# =============================================================================

_log --info "Setup completed."
print "\nRestart your computer for all changes to take effect."
