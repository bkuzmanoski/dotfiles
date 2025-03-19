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
          document.querySelectorAll('div,span').forEach(element => {
            const backgroundImage = window.getComputedStyle(element).backgroundImage;
            if (backgroundImage && backgroundImage.includes('url(')) {
              element.classList.add('_britown-has-bg-image');
            }
          });
          const css = 'html { background: #ffffff; filter: invert(90%) hue-rotate(180deg); } ' +
                      'img, video, canvas, figure svg, ._britown-has-bg-image { ' +
                      '  filter: invert(100%) hue-rotate(-180deg); ' +
                      '}';
          var styleElement = document.getElementById('_britown-dark-mode');
          if (!styleElement) {
            styleElement = document.createElement('style');
            styleElement.id = '_britown-dark-mode';
            document.head.appendChild(styleElement);
            styleElement.innerHTML = css;
          } else {
            document.querySelectorAll('._britown-has-bg-image').forEach(element => {
              element.classList.remove('_britown-has-bg-image');
            });
            styleElement.parentNode.removeChild(styleElement);
          }
        })();
      "
      return ""
    end tell
  end if
end tell
