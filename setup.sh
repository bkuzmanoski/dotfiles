#!/bin/zsh

SCRIPT_DIR="${0:A:h}"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
  case "$1" in
    "--info")    print "[INFO]    $2" ;;
    "--warning") print "[WARNING] $2" ;;
    "--error")   print "[ERROR]   $2" ;;
    *).          print "[MESSAGE] $@" ;;
  esac
}

backup_if_needed() {
  local target_path="$1"
  local backup_path="${target_path}.backup"

  if [[ -e "${target_path}" && ! -L "${target_path}" ]]; then
    mv "${target_path}" "${backup_path}"
    log --info "Backed up existing configuration: ${backup_path}"
  fi
}

defaults_write() {
  zparseopts -D -E \
    -sudo=use_sudo \
    -currenthost=use_currenthost

  local -a write_cmd=(${use_sudo:+"sudo "}"defaults""${use_currenthost:+" -currentHost"}"" write" "$@")

  log --info "Executing: ${write_cmd[*]}"
  ${write_cmd[@]}
}

plutil_replace() {
  log --info "Executing: plutil -replace $*"
  plutil -replace "$@"
}

set_system_hotkey() {
  local key="$1"
  local enabled="$2"
  local parameter1="$3"
  local parameter2="$4"
  local parameter3="$5"

  defaults_write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "${key}" "<dict><key>enabled</key><${enabled}/><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>${parameter1}</integer><integer>${parameter2}</integer><integer>${parameter3}</integer></array></dict></dict>"
}

add_app_to_dock() {
  local app_path="$1"
  defaults_write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${app_path}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
}

# =============================================================================
# Install Homebrew, apps, and fonts
# =============================================================================

if ! which -s brew >/dev/null; then
  log --info "Installing Homebrew..."

  (
    exec 2>&1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  )

  if [[ $? -ne 0 ]]; then
    log --error "Homebrew installation failed, exiting."
    exit 1
  fi

  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

log --info "Installing Homebrew bundle..."

(
  exec 2>&1
  brew bundle --file "${SCRIPT_DIR}/Brewfile"
)

if [[ $? -ne 0 ]]; then
  log --error "Homebrew bundle installation failed, exiting."
  exit 1
fi

# =============================================================================
# Link dotfiles
# =============================================================================

