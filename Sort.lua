local _, IQT = ...

local tsort = table.sort
local strlower = string.lower

-- WatchFrame (MoP Classic) draws quests in watch-list order: we reorder the
-- watch list with ShiftQuestWatches, like Blizzard's "Move Up/Down".
-- ObjectiveTracker (Forever) has no shift API: we re-anchor its quest blocks
-- after each layout, and when the tracker is full (it only lays out the
-- watches that fit, in watch order) we also move watches by remove + re-add
-- (AddQuestWatch appends), so the quests that fit are the top-sorted ones.

local pending = false
local suppressHooks = false

---------------------------------------------------------------------------
-- Backend: WatchFrame (MoP Classic)
---------------------------------------------------------------------------

local WatchFrameBackend = {}

function WatchFrameBackend.Collect()
	local headers, current = {}, nil
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, isHeader = GetQuestLogTitle(i)
		if isHeader then
			current = title
		else
			headers[i] = current
		end
	end

	local playerZone = GetRealZoneText() or ""
	local playerMap = C_Map.GetBestMapForUnit("player")
	local money = GetMoney()
	local list = {}

	for i = 1, GetNumQuestWatches() do
		local questIndex = GetQuestIndexForWatch(i)
		if questIndex then
			local title, level, _, _, _, isComplete, _, questID, startEvent = GetQuestLogTitle(questIndex)
			local numObjectives = GetNumQuestLeaderBoards(questIndex)
			local completed = (isComplete == 1)
				or (numObjectives == 0 and money >= GetQuestLogRequiredMoney(questIndex) and not startEvent)
			local zone = headers[questIndex] or ""
			local inZone = (zone == playerZone)
				or (questID and playerMap and GetQuestUiMapID(questID) == playerMap)
			list[#list + 1] = {
				key = questIndex,
				questID = questID or 0,
				title = strlower(title or ""),
				level = level or 0,
				zone = zone,
				inZone = inZone and true or false,
				completed = completed and true or false,
			}
		end
	end
	return list
end

-- Native sort must be "Manual" or Blizzard reorders on top of us
local function EnsureNativeManual()
	if WATCHFRAME_SORT_TYPE ~= WATCHFRAME_SORT_MANUAL then
		suppressHooks = true
		WatchFrame_SetSorting(WATCHFRAME_SORT_MANUAL)
		suppressHooks = false
	end
end

function WatchFrameBackend.Apply(list)
	EnsureNativeManual()
	local changed = false
	for pos, q in ipairs(list) do
		local cur = GetQuestWatchIndex(q.key)
		if cur and cur ~= pos then
			ShiftQuestWatches(cur, pos)
			changed = true
		end
	end
	if changed then
		WatchFrame_Update()
	end
end

function WatchFrameBackend.Init()
	-- Picking a Blizzard sort option hands control back to Blizzard
	hooksecurefunc("WatchFrame_SetSorting", function()
		if not suppressHooks then
			IQT.Disable("Blizzard sort selected, custom sort turned off.")
		end
	end)
	-- Moving a quest by hand means the user wants a manual order
	hooksecurefunc("WatchFrame_MoveQuest", function()
		IQT.Disable("Quest moved by hand, custom sort turned off.")
	end)
end

---------------------------------------------------------------------------
-- Backend: ObjectiveTracker (Forever / modern C_QuestLog)
---------------------------------------------------------------------------

local TrackerBackend = {}

-- Squared distance to the quest's POI; quests off this continent or without
-- a POI sort last.
local function DistanceTo(questID)
	local distanceSq, onContinent = C_QuestLog.GetDistanceSqToQuest(questID)
	if distanceSq and onContinent then
		return distanceSq
	end
	return math.huge
end

function TrackerBackend.Collect()
	local infoByID, headers, current = {}, {}, nil
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info then
			if info.isHeader then
				current = info.title
			elseif info.questID then
				infoByID[info.questID] = info
				headers[info.questID] = current
			end
		end
	end

	local playerZone = GetRealZoneText() or ""
	local list = {}

	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		if questID then
			local info = infoByID[questID]
			local zone = headers[questID] or ""
			local title = (info and info.title) or C_QuestLog.GetTitleForQuestID(questID) or ""
			local level = info and (info.level or info.difficultyLevel) or 0
			local completed = C_QuestLog.IsComplete(questID) or C_QuestLog.ReadyForTurnIn(questID)
			-- Like WatchFrame / Kaliel's Tracker: no objectives = ready to hand in
			local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
			if not completed and logIndex and GetNumQuestLeaderBoards(logIndex) == 0
					and GetMoney() >= (C_QuestLog.GetRequiredMoney(questID) or 0)
					and not (info and info.startEvent) then
				completed = true
			end
			local inZone = (zone == playerZone) or (info and info.isOnMap)
			list[#list + 1] = {
				key = questID,
				questID = questID,
				title = strlower(title),
				level = level,
				zone = zone,
				inZone = inZone and true or false,
				distance = DistanceTo(questID),
				completed = completed and true or false,
			}
		end
	end
	return list
