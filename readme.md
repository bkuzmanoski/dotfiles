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

- **macOS**

  - System Settings
    - Menu Bar → Turn off "Wi-Fi"
    - Menu Bar → Turn off "Now Playing"
    - Menu Bar → Turn off "Spotlight"
    - Displays → Turn off "Automatically adjust brightness"
    - Notifications → Turn off "Allow notifications from iPhone"
    - Keyboard → Keyboard Shortcuts → Mission Control → Click on "Restore Defaults"
  - Set up Menu Bar, Control Center, and Notification Center layouts (see reference screenshots)
  - Set up Finder favorites (see reference screenshot)

- **Apps**

  - 1Password
    - Settings
      - General
        - Set "Save new items in" to "Personal"
        - Set "Show Quick Access" shortcut to ⌃⇧␣
        - Clear "Autofill" shortcut
      - Appearance → Set "Density" to "Compact"
      - Security
        - Set "App unlock preset" to "Convenient"
        - Turn on "Use Universal Clipboard to copy to other devices"
      - Developer
        - Turn on "Show 1Password Developer experience"
        - Turn on "Integrate with 1Password CLI"

  - Affinity
    - Set up studios: "Pixel", "Colour Grading", "Retouching"
    - Settings
      - General → Document → Turn off "Reopen document(s) on startup"
      - Machine Learning Models -> Segmentation -> Install
      - Home Screen → Turn off all options

  - AltTab
    - Settings
      - Controls
        - Shortcut 1 → Trigger → Set "Hold" to "⌘"
        - Shortcut 2 → Trigger → Set "Hold" to "⌘"

  - CleanShot X
    - Settings
      - General → After capture
        - Screenshot
          - Turn off "Show Quick Access Overlay"
          - Turn on "Copy file to clipboard"
        -Recording
          - Turn off "Show Quick Access Overlay"
          - Turn on "Copy file to clipboard"
          - Turn on "Save"
      - Shortcuts
        - General
          - Clear "All-In-One" shortcut
          - Set "Open Capture History" shortcut to ⇧⌘6
        - Screenshots
          - Set "Capture Area" shortcut to ⇧⌘2
          - Set "Capture Fullscreen" shortcut to ⇧⌘1
      - Screen Recording
        - Set "Record Screen / Stop Recording" shortcut to ⇧⌘5
      - OCR
        - Set "Capture Text" shortcut to ⇧⌘4
      - Annotate
        - Set "Annotate Last Screenshot" shortcut to ⇧⌘3
        - Clear "Save" shortcut
        - Set "Save as" shortcut to ⌘S

  - Figma
    - Settings
      - Turn off "Rename duplicated layers"
      - Turn off "Flip objects while resizing"
      - Turn on "Invert Zoom Direction"
      - Nudge Amount… → Set "Big nudge" to 8px
      - Turn off "Show Figma in Menu Bar"

  - FineTune
    - Set HypetheSonics EQ preset
    - Settings → General
      - Set "Icon Style" to speaker
      - Set "Popup Size" to "Compact"

  - Ghostty
    - Grant Full Disk Access permission

  - Google Chrome
    - Grant Screen & System Audio Recording permission
    - Settings
      - You and Google → Sync and Google services → Turn off "Make searches and browsing better"
      - Privacy and security
        - Ads privacy
          - Turn off "Ad topics"
          - Turn off "Site-suggested ads"
          - Turn off "Ads measurement"
        - Site settings
          - Additional permissions → Web app installations → Select "Don't allow sites to install web apps on your device"
          - Additional content settings → Third-party sign-in → Select "Block sign-in prompts from identity services"
      - AI innovations → Gemini in Chrome
        - Turn off "Show Gemini at the top of the browser"
        - Turn off "Show Gemini in Mac menu bar and turn on keyboard shortcut"
      - Search engine → Manage search engines and site search → Set "Google Web" as default search engine
      - Downloads → Turn off "Show downloads when they're complete"
      - System → Turn off "On-device AI"
    - Flags
      - [#lens-overlay-optimization-filter](chrome://flags/#lens-overlay-optimization-filter) → Set to "Disabled"

  - Hammerspoon
    - Settings → Turn on "Launch Hammerspoon at login"

  - Homerow
    - Settings → Turn on "Launch on login"

  - IINA
    - Settings → Utilities → Select "Set IINA as the Default Application…"

  - Mail
    - Set up sidebar favorites (see reference screenshot)
    - Turn off "Show Mail Categories"
    - Settings
      - Junk Mail
        - Turn on "Enable junk mail filtering"
        - Set "When junk mail arrives" to "Perform custom actions (Click Advanced to configure)"
        - Advanced → Perform the following actions → Add "Mark as Read"

  - Raycast
    - Import settings file
    - Disable unused extensions/commands

  - RunCat Neo
    - Settings
      - General → Turn on "Launch at login"
      - Metrics
        - Turn off "Enable Storage Capacity Monitoring"
        - Turn off "Enable Battery Status Monitoring"

  - Scratchpad
    - Launch at login
    - Set Font to "JetBrains Mono Regular Regular"

  - VS Code
    - Sync settings and extensions
    - Position Command Center in center of window

  - Xcode
    - Install [Additional Tools for Xcode](https://developer.apple.com/download/all/?q=additional%20tools)
