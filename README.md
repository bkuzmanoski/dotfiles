# macOS dotfiles

This repository contains scripts and configuration files to automate the setup of a new macOS system with my preferred settings and apps.

## Installation

### 1. Install Homebrew and Command Line Tools

Start by installing Homebrew:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install Command Line Tools when prompted.

When installation finishes, run the command to add Homebrew to `.zprofile`.

### 2. Configure Git

Set up Git:

```bash
# Set your name and email
git config --global user.name "Brian Kuzmanoski"
git config --global user.email "[GitHub email address]"

# Generate SSH key
ssh-keygen -t ed25519 -C "[GitHub email address]"

# Start the SSH agent
eval "$(ssh-agent -s)"

# Add your SSH key to the agent
ssh-add ~/.ssh/id_ed25519

# Copy the public key to clipboard
pbcopy < ~/.ssh/id_ed25519.pub
```

Add the SSH key to your GitHub account:

1. Go to GitHub → Settings → SSH and GPG keys
2. Click "New SSH key"
3. Paste the key and save

### 3. Clone this repository

```bash
git clone git@github.com:bkuzmanoski/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

### 4. Run the setup script

```bash
# Make the script executable
chmod +x setup.sh

# Run with verbose logging
./setup.sh -v
```

### 5. Manual configuration steps

#### System

- Complete initial setup including logging into iCloud
- Use `bkuzmanoski` as the username/home folder
- Set Apple Intelligence & Siri keyboard shortcut to FnS
- Never automatically hide and show the Menu Bar
- Set display resolution
- Disable "Automatically adjust brightness"
- In Spotlight preferences, add `~/Pictures` to search privacy exclusions
- "Adopt" apps in App Store → Account

#### Applications

1. **Finder and desktop**

   - Configure Menu Bar layout
   - Configure Notification Centre layout
   - Configure Finder sidebar favorites

2. **Mail**

   - Add any additional accounts as required
   - Configure sidebar favorites

3. **Notes**

   - Disable "Group notes by date"

4. **1Password**

   - Add personal vault
   - Show Quick Access on icon click
   - Clear Show Quick Access shortcut
   - Clear Autofill shortcut
   - Set Compact density
   - Set security settings:
     - Never require password
     - Never auto-lock
     - Disable lock on sleep, screensaver, or switching users
   - Enable Universal Clipboard
   - Enable CLI integration
   - Grant Accessibility permission

5. **CleanShot X**

   - Log in, enter activation key, and set as default screenshot app
   - Set up keyboard shortcuts:
     - Clear All-In-One shortcut
     - Capture Fullscreen: ⇧⌘1
     - Capture Area: ⇧⌘2
     - Annotate Last Screenshot: ⇧⌘3
     - Record Screen / Stop Recording: ⇧⌘5
   - Grant Screen & System Audio Recording permission

6. **Figma**

   - Disable "Rename duplicated layers"
   - Disable "Flip Objects While Resizing"
   - Enable "Invert Zoom Direction"
   - Set big nudge to 8px
   - Disable Menu Bar icon

7. **Ghostty**

   - Grant Accessibility and Full Disk Access permissions

8. **Google Chrome**

   - Set as default browser and decline sending usage and crash statistics
   - Log in and sync profile
   - Disable Ads privacy settings (Ad topics, Site-suggested ads, Ads measurement)
   - Log into Raindrop
   - Grant Screen & System Audio Recording permission

9. **NextDNS**

   - Start at login
   - Set Configuration ID

10. **Raycast**

    - Accept defaults on launch and grant permissions, but don't install any extensions
    - Log in, and enable Cloud Sync
    - Enable Auto Renew Authorization for the 1Password extension
    - Grant Calendar permission

11. **VSCode**

    - Log in and enable Settings Sync

## What's Included

- `setup.sh`: Setup script that installs apps and configures settings
- `Brewfile`: Bundle of applications and tools to be installed via Homebrew
- `.zprofile` and `.zshrc`: Zsh configuration
- `/assets`: Reference screenshots
- `/eza`: eza configuration
- `/ghostty`: Ghostty configuration
- `/micro`: micro configuration
- `/raycast`: Raycast script commands
- `/wallpapers`: Desktop wallpapers
  - `raycast.heic` automatically adapts to light/dark mode
  - Change default in `setup.sh`

## Backups

The setup script creates a backup of macOS defaults before making any changes. Backups for each run are stored in `~/.dotfiles_setup/[timestamp]_backups`.

## Logs

A log for each run is saved to `~/.dotfiles_setup/[timestamp].log`.
