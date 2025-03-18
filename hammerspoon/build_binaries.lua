return function()
  local sourceDir = hs.configdir .. "/helpers"
  local binDir = sourceDir .. "/bin"
  os.execute("mkdir -p " .. binDir)

  local filesToBuild = {}
  for file in hs.fs.dir(sourceDir) do
    if file:match("%.swift$") then
      local binaryPath = binDir .. "/" .. file:gsub("%.swift$", "")
      if hs.fs.attributes(binaryPath) == nil then
        table.insert(filesToBuild, { source = sourceDir .. "/" .. file, target = binaryPath })
      end
    end
  end

  for _, build in ipairs(filesToBuild) do
    local success = os.execute(string.format("swiftc -O '%s' -o '%s'", build.source, build.target))
    if not success then print("Failed to build " .. build.source) end
  end
end