typeset -A configuration_paths=(
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

for configuration_path in "${(k)configuration_paths[@]}"; do
  log --info "Linking: ${configuration_path}"

  typeset source_path="${SCRIPT_DIR}/${configuration_path}"
  typeset target_path="${configuration_paths[${configuration_path}]}"

  if [[ "${configuration_path}" == *\** ]]; then
    if [[ -e "${target_path}" && ! -d "${target_path}" ]]; then
      log --error "Source path contains multiple files but target path is not a directory. Skipping."
      continue
    fi

    typeset expanded_source_path="${SCRIPT_DIR}/${configuration_path}"
    typeset -a source_files=(${~expanded_source_path})

    if [[ ${#source_files[@]} -eq 0 ]]; then
      log --warning "No files found matching pattern: ${configuration_path}"
      continue
    fi

    mkdir -p "${target_path}"

    for source_file_path in "${source_files[@]}"; do
      typeset file_name="$(basename "${source_file_path}")"
      typeset target_file_path="${target_path}/${file_name}"

      backup_if_needed "${target_file_path}"
      ln -sfh "${source_file_path}" "${target_file_path}" 2>/dev/null

      if [[ $? -ne 0 ]]; then
        log --error "Failed to link file: ${source_file_path}"
      fi
    done
  else
    backup_if_needed "${target_path}"
    mkdir -p "$(dirname "${target_path}")" && \
    ln -sfh "${source_path}" "${target_path}" 2>/dev/null

    if [[ $? -ne 0 ]]; then
      log --error "Failed to link: ${configuration_path}"
    fi
  fi
done

# =============================================================================
# Set up environment
# =============================================================================

# Hide "Last login" message in terminal
log --info "Creating ~/.hushlogin"
touch "${HOME}/.hushlogin"

# Enable Touch ID for sudo
if [[ ! -f /etc/pam.d/sudo_local ]]; then
  log --info "Enabling Touch ID for sudo."
  print "auth       sufficient     pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
else
  log --info "Touch ID for sudo already enabled."
fi

# Enable bat to use themes in config directory
log --info "Rebuilding bat cache."
bat cache --build >/dev/null

if [[ $? -ne 0 ]]; then
  log --error "Failed to build bat cache"
fi

# =============================================================================
# Write defaults
# =============================================================================

log --info "Setting defaults..."

# macOS settings
defaults_write --sudo /Library/Preferences/com.apple.commerce AutoUpdate -bool true # Enable automatic App Store updates
defaults_write --sudo /Library/Preferences/com.apple.PowerManagement "Battery Power" -dict-add "ReduceBrightness" -int 0
defaults_write --sudo /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
defaults_write --sudo com.apple.CoreBrightness.plist "CBUser-$(dscl . -read "/Users/$(print "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }')/" GeneratedUID | awk -F': ' '{ print $2 }')" -dict-add CBColorAdaptationEnabled -bool false # Disable True Tone
defaults_write "${HOME}/Library/Group Containers/group.com.apple.notes/Library/Preferences/group.com.apple.notes.plist" kICSettingsNoteDateHeadersTypeKey -integer 1 # Disable group notes by date
defaults_write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 0 # Disable three-finger swipe gesture for switching between full-screen applications
defaults_write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 0 # Disable three-finger swipe gesture for Mission Control and App Exposé
defaults_write com.apple.bird com.apple.clouddocs.unshared.moveOut.suppress -bool true # Suppress warnings when moving files out of iCloud Drive
defaults_write com.apple.dock autohide -bool true # Enable Dock auto-hide
defaults_write com.apple.dock autohide-delay -float 0 # Remove delay before Dock shows
defaults_write com.apple.dock autohide-time-modifier -float 0.15 # Increase Dock show/hide animation speed
defaults_write com.apple.dock expose-group-apps -bool true # Group windows by application in Mission Control
defaults_write com.apple.dock mru-spaces -bool false # Disable automatic rearranging of Spaces based on most recent use
defaults_write com.apple.dock persistent-apps -array # Clear default Dock items
defaults_write com.apple.dock show-recents -bool false
defaults_write com.apple.dock showAppExposeGestureEnabled -bool true # Enable app exposé with multi-finger swipe down
defaults_write com.apple.Dock showhidden -bool true # Make hidden app icons translucent in Dock
defaults_write com.apple.dock wvous-br-corner -int 1 # Disable bottom-right hot corner (default is Quick Note)
defaults_write com.apple.finder _FXSortFoldersFirst -bool true
defaults_write com.apple.finder FXDefaultSearchScope -string "SCcf" # Set default search scope to current folder
defaults_write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults_write com.apple.finder FXPreferredViewStyle -string "Nlsv" # Set default view to list view
defaults_write com.apple.finder NewWindowTarget -string "PfHm" # Open new windows in Home folder
defaults_write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
defaults_write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults_write com.apple.finder ShowMountedServersOnDesktop -bool false
defaults_write com.apple.finder ShowPathbar -bool true
defaults_write com.apple.finder ShowPreviewPane -bool true
defaults_write com.apple.finder ShowRecentTags -bool false
defaults_write com.apple.finder ShowRemovableMediaOnDesktop -bool false
defaults_write com.apple.finder ShowSidebar -bool false
defaults_write com.apple.finder ShowStatusBar -bool true
defaults_write com.apple.finder WarnOnEmptyTrash -bool false
plutil_replace DesktopViewSettings.IconViewSettings.arrangeBy -string "grid" "${HOME}/Library/Preferences/com.apple.finder.plist"
defaults_write com.apple.Spotlight EnabledPreferenceRules -array "System.iphoneApps" # Hide iPhone apps in Spotlight
defaults_write com.apple.TextEdit NSFixedPitchFont -string "JetBrainsMono-Regular"
defaults_write com.apple.TextEdit NSFixedPitchFontSize -int 13
defaults_write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false # Open a blank document on launch
defaults_write com.apple.TextEdit RichText -bool false
defaults_write com.apple.TextInputMenu visible -bool false
defaults_write com.apple.universalaccess closeViewPanningMode -int 1 # Set zoomed image to move when the pointer reaches edge
defaults_write com.apple.universalaccess closeViewScrollWheelToggle -bool true # Enable zoom with scroll wheel modifier (⌃)
defaults_write com.apple.universalaccess closeViewSmoothImages -bool false # Disable smooth images when zooming
defaults_write com.apple.universalaccess closeViewZoomScreenShareEnabledKey -bool true # Show zoomed image while screen sharing
defaults_write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false
defaults_write com.apple.WindowManager EnableTilingByEdgeDrag -bool false # Disable window tiling when dragging to screen edge (can still hold ⌥ to tile)
defaults_write com.apple.WindowManager EnableTopTilingByEdgeDrag -bool false # Disable window tiling when dragging to top edge (can still hold ⌥ to tile)
defaults_write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" # Set title bar double-click action to maximize window
defaults_write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
defaults_write NSGlobalDomain AppleKeyboardUIMode -int 2 # Enable full keyboard access
defaults_write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true
defaults_write NSGlobalDomain ApplePressAndHoldEnabled -bool false # Disable press-and-hold for keys in favor of key repeat
defaults_write NSGlobalDomain AppleShowAllExtensions -bool true
defaults_write NSGlobalDomain AppleShowAllFiles -bool true
defaults_write NSGlobalDomain AppleShowScrollBars -string "WhenScrolling"
defaults_write NSGlobalDomain AppleSpacesSwitchOnActivate -bool false # Do not switch Spaces when switching to an app
defaults_write NSGlobalDomain com.apple.trackpad.forceClick -bool false # Disable Dictionary lookup with force click on Trackpad
defaults_write NSGlobalDomain InitialKeyRepeat -int 15 # Decrease delay before key starts repeating
defaults_write NSGlobalDomain KeyRepeat -int 2 # Increase key repeat rate
defaults_write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults_write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false # Don't add full stop with double space
defaults_write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults_write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
set_system_hotkey 64 "false" 32 49 1048576 # Disable Show Spotlight search
set_system_hotkey 65 "false" 32 49 1572864 # Disable Show Finder search window
set_system_hotkey 28 "false" 51 20 1179648 # Disable Save picture of screen as a file
set_system_hotkey 29 "false" 51 20 1441792 # Disable Copy picture of screen to the clipboard
set_system_hotkey 30 "false" 52 21 1179648 # Disable Save picture of selected area as a file
set_system_hotkey 31 "false" 52 21 1441792 # Disable Copy picture of selected area to the clipboard
set_system_hotkey 184 "false" 53 23 1179648 # Disable Screenshot and recording options
add_app_to_dock "/System/Applications/Mail.app"
add_app_to_dock "/Applications/Google Chrome.app"
add_app_to_dock "/Applications/Figma.app"
add_app_to_dock "/Applications/Visual Studio Code.app"
add_app_to_dock "/Applications/Ghostty.app"

# App settings
defaults_write com.colliderli.iina actionAfterLaunch -int 2
defaults_write com.colliderli.iina controlBarToolbarButtons -array 6 0
defaults_write com.colliderli.iina enableOSD -bool false
defaults_write com.colliderli.iina oscPosition -int 2
defaults_write com.colliderli.iina pauseWhenOpen -bool true
defaults_write com.colliderli.iina quitWhenNoOpenedWindow -bool true
defaults_write com.colliderli.iina screenShotFolder -string "~/Downloads"
defaults_write com.colliderli.iina SUAutomaticallyUpdate -bool true
defaults_write com.colliderli.iina SUEnableAutomaticChecks -bool true
defaults_write com.colliderli.iina themeMaterial -int 4
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Developer Tools" "\$@i" # Map Developer Tools keyboard shortcut to ⇧⌘I
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "Email Link" "\U0000" # Remove keyboard shortcut for Email Link (conflicts with ⇧⌘I)
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New Tab to the Right" "@t" # Map New Tab to the Right keyboard shortcut to ⌘T
defaults_write com.google.Chrome NSUserKeyEquivalents -dict-add "New tab" "\U0000" # Remove keyboard shortcut for New Tab (conflicts with ⌘T)
defaults_write com.lwouis.alt-tab-macos "NSStatusItem Visible Item-0" -int 0
defaults_write com.lwouis.alt-tab-macos appearanceStyle -int 2 # Set appearance to "Titles"
defaults_write com.lwouis.alt-tab-macos appearanceVisibility -int 1 # Set appearance visibility to "High"
defaults_write com.lwouis.alt-tab-macos hideAppBadges -bool true
defaults_write com.lwouis.alt-tab-macos hideSpaceNumberLabels -bool true
defaults_write com.lwouis.alt-tab-macos hideStatusIcons -bool true
defaults_write com.lwouis.alt-tab-macos holdShortcut -string "⌘"
defaults_write com.lwouis.alt-tab-macos holdShortcut2 -string "⌘"
defaults_write com.lwouis.alt-tab-macos windowDisplayDelay -int 0
defaults_write com.raycast.macos "NSStatusItem Visible raycastIcon" -int 0
defaults_write com.raycast.macos raycastGlobalHotkey -string "Command-49" # Set hotkey to ⌘␣
defaults_write com.superultra.Homerow non-search-shortcut -string "⌥⇧Space" # Set Clicking keyboard shortcut to ⌥⇧␣
defaults_write com.superultra.Homerow scroll-shortcut -string "" # Disable Scrolling keyboard shortcut
defaults_write com.superultra.Homerow show-menubar-icon -bool false
defaults_write org.hammerspoon.Hammerspoon HSUploadCrashData -bool false
defaults_write org.hammerspoon.Hammerspoon MJShowMenuIconKey -bool false
defaults_write org.hammerspoon.Hammerspoon SUAutomaticallyUpdate -bool true
defaults_write org.hammerspoon.Hammerspoon SUEnableAutomaticChecks -bool true
defaults_write pl.maketheweb.cleanshotx dimScreenWhileRecording -bool false #
defaults_write pl.maketheweb.cleanshotx doNotDisturbWhileRecording -bool true
defaults_write pl.maketheweb.cleanshotx exportPath -string "${HOME}/Downloads"
defaults_write pl.maketheweb.cleanshotx freezeScreen -bool true
defaults_write pl.maketheweb.cleanshotx keyboardOverlaySize -int 27
defaults_write pl.maketheweb.cleanshotx rememberRecordingArea -bool false
defaults_write pl.maketheweb.cleanshotx screenshotSound -int 3
defaults_write pl.maketheweb.cleanshotx showKeystrokes -bool true
defaults_write pl.maketheweb.cleanshotx showMenubarIcon -bool false
defaults_write pl.maketheweb.cleanshotx videoFPS -int 30

# =============================================================================
# Finalization
# =============================================================================

log --info "Setup completed."
print "\nRestart your computer for all changes to take effect."
