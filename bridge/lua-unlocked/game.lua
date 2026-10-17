-- absw "unlocked" patch for game.lua (only in the -unlocked APK, not in the stable build).
-- Loads the original script, then on every launch (startSequenceEnded runs once, after the splash and
-- before the main menu) opens all content and refills the four power-ups and the Millennium Falcon
-- ("Mighty Eagles", eaglepurchases.lua) to 999, as the HD unlocked APK does (bridge/lua-paid). Power-up
-- gifts and Falcon rewards (stars, level rewards, purchases) stop at that count.
local G = _G
loadLuaFile(scriptPath .. "/game.orig.lua", "", false, false)

local POWERUP_MAX = 999  -- CounterButton has bubbles for 1, 2 and 3 digits
local FALCON_MAX = 999   -- the largest count the HUD shows, as in the HD APK
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

-- Every power-up count change goes through SettingsWrapper.setPowerUpAmount: PowerupManager.addPowerUp
-- (gifts at level start, bundles, the power-up machine, video rewards, refunds) and using one (count - 1).
-- Capping the stored value there keeps every gain at POWERUP_MAX without touching decreases.
local function capPowerupGains()
  local originalSet = SettingsWrapper.setPowerUpAmount
  SettingsWrapper.setPowerUpAmount = function(self, name, amount)
    amount = G.tonumber(amount) or amount
    if G.type(amount) == "number" and amount > POWERUP_MAX then
      amount = POWERUP_MAX
    end
    originalSet(self, name, amount)
  end
end

-- SettingsWrapper.addMightyEagles is the only code that raises the Falcon count (reduceEagle lowers it),
-- so capping it covers star rewards, level rewards, the story Falcon, videos, toy codes and purchases.
-- Reward popups still announce the full amount; only the stored count stops at FALCON_MAX.
local function capFalconRewards()
  local originalAdd = SettingsWrapper.addMightyEagles
  SettingsWrapper.addMightyEagles = function(self, amount)
    local current = self:getMEAmount()
    if amount > 0 and current + amount > FALCON_MAX then
      amount = G.math.max(FALCON_MAX - current, 0)
    end
    originalAdd(self, amount)
  end
end

local function refillFalcons()
  local current = SettingsWrapper:getMEAmount()
  if current < FALCON_MAX then
    SettingsWrapper:addMightyEagles(FALCON_MAX - current)
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
  capPowerupGains()  -- startSequenceEnded runs once per launch, so these wrap once
  originalStartSequenceEnded(...)  -- also gives the first-run power-ups, so refill after it
  capFalconRewards()
  unlockContent()
  refillPowerups()
  refillFalcons()
  saveSettings()
  savePurchases()  -- also writes eaglepurchases.lua
  -- The game's print is silent in release builds.
  G.print("[absw] unlocked: all episodes and levels; power-ups and Falcons at " .. POWERUP_MAX .. "/"
    .. SettingsWrapper:getMEAmount())
end
