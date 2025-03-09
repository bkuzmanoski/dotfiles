# macOS dotfiles

This repository contains scripts to automate the setup of a new macOS installation with my preferred settings and apps.

## What's included

- **/bat**: bat themes
- **/eza**: eza theme
- **/fd**: fd configuration
- **/ghostty**: Ghostty configuration
- **/hammerspoon**: Hammerspoon configuration
- **/micro**: micro configuration
- **/raycast**: Raycast settings and script commands
- **/reference**: Reference screenshots for things I couldn't automate
- **/sketchybar**: Sketchybar configuration
- **/wallpapers**: Desktop wallpapers (`*-dynamic.heic` wallpapers adapt to light/dark mode)
- **/zsh**: Zsh plugins and scripts
- `.zprofile` and `.zshrc`: Zsh configuration
- `Brewfile`: Bundle of applications and tools to be installed via Homebrew
- `setup.sh`: Setup script that installs apps and configures settings

Not included: Google Chrome and VS Code configurations (synced via account).

## Installation

1. **Set up git**

   ```zsh
   # Generate a new SSH key and add it to ssh-agent
   ssh-keygen -t ed25519 -C "<email address>"
   ssh-add ~/.ssh/id_ed25519

   # Copy the key to the clipboard
   pbcopy < ~/.ssh/id_ed25519.pub
   ```

   Associate the SSH key on your clipboard with your Github account in [Github Settings](https://github.com/settings/keys).

2. **Clone this repository**

   ```zsh
   git clone https://github.com/bkuzmanoski/dotfiles ~/.dotfiles
   ```

   You will be prompted to install Xcode Command Line Tools when you first run `git`.

3. **Run the setup script**

   Grant Terminal.app Full Disk Access permission. This is necessary to write to some plist files.

   ```zsh
   cd ~/.dotfiles
   ./setup.sh
   ```

   A log for each run is saved to `~/.dotfiles_setup/[timestamp].log`.

   The setup script also creates a backup of macOS and app defaults before making any changes. Backups for each run are stored in `~/.dotfiles_setup/[timestamp]_backups`.

   The setup script can be re-run if there are any errors. The log and backups can be deleted after successful setup.

## Manual configuration steps

- **macOS**:

  - Onboarding:
    - Don't transfer any information using Migration Assistant
    - Don't set up Screen Time
    - Sign in to iCloud
    - Enable Location Services
    - Turn off "Share Mac Analytics with Apple"
    - Don't set up Siri
    - Set system appearance to Auto
  - System settings:
    - Turn off Apple Intelligence
    - Control Centre → Wi-Fi → Select "Don't Show in Menu Bar"
    - Control Centre → Now Playing → Select "Don't Show in Menu Bar"
    - Control Centre → Spotlight → Select "Don't Show in Menu Bar"
    - Displays → Turn off "Automatically adjust brightness"
    - Keyboard → Keyboard Shortcuts -> Mission Control -> Click on "Restore Defaults"
  - Set up Finder sidebar favorites (see reference screenshot)
  - Mail:
    - Set up Mail sidebar favorites (see reference screenshot)
    - Settings → Viewing → Turn on "Mark all messages as read when opening a conversation"
    - Settings → Composing → Set Message Format to "Plain Text"
    - Settings → Composing → Turn on "Use the same message format as the original message"
  - Set up Menu Bar layout (see reference screenshot)
  - Set up Notification Centre layout (see reference screenshot)
  - Turn off "Reopen windows when logging back in" when restarting

- **1Password**

  - Sign in
  - Set "Show Quick Access" shortcut to ⌥⇧␣
  - Clear "Autofill" shortcut
  - Security settings:
    - Set "Confirm my account password" to never
    - Set "Auto-lock" to never
    - Turn off "Lock on sleep, screensaver, or switching users"

- **Alcove**

  - Activate license
  - Launch at login

- **AltTab**

  - Grant Accessibility and Screen & System Audio Recording permissions

- **CleanShot X**

  - Grant Screen & System Audio Recording permission
  - Onboarding:
    - Log in
    - Enter activation key
    - Set as default screenshot tool
    - Do not share usage statistics
  - General → After capture → Screenshot → Turn off "Show Quick Access Overlay"
  - General → After capture → Screenshot → Turn on "Copy file to clipboard"
  - Shortcuts → Set "All-In-One" shortcut to ⇧⌘5
  - Shortcuts → Set "Open Capture History" shortcut to ⇧⌘6
  - Shortcuts → Set "Capture Area" shortcut to ⇧⌘2
  - Shortcuts → Set "Capture Fullscreen" shortcut to ⇧⌘1
  - Shortcuts → Set "Capture Text" shortcut to ⇧⌘4
  - Shortcuts → Set "Annotate Last Screenshot" shortcut to ⇧⌘3

- **Figma**

  - Turn off "Show Figma in Menu Bar"
  - Turn off "Rename duplicated layers"
  - Turn off "Flip objects while resizing"
  - Turn on "Invert zoom direction"
  - Set "Big nudge" to 8px

- **Ghostty**

  - Grant Full Disk Access permission

- **Google Chrome**

  - Grant Screen & System Audio Recording permission
  - Set as default browser and decline sending usage and crash statistics
  - Log in and sync profile
  - Turn off ads privacy settings (ad topics, site-suggested ads, and ads measurement)
  - Turn off "Make searches and browsing better"
  - Turn off "Show downloads when they're complete"
  - Select "Block sign-in prompts from identity services"
  - Log in to Raindrop
  - Set uBlock Origin Lite filtering mode to "Optimal"

- **Hammerspoon**

  - Grant Accessibility permission
  - Launch Hammerspoon at login

- **Menuwhere**

  - Grant Accessibility permission
  - Activate license
  - Launch automatically on login
  - Set "Pop up frontmost app menu with hot key" to ✦m

- **NextDNS**

  - Start at login
  - Set Configuration ID
  - Enable

- **Raycast**

  - Don't install extensions during onboarding
  - Import settings file
  - Disable Raycast AI, Raycast Focus, and Raycast Notes extensions

- **Scratchpad**

  - Launch at login
  - Set Font to "JetBrains Mono Regular Light"

- **Sketchybar**

  - Grant Accessibility permission

- **VS Code**

  - Log in and enable settings sync
  - Re-set "chat.commandCenter.enabled" to `false`
