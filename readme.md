# macOS dotfiles

This repository contains scripts to automate the setup of a new macOS installation with my preferred settings and apps.

## What's included

- **/bat**: bat themes
- **/eza**: eza theme
- **/fd**: fd configuration
- **/ghostty**: Ghostty configuration
- **/micro**: micro configuration
- **/raycast**: Raycast settings and script commands
- **/reference**: Reference screenshots for things I couldn't automate
- **/ripgrep**: ripgrep configuration
- **/wallpapers**: Desktop wallpapers
- **/zsh**: Zsh plugins and scripts
- `.zprofile` and `.zshrc`: Zsh configuration
- `Brewfile`: Bundle of apps and tools to be installed via Homebrew
- `setup.sh`: Setup script that installs apps and configures settings

Not included: Google Chrome and VS Code configurations (synced via account).

## Installation

1. **Set up git**

   You will be prompted to install Xcode Command Line Tools when you first run `git`.

   ```zsh
   git config --global user.name "Brian Kuzmanoski"
   git config --global user.email "<email address>"

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

3. **Run the setup script**

   Grant Terminal.app Full Disk Access permission. This is necessary to write to some plist files.

   ```zsh
   cd ~/.dotfiles
   ./setup.sh
   ```

   The setup script can be re-run if there are any errors.

## Manual configuration steps

- **macOS**:

  - System settings:
    - Control Centre → Wi-Fi → Select "Don't Show in Menu Bar"
    - Control Centre → Now Playing → Select "Don't Show in Menu Bar"
    - Control Centre → Spotlight → Select "Don't Show in Menu Bar"
    - Displays → Turn off "Automatically adjust brightness"
  - Set up Finder sidebar favorites (see reference screenshot)
  - Mail:
    - Set up Mail sidebar favorites (see reference screenshot)
    - Turn off "Show Mail Categories"
    - Settings → Junk Mail → Turn on "Enable junk mail filtering"
    - Settings → Junk Mail → Set "When junk mail arrives" to "Perform custom actions (Click Advanced to configure)"
    - Settings → Junk Mail → Advanced → _Perform..._ "Move Message to mailbox: Junk" and "Mark as Read"
    - Settings → Viewing → Turn on "Mark all messages as read when opening a conversation"
    - Settings → Composing → Set "Message format" to "Plain Text"
    - Settings → Composing → Set "Undo send delay" to "Off"
    - Settings → Composing → Turn on "Use the same message format as the original message"
  - Set up Menu Bar layout (see reference screenshot)
  - Set up Notification Centre layout (see reference screenshot)

- **1Password**

  - Set "Show Quick Access" shortcut to ⌥⇧␣
  - Clear "Autofill" shortcut
  - Security settings:
    - Set "Confirm my account password" to never
    - Set "Auto-lock" to never
    - Turn off "Lock on sleep, screensaver, or switching users"

- **CleanShot X**

  - General → After capture → Screenshot → Turn off "Show Quick Access Overlay"
  - General → After capture → Screenshot → Turn on "Copy file to clipboard"
  - General → After capture → Recording → Turn off "Show Quick Access Overlay"
  - General → After capture → Recording → Turn on "Copy file to clipboard"
  - General → After capture → Recording → Turn on "Save"
  - Shortcuts → General → Clear "All-In-One" shortcut
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
  - Turn off ads privacy settings (ad topics, site-suggested ads, and ads measurement)
  - Turn off "Make searches and browsing better"
  - Turn off "Show downloads when they're complete"
  - Select "Third-party sign-in" → "Block sign-in prompts from identity services"
  - Set "Google Web" as default search engine

- **NextDNS**

  - Start at login
  - Set Configuration ID
  - Enable

- **Raycast**

  - Import settings file
  - Disable Raycast Focus and other unwanted extensions/commands

- **VS Code**

  - Sync settings and extensions
  - Position Command Center in center
