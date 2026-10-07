local _, IQT = ...

-- Play a sound when an objective of a tracked quest completes. Ported from
-- the markgravity/kaliels-tracker mod, which played UI_QuesTrollingForward_01
-- from the objective line's completion glow; here the same sound kit is played
-- when a quest log update flips an objective from unfinished to finished.

local SOUND = SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 43936

-- questID -> { [objectiveIndex] = finished }
local objectives = {}

-- Tracked quests as questID -> questLogIndex, for either tracker
local function TrackedQuests()
	local quests = {}
	if IQT.backend == "watchframe" then
		for i = 1, GetNumQuestWatches() do
			local questIndex = GetQuestIndexForWatch(i)
			if questIndex then
				local questID = select(8, GetQuestLogTitle(questIndex))
				if questID then
					quests[questID] = questIndex
				end
			end
		end
	else
		for i = 1, C_QuestLog.GetNumQuestWatches() do
			local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
			local questIndex = questID and C_QuestLog.GetLogIndexForQuestID(questID)
			if questIndex then
				quests[questID] = questIndex
			end
		end
	end
	return quests
end

-- A quest seen for the first time (login, newly tracked) is only recorded;
-- the sound needs an objective we saw unfinished before.
local function Scan()
	local completed = false
	local current = {}
	for questID, questIndex in pairs(TrackedQuests()) do
		local previous = objectives[questID]
		local states = {}
		for i = 1, GetNumQuestLeaderBoards(questIndex) do
			local _, _, finished = GetQuestLogLeaderBoard(i, questIndex)
			states[i] = finished
			if finished and previous and previous[i] == false then
				completed = true
			end
		end
		current[questID] = states
	end
	objectives = current

	if completed and IQT.Settings().objectiveSound then
		PlaySound(SOUND, "Master")
	end
end

function IQT.SetObjectiveSound(on)
	IQT.Settings().objectiveSound = on and true or false
end

function IQT.InitObjectiveSound()
	local frame = CreateFrame("Frame")
	frame:RegisterEvent("QUEST_LOG_UPDATE")
	frame:SetScript("OnEvent", Scan)
	Scan()
end
