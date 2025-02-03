# macOS dotfiles

This repository contains scripts and configuration files to automate the setup of a new macOS system with my preferred settings and apps.

## What's included

- **/assets**: Reference screenshots
- **/bat**: bat themes
- **/btop**: btop configuration
- **/claude**: Claude and MCP Servers configuration (NB: copy `claude_desktop_config.json.template` → `claude_desktop_config.json` and add keys before running setup)
- **/colima**: colima configuration
- **/eza**: eza theme
- **/ghostty**: Ghostty configuration
- **/micro**: micro configuration
- **/raycast**: Raycast script commands
- **/wallpapers**: Desktop wallpapers (`raycast.heic` automatically adapts to light/dark mode)
- `.zprofile` and `.zshrc`: Zsh configuration
- `Brewfile`: Bundle of applications and tools to be installed via Homebrew
- `setup.sh`: Setup script that installs apps and configures settings

## Installation

### 1. Clone this repository

```zsh
git clone git@github.com:bkuzmanoski/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

### 2. Run the setup script

```zsh
# Make the script executable
chmod +x setup.sh

# Run the script
./setup.sh
```

The setup script can be safely re-run if there are any errors.

#### Backups

The setup script creates a backup of macOS and app defaults before making any changes. Backups for each run are stored in `~/.dotfiles_setup/[timestamp]_backups`.

#### Logs

A log for each run is saved to `~/.dotfiles_setup/[timestamp].log`.

### 3. Manual configuration steps

#### System

- Log in to iCloud
- Set Apple Intelligence & Siri keyboard shortcut to FnS
- Never automatically hide and show the Menu Bar
- Disable automatically adjust brightness
- In Spotlight preferences, add `~/Pictures` to search privacy exclusions
- "Adopt" apps in App Store → Account

#### Applications

1. **Finder and desktop**

   - Configure Menu Bar layout
   - Configure Notification Centre layout
   - Configure Finder sidebar favorites

2. **Mail**

   - Configure sidebar favorites

3. **Notes**

   - Disable group notes by date

4. **1Password**

   - Add personal vault
   - Show Quick Access on icon click
   - Set Quick Access shortcut to ⌃⇧Space
   - Clear Autofill shortcut
   - Set compact density
   - Set security settings:
     - Never require password
     - Never auto-lock
     - Disable lock on sleep, screensaver, or switching users
   - Enable Universal Clipboard
   - Grant Accessibility permission

5. **Alcove**

   - Activate licence and grant permissions

6. **CleanShot X**

   - Log in, enter activation key, and set as default screenshot app
   - Set up keyboard shortcuts:
     - Clear All-In-One shortcut
     - Capture Fullscreen: ⇧⌘1
     - Capture Area: ⇧⌘2
     - Annotate Last Screenshot: ⇧⌘3
     - Record Screen / Stop Recording: ⇧⌘5
   - Grant Screen & System Audio Recording permission

7. **Figma**

   - Disable rename duplicated layers
   - Disable flip objects while resizing
   - Enable invert zoom direction
   - Set big nudge to 8px
   - Disable Menu Bar icon

8. **Ghostty**

   - Grant Accessibility and Full Disk Access permissions

9. **Google Chrome**

   - Set as default browser and decline sending usage and crash statistics
   - Log in and sync profile
   - Disable ads privacy settings (ad topics, site-suggested ads, and ads measurement)
   - Log in to Raindrop
   - Grant Screen & System Audio Recording permission

10. **NextDNS**

    - Start at login
    - Set Configuration ID

11. **Raycast**

    - Accept defaults on launch and grant permissions, but don't install any extensions
    - Grant Calendar permission
    - Log in and enable Cloud Sync

12. **VSCode**

    - Log in and enable settings sync
