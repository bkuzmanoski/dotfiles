# macOS dotfiles

This repository contains scripts and configuration files to automate the setup of a new macOS system with my preferred settings and apps.

## What's included

- **/bat**: bat themes
- **/claude**: Claude and MCP Servers configuration
- **/colima**: colima configuration
- **/eza**: eza theme
- **/ghostty**: Ghostty configuration
- **/micro**: micro configuration
- **/raycast**: Raycast script commands
- **/reference**: Reference screenshots for things I couldn't automate
- **/sketchybar**: Sketchybar configuration
- **/wallpapers**: Desktop wallpapers (`raycast.heic` automatically adapts to light/dark mode)
- `.zprofile` and `.zshrc`: Zsh configuration
- `Brewfile`: Bundle of applications and tools to be installed via Homebrew
- `setup.sh`: Setup script that installs apps and configures settings

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
   git clone git@github.com:bkuzmanoski/dotfiles.git ~/.dotfiles
   cd ~/.dotfiles
   ```

   You will be prompted to install Xcode Command Line Tools when you first run `git`.

3. **Grant Terminal.app Full Disk Access permission**

4. **Create Claude MCP config file**

   ```zsh
   cp ~/.dotfiles/claude/claude_desktop_config.json.template ~/.dotfiles/claude/claude_desktop_config.json
   ```

   Add your keys to this file prior to running Claude.app.

5. **Run the setup script**

   ```zsh
   # Make the script executable
   chmod +x setup.sh

   # Run the script
   ./setup.sh
   ```

   A log for each run is saved to `~/.dotfiles_setup/[timestamp].log`.

   The setup script also creates a backup of macOS and app defaults before making any changes. Backups for each run are stored in `~/.dotfiles_setup/[timestamp]_backups`.

   The setup script can be re-run if there are any errors. The log and backups can be deleted after a successful installation.

## Manual configuration steps

- **System**:

  - "Adopt" apps in App Store → Account
  - Set Apple Intelligence & Siri keyboard shortcut to FnS
  - In Spotlight settings, add `~/Pictures` to search privacy exclusions
  - In Keyboard settings, disable the "Convert Text to Simplified Chinese" keyboard shortcut under Services
  - Configure Menu Bar layout (see reference screenshot)
  - Configure Notification Centre layout (see reference screenshot)
  - Configure Finder sidebar favorites (see reference screenshot)
  - Configure Mail sidebar favorites (see reference screenshot)

3. **1Password**

   - Grant Accessibility permission
   - Add personal vault
   - Show Quick Access on icon click
   - Clear Quick Access and Autofill shortcuts
   - Set compact density
   - Set security settings:
     - Never require password
     - Never auto-lock
     - Disable lock on sleep, screensaver, or switching users
   - Enable Integrate with 1Password CLI
   - Enable Universal Clipboard

4. **Alcove**

   - Activate licence

5. **CleanShot X**

   - Log in, enter activation key, and set as default screenshot app
   - Clear All-In-One, Capture Area, and Capture Fullscreen shortcuts
   - Set Annotate Last Screenshot shortcut to ♦︎3

6. **Figma**

   - Disable rename duplicated layers
   - Disable flip objects while resizing
   - Enable invert zoom direction
   - Set big nudge to 8px
   - Disable Menu Bar icon

7. **Ghostty**

   - Grant Accessibility and Full Disk Access permissions

8. **Google Chrome**

   - Grant Screen & System Audio Recording permission
   - Set as default browser and decline sending usage and crash statistics
   - Disable ads privacy settings (ad topics, site-suggested ads, and ads measurement)
   - Disable "Make searches and browsing better"
   - Log in and sync profile
   - Log in to Raindrop

9. **Menuwhere**

   - Activate licence and grant Accessibility permission

10. **NextDNS**

    - Start at login
    - Set Configuration ID

11. **Raycast**

    - Accept defaults on launch and grant permissions, but don't install any extensions
    - Log in and enable Cloud Sync

12. **VSCode**

    - Log in and enable settings sync
