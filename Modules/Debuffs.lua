local addon = LoCA
local locaDebuffs = addon:CreateDebuffs()

local container
local isLocked = true

local LOC_TYPE_MAP = {
  ROOT = 1,
  SCHOOL_INTERRUPT = 2,
  DISARM = 2,
  PACIFYSILENCE = 2,
  SILENCE = 2,
  STUN_MECHANIC = 3,
  PACIFY = 3,
  STUN = 4,
  FEAR = 4,
  FEAR_MECHANIC = 4,
  CHARM = 4,
  CONFUSE = 4,
  POSSESS = 4,
}

-- 1.12 has no GetSchoolString; lockoutSchool is a school bitmask.
local SCHOOL_NAMES = {
  { 1, "Physical" },
  { 2, "Holy" },
  { 4, "Fire" },
  { 8, "Nature" },
  { 16, "Frost" },
  { 32, "Shadow" },
  { 64, "Arcane" },
}

local function SchoolString(mask)
  local native = getglobal("GetSchoolString")
  if type(native) == "function" then
    return native(mask)
  end
  for _, school in ipairs(SCHOOL_NAMES) do
    if math.mod(math.floor(mask / school[1]), 2) == 1 then
      return school[2]
    end
  end
  return "Spell"
end

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"

local initializedDebuffs = {}
local iconFrame

local TIME_COMPARISON_THRESHOLD = 0.1

-- Returns found, name, icon, timeLeft (nil when the debuff has no duration), spellId.
local function GetPlayerDebuff(index)
  if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
    local aura = C_UnitAuras.GetDebuffDataByIndex("player", index)
    if not aura then return false end
    local timeLeft
    if aura.expirationTime and aura.expirationTime > 0 then
      timeLeft = aura.expirationTime - GetTime()
    end
    return true, aura.name, aura.icon, timeLeft, aura.spellId
  end

  -- SuperWoW adds the spell id as UnitDebuff's 4th return
  local texture, _, _, spellId = UnitDebuff("player", index)
  if not texture then return false end

  local name
  if spellId and GetSpellInfo then
    name = GetSpellInfo(spellId)
  end

  local timeLeft
  local buffIndex = GetPlayerBuff(index - 1, "HARMFUL")
  if buffIndex and buffIndex >= 0 then
    timeLeft = GetPlayerBuffTimeLeft(buffIndex)
    if timeLeft and timeLeft <= 0 then timeLeft = nil end
  end

  return true, name, texture, timeLeft, spellId
end

-- Fallback for custom mode: debuffs that aren't in the tracked list (such as
-- octowow's custom spells) are classified by the generated spell table or by
-- the mechanic ClassicAPI reports for them. Ids are from SpellMechanic.dbc; snares and dazes are left
-- out, like in the default list.
local MECHANIC_MAP = {
  [1] = { category = "Charmed", type = 4 },
  [2] = { category = "Disoriented", type = 4 },
  [3] = { category = "Disarmed", type = 2 },
  [5] = { category = "Feared", type = 4 },
  [7] = { category = "Rooted", type = 1 },
  [8] = { category = "Pacified", type = 3 },
  [9] = { category = "Silenced", type = 2 },
  [10] = { category = "Asleep", type = 4 },
  [12] = { category = "Stunned", type = 3 },
  [13] = { category = "Frozen", type = 4 },
  [14] = { category = "Incapacitated", type = 4 },
  [17] = { category = "Polymorphed", type = 4 },
  [18] = { category = "Banished", type = 4 },
  [20] = { category = "Shackled", type = 4 },
  [23] = { category = "Feared", type = 4 },
  [24] = { category = "Horrified", type = 4 },
  [30] = { category = "Sapped", type = 4 },
}

local function FindSpellApi(name)
  if C_Spell and type(C_Spell[name]) == "function" then
    return C_Spell[name]
  end
  local global = getglobal(name)
  if type(global) == "function" then
    return global
  end
end

