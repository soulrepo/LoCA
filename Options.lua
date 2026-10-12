-- Native 1.12 options panel, replacing the original AceConfig dialog.
-- Open with /loca.
local addon = LoCA
local options = {}
addon.options = options

local frame, debuffListFrame
local widgets = {}

local WEIGHT_NAMES = {
  [1] = "Movement/Root",
  [2] = "Disarm/Silence",
  [3] = "Stun",
  [4] = "Full",
}

local function Round(value)
  return math.floor(value * 10 + 0.5) / 10
end

local function CreateCheck(name, parent, label, onClick)
  local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
  check:SetWidth(24)
  check:SetHeight(24)
  getglobal(name .. "Text"):SetText(label)
  check:SetScript("OnClick", function() onClick(this:GetChecked() and true or false) end)
  return check
end

local function CreateButton(name, parent, label, width, onClick)
  local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  button:SetWidth(width)
  button:SetHeight(22)
  button:SetText(label)
  button:SetScript("OnClick", onClick)
  return button
end

local function CreateSlider(name, parent, label, minValue, maxValue, onChange)
  local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  slider:SetWidth(160)
  slider:SetMinMaxValues(minValue, maxValue)
  slider:SetValueStep(0.1)
  getglobal(name .. "Low"):SetText(minValue)
  getglobal(name .. "High"):SetText(maxValue)
  slider.label = label
  slider:SetScript("OnValueChanged", function()
    local value = Round(this:GetValue())
    getglobal(this:GetName() .. "Text"):SetText(this.label .. ": " .. value)
    if not this.refreshing then
      onChange(value)
    end
  end)
  return slider
end

local function CreateHeader(parent, text, anchor, yOffset)
  local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  header:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
  header:SetText(text)
  return header
end