end

local function QuestName(questID)
	return C_QuestLog.GetTitleForQuestID(questID) or tostring(questID)
end

local function IsQuestBlock(module, block)
	local blocks = module.usedBlocks and module.usedBlocks[module.blockTemplate]
	return blocks and block.id and blocks[block.id] == block
end

-- Blocks in the order Blizzard laid them out (read only, never written)
local function BlockChain(module)
	local chain = {}
	local block = module.firstBlock
	while block and #chain < 200 do
		chain[#chain + 1] = block
		block = block.nextBlock
	end
	return chain
end

-- Same anchors as ObjectiveTrackerModuleMixin:AnchorBlock. Only frame points
-- change; Blizzard's own fields (firstBlock, nextBlock...) stay untouched.
local function AnchorChain(module, order)
	local previous
	for _, block in ipairs(order) do
		block:ClearAllPoints()
		if previous then
			block:SetPoint("TOP", previous, "BOTTOM", 0, module.fromBlockOffsetY)
		else
			block:SetPoint("TOP", module.ContentsFrame, "TOP", 0, module.fromHeaderOffsetY)
		end
		block:SetPoint("LEFT", block.offsetX or module.blockOffsetX, 0)
		if not block.fixedWidth then
			block:SetPoint("RIGHT")
		end
		previous = block
	end
end

local function CurrentWatchOrder()
	local ids = {}
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		ids[i] = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
	end
	return ids
end

local attemptedSignature
local lastWatchMove = 0
local DISTANCE_WATCH_MOVE_INTERVAL = 30

-- Move watches so the watch order matches the sort. Two passes (remove,
-- then re-add next frame: same-frame remove + add can leave a quest
-- unwatched), each sorted order tried once, and any quest that ends up
-- unwatched is re-added.
local function ReorderWatches(list)
	if IQT.reordering or InCombatLockdown() then return end
	local current = CurrentWatchOrder()
	local first
	for pos, q in ipairs(list) do
		if current[pos] ~= q.key then
			first = pos
			break
		end
	end
	if not first then return end

	local signature = {}
	for i, q in ipairs(list) do signature[i] = q.key end
	signature = table.concat(signature, ",")
	if signature == attemptedSignature then return end
	if IQT.Settings().sort == "distance" and GetTime() - lastWatchMove < DISTANCE_WATCH_MOVE_INTERVAL then
		return
	end
	attemptedSignature = signature
	lastWatchMove = GetTime()

	local toMove = {}
	for pos = first, #list do
		toMove[#toMove + 1] = list[pos].key
	end

	IQT.reordering = true
	for _, questID in ipairs(toMove) do
		C_QuestLog.RemoveQuestWatch(questID)
	end
	C_Timer.After(0, function()
		for _, questID in ipairs(toMove) do
			C_QuestLog.AddQuestWatch(questID)
		end
		C_Timer.After(1, function()
			IQT.reordering = false
			for _, questID in ipairs(current) do
				if C_QuestLog.GetQuestWatchType(questID) == nil then
					C_QuestLog.AddQuestWatch(questID)
				end
			end
		end)
	end)
end

-- Quest blocks take the sorted order; other blocks (auto-quest pop-ups)
-- keep their slots.
function TrackerBackend.Apply(list)
	local module = QuestObjectiveTracker
	if not module then return end
	local chain = BlockChain(module)
	if #chain < 2 then return end

	local order = chain
	if IQT.IsActive() then
		local rank = {}
		for i, q in ipairs(list) do
			rank[q.key] = i
		end
		local quests = {}
		for _, block in ipairs(chain) do
			if IsQuestBlock(module, block) and rank[block.id] then
				quests[#quests + 1] = block
			end
		end
		tsort(quests, function(a, b) return rank[a.id] < rank[b.id] end)

		order = {}
		local q = 1
		for i, block in ipairs(chain) do
			if IsQuestBlock(module, block) and rank[block.id] then
				order[i] = quests[q]
				q = q + 1
			else
				order[i] = block
			end
		end
	end
	local names = {}
	for i, block in ipairs(order) do
		names[i] = tostring(block.id)
	end
	local signature = table.concat(names, ",")
	if signature ~= IQT.lastOrder or module.firstBlock ~= IQT.lastFirstBlock then
		AnchorChain(module, order)
	end
	IQT.lastOrder = signature
	IQT.lastFirstBlock = module.firstBlock

	-- Tracker full: make Blizzard lay out the top-sorted quests
	if IQT.IsActive() and module.hasSkippedBlocks and not module:IsCollapsed() then
		-- not from inside Blizzard's layout pass
		C_Timer.After(0, function() ReorderWatches(list) end)
	end

end

-- Quest blocks the native tracker is currently showing, by questID
local function ShownQuestBlocks()
	local shown = {}
	local module = QuestObjectiveTracker
	if module and module.usedBlocks then
		for _, blocks in pairs(module.usedBlocks) do
			for id, block in pairs(blocks) do
				if block:IsShown() then
					shown[id] = true
				end
			end
		end
	end
	return shown
end

function IQT.Debug()
	if IQT.backend ~= "tracker" then
		IQT.Print("backend: "..tostring(IQT.backend))
		return
	end
	local module = QuestObjectiveTracker
	local shown = ShownQuestBlocks()
	local completed = {}
	for _, q in ipairs(TrackerBackend.Collect()) do
		completed[q.key] = q.completed
	end
	IQT.Print("R3 binding: "..tostring(GetBindingAction("PADRSTICK", true)))
	IQT.Print(("layouts hooked %d, last applied order: %s"):format(IQT.layoutCount or 0, IQT.lastOrder or "none"))
	IQT.Print(("watches %d, availableHeight %s, contentsHeight %s, skipped %s, collapsed %s"):format(
		C_QuestLog.GetNumQuestWatches(),
		tostring(module and module.availableHeight), tostring(module and module.contentsHeight),
		tostring(module and module.hasSkippedBlocks), tostring(module and module:IsCollapsed())))
	for i = 1, C_QuestLog.GetNumQuestWatches() do
		local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
		IQT.Print(("%d. %s [%s] complete=%s shown=%s"):format(i, QuestName(questID), tostring(questID),
			tostring(completed[questID] or false), tostring(shown[questID] or false)))
	end
end

local function HookTracker()
	-- Runs after every native layout of the quest module; the hook's taint
	-- doesn't spread into Blizzard's update.
	hooksecurefunc(QuestObjectiveTracker, "LayoutContents", function()
		IQT.layoutCount = (IQT.layoutCount or 0) + 1
		IQT.SortNow()
	end)
	IQT.SortNow()
end

function TrackerBackend.Init()
	-- The tracker doesn't re-layout as you move; refresh distance order
	C_Timer.NewTicker(2, function()
		if IQT.Settings().sort == "distance" and QuestObjectiveTracker and QuestObjectiveTracker:IsVisible() then
			IQT.SortNow()
		end
	end)
	if QuestObjectiveTracker then
		HookTracker()
	elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
		EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", HookTracker)
	end
end

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------

local function ByTitle(a, b)
	if a.title ~= b.title then
		return a.title < b.title
	end
	return a.questID < b.questID
end

local COMPARATORS = {
	zone = function(a, b)
		if IQT.Settings().currentZoneFirst and a.inZone ~= b.inZone then
			return a.inZone
		end
		if a.zone ~= b.zone then
			return a.zone < b.zone
		end
		if a.level ~= b.level then
			return a.level < b.level
		end
		return ByTitle(a, b)
	end,
	level = function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return ByTitle(a, b)
	end,
	levelReversed = function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return ByTitle(a, b)
	end,
	title = ByTitle,
	distance = function(a, b)
		local da, db = a.distance or math.huge, b.distance or math.huge
		if da ~= db then
			return da < db
		end
		return ByTitle(a, b)
	end,
}

-- Stable move of completed quests to the top or bottom
local function PlaceCompleted(list, where)
	local done, open = {}, {}
	for _, q in ipairs(list) do
		if q.completed then
			done[#done + 1] = q
		else
			open[#open + 1] = q
		end
	end
	local first, second = open, done
	if where == "top" then
		first, second = done, open
	end
	local result = {}
	for _, q in ipairs(first) do result[#result + 1] = q end
	for _, q in ipairs(second) do result[#result + 1] = q end
	return result
end

local function Backend()
	return IQT.backend == "watchframe" and WatchFrameBackend or TrackerBackend
end

function IQT.SortNow()
	local watchFrame = IQT.backend == "watchframe"
	-- The tracker backend also runs when inactive, to restore Blizzard's order
	if (watchFrame and not IQT.IsActive()) or IQT.forbidden then return end
	-- Never change the watch list in combat; PLAYER_REGEN_ENABLED sorts again
	if watchFrame and InCombatLockdown() then return end
	local db = IQT.Settings()

	local list = Backend().Collect()

	local cmp = COMPARATORS[db.sort]
	if cmp then
		tsort(list, cmp)
	end
	if db.sortCompleted ~= "none" then
		list = PlaceCompleted(list, db.sortCompleted)
	end

	Backend().Apply(list)
end

function IQT.RequestSort()
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		IQT.SortNow()
	end)
end

function IQT.OnCombatEnd()
	IQT.RequestSort()
end

function IQT.SetSort(id)
	IQT.Settings().sort = id
	attemptedSignature = nil
	IQT.RequestSort()
end

function IQT.SetSortCompleted(id)
	IQT.Settings().sortCompleted = id
	attemptedSignature = nil
	IQT.RequestSort()
end

function IQT.SetCurrentZoneFirst(on)
	IQT.Settings().currentZoneFirst = on and true or false
	IQT.RequestSort()
end

function IQT.Disable(reason)
	local db = IQT.Settings()
	if db.sort == "none" and db.sortCompleted == "none" then return end
	db.sort = "none"
	db.sortCompleted = "none"
	if reason then
		IQT.Print(reason)
	end
end

function IQT.InitSort()
	Backend().Init()
end