-- Returns the mapped mechanic ids for a spell: the spell's own mechanic, then its per-effect ones.
local function GetSpellMechanics(spellId)
  local mechanics = {}

  local getMechanic = FindSpellApi("GetSpellMechanicByID")
  if getMechanic then
    local mechanicId = getMechanic(spellId)
    if mechanicId and mechanicId ~= 0 then
      table.insert(mechanics, mechanicId)
    end
  end

  local getEffectMechanics = FindSpellApi("GetSpellEffectMechanics")
  if getEffectMechanics then
    local first, second, third = getEffectMechanics(spellId)
    if type(first) == "table" then
      first, second, third = first[1], first[2], first[3]
    end
    for _, mechanicId in ipairs({ first or 0, second or 0, third or 0 }) do
      if mechanicId ~= 0 then
        table.insert(mechanics, mechanicId)
      end
    end
  end

  return mechanics
end

local mechanicCache = {}

-- Classifies an unlisted debuff: first by the spell table generated from the
-- client's Spell.dbc (Modules/SpellData.lua), which also covers spells that only
-- carry a stun/root/fear aura, then by the mechanic ClassicAPI reports.
function locaDebuffs:ClassifyByMechanic(spellId, name, icon)
  if not spellId then return nil end

  local cached = mechanicCache[spellId]
  if cached ~= nil then
    return cached or nil
  end

  local best
  local known = addon.spellData and addon.spellData[spellId]
  if known then
    best = addon.spellCategories[known]
  else
    for _, mechanicId in ipairs(GetSpellMechanics(spellId)) do
      local mapped = MECHANIC_MAP[mechanicId]
      if mapped and (not best or mapped.type > best.type) then
        best = mapped
      end
    end
  end

  local debuff = false
  if best then
    debuff = {
      spellId = spellId,
      name = name,
      icon = icon,
      category = best.category,
      weight = best.type,
      type = best.type,
      active = true,
    }
  end

  mechanicCache[spellId] = debuff
  return debuff or nil
end

function locaDebuffs:OnDebuffsChanged()
  local candidatesForActivation = {}
  local candidateDurations = {}

  for i = 1, 16 do
    local found, name, icon, durationLeft, spellId = GetPlayerDebuff(i)
    if not found then break end

    local debuffIcon = name and initializedDebuffs[name]
    if not debuffIcon and locaDebuffs.db.mechanicFallback then
      debuffIcon = locaDebuffs:ClassifyByMechanic(spellId, name, icon)
    end

    -- check if the debuff is being monitored for alerts
    if debuffIcon and debuffIcon.active then
      table.insert(candidatesForActivation, debuffIcon)
      table.insert(candidateDurations, durationLeft or 0)
    end
  end

  local maxDuration = -1
  local targetIndex = 0
  local maxWeight = 1

  for idx, candidateDuration in ipairs(candidateDurations) do
    local candidateWeight = candidatesForActivation[idx].weight

    if candidateWeight > maxWeight then
      maxDuration = candidateDuration
      targetIndex = idx
      maxWeight = candidateWeight
    elseif candidateWeight == maxWeight then
      if candidateDuration > maxDuration then
        maxDuration = candidateDuration
        targetIndex = idx
        maxWeight = candidateWeight
      end
    end
  end

  local duration = candidateDurations[targetIndex]
  if duration and duration <= 0 then duration = nil end

  locaDebuffs:ActivateNewDebuff(candidatesForActivation[targetIndex], duration)
end

function locaDebuffs:OnLossOfControlEvent(locData, eventIndex)
  local locType = locData.locType
  local spellID = locData.spellID
  local text = locData.displayText
  local iconTexture = locData.iconTexture
  local timeRemaining = locData.timeRemaining
  local lockoutSchool = locData.lockoutSchool
  local priority = locData.priority or 0

  if text then
    if locType == "SCHOOL_INTERRUPT" then
      if lockoutSchool and lockoutSchool ~= 0 then
        text = string.format("%s Locked", SchoolString(lockoutSchool))
      end
    end

    -- make a fake debuff configuration object
    local debuffConfiguration = {
      spellId = spellID,
      name = text,
      icon = iconTexture,
      weight = priority,
      category = text,
      type = LOC_TYPE_MAP[locType]
    }

    -- in case that there's a missed loctype just use the highest one
    if not debuffConfiguration.type then
      debuffConfiguration.type = 4
    end

    if not iconFrame.active or debuffConfiguration.weight > iconFrame.weight then
      locaDebuffs:ActivateNewDebuff(debuffConfiguration, timeRemaining)
    elseif iconFrame.active and debuffConfiguration.weight == iconFrame.weight and (timeRemaining == nil or timeRemaining > (iconFrame.timeLeft or 0)) then
      locaDebuffs:ActivateNewDebuff(debuffConfiguration, timeRemaining)
    end
  end