local function CreateDialog(name, width, height, title)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetWidth(width)
  f:SetHeight(height)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  f:Hide()
  table.insert(UISpecialFrames, name)

  local titleText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  titleText:SetPoint("TOP", f, "TOP", 0, -18)
  titleText:SetText(title)
  f.title = titleText

  local close = CreateFrame("Button", name .. "Close", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

  return f
end

function options:CreateFrame()
  local debuffs = addon.debuffs
  frame = CreateDialog("LoCAOptionsFrame", 360, 520, addon.addonTitle)

  local description = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  description:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -48)
  description:SetWidth(312)
  description:SetJustifyH("LEFT")
  description:SetText("Retail: close to the standard Blizzard alerts (needs ClassicAPI).\nCustom: choose which debuffs alert and with what priority.")

  -- Mode
  local modeHeader = CreateHeader(frame, "Mode", description, -10)
  widgets.retail = CreateCheck("LoCAOptionsModeRetail", frame, "Retail", function()
    addon.db.debuffs.mode = "retail"
    addon:OnUpdateSettings()
    options:Refresh()
  end)
  widgets.retail:SetPoint("TOPLEFT", modeHeader, "BOTTOMLEFT", 0, -4)
  widgets.custom = CreateCheck("LoCAOptionsModeCustom", frame, "Custom", function()
    addon.db.debuffs.mode = "custom"
    addon:OnUpdateSettings()
    options:Refresh()
  end)
  widgets.custom:SetPoint("LEFT", widgets.retail, "RIGHT", 100, 0)

  -- Lock / test / debuff list
  widgets.lock = CreateButton("LoCAOptionsLock", frame, "Unlock", 90, function()
    if debuffs:IsLocked() then debuffs:Unlock() else debuffs:Lock() end
    options:Refresh()
  end)
  widgets.lock:SetPoint("TOPLEFT", widgets.retail, "BOTTOMLEFT", 0, -10)
  widgets.test = CreateButton("LoCAOptionsTest", frame, "Test", 90, function() debuffs:RunTest() end)
  widgets.test:SetPoint("LEFT", widgets.lock, "RIGHT", 8, 0)
  widgets.debuffList = CreateButton("LoCAOptionsDebuffList", frame, "Tracked Debuffs", 120, function()
    options:ToggleDebuffList()
  end)
  widgets.debuffList:SetPoint("LEFT", widgets.test, "RIGHT", 8, 0)

  -- Visuals
  local visualsHeader = CreateHeader(frame, "Visuals", widgets.lock, -14)
  widgets.scale = CreateSlider("LoCAOptionsScale", frame, "Scale", 0.1, 3, function(value) debuffs:SetScale(value) end)
  widgets.scale:SetPoint("TOPLEFT", visualsHeader, "BOTTOMLEFT", 4, -18)
  widgets.alpha = CreateSlider("LoCAOptionsAlpha", frame, "Alpha", 0.1, 1, function(value) debuffs:SetAlpha(value) end)
  widgets.alpha:SetPoint("TOPLEFT", widgets.scale, "BOTTOMLEFT", 0, -28)

  widgets.showRedLines = CreateCheck("LoCAOptionsRedLines", frame, "Show Red Lines", function(val) debuffs:SetShowRedLines(val) end)
  widgets.showRedLines:SetPoint("TOPLEFT", widgets.alpha, "BOTTOMLEFT", -4, -18)
  widgets.showBackground = CreateCheck("LoCAOptionsBackground", frame, "Show Background", function(val) debuffs:SetShowBackground(val) end)
  widgets.showBackground:SetPoint("TOPLEFT", widgets.showRedLines, "BOTTOMLEFT", 0, 0)
  widgets.showSecondsLabel = CreateCheck("LoCAOptionsSeconds", frame, "Show Seconds Label", function(val) debuffs:SetShowSecondsLabel(val) end)
  widgets.showSecondsLabel:SetPoint("TOPLEFT", widgets.showBackground, "BOTTOMLEFT", 0, 0)

  -- Tracked categories
  local categoriesHeader = CreateHeader(frame, "Tracked Categories", widgets.showSecondsLabel, -10)
  widgets.types = {}
  local previous = categoriesHeader
  for i = 1, 4 do
    local index = i
    local check = CreateCheck("LoCAOptionsType" .. i, frame, addon.db.debuffs.types[i].name, function(val)
      addon.db.debuffs.types[index].active = val
      debuffs:DeactivateDebuff()
      addon:OnUpdateSettings()
    end)
    check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, (i == 1) and -4 or 0)
    widgets.types[i] = check
    previous = check
  end

  widgets.reset = CreateButton("LoCAOptionsReset", frame, "Reset All", 90, function()
    addon:ResetSettings()
  end)
  widgets.reset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 18)

  frame:SetScript("OnShow", function() options:Refresh() end)
end

local ROW_HEIGHT = 26

