local addonName, IQT = ...

IQT.name = addonName

-- Sort modes (nil/"none" = leave the native tracker sort alone)
IQT.SORTS = {
	{ id = "none",          text = "Off (Blizzard sort)" },
	{ id = "zone",          text = "by Zone" },
	{ id = "level",         text = "by Level" },
	{ id = "levelReversed", text = "by Level (reversed)" },
	{ id = "title",         text = "by Title" },
	{ id = "distance",      text = "by Distance" },
}

IQT.COMPLETED = {
	{ id = "none",   text = "Keep in place" },
	{ id = "top",    text = "Completed at top" },
	{ id = "bottom", text = "Completed at bottom" },
}

local DEFAULTS = {
	sort = "none",
	sortCompleted = "none",
	currentZoneFirst = true,
}

function IQT.Settings()
	ImprovedQuestTrackerDB = ImprovedQuestTrackerDB or {}
	local db = ImprovedQuestTrackerDB
	for k, v in pairs(DEFAULTS) do
		if db[k] == nil then
			db[k] = v
		end
	end
	return db
end

function IQT.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Improved Quest Tracker|r: "..msg)
end

function IQT.IsActive()
	local db = IQT.Settings()
	return db.sort ~= "none" or db.sortCompleted ~= "none"
end

local frame = CreateFrame("Frame")
IQT.eventFrame = frame

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local addon, func = ...
		if addon == addonName then
			IQT.forbidden = true
			IQT.Print(event.." on "..tostring(func)..". Reordering stopped until /reload.")
		end
	elseif event == "PLAYER_LOGIN" then
		IQT.Settings()
		if WatchFrame and ShiftQuestWatches then
			IQT.backend = "watchframe"
		elseif C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex and C_QuestLog.AddQuestWatch then
			IQT.backend = "tracker"
		else
			IQT.Print("No supported quest tracker found, addon disabled.")
			return
		end
		-- Distance sort needs the native quest POI distance (Forever); the
		-- WatchFrame backend can't refresh order as you move either
		if IQT.backend ~= "tracker" or not C_QuestLog.GetDistanceSqToQuest then
			for i, entry in ipairs(IQT.SORTS) do
				if entry.id == "distance" then
					tremove(IQT.SORTS, i)
					break
				end
			end
			if IQT.Settings().sort == "distance" then
				IQT.Settings().sort = "none"
			end
		end
		IQT.InitSort()
		IQT.InitMenu()
		self:RegisterEvent("QUEST_LOG_UPDATE")
		self:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
		self:RegisterEvent("QUEST_ACCEPTED")
		self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		IQT.RequestSort()
	elseif event == "PLAYER_REGEN_ENABLED" then
		IQT.OnCombatEnd()
	else
		IQT.RequestSort()
	end
end)
