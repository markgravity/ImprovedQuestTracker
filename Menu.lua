local _, IQT = ...

local function IsSortSelected(id)
	return IQT.Settings().sort == id
end

local function IsCompletedSelected(id)
	return IQT.Settings().sortCompleted == id
end

local function IsZoneFirst()
	return IQT.Settings().currentZoneFirst
end

local function ToggleZoneFirst()
	IQT.SetCurrentZoneFirst(not IQT.Settings().currentZoneFirst)
end

local function BuildMenu(rootDescription)
	rootDescription:CreateTitle("Sort Quests")
	for _, s in ipairs(IQT.SORTS) do
		rootDescription:CreateRadio(s.text, IsSortSelected, IQT.SetSort, s.id)
	end
	rootDescription:CreateCheckbox("Current zone first", IsZoneFirst, ToggleZoneFirst)

	rootDescription:CreateDivider()
	rootDescription:CreateTitle("Completed Quests")
	for _, c in ipairs(IQT.COMPLETED) do
		rootDescription:CreateRadio(c.text, IsCompletedSelected, IQT.SetSortCompleted, c.id)
	end
end

-- Frames are created without a parent, then parented (Forever hooks
-- CreateFrame for gamepad navigation; this avoids tainting it).
local function NewFrame(frameType, name, parent, template)
	local f = CreateFrame(frameType, name, nil, template)
	f:SetParent(parent)
	return f
end

-- MoP Classic: extend the native header right-click menu
local function InitWatchFrameMenu()
	Menu.ModifyMenu("MENU_WATCH_FRAME_HEADER", function(owner, rootDescription)
		rootDescription:CreateDivider()
		BuildMenu(rootDescription)
	end)
end

-- Forever: opening Blizzard's Menu from addon code taints the gamepad
-- manager (ADDON_ACTION_FORBIDDEN on SetPreferredGamepadInteractTarget).
-- The header button opens our own dropdown (Dropdown.lua) instead; the
-- options are also added to Blizzard's quest right-click menu, which
-- Blizzard opens itself.
local function InitQuestMenu()
	Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", function(owner, rootDescription)
		rootDescription:CreateDivider()
		local submenu = rootDescription:CreateButton("Sort Quests")
		BuildMenu(submenu)
	end)
end

-- Controller: while the tracker has gamepad focus, show an "R3 Sort" prompt
-- next to Blizzard's footer (ObjectiveTrackerFrame.gamepadFooter) and catch
-- R3 to open our dropdown. We don't add to Blizzard's footer itself: its
-- binding activation would run our data and get tainted.

local LEGEND_PADDING = 10
local ICON_SIZE = 24
local R3_ATLAS = {
	Letters = "Gamepad-Xbox1-Stick-R3-Normal",
	Shapes  = "Gamepad-PS-StickR3-Normal",
	Reverse = "gamepad-switch-128x-stick-r3-normal",
}

local function PadStyle()
	local m = InputDeviceIconSetManager
	local s = m and m.GetActiveInputDeviceIconSet and m:GetActiveInputDeviceIconSet()
	if not s and C_GamePad and C_GamePad.GetDeviceMappedState then
		local st = C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID())
		s = st and st.labelStyle
	end
	return (s == "Shapes" or s == "Reverse") and s or "Letters"
end

local hint, bindingOwner, bindingPending

local function CreateHint()
	local f = NewFrame("Frame", "ImprovedQuestTrackerGamepadHint", UIParent)
	f:SetFrameStrata("HIGH")
	f:Hide()

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetAtlas("gamepad-footer-slot-bg")
	local border = f:CreateTexture(nil, "BORDER")
	border:SetAllPoints()
	border:SetAtlas("gamepad-footer-slot-frameneutral")

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(ICON_SIZE, ICON_SIZE)
	icon:SetPoint("LEFT", LEGEND_PADDING, 0)
	f.icon = icon

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	text:SetText("Sort")
	f.text = text
	return f
end

