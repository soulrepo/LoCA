-- LoCA - Loss of Control Alerter
-- 1.12 (Lua 5.0) port for octowow. Original by Rdmx (MIT), Ace3 replaced by a
-- small native settings store and options panel (see Options.lua).
-- Retail mode relies on ClassicAPI.dll's C_LossOfControl; custom mode reads
-- player debuffs (ClassicAPI's C_UnitAuras, falling back to SuperWoW spell ids).

LoCA = {}
local addon = LoCA
local addonName = "LoCA"

addon.addonTitle = GetAddOnMetadata(addonName, "Title") or "Loss of Control Alerter"

addon.defaultSettings = {
  debuffs = {
    mode = "retail", --[[ custom/retail --]]
    scale = 1,
    alpha = 1,
    types = {
      { name = "Movement/Root", active = true, },
      { name = "Silence/Disarm", active = true, },
      { name = "Stun", active = true, },
      { name = "Full", active = true, }
    },
    showRedLines = true,
    showBackground = true,
    showSecondsLabel = true,
    -- Custom mode matches debuffs by name, so any rank of a spell works.
    debuffsTable = {
      { spellId = 122, category = "Rooted", weight = 1, active = true, type = 1 },     --[[ Frost Nova --]]
      { spellId = 12494, category = "Rooted", weight = 1, active = true, type = 1 },   --[[ Frostbite --]]
      { spellId = 19675, category = "Rooted", weight = 1, active = true, type = 1 },   --[[ Feral Charge --]]
      { spellId = 23694, category = "Rooted", weight = 1, active = true, type = 1 },   --[[ Improved Hamstring --]]
      { spellId = 339, category = "Rooted", weight = 1, active = true, type = 1 },     --[[ Entangling Roots --]]

      { spellId = 18469, category = "Silenced", weight = 2, active = true, type = 2 }, --[[ Improved Counterspell --]]
      { spellId = 15487, category = "Silenced", weight = 2, active = true, type = 2 }, --[[ Silence --]]
      { spellId = 18425, category = "Silenced", weight = 2, active = true, type = 2 }, --[[ Improved Kick --]]
      { spellId = 18498, category = "Silenced", weight = 2, active = true, type = 2 }, --[[ Improved Shield Bash --]]
      { spellId = 19647, category = "Silenced", weight = 2, active = true, type = 2 }, --[[ Spell Lock --]]
      { spellId = 676, category = "Disarmed", weight = 2, active = true, type = 2 },   --[[ Disarm --]]

      { spellId = 408, category = "Stunned", weight = 3, active = true, type = 3 },    --[[ Kidney Shot --]]
      { spellId = 1833, category = "Stunned", weight = 3, active = true, type = 3 },   --[[ Cheap Shot --]]
      { spellId = 8983, category = "Stunned", weight = 3, active = true, type = 3 },   --[[ Bash --]]
      { spellId = 20615, category = "Stunned", weight = 3, active = true, type = 3 },  --[[ Intercept Stun --]]
      { spellId = 7922, category = "Stunned", weight = 3, active = true, type = 3 },   --[[ Charge Stun --]]
      { spellId = 12809, category = "Stunned", weight = 3, active = true, type = 3 },  --[[ Concussion Blow --]]
      { spellId = 9005, category = "Stunned", weight = 3, active = true, type = 3 },   --[[ Pounce --]]
      { spellId = 853, category = "Stunned", weight = 3, active = true, type = 3 },    --[[ Hammer of Justice --]]
      { spellId = 24394, category = "Stunned", weight = 3, active = true, type = 3 },  --[[ Intimidation --]]
      { spellId = 15269, category = "Stunned", weight = 3, active = true, type = 3 },  --[[ Blackout --]]
      { spellId = 12355, category = "Stunned", weight = 3, active = true, type = 3 },  --[[ Impact --]]
      { spellId = 5530, category = "Stunned", weight = 3, active = true, type = 3 },   --[[ Mace Stun Effect --]]
      { spellId = 20549, category = "Stunned", weight = 3, active = true, type = 3 },  --[[ War Stomp --]]

      { spellId = 20066, category = "Incapacitated", weight = 4, active = true, type = 4 }, --[[ Repentance --]]
      { spellId = 1776, category = "Incapacitated", weight = 4, active = true, type = 4 },  --[[ Gouge --]]
      { spellId = 19386, category = "Asleep", weight = 4, active = true, type = 4 },        --[[ Wyvern Sting --]]
      { spellId = 2637, category = "Asleep", weight = 4, active = true, type = 4 },         --[[ Hibernate --]]
      { spellId = 19503, category = "Disoriented", weight = 4, active = true, type = 4 },   --[[ Scatter Shot --]]
      { spellId = 2094, category = "Disoriented", weight = 4, active = true, type = 4 },    --[[ Blind --]]
      { spellId = 12825, category = "Polymorphed", weight = 4, active = true, type = 4 },   --[[ Polymorph --]]
      { spellId = 6213, category = "Feared", weight = 4, active = true, type = 4 },         --[[ Fear --]]
      { spellId = 8122, category = "Feared", weight = 4, active = true, type = 4 },         --[[ Psychic Scream --]]
      { spellId = 5246, category = "Feared", weight = 4, active = true, type = 4 },         --[[ Intimidating Shout --]]
      { spellId = 5484, category = "Feared", weight = 4, active = true, type = 4 },         --[[ Howl of Terror --]]
      { spellId = 6789, category = "Horrified", weight = 4, active = true, type = 4 },      --[[ Death Coil --]]
      { spellId = 6358, category = "Charmed", weight = 4, active = true, type = 4 },        --[[ Seduction --]]
      { spellId = 11297, category = "Sapped", weight = 4, active = true, type = 4 },        --[[ Sap --]]
      { spellId = 3355, category = "Frozen", weight = 4, active = true, type = 4 },         --[[ Freezing Trap Effect --]]
    }
  }
}

local function CopyTable(src)
  local copy = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      copy[k] = CopyTable(v)
    else
      copy[k] = v
    end
  end
  return copy
end

-- Fills in missing keys from the defaults without touching saved values.
local function ApplyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      if type(v) == "table" then
        db[k] = CopyTable(v)
      else
        db[k] = v
      end
    elseif type(v) == "table" and type(db[k]) == "table" and k ~= "debuffsTable" then
      ApplyDefaults(db[k], v)
    end
  end
end

-- Adds default debuffs that a saved list doesn't know about yet.
local function MergeDebuffsTable(saved, defaults)
  local known = {}
  for _, debuff in ipairs(saved) do
    known[debuff.spellId] = true
  end
  for _, debuff in ipairs(defaults) do
    if not known[debuff.spellId] then
      table.insert(saved, CopyTable(debuff))
    end
  end
end

function addon:HasLossOfControlAPI()
  return C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData and true or false
end

function addon:OnUpdateSettings()
  local debuffs = addon.debuffs
  local mode = addon.db.debuffs.mode

  if mode == "retail" and not addon:HasLossOfControlAPI() then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555LoCA:|r C_LossOfControl not found (is ClassicAPI loaded?), using custom mode.")
    mode = "custom"
    addon.db.debuffs.mode = mode
  end

  debuffs:DeactivateDebuff()

  if mode == "retail" then
    addon.eventHandler:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    addon.eventHandler:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    addon.eventHandler:UnregisterEvent("UNIT_AURA")
    addon.eventHandler:UnregisterEvent("PLAYER_AURAS_CHANGED")

    debuffs:OnLossOfControlUpdate(C_LossOfControl.GetActiveLossOfControlData(1))
  else
    if addon:HasLossOfControlAPI() then
      addon.eventHandler:UnregisterEvent("LOSS_OF_CONTROL_ADDED")
      addon.eventHandler:UnregisterEvent("LOSS_OF_CONTROL_UPDATE")
    end
    addon.eventHandler:RegisterEvent("UNIT_AURA")
    addon.eventHandler:RegisterEvent("PLAYER_AURAS_CHANGED")

    addon:OnAuraEvent("player")
  end

  debuffs:OnUpdateSettings()
end

function addon:OnInitialize()
  if type(LoCADB) ~= "table" then
    LoCADB = {}
  end
  ApplyDefaults(LoCADB, addon.defaultSettings)
  MergeDebuffsTable(LoCADB.debuffs.debuffsTable, addon.defaultSettings.debuffs.debuffsTable)
  addon.db = LoCADB

  addon.eventHandler:RegisterEvent("PLAYER_ENTERING_WORLD")

  addon.debuffs:OnInitialize(addon.db.debuffs)
  addon.options:OnInitialize()

  addon:OnUpdateSettings()
end

function addon:ResetSettings()
  LoCADB = nil
  addon:OnInitialize()
  addon.options:Refresh()
end

function addon:OnEvent()
  if event == "ADDON_LOADED" then
    if arg1 == addonName then
      addon:OnInitialize()
    end
  elseif event == "UNIT_AURA" then
    addon:OnAuraEvent(arg1)
  elseif event == "PLAYER_AURAS_CHANGED" then
    addon:OnAuraEvent("player")
  elseif event == "LOSS_OF_CONTROL_ADDED" then
    if addon.db.debuffs.mode == "retail" then
      -- There exist 2 payloads for LOSS_OF_CONTROL_ADDED:
      -- - either eventIndex only
      -- - or unitTarget first, then eventIndex
      local eventIndex = arg2 or arg1
      if type(eventIndex) ~= "number" then
        eventIndex = 1
      end
      local data = C_LossOfControl.GetActiveLossOfControlData(eventIndex)
      if data then
        addon.debuffs:OnLossOfControlEvent(data, eventIndex)
      end
    end
  elseif event == "LOSS_OF_CONTROL_UPDATE" then
    if addon.db.debuffs.mode == "retail" then
      addon.debuffs:OnLossOfControlUpdate(C_LossOfControl.GetActiveLossOfControlData(1))
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    addon:OnUpdateSettings()
  end
end

function addon:OnAuraEvent(unitId)
  -- we are only interested in our debuffs
  if unitId ~= "player" or addon.db.debuffs.mode ~= "custom" then
    return
  end

  addon.debuffs:OnDebuffsChanged()
end

addon.eventHandler = CreateFrame("Frame")
addon.eventHandler:SetScript("OnEvent", function() addon:OnEvent() end)
addon.eventHandler:RegisterEvent("ADDON_LOADED")

function addon:CreateDebuffs()
  addon.debuffs = {
    NotifyUpdate = function()
      addon:OnUpdateSettings()
    end
  }

  return addon.debuffs
end

-- Slash commands
SLASH_LOCA1 = "/loca"
SlashCmdList["LOCA"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "test" then
    addon.debuffs:RunTest()
  elseif msg == "unlock" then
    addon.debuffs:Unlock()
  elseif msg == "lock" then
    addon.debuffs:Lock()
  elseif msg == "reset" then
    addon:ResetSettings()
    DEFAULT_CHAT_FRAME:AddMessage("LoCA: settings reset.")
  else
    addon.options:Toggle()
  end
end
