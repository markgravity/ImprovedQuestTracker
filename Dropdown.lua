local addonName, IQT = ...

-- Our own dropdown, styled like the native Menu (Blizzard_Menu MenuStyle1 /
-- MenuVariants). Blizzard's Menu can't be opened from addon code on Forever:
-- it switches the gamepad binding set inside our call and the protected
-- SetPreferredGamepadInteractTarget gets blocked. This frame never touches
-- the gamepad manager; controller input is read directly.

local ROW_HEIGHT = 20
local INSET = { left = 8, top = 8, right = 8, bottom = 15 }
local PAD_WIDTH = 20

local dropdown, rows, entries, anchorFrame
local focusIndex
local downSeen = {}

local function NewFrame(frameType, name, parent, template)
	local f = CreateFrame(frameType, name, nil, template)
	f:SetParent(parent)
	return f
end

---------------------------------------------------------------------------
-- Controller glyphs (InputIconTexture atlases per label style)
---------------------------------------------------------------------------

local GLYPHS = {
	Letters = { dpad = "gamepad-xbox1-dpadall-normal", select = "gamepad-xbox1-buttona-normal", close = "gamepad-xbox1-buttonb-normal" },
	Shapes  = { dpad = "gamepad-ps-dpadall-normal", select = "gamepad-ps-buttoncrox-normal", close = "gamepad-ps-buttoncircle-normal" },
	Reverse = { dpad = "gamepad-switch-128x-dpad-all-normal", select = "gamepad-switch-128x-face-b-normal", close = "gamepad-switch-128x-face-a-normal" },
}

local function GamepadActive()
	return C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()
end

local function Style()
	local m = InputDeviceIconSetManager
	local s = m and m.GetActiveInputDeviceIconSet and m:GetActiveInputDeviceIconSet()
	if not s and C_GamePad and C_GamePad.GetDeviceMappedState then
		local st = C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID())
		s = st and st.labelStyle
	end
	return (s == "Shapes" or s == "Reverse") and s or "Letters"
end

local function Glyph(key)
	local atlas = GLYPHS[Style()][key]
	if C_Texture.GetAtlasInfo(atlas) then
		return "|A:"..atlas..":16:16|a"
	end
	return ""
end

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------

