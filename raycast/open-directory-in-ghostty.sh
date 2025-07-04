#!/usr/bin/osascript

# @raycast.title Open Directory in Ghostty
# @raycast.packageName Finder
# @raycast.icon icons/open-directory-in-ghostty.png

# @raycast.mode silent

# @raycast.schemaVersion 1

on getSelectedFolderPath()
	tell application "Finder"
		set selectedItems to selection as list
		if (count of selectedItems) is 1 and class of first item of selectedItems is folder then
			return POSIX path of (first item of selectedItems as alias)
		else
			return POSIX path of (insertion location as alias)
		end if
	end tell
end getSelectedFolderPath

set currentPath to getSelectedFolderPath()
do shell script "open -a Ghostty " & quoted form of currentPath

return ""