end

function locaDebuffs:OnLossOfControlUpdate(locData)
  if locData then
    if iconFrame.active and locData.spellID ~= iconFrame.spellId then
      locaDebuffs:DeactivateDebuff()
    end
    locaDebuffs:OnLossOfControlEvent(locData)
  else
    locaDebuffs:DeactivateDebuff()
  end
end

function locaDebuffs:LoadPosition()
  container:ClearAllPoints()
  local position = locaDebuffs.db.position
  if position then
    container:SetPoint(position.point, UIParent, position.relativePoint, position.xOfs, position.yOfs)
  else
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

function locaDebuffs:SavePosition()
  local point, _, relativePoint, xOfs, yOfs = container:GetPoint()

  if not locaDebuffs.db.position then
    locaDebuffs.db.position = {}
  end

  locaDebuffs.db.position.point = point
  locaDebuffs.db.position.relativePoint = relativePoint
  locaDebuffs.db.position.xOfs = xOfs
  locaDebuffs.db.position.yOfs = yOfs
end

function locaDebuffs:CreateContainerFrame()
  container = CreateFrame("Frame", "LoCAContainer", UIParent)
  container:SetMovable(false)
  container:SetWidth(160)
  container:SetHeight(50)
  container:SetBackdrop({
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  container:SetBackdropBorderColor(0.4, 1, 0.4, 0)
  container:SetClampedToScreen(true)
  container:SetScript("OnMouseDown", function() if arg1 == "LeftButton" then this:StartMoving() end end)
  container:SetScript("OnMouseUp", function() if arg1 == "LeftButton" then this:StopMovingOrSizing() locaDebuffs:SavePosition() end end)
  container:EnableMouse(false)
  container:Show()
  container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function locaDebuffs:UpdateContainer()
  container:SetScale(locaDebuffs.db.scale)
  container:SetAlpha(locaDebuffs.db.alpha)

  if locaDebuffs.db.showSecondsLabel and iconFrame.timeLeft then
    iconFrame.secondsText:Show()
  else
    iconFrame.secondsText:Hide()
  end

  if locaDebuffs.db.showRedLines then
    iconFrame.redLineTop:Show()
    iconFrame.redLineBottom:Show()
  else
    iconFrame.redLineTop:Hide()
    iconFrame.redLineBottom:Hide()
  end

  if locaDebuffs.db.showBackground then
    iconFrame.backgroundTexture:Show()
  else
    iconFrame.backgroundTexture:Hide()
  end
end

-- Resolves spell names/icons for the custom list. Can be called again after a reset.
function locaDebuffs:InitializeDebuffsTable()
  initializedDebuffs = {}
  local usable = {}

  for _, debuff in ipairs(locaDebuffs.db.debuffsTable) do
    local name, _, spellicon
    if GetSpellInfo then
      name, _, spellicon = GetSpellInfo(debuff.spellId)
    end
    debuff.name = name
    debuff.icon = spellicon

    -- drop any old debuff configuration that is unusable
    if name then
      initializedDebuffs[name] = debuff
      table.insert(usable, debuff)
    end
  end

  locaDebuffs.db.debuffsTable = usable
end

function locaDebuffs:OnInitialize(db)
  locaDebuffs.db = db

  if not container then
    locaDebuffs:CreateContainerFrame()
    iconFrame = locaDebuffs:CreateIcon()
  end

  locaDebuffs:InitializeDebuffsTable()

  locaDebuffs:OnUpdateSettings()
end

-- A horizontal strip that fades out towards both ends.
local function CreateFadedStrip(parent, layer, width, height, r, g, b, a)
  local left = parent:CreateTexture(nil, layer)
  left:SetTexture(WHITE_TEXTURE)
  left:SetWidth(width / 2)
  left:SetHeight(height)
  left:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, a)

  local right = parent:CreateTexture(nil, layer)
  right:SetTexture(WHITE_TEXTURE)
  right:SetWidth(width / 2)
  right:SetHeight(height)
  right:SetGradientAlpha("HORIZONTAL", r, g, b, a, r, g, b, 0)
  right:SetPoint("LEFT", left, "RIGHT", 0, 0)

  local strip = { left = left, right = right }
  strip.Show = function() left:Show() right:Show() end
  strip.Hide = function() left:Hide() right:Hide() end
  strip.SetPoint = function(_, point, relativeTo, relativePoint, x, y)
    -- anchor the pair by its center
    left:ClearAllPoints()
    left:SetPoint("RIGHT", relativeTo, relativePoint, (x or 0), (y or 0))
  end
  return strip
end

function locaDebuffs:CreateIcon()
  local btn = CreateFrame("Frame", "LoCAIcon", container)
  btn:SetWidth(40)
  btn:SetHeight(40)
  btn:SetFrameStrata("LOW")

  local texture = btn:CreateTexture(nil, "ARTWORK")
  texture:SetAllPoints(btn)
  texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local cd = CreateFrame("Model", "LoCAIconCooldown", btn, "CooldownFrameTemplate")
  cd.noomnicc = true
  cd.noCooldownCount = true
  cd:SetAllPoints(btn)

  -- the retail LoC textures don't exist in 1.12, so draw them with plain textures
  local backgroundTexture = CreateFadedStrip(btn, "BACKGROUND", 160, 50, 0, 0, 0, 0.6)
  backgroundTexture:SetPoint("CENTER", container, "CENTER", 0, 0)

  local redLineTop = CreateFadedStrip(btn, "BORDER", 160, 2, 1, 0, 0, 0.9)
  redLineTop:SetPoint("CENTER", container, "TOP", 0, 0)

  local redLineBottom = CreateFadedStrip(btn, "BORDER", 160, 2, 1, 0, 0, 0.9)
  redLineBottom:SetPoint("CENTER", container, "BOTTOM", 0, 0)

  local debuffTitle = btn:CreateFontString(nil, "OVERLAY")
  debuffTitle:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE")
  debuffTitle:SetTextColor(1, 1, 0, 1)
  debuffTitle:SetPoint("LEFT", btn, "RIGHT", 6, 8)

  local text = btn:CreateFontString(nil, "OVERLAY")
  text:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
  text:SetTextColor(1, 1, 1, 1)
  text:SetPoint("LEFT", btn, "RIGHT", 6, -10)

  local secondsText = btn:CreateFontString(nil, "OVERLAY")
  secondsText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
  secondsText:SetTextColor(1, 1, 1, 1)
  secondsText:SetPoint("LEFT", btn, "RIGHT", 36, -10)
  secondsText:SetText("seconds")

  btn.text = text
  btn.secondsText = secondsText
  btn.textureIcon = texture
  btn.cd = cd
  btn.redLineBottom = redLineBottom
  btn.redLineTop = redLineTop
  btn.debuffTitle = debuffTitle
  btn.backgroundTexture = backgroundTexture

  btn.spellId = 0
  btn.name = ""
  btn.weight = 0
  btn.duration = 0

  btn.activate = function(debuff, timeLeft)
    if btn.active then return end

    btn.spellId = debuff.spellId
    btn.name = debuff.name
    btn.weight = debuff.weight
    btn.active = true

    btn.textureIcon:SetTexture(debuff.icon)
    btn.debuffTitle:SetText(debuff.category)

    container:SetBackdropColor(0, 0, 0, 0.4)
    btn:Show()
    if timeLeft then
      btn.cd:Show()
      CooldownFrame_SetTimer(btn.cd, GetTime(), timeLeft, 1)
      btn.text:Show()
      btn.start = GetTime()
      btn.duration = timeLeft
      btn.settimeleft(timeLeft)
      btn:SetScript("OnUpdate", function() locaDebuffs:OnUpdateTimer(this) end)

      btn.secondsText:SetPoint("LEFT", btn, "RIGHT", 6 + btn.text:GetStringWidth(), -10)
      if locaDebuffs.db.showSecondsLabel then
        btn.secondsText:Show()
      end
    else
      btn.timeLeft = nil
      btn.cd:Hide()
      btn.text:Hide()
      btn.secondsText:Hide()
    end
  end

  -- called to hide and stop the frame
  btn.deactivate = function()
    if not btn.active then return end
    container:SetBackdropColor(0, 0, 0, 0)
    btn:Hide()
    btn.text:SetText("")
    btn.cd:Hide()
    btn:SetScript("OnUpdate", nil)
    btn.active = false
    btn.timeLeft = nil
  end

  btn.settimeleft = function(timeleft)
    btn.timeLeft = timeleft
    btn.text:Show()
    btn.text:SetText(string.format("%.1f", timeleft))

    -- set smaller font if the time left is too big, so it can fit
    if timeleft > 60 then
      btn.text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    else
      btn.text:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    end
  end

  btn:Hide()

  btn:SetPoint("LEFT", container, "LEFT", 8, 0)

  return btn
end

function locaDebuffs:ActivateNewDebuff(newDebuff, durationLeft)
  if not newDebuff then
    locaDebuffs:DeactivateDebuff()
    return
  end

  local category = locaDebuffs.db.types[newDebuff.type]
  if category and not category.active then return end

  if iconFrame.active then
    -- if the spell has the same time remaining or no duration, there's no need to update it
    if iconFrame.spellId == newDebuff.spellId and (not iconFrame.timeLeft or not durationLeft or math.abs(iconFrame.timeLeft - durationLeft) < TIME_COMPARISON_THRESHOLD) then
      return
    end
    locaDebuffs:DeactivateDebuff()
  end

  iconFrame.activate(newDebuff, durationLeft)
end

function locaDebuffs:DeactivateDebuff()
  if iconFrame and iconFrame.active then
    iconFrame.deactivate()
  end
end

function locaDebuffs:OnUpdateTimer(frame)
  local cooldown = frame.start + frame.duration - GetTime()
  if cooldown <= 0 then
    locaDebuffs:DeactivateDebuff()
  else
    frame.settimeleft(cooldown)
  end
end

function locaDebuffs:RunTest()
  local name, _, spellicon
  if GetSpellInfo then
    name, _, spellicon = GetSpellInfo(8643)
  end

  local testDebuff = {
    spellId = 8643,
    name = name or "Kidney Shot",
    icon = spellicon or "Interface\\Icons\\Ability_Rogue_KidneyShot",
    weight = 3,
    category = "Stunned",
    type = 3
  }

  locaDebuffs:DeactivateDebuff()
  locaDebuffs:ActivateNewDebuff(testDebuff, 5.9)
end

function locaDebuffs:IsLocked()
  return isLocked
end

function locaDebuffs:Unlock()
  isLocked = false
  container:SetBackdropBorderColor(0.4, 1, 0.4, 0.7)
  container:SetMovable(true)
  container:EnableMouse(true)
end

function locaDebuffs:Lock()
  isLocked = true
  container:SetBackdropBorderColor(0.4, 1, 0.4, 0)
  container:EnableMouse(false)
  container:SetMovable(false)
end

function locaDebuffs:GetScale()
  return locaDebuffs.db.scale
end

function locaDebuffs:SetScale(val)
  locaDebuffs.db.scale = val
  locaDebuffs:UpdateContainer()
end

function locaDebuffs:GetAlpha()
  return locaDebuffs.db.alpha
end

function locaDebuffs:SetAlpha(val)
  locaDebuffs.db.alpha = val
  locaDebuffs:UpdateContainer()
end

function locaDebuffs:OnUpdateSettings()
  locaDebuffs:LoadPosition()

  locaDebuffs:UpdateContainer()
end

function locaDebuffs:SetShowRedLines(val)
  locaDebuffs.db.showRedLines = val

  locaDebuffs:UpdateContainer()
end

function locaDebuffs:SetShowSecondsLabel(val)
  locaDebuffs.db.showSecondsLabel = val

  locaDebuffs:UpdateContainer()
end

function locaDebuffs:SetMechanicFallback(val)
  locaDebuffs.db.mechanicFallback = val

  locaDebuffs:NotifyUpdate()
end

function locaDebuffs:SetShowBackground(val)
  locaDebuffs.db.showBackground = val

  locaDebuffs:UpdateContainer()
end
