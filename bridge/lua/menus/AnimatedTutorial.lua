-- absw display patch for AnimatedTutorial (tutorial popups and story comics).
-- Loads the original script, then replaces getTutorialScale: on Android it picked fixed steps from
-- the screen *width* (>= 2048 px -> x2, >= 1920 px -> x1.5), which made the 950x768 tutorial area
-- taller than wide phone screens. Fit it to the screen instead.
local G = _G
local gl = gamelua
gl.loadLuaFileToObject(gl.scriptPath .. "/menus/AnimatedTutorial.orig.lua", gl.this.ui, "")

local cls = gl.this.ui.AnimatedTutorial
local env = G.getfenv(cls.layout)
local originalScale = env.getTutorialScale

env.getTutorialScale = function(staticImage)
  local model = gl.deviceModel
  if staticImage or model == "ipad" or model == "iphone" or model == "windows" then
    return originalScale(staticImage)
  end
  return G.math.min(gl.screenHeight / 768, gl.screenWidth / 950)
end

G.print("[absw] AnimatedTutorial: tutorial scale fitted to " .. gl.screenWidth .. "x" .. gl.screenHeight)
