-- Battle Factory Remix unified dispatcher for Pokemon Red and Crystal.
-- Each game's existing implementation is kept isolated so neither codepath
-- loads generation-specific modules belonging to the other game.
local GameVersion=require("src.core.GameVersion")

return function(mod)
  local version=GameVersion.get and GameVersion.get() or "red"
  local rel
  if version=="crystal" then
    rel="variants/crystal/main.lua"
  elseif version=="red" then
    rel="variants/red/main.lua"
  else
    error("Battle Factory Remix does not support game version: "..tostring(version))
  end

  local source,err=mod:read(rel)
  assert(source,err or ("Unable to read "..rel))
  local chunk,compileErr=load(source,"@"..rel)
  assert(chunk,compileErr)
  local installer=chunk()
  assert(type(installer)=="function",rel.." must return a mod installer")
  return installer(mod)
end
