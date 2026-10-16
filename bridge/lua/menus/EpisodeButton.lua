-- absw display patch for EpisodeButton (planet score/star/medal panel).
-- Loads the original script, then undoes the iPad-Retina font shrink (x0.4) that Android builds
-- applied to any screen at least 2000 px wide: wide phones use the phone fonts.
local G = _G
local gl = gamelua
gl.loadLuaFileToObject(gl.scriptPath .. "/menus/EpisodeButton.orig.lua", gl.this.ui, "")

local cls = gl.this.ui.EpisodeButton
local originalInit = cls.init

cls.init = function(self, ...)
  originalInit(self, ...)
  if gl.deviceModel == "android" and gl.screenWidth >= 2000 and not gl.isIpad3() then
    self.fontScale = self.fontScale / 0.4
  end
end

G.print("[absw] EpisodeButton: phone font scale kept for " .. gl.screenWidth .. "x" .. gl.screenHeight)
