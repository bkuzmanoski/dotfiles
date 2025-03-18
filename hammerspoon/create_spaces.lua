return function(numberOfSpaces)
  if not numberOfSpaces then return end

  local primaryScreen = hs.screen.primaryScreen()
  local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)
  if numberOfSpaces <= spacesCount then return end

  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end
