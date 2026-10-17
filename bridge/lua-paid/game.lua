-- absw "paid content" patch for game.lua (only in the HD -unlocked APK).
-- Loads the original script, then on every launch (startSequenceEnded runs once, after the splash and
-- before the main menu):
-- * Restores the paid episodes (Path of the Jedi, Bounty Missions) through the game's own purchase-restore
--   callback, the same path that runs when Google Play reports them as owned. Progress gates stay: levels
--   inside every episode still open one by one, and base episodes, Boba Fett rocket packs, golden droids
--   and bonus levels are untouched.
-- * Sets the four power-ups and the Millennium Falcon ("Mighty Eagles", eaglepurchases.lua) to 999, the
--   largest count the HUD shows, and keeps power-up gifts and Falcon rewards (stars, level rewards,
--   purchases) from raising either count past it.
local G = _G
loadLuaFile(scriptPath .. "/game.orig.lua", "", false, false)

local POWERUP_MAX = 999  -- CounterButton has bubbles for 1, 2 and 3 digits
local FALCON_MAX = 999

local function restorePaidEpisodes()
  local restored = {}
  for _, folder in G.ipairs(actions.myLevelFolders.iapLevelFolders) do
    local iapId = getEpisodeMetadataWithParam(folder, "iapPurchaseId")
    if iapId and not SettingsWrapper:isEpisodePurchased(iapId) then
      iapRestoreCallback(iapId, BUY_CALLBACK_STATUS_RESTORED, nil)  -- purchaseEpisode + savePurchases
      restored[#restored + 1] = folder
    end
  end
  return restored
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

local originalStartSequenceEnded = startSequenceEnded
startSequenceEnded = function(...)
  capPowerupGains()  -- startSequenceEnded runs once per launch, so these wrap once
  originalStartSequenceEnded(...)  -- also gives the first-run power-ups, so refill after it
  capFalconRewards()
  local restored = restorePaidEpisodes()
  refillPowerups()
  refillFalcons()
  savePurchases()
  -- The game's print is silent in release builds.
  G.print("[absw] paid content: restored {" .. G.table.concat(restored, ", ") .. "}; power-ups and Falcons at "
    .. POWERUP_MAX .. "/" .. SettingsWrapper:getMEAmount())
end
