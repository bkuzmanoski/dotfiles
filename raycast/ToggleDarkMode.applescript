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
          const styleId = '_britown-dark-mode';
          const bgClass = '_britown-has-bg-image';
          const existingStyle = document.getElementById(styleId);

          if (!existingStyle) {
            document.querySelectorAll('div,span').forEach(element => {
              if (window.getComputedStyle(element).backgroundImage.includes('url(')) {
                element.classList.add(bgClass);
              }
            });

            const style = document.createElement('style');
            style.id = styleId;
            style.innerHTML = 'html { background: #ffffff; filter: invert(90%) hue-rotate(180deg) }' +
                              'img, video, canvas, figure svg, .' + bgClass + ' { filter: invert(100%) hue-rotate(-180deg) }';
            document.head.appendChild(style);
          } else {
            document.querySelectorAll('.' + bgClass).forEach(element => element.classList.remove(bgClass));
            existingStyle.remove();
          }
        })();
      "
      return ""
    end tell
  end if
end tell
