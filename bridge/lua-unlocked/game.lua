-- absw "unlocked" patch for game.lua (only in the -unlocked APK, not in the stable build).
-- Loads the original script, then on every launch (startSequenceEnded runs once, after the splash and
-- before the main menu) opens all content and refills the four power-ups. The Millennium Falcon is
-- stored separately ("Mighty Eagles" in eaglepurchases.lua) and is left untouched.
local G = _G
loadLuaFile(scriptPath .. "/game.orig.lua", "", false, false)

local POWERUP_MAX = 999  -- CounterButton has bubbles for 1, 2 and 3 digits
local EPISODE_GROUPS = { "normalLevelFolders", "iapLevelFolders", "droidLevelFolders" }

local function unlockContent()
  -- Paid episodes (Path of the Jedi, Bounty Hunter) count as purchased, as after a real purchase.
  for _, folder in G.ipairs(actions.myLevelFolders.iapLevelFolders) do
    local iapId = getEpisodeMetadataWithParam(folder, "iapPurchaseId")
    if iapId then
      SettingsWrapper:purchaseEpisode(iapId)
    end
  end
  unlockAllBobaLevels()  -- otherwise opened by finding rocket packs
  -- Every level of every episode. isLevelUnlocked still applies each episode's openLevelsLimit.
  for _, group in G.ipairs(EPISODE_GROUPS) do
    for _, folder in G.ipairs(actions.myLevelFolders[group]) do
      local levels = actions.myLevels[folder]
      if levels and SettingsWrapper:getLevelProgress(folder) < #levels then
        settings.root.levelProgress[folder] = #levels
      end
    end
  end
  -- Bonus levels, otherwise opened by finding golden droids.
  for _, level in G.ipairs(actions.myLevels.bonus) do
    SettingsWrapper:storeDroidLevelUnlocked(level)
  end
end

local function refillPowerups()
  if not PowerupManager then
    return  -- only loaded when the build has power-ups (isIapEnabled)
  end
  for _, name in G.ipairs(PowerupManager.POWERUP_NAMES) do
    SettingsWrapper:setPowerUpAmount(name, POWERUP_MAX)
  end
end

-- Episodes that only open "after the first episode" or through an IAP id stay disabled in the
-- episode selection otherwise (Bounty Hunter). The "nextEpisode" placeholder keeps its state.
local originalIsEpisodeDisabled = isEpisodeDisabled
isEpisodeDisabled = function(folder)
  if folder ~= "nextEpisode" and actions.myLevels[folder] then
    return false
  end
  return originalIsEpisodeDisabled(folder)
end

local originalStartSequenceEnded = startSequenceEnded
startSequenceEnded = function(...)
  originalStartSequenceEnded(...)  -- also gives the first-run power-ups, so refill after it
  unlockContent()
  refillPowerups()
  saveSettings()
  savePurchases()
  G.print("[absw] unlocked: all episodes and levels; power-ups set to " .. POWERUP_MAX)  -- the game's print is silent in release builds
end