local function BuildEntries()
	local list = {}
	list[#list + 1] = { kind = "title", text = "Sort Quests" }
	for _, s in ipairs(IQT.SORTS) do
		list[#list + 1] = {
			kind = "radio", text = s.text,
			isSelected = function() return IQT.Settings().sort == s.id end,
			onSelect = function() IQT.SetSort(s.id) end,
		}
	end
	list[#list + 1] = {
		kind = "checkbox", text = "Current zone first",
		isSelected = function() return IQT.Settings().currentZoneFirst end,
		onSelect = function() IQT.SetCurrentZoneFirst(not IQT.Settings().currentZoneFirst) end,
	}
	list[#list + 1] = { kind = "divider" }
	list[#list + 1] = { kind = "title", text = "Completed Quests" }
	for _, c in ipairs(IQT.COMPLETED) do
		list[#list + 1] = {
			kind = "radio", text = c.text,
			isSelected = function() return IQT.Settings().sortCompleted == c.id end,
			onSelect = function() IQT.SetSortCompleted(c.id) end,
		}
	end
	list[#list + 1] = { kind = "divider" }
	list[#list + 1] = {
		kind = "checkbox", text = "Objective complete sound",
		isSelected = function() return IQT.Settings().objectiveSound end,
		onSelect = function() IQT.SetObjectiveSound(not IQT.Settings().objectiveSound) end,
	}
	return list
end

local function Selectable(entry)
	return entry and (entry.kind == "radio" or entry.kind == "checkbox")
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function RefreshRow(row)
	local entry = row.entry
	if Selectable(entry) then
		row.check:SetShown(entry.isSelected())
	end
	row.highlight:SetShown(row.index == focusIndex)
end

local function Refresh()
	for _, row in ipairs(rows) do
		RefreshRow(row)
	end
end

local function SetFocus(index)
	focusIndex = index
	Refresh()
end

local function Activate(index)
	local entry = entries[index]
	if not Selectable(entry) then return end
	entry.onSelect()
	if entry.kind == "checkbox" then
		PlaySound(entry.isSelected() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	else
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end
	Refresh()
end

local function CreateRow(parent, index, entry)
	local row = NewFrame("Button", nil, parent)
	row.index = index
	row.entry = entry

	if entry.kind == "divider" then
		row:SetHeight(13)
		local divider = row:CreateTexture(nil, "ARTWORK")
		divider:SetPoint("LEFT")
		divider:SetPoint("RIGHT")
		divider:SetHeight(13)
		divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
		row:EnableMouse(false)
	else
		row:SetHeight(ROW_HEIGHT)
	end

	local highlight = row:CreateTexture(nil, "BACKGROUND")
	highlight:SetAllPoints()
	highlight:SetBlendMode("ADD")
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	highlight:Hide()
	row.highlight = highlight

	local text = row:CreateFontString(nil, "ARTWORK", entry.kind == "title" and "GameFontNormal" or "GameFontHighlight")
	text:SetHeight(ROW_HEIGHT)
	text:SetJustifyH("LEFT")
	text:SetText(entry.text or "")
	row.text = text

	if entry.kind == "radio" then
		local tick = row:CreateTexture(nil, "ARTWORK")
		tick:SetAtlas("common-dropdown-tickradial", true)
		tick:SetPoint("LEFT", -3, 0)
		local check = row:CreateTexture(nil, "OVERLAY")
		check:SetAtlas("common-dropdown-icon-radialtick-yellow", true)
		check:SetPoint("TOPLEFT", tick, "TOPLEFT")
		row.check = check
		text:SetPoint("LEFT", tick, "RIGHT", 1, 0)
		row.contentWidth = tick:GetWidth() - 3 + 1 + text:GetStringWidth()
	elseif entry.kind == "checkbox" then
		local tick = row:CreateTexture(nil, "ARTWORK")
		tick:SetAtlas("common-dropdown-ticksquare", true)
		tick:SetPoint("LEFT")
		local check = row:CreateTexture(nil, "OVERLAY")
		check:SetAtlas("common-dropdown-icon-checkmark-yellow", true)
		check:SetPoint("CENTER", tick, "CENTER", 2, 1)
		row.check = check
		text:SetPoint("LEFT", tick, "RIGHT", 7, 1)
		row.contentWidth = tick:GetWidth() + 7 + text:GetStringWidth()
	else
		text:SetPoint("LEFT")
		row.contentWidth = text:GetStringWidth()
	end

	if Selectable(entry) then
		row:RegisterForClicks("LeftButtonUp")
		row:SetScript("OnEnter", function(self) SetFocus(self.index) end)
		row:SetScript("OnLeave", function(self)
			if focusIndex == self.index and not GamepadActive() then
				SetFocus(nil)
			end
		end)
		row:SetScript("OnClick", function(self) Activate(self.index) end)
	else
		row:EnableMouse(false)
	end

	return row
end

---------------------------------------------------------------------------
-- Controller navigation
---------------------------------------------------------------------------

local function MoveFocus(step)
	local n = #entries
	local i = focusIndex or (step > 0 and 0 or n + 1)
	for _ = 1, n do
		i = i + step
		if i < 1 then i = n elseif i > n then i = 1 end
		if Selectable(entries[i]) then
			SetFocus(i)
			return
		end
	end
end

local function FirstSelectedIndex()
	for i, entry in ipairs(entries) do
		if Selectable(entry) and entry.kind == "radio" and entry.isSelected() then
			return i
		end
	end
end

local function OnGamePadButtonDown(self, button)
	downSeen[button] = true
	if button == "PADDUP" then
		MoveFocus(-1)
	elseif button == "PADDDOWN" then
		MoveFocus(1)
	elseif button == "PAD1" then
		if focusIndex then
			Activate(focusIndex)
		end
	end
end

local function OnGamePadButtonUp(self, button)
	-- Only act on releases whose press we saw (the press that opened the
	-- dropdown must not close it), and close on release so it doesn't leak.
	if not downSeen[button] then return end
	downSeen[button] = nil
	if button == "PAD2" then
		IQT.HideDropdown()
	end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function CreateDropdown()
	local f = NewFrame("Frame", "ImprovedQuestTrackerDropdown", UIParent)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:Hide()

	local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAtlas("common-dropdown-bg")
	bg:SetPoint("TOPLEFT", -10, 3)
	bg:SetPoint("BOTTOMRIGHT", 10, -3)
	bg:SetAlpha(0.925)

	local hint = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", INSET.left, 6)
	hint:SetJustifyH("LEFT")
	f.hint = hint

	entries = BuildEntries()
	rows = {}
	local width, height = 0, INSET.top
	local previous
	for i, entry in ipairs(entries) do
		local row = CreateRow(f, i, entry)
		if previous then
			row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT")
		else
			row:SetPoint("TOPLEFT", INSET.left, -INSET.top)
		end
		row:SetPoint("RIGHT", -INSET.right, 0)
		width = math.max(width, row.contentWidth)
		height = height + row:GetHeight()
		rows[i] = row
		previous = row
	end
	f.baseWidth = width + PAD_WIDTH + INSET.left + INSET.right
	f.baseHeight = height + INSET.bottom

	f:SetScript("OnGamePadButtonDown", OnGamePadButtonDown)
	f:SetScript("OnGamePadButtonUp", OnGamePadButtonUp)
	f:SetScript("OnHide", function(self)
		self:EnableGamePadButton(false)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		self:UnregisterEvent("PLAYER_REGEN_DISABLED")
		wipe(downSeen)
	end)
	f:SetScript("OnEvent", function(self, event)
		if event == "GLOBAL_MOUSE_DOWN" then
			if not self:IsMouseOver() and not (anchorFrame and anchorFrame:IsMouseOver()) then
				self:Hide()
			end
		elseif event == "PLAYER_REGEN_DISABLED" then
			self:Hide()
		end
	end)

	-- Escape closes it like other windows
	tinsert(UISpecialFrames, f:GetName())
	return f
end

function IQT.ShowDropdown(anchor)
	if InCombatLockdown() then
		IQT.Print("Not available in combat.")
		return
	end
	dropdown = dropdown or CreateDropdown()
	anchorFrame = anchor

	local gamepad = GamepadActive()
	local width, height = dropdown.baseWidth, dropdown.baseHeight
	if gamepad then
		dropdown.hint:SetText(Glyph("dpad").." Move   "..Glyph("select").." Select   "..Glyph("close").." Close")
		dropdown.hint:Show()
		width = math.max(width, dropdown.hint:GetStringWidth() + INSET.left + INSET.right)
		height = height + 16
	else
		dropdown.hint:Hide()
	end
	dropdown:SetSize(width, height)

	dropdown:ClearAllPoints()
	if anchor then
		dropdown:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
	else
		dropdown:SetPoint("CENTER")
	end

	focusIndex = gamepad and FirstSelectedIndex() or nil
	wipe(downSeen)
	dropdown:Show()
	Refresh()
	dropdown:EnableGamePadButton(gamepad and true or false)
	dropdown:RegisterEvent("GLOBAL_MOUSE_DOWN")
	dropdown:RegisterEvent("PLAYER_REGEN_DISABLED")
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

function IQT.HideDropdown()
	if dropdown and dropdown:IsShown() then
		dropdown:Hide()
	end
end

function IQT.ToggleDropdown(anchor)
	if dropdown and dropdown:IsShown() then
		IQT.HideDropdown()
	else
		IQT.ShowDropdown(anchor or IQT.sortButton)
	end
end

-- Key binding (Bindings.xml)
BINDING_HEADER_IMPROVEDQUESTTRACKER = "Improved Quest Tracker"
BINDING_NAME_IMPROVEDQUESTTRACKER_TOGGLE = "Toggle sort menu"

function ImprovedQuestTracker_ToggleDropdown()
	local anchor = IQT.sortButton
	if anchor and not anchor:IsVisible() then
		anchor = nil
	end
	IQT.ToggleDropdown(anchor)
end