-- Blizzard's binding stack owns R3 (InputFunctionBindingButton_PADRSTICK, a
-- priority override it re-applies), so an override binding loses. A frame
-- taking pad buttons sees them before any binding: keep R3, pass the rest on.
local function GetListener()
	if bindingOwner then return bindingOwner end
	bindingOwner = NewFrame("Frame", "ImprovedQuestTrackerR3Listener", UIParent)
	bindingOwner:SetScript("OnGamePadButtonDown", function(self, button)
		-- Propagation can't change in combat (the listener is off by then)
		if InCombatLockdown() then return end
		if button == "PADRSTICK" then
			self:SetPropagateKeyboardInput(false)
			IQT.ToggleDropdown(IQT.sortButton)
		else
			self:SetPropagateKeyboardInput(true)
		end
	end)
	bindingOwner:SetScript("OnGamePadButtonUp", function(self, button)
		if InCombatLockdown() then return end
		self:SetPropagateKeyboardInput(button ~= "PADRSTICK")
	end)
	return bindingOwner
end

local function SetR3Binding(on)
	if InCombatLockdown() then
		bindingPending = on
		return
	end
	bindingPending = nil
	local listener = GetListener()
	listener:SetPropagateKeyboardInput(true)
	listener:EnableGamePadButton(on and true or false)
end

local function ShowHint()
	if InCombatLockdown() then return end
	local footer = ObjectiveTrackerFrame.gamepadFooter
	local legend = footer and footer.inputLegend
	if not legend then return end
	local target = legend.promptContainerFrame or legend

	hint = hint or CreateHint()
	local atlas = R3_ATLAS[PadStyle()]
	if C_Texture.GetAtlasInfo(atlas) then
		hint.icon:SetAtlas(atlas)
	end
	hint:SetSize(LEGEND_PADDING * 2 + ICON_SIZE + 4 + hint.text:GetStringWidth(), ICON_SIZE + LEGEND_PADDING * 2)
	hint:ClearAllPoints()
	hint:SetPoint("TOPRIGHT", target, "TOPLEFT", -4, 0)
	hint:Show()
	SetR3Binding(true)
end

local function HideHint()
	if hint then hint:Hide() end
	SetR3Binding(false)
end

local function InitGamepadHint()
	if not (ObjectiveTrackerFrame and ObjectiveTrackerFrame.FocusGamepad) then return end
	hooksecurefunc(ObjectiveTrackerFrame, "FocusGamepad", ShowHint)
	hooksecurefunc(ObjectiveTrackerFrame, "UnfocusGamepad", HideHint)

	local events = NewFrame("Frame", nil, UIParent)
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			-- Still allowed here; stop catching pad buttons for the fight
			if hint then hint:Hide() end
			if bindingOwner and bindingOwner:IsGamePadButtonEnabled() then
				bindingOwner:SetPropagateKeyboardInput(true)
				bindingOwner:EnableGamePadButton(false)
				bindingPending = true
			end
		elseif bindingPending ~= nil then
			local on = bindingPending
			SetR3Binding(on)
			if on and hint then hint:Show() end
		end
	end)
end

-- The "Quests" module header gets a filter button left of its minimize
-- button, using the native tracker button art.
local function InitTrackerButton()
	local header = QuestObjectiveTracker and QuestObjectiveTracker.Header
	if not header or IQT.sortButton then return end

	InitQuestMenu()

	local button = NewFrame("Button", "ImprovedQuestTrackerSortButton", header)
	button:SetSize(18, 19)
	button:SetNormalAtlas("UI-QuestTrackerButton-Filter")
	button:SetPushedAtlas("UI-QuestTrackerButton-Filter-Pressed")
	button:SetHighlightAtlas("UI-QuestTrackerButton-Yellow-Highlight", "ADD")
	if header.MinimizeButton then
		button:SetPoint("RIGHT", header.MinimizeButton, "LEFT", -2, 0)
	else
		button:SetPoint("RIGHT", header, "RIGHT", -20, 0)
	end
	button:SetFrameLevel(header:GetFrameLevel() + 5)
	button:RegisterForClicks("LeftButtonUp")
	button:SetScript("OnClick", function(self)
		GameTooltip:Hide()
		IQT.ToggleDropdown(self)
	end)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Sort Quests")
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	IQT.sortButton = button

	InitGamepadHint()
end

function IQT.InitMenu()
	if not (Menu and MenuUtil) then
		IQT.Print("Menu API not found, use /iqt to change sorting.")
		return
	end
	if IQT.backend == "watchframe" then
		InitWatchFrameMenu()
	elseif QuestObjectiveTracker then
		InitTrackerButton()
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", InitTrackerButton)
	end
end
