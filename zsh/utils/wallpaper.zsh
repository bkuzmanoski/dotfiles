wallpaper() {
  local wallpaper_path="$(fd -g "*.{heic,png}" ${HOME}/.dotfiles/wallpapers | fzf --delimiter="/" --with-nth=-1)"
  [[ -z "${wallpaper_path}" ]] && return

  /usr/libexec/PlistBuddy -c "set AllSpacesAndDisplays:Desktop:Content:Choices:0:Files:0:relative file:///${wallpaper_path}" "${HOME}/Library/Application Support/com.apple.wallpaper/Store/Index.plist" && \
  killall WallpaperAgent
}
