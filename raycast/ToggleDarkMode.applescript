#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Toggle Dark Mode
# @raycast.mode silent
# @raycast.packageName Google Chrome
# @raycast.icon icons/toggle-dark-mode.png

tell application "Google Chrome"
  if (count of windows) > 0 then
    tell active tab of window 1
      execute javascript "
        (function() {
          var css = 'html { filter: invert(90%) hue-rotate(180deg); } img, video, canvas, figure svg { filter: invert(100%) hue-rotate(-180deg); }';
          var style = document.getElementById('custom-dark-mode');
          if (!style) {
            style = document.createElement('style');
            style.id = 'custom-dark-mode';
            document.head.appendChild(style);
            style.innerHTML = css;
          } else {
            style.parentNode.removeChild(style);
          }
        })();
      "
      return ""
    end tell
  end if
end tell