function options:CreateDebuffList()
  debuffListFrame = CreateDialog("LoCADebuffListFrame", 340, 440, "Tracked Debuffs")
  debuffListFrame:SetPoint("CENTER", UIParent, "CENTER", 360, 0)

  local hint = debuffListFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", debuffListFrame, "TOPLEFT", 24, -44)
  hint:SetWidth(290)
  hint:SetJustifyH("LEFT")
  hint:SetText("Used in Custom mode. Higher weighted alerts overwrite lower ones.")

  local scroll = CreateFrame("ScrollFrame", "LoCADebuffListScroll", debuffListFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", debuffListFrame, "TOPLEFT", 20, -70)
  scroll:SetPoint("BOTTOMRIGHT", debuffListFrame, "BOTTOMRIGHT", -40, 20)

  local child = CreateFrame("Frame", "LoCADebuffListChild", scroll)
  child:SetWidth(270)
  child:SetHeight(ROW_HEIGHT)
  scroll:SetScrollChild(child)

  debuffListFrame.child = child
  debuffListFrame.rows = {}
  debuffListFrame:SetScript("OnShow", function() options:RefreshDebuffList() end)
end

function options:GetDebuffRow(index)
  local rows = debuffListFrame.rows
  if rows[index] then return rows[index] end

  local child = debuffListFrame.child
  local row = CreateFrame("Frame", nil, child)
  row:SetWidth(270)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

  row.check = CreateFrame("CheckButton", "LoCADebuffRow" .. index .. "Check", row, "UICheckButtonTemplate")
  row.check:SetWidth(22)
  row.check:SetHeight(22)
  row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.check:SetScript("OnClick", function()
    this:GetParent().debuff.active = this:GetChecked() and true or false
    addon.debuffs:NotifyUpdate()
  end)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetWidth(20)
  row.icon:SetHeight(20)
  row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)

  row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.label:SetWidth(130)
  row.label:SetJustifyH("LEFT")

  row.weight = CreateFrame("Button", "LoCADebuffRow" .. index .. "Weight", row, "UIPanelButtonTemplate")
  row.weight:SetWidth(92)
  row.weight:SetHeight(20)
  row.weight:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.weight:SetScript("OnClick", function()
    local debuff = this:GetParent().debuff
    debuff.weight = math.mod(debuff.weight, 4) + 1
    options:UpdateDebuffRow(this:GetParent())
    addon.debuffs:NotifyUpdate()
  end)
  row.weight:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Weight: " .. this:GetParent().debuff.weight .. " - " .. WEIGHT_NAMES[this:GetParent().debuff.weight])
    GameTooltip:AddLine("Click to change. Higher weighted alerts overwrite lower ones.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  row.weight:SetScript("OnLeave", function() GameTooltip:Hide() end)

  rows[index] = row
  return row
end

function options:UpdateDebuffRow(row)
  local debuff = row.debuff
  row.check:SetChecked(debuff.active)
  row.icon:SetTexture(debuff.icon)
  row.label:SetText(debuff.name)
  row.weight:SetText("Weight " .. debuff.weight)
end

function options:RefreshDebuffList()
  if not debuffListFrame then return end
  local list = addon.db.debuffs.debuffsTable
  local count = table.getn(list)
  for i = 1, count do
    local row = options:GetDebuffRow(i)
    row.debuff = list[i]
    options:UpdateDebuffRow(row)
    row:Show()
  end
  for i = count + 1, table.getn(debuffListFrame.rows) do
    debuffListFrame.rows[i]:Hide()
  end
  debuffListFrame.child:SetHeight(math.max(count, 1) * ROW_HEIGHT)
end

function options:ToggleDebuffList()
  if not debuffListFrame then
    options:CreateDebuffList()
  end
  if debuffListFrame:IsShown() then
    debuffListFrame:Hide()
  else
    debuffListFrame:Show()
  end
end

function options:Refresh()
  if not frame then return end
  local db = addon.db.debuffs

  widgets.retail:SetChecked(db.mode == "retail")
  widgets.custom:SetChecked(db.mode == "custom")
  if addon:HasLossOfControlAPI() then
    widgets.retail:Enable()
  else
    widgets.retail:Disable()
  end

  widgets.lock:SetText(addon.debuffs:IsLocked() and "Unlock" or "Lock")

  if db.mode == "custom" then
    widgets.debuffList:Enable()
  else
    widgets.debuffList:Disable()
    if debuffListFrame then debuffListFrame:Hide() end
  end

  widgets.scale.refreshing = true
  widgets.scale:SetValue(db.scale)
  widgets.scale.refreshing = nil
  widgets.alpha.refreshing = true
  widgets.alpha:SetValue(db.alpha)
  widgets.alpha.refreshing = nil
  LoCAOptionsScaleText:SetText("Scale: " .. Round(db.scale))
  LoCAOptionsAlphaText:SetText("Alpha: " .. Round(db.alpha))

  widgets.showRedLines:SetChecked(db.showRedLines)
  widgets.showBackground:SetChecked(db.showBackground)
  widgets.showSecondsLabel:SetChecked(db.showSecondsLabel)

  for i = 1, 4 do
    widgets.types[i]:SetChecked(db.types[i].active)
  end

  options:RefreshDebuffList()
end

function options:OnInitialize()
  if not frame then
    options:CreateFrame()
  end
  options:Refresh()
end

function options:Toggle()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end
