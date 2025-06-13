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
- **/ripgrep**: ripgrep configuration
- **/wallpapers**: Desktop wallpaper
- **/zsh**: Zsh plugins and scripts
- `.zprofile` and `.zshrc`: Zsh configuration
- `Brewfile`: Bundle of apps and tools to be installed via Homebrew
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
    - Keyboard → Keyboard Shortcuts → Mission Control → Click on "Restore Defaults"
    - Keyboard → Keyboard Shortcuts → Services → Text → Turn off "Convert Text to Simplified Chinese"
  - Set up Finder sidebar favorites (see reference screenshot)
  - Mail:
    - Set up Mail sidebar favorites (see reference screenshot)
    - Turn off "Show Mail Categories"
    - Settings → Junk Mail → Turn on "Enable junk mail filtering"
    - Settings → Junk Mail → Set "When junk mail arrives" to "Perform custom actions (Click Advanced to configure)"
    - Settings → Junk Mail → Advanced → _If..._ "Message is junk mail" _Perform..._ "Move Message to mailbox: Junk" and "Mark as Read"
    - Settings → Viewing → Turn on "Mark all messages as read when opening a conversation"
    - Settings → Composing → Set "Message format" to "Plain Text"
    - Settings → Composing → Set "Undo send delay" to "Off"
    - Settings → Composing → Turn on "Use the same message format as the original message"
  - Set up Menu Bar layout (see reference screenshot)
  - Set up Notification Centre layout (see reference screenshot)
  - Turn off "Reopen windows when logging back in" when restarting
  - Create five spaces on primary screen

- **1Password**

  - Sign in
  - Set "Show Quick Access" shortcut to ⌥⇧␣
  - Clear "Autofill" shortcut
  - Security settings:
    - Set "Confirm my account password" to never
    - Set "Auto-lock" to never
    - Turn off "Lock on sleep, screensaver, or switching users"

- **AltTab**

  - Grant Accessibility permission
  - Turn off "Menubar icon"
  - Turn on "Hide app badges"
  - Turn on "Hide status icons"
  - Turn on "Hide Space number labels"

- **CleanShot X**

  - Grant Accessibility and Screen & System Audio Recording permissions
  - Onboarding:
    - Log in
    - Enter activation key
    - Set as default screenshot tool
    - Do not share usage statistics
  - General → After capture → Screenshot → Turn off "Show Quick Access Overlay"
  - General → After capture → Screenshot → Turn on "Copy file to clipboard"
  - General → After capture → Recording → Turn off "Show Quick Access Overlay"
  - General → After capture → Recording → Turn on "Copy file to clipboard"
  - General → After capture → Recording → Turn on "Save"
  - Shortcuts → General → Set "Open Capture History" shortcut to ⇧⌘6
  - Shortcuts → Screenshots → Set "Capture Area" shortcut to ⇧⌘2
  - Shortcuts → Screenshots → Set "Capture Fullscreen" shortcut to ⇧⌘1
  - Shortcuts → Screen Recording → Set "Record Screen / Stop Recording" shortcut to ⇧⌘5
  - Shortcuts → OCR → Set "Capture Text" shortcut to ⇧⌘4
  - Shortcuts → Annotate → Set "Annotate Last Screenshot" shortcut to ⇧⌘3
  - Shortcuts → Annotate → Clear "Save" shortcut
  - Shortcuts → Annotate → Set "Save as" shortcut to ⌘S

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
  - Turn off "Show Bookmarks Bar"
  - Turn on "Allow JavaScript from Apple Events"
  - Log in to Raindrop
  - Set uBlock Origin Lite filtering mode to "Optimal"

- **Hammerspoon**

  - Grant Accessibility permission
  - Launch Hammerspoon at login

- **NextDNS**

  - Start at login
  - Set Configuration ID
  - Enable

- **Pixelmator Pro**

  - Set initial workspace layout to "Illustration"
  - Create a new workspace layout ("Custom") and relocate Tools to the bottom

- **Pure Paste**

  - Grant Accessibility permission
  - Launch at login

- **Raycast**

  - Don't install extensions during onboarding
  - Import settings file
  - Disable Raycast AI, Raycast Focus, and Raycast Notes extensions

- **VS Code**

  - Log in and enable settings sync
  - Position Command Center in center
  - Set "chat.commandCenter.enabled" to "false"
