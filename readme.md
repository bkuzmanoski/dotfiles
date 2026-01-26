# macOS dotfiles

Scripts to automate the setup of a new macOS installation with my preferred settings and apps.

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

   Grant Terminal.app Full Disk Access permission (required to write to some plist files).

   ```zsh
   cd ~/.dotfiles
   ./setup.sh
   ```

   The setup script can be re-run if there are any errors.

## Manual steps

- **System Settings**

  - Menu Bar → Turn off "Wi-Fi"
  - Menu Bar → Turn off "Now Playing"
  - Menu Bar → Turn off "Spotlight"
  - Displays → Turn off "Automatically adjust brightness"
  - Notifications → Turn off "Allow notifications from iPhone"
  - Keyboard → Keyboard Shortcuts → Mission Control → Click on "Restore Defaults"
  - Set up Menu Bar, Control Center, and Notification Center layout (see reference screenshots)

- **App Settings**

  - 1Password
    - Set "Show Quick Access" shortcut to ⌃⇧␣
    - Clear "Autofill" shortcut
    - Security settings:
      - Set "Confirm my account password" to never
      - Set "Auto-lock" to never
      - Turn off "Lock on sleep, screensaver, or switching users"
    - Developer settings:
      - Turn on "Show 1Password Developer dxperience"
      - Turn on "Integrate with 1Password CLI"

  - CleanShot X
    - Complete onboarding
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

  - Figma
    - Turn off "Show Figma in Menu Bar"
    - Turn off "Rename duplicated layers"
    - Turn off "Flip objects while resizing"
    - Set "Big nudge" to 8px

  - Folder Preview
    - Turn on "Launch at login"
    - Enable Extensions

  - Hammerspoon
    - Turn on "Launch Hammerspoon at login"

  - Homerow
    - Turn on "Launch on login"

  - Ghostty
    - Grant Full Disk Access permission

  - Google Chrome
    - Grant Screen & System Audio Recording permission
    - Turn off ads privacy settings (ad topics, site-suggested ads, and ads measurement)
    - Turn off "Make searches and browsing better"
    - Turn off "Show downloads when they're complete"
    - Select "Third-party sign-in" → "Block sign-in prompts from identity services"
    - Set "Google Web" as default search engine
    - Enable `chrome://flags/#tabstrip-combo-button`

  - IINA
    - Utilities → Select "Set IINA as the Default Application…"

  - Mail
    - Set up Mail sidebar favorites: "All Inboxes", "All Sent", "All Archive"
    - Turn off "Show Mail Categories"
    - Settings → Junk Mail → Turn on "Enable junk mail filtering"
    - Settings → Junk Mail → Set "When junk mail arrives" to "Perform custom actions (Click Advanced to configure)"
    - Settings → Junk Mail → Advanced → Perform the following actions → Add "Mark as Read"

  - Raycast
    - Complete onboarding
    - Import settings file
    - Disable unused extensions/commands

  - VS Code
    - Sync settings and extensions
    - Position Command Center in center of window

  - Xcode
    - Install [Additional Tools for Xcode](https://developer.apple.com/download/all/?q=additional%20tools)
