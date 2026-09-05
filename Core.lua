-- Shows the group's current kick-rotation number above every raid-marked nameplate.
--
-- Why it is built this way (Midnight 12.x secret values):
--   * GetRaidTargetIndex() returns an OPAQUE secret for a marked unit and plain
--     nil for an unmarked one. A presence test (~= nil) is legal; reading which
--     marker it is, is not. So any marker qualifies -- we cannot tell them apart.
--   * The unit's NPC ID is unreachable (unit identity is secret), so mobs cannot
--     be filtered by type. The marker, set by a human, is the filter. Secrecy is
--     not combat-gated here: in a key everything is secret from the moment the
--     keystone is activated, so there is no pre-pull window to read identity in.
--   * notInterruptible is a secret boolean and cannot be tested. UNIT_SPELLCAST_
--     INTERRUPTIBLE firing is the substitute: the event itself is the information.
--   * The counter is our own local number, so displaying it is unrestricted.
--
-- No addon communication: every client derives the same number from the same
-- events. A client that misses an event stays one behind until the next pull,
-- which is why the counter resets when combat ends.

local DEFAULT_KICKERS = 3
local PREFIX = "KickRot"
local ROSTER_WINDOW = 3   -- seconds to collect replies after a ready check
local OWN_KICK_WINDOW = 0.7
local BOX_SIZE, BOX_OFFSET_Y = 36, 18

-- Red plate, white border, white text. The border stays white, so the cast
-- state is carried by how bright the red is.
local BORDER = { 1, 1, 1, 1 }
local IDLE = { 0.50, 0.04, 0.04, 0.92 }
local ACTIVE = { 0.92, 0.11, 0.11, 0.96 }
local MINE = { 0.10, 0.55, 0.12, 0.95 }    -- your turn, your kick is ready
local MINE_CD = { 0.28, 0.28, 0.30, 0.92 } -- your turn, but your kick is down
local FLASH = { 0.30, 1.00, 0.35, 1 }      -- your interrupt just landed

-- Nameplates sit low and overlap each other constantly. DIALOG lifts the box
-- clear of all of them; SetFixedFrameStrata stops the nameplate parent from
-- pulling it back down, and the high level sorts it above sibling boxes.
local STRATA, LEVEL = "DIALOG", 6200

local current = 1   -- global mode: the one number everybody sees
local nextStart = 1 -- per-mob mode: start number handed to the next marked mob
local counters = {} -- per-mob mode: unit token -> that mob's number
local boxes = {}    -- unit token -> frame
local tracked = {}  -- unit token -> true
local casting = {}  -- unit token -> true while an interruptible cast is up

-- Created on first use rather than in ADDON_LOADED, which had to compare against
-- the addon's folder name -- and that name is whatever the user's unzip produced.
-- Only ever called from event handlers and the slash command, so the saved table
-- has already been restored by the time this runs.
local function DB()
	if type(KickRotationDB) ~= "table" then
		KickRotationDB = {}
	end
	return KickRotationDB
end

local function Kickers()
	local n = tonumber(DB().kickers)
	return (n and n >= 1) and n or DEFAULT_KICKERS
end

-- Your own cooldown: startTime and duration may be secret, but isActive is
-- flagged NeverSecret, so the ready/down decision is allowed even in a key.
-- The secret numbers still render, because SetCooldown accepts secrets.
local function MyCooldown()
	local id = DB().spellID
	if not id then return nil end
	return C_Spell.GetSpellCooldown(id)
end

local function Mode()
	return DB().mode == "global" and "global" or "per-mob"
end

-- The number to show on one nameplate. In per-mob mode a newly marked mob is
-- handed the next start number, so two marked mobs never open on the same
-- kicker. Note the side effect: first call for a unit assigns its counter.
local function Number(unit)
	if Mode() == "global" then return current end

	local n = counters[unit]
	if not n then
		n = nextStart
		counters[unit] = n
		nextStart = nextStart % Kickers() + 1
	end
	return n
end

local function IsNameplate(unit)
	return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function AcquireBox(unit)
	local box = boxes[unit]
	if box then return box end

	box = CreateFrame("Frame", nil, UIParent)
	box:SetSize(BOX_SIZE, BOX_SIZE)

	box.border = box:CreateTexture(nil, "BACKGROUND", nil, -2)
	box.border:SetPoint("TOPLEFT", -2, 2)
	box.border:SetPoint("BOTTOMRIGHT", 2, -2)

	box.bg = box:CreateTexture(nil, "BACKGROUND", nil, -1)
	box.bg:SetAllPoints()

	box.border:SetColorTexture(unpack(BORDER))

	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	box.cd = CreateFrame("Cooldown", nil, box, "CooldownFrameTemplate")
	box.cd:SetAllPoints()
	box.cd:SetDrawEdge(false)
	box.cd:Hide()

	box.label:SetPoint("CENTER")
	box.label:SetTextColor(1, 1, 1)
	local font = box.label:GetFont()
	box.label:SetFont(font, 22, "OUTLINE")

	boxes[unit] = box
	return box
end

local function Refresh(unit)
	local box = boxes[unit]

	-- Presence test only: the index itself is secret and must not be read.
	if not tracked[unit] or GetRaidTargetIndex(unit) == nil then
		if box then box:Hide() end
		return
	end

	local plate = C_NamePlate.GetNamePlateForUnit(unit)
	if not plate then
		if box then box:Hide() end
		return
	end

	box = AcquireBox(unit)
	box:SetParent(plate)
	box:ClearAllPoints()
	box:SetPoint("BOTTOM", plate, "TOP", 0, BOX_OFFSET_Y)

	-- Reapplied after every SetParent: parenting can reset both of these.
	box:SetFrameStrata(STRATA)
	if box.SetFixedFrameStrata then
		box:SetFixedFrameStrata(true)
	end
	box:SetFrameLevel(LEVEL)

	local n = Number(unit)
	local isMine = DB().position == n
	local cd = isMine and MyCooldown() or nil
	local onCooldown = cd and cd.isActive == true

	local c
	if isMine then
		c = onCooldown and MINE_CD or MINE
	else
		c = casting[unit] and ACTIVE or IDLE
	end
	box.bg:SetColorTexture(c[1], c[2], c[3], c[4])

	if cd and onCooldown then
		box.cd:SetCooldown(cd.startTime, cd.duration)
		box.cd:Show()
	else
		box.cd:Hide()
	end

	box.label:SetText(n)
	box:Show()
end

local function RefreshAll()
	for unit in pairs(tracked) do
		Refresh(unit)
	end
end

local lastOwnCast = { spellID = nil, at = 0 }
local learnSeen = {}

-- Rather than ship a class table of interrupt IDs that goes stale every patch,
-- the addon watches for its own cast landing on a mob's interrupt. Two sightings
-- of the same spell are required, so one coincidence does not lock in the wrong
-- one. Works for any class, spec and locale.
local function LearnInterrupt(spellID)
	learnSeen[spellID] = (learnSeen[spellID] or 0) + 1
	if learnSeen[spellID] < 2 then return end

	DB().spellID = spellID
	local info = C_Spell.GetSpellInfo(spellID)
	print("|cffffcc00KickRotation|r learned your interrupt: "
		.. ((info and info.name) or spellID) .. ". Cooldown display is active.")
end

-- Your cast succeeded and a mob's cast ended in the same moment, so it was
-- yours. interruptedBy would say so outright, but it is secret and cannot be
-- compared against you.
local function OnMobInterrupted(unit)
	if not lastOwnCast.spellID or GetTime() - lastOwnCast.at > OWN_KICK_WINDOW then return end

	if not DB().spellID then
		LearnInterrupt(lastOwnCast.spellID)
		return
	end
	if lastOwnCast.spellID ~= DB().spellID then return end

	local box = boxes[unit]
	if not box then return end
	box.border:SetColorTexture(unpack(FLASH))
	C_Timer.After(0.6, function()
		if boxes[unit] then boxes[unit].border:SetColorTexture(unpack(BORDER)) end
	end)
end

local function Advance(unit)
	if Mode() == "global" then
		current = current % Kickers() + 1
		RefreshAll()
		return
	end

	local n = counters[unit]
	if n then
		counters[unit] = n % Kickers() + 1
		Refresh(unit)
	end
end

function KickRotation_Reset()
	current, nextStart, counters = 1, 1, {}
	RefreshAll()
end

local handlers = {}

function handlers.NAME_PLATE_UNIT_ADDED(unit)
	if IsNameplate(unit) then
		tracked[unit] = true
		Refresh(unit)
	end
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
	-- The token is a slot, not a mob: once it is released its counter is gone.
	tracked[unit], casting[unit], counters[unit] = nil, nil, nil
	local box = boxes[unit]
	if box then
		box:Hide()
		box:SetParent(UIParent)
	end
end

function handlers.RAID_TARGET_UPDATE()
	RefreshAll()
end

-- A cast begins with START/CHANNEL_START. INTERRUPTIBLE only fires when a cast
-- CHANGES to interruptible mid-flight, so it cannot be the sole trigger -- it is
-- an additional state update on top of an already-started cast.
local function CastStarted(unit)
	if IsNameplate(unit) then
		casting[unit] = true
		Refresh(unit)
	end
end

function handlers.UNIT_SPELLCAST_START(unit) CastStarted(unit) end
function handlers.UNIT_SPELLCAST_CHANNEL_START(unit) CastStarted(unit) end
function handlers.UNIT_SPELLCAST_INTERRUPTIBLE(unit) CastStarted(unit) end

-- An interrupt, a failed cast and a quiet failure are indistinguishable here,
-- so every early end of a cast advances the rotation.
local function CastEnded(unit, advance)
	if not IsNameplate(unit) then return end
	local wasCasting = casting[unit]
	casting[unit] = nil
	if advance and wasCasting then
		OnMobInterrupted(unit)
		Advance(unit)
	else
		Refresh(unit)
	end
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit) CastEnded(unit, true) end
function handlers.UNIT_SPELLCAST_FAILED(unit) CastEnded(unit, true) end
function handlers.UNIT_SPELLCAST_FAILED_QUIET(unit) CastEnded(unit, true) end
function handlers.UNIT_SPELLCAST_STOP(unit) CastEnded(unit, false) end
function handlers.UNIT_SPELLCAST_CHANNEL_STOP(unit) CastEnded(unit, false) end

-- Leaving combat resyncs everyone: a client that missed an event would
-- otherwise stay off by one for the rest of the dungeon.
function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
	if unit ~= "player" or issecretvalue(spellID) then return end
	lastOwnCast.spellID, lastOwnCast.at = spellID, GetTime()
end

function handlers.SPELL_UPDATE_COOLDOWN()
	if DB().position then RefreshAll() end
end

-- Ready check: the last moment before the key starts, and the only window in
-- which addon messaging is allowed -- it is locked down once a run is underway.
-- Everyone announces themselves, everyone sorts the same names, so every client
-- derives the same assignment with nobody configuring anything.
local roster = {}
local rosterPending = false

local function AnnounceRoster()
	rosterPending = false

	local names = {}
	for name in pairs(roster) do names[#names + 1] = name end
	sort(names)
	if #names == 0 then return end

	local me = UnitName("player")
	DB().kickers = #names
	for i, name in ipairs(names) do
		if name == me then DB().position = i end
	end

	print("|cffffcc00KickRotation|r " .. #names .. " in the group have the addon:")
	for i, name in ipairs(names) do
		print(format("  %d. %s%s", i, name, (name == me) and "  <-- you" or ""))
	end
	RefreshAll()
end

function handlers.READY_CHECK()
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		print("|cffffcc00KickRotation|r addon messaging is locked down -- "
			.. "run the ready check before the key is started.")
		return
	end

	roster = { [UnitName("player")] = true }
	if not rosterPending then
		rosterPending = true
		C_Timer.After(ROSTER_WINDOW, AnnounceRoster)
	end
	C_ChatInfo.SendAddonMessage(PREFIX, "HI:" .. UnitName("player"), "PARTY")
end

function handlers.CHAT_MSG_ADDON(prefix, text)
	if prefix ~= PREFIX then return end
	local name = text:match("^HI:(.+)$")
	if name then roster[name] = true end
end

function handlers.PLAYER_REGEN_ENABLED()
	KickRotation_Reset()
end

if C_ChatInfo.RegisterAddonMessagePrefix then
	C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)

BINDING_HEADER_KICKROTATION = "Kick Rotation"
BINDING_NAME_KICKROTATION_RESET = "Reset to 1"

SLASH_KICKROTATION1 = "/kickrot"
SlashCmdList.KICKROTATION = function(msg)
	local n = tonumber(msg)
	if n and n >= 1 then
		DB().kickers = floor(n)
		KickRotation_Reset()
		print("|cffffcc00KickRotation|r kickers set to " .. Kickers() .. ".")
		return
	end
	local cmd, rest = msg:match("^(%S+)%s+(.+)$")

	if cmd == "me" then
		local pos = tonumber(rest)
		if pos and pos >= 1 then
			DB().position = floor(pos)
			RefreshAll()
			print("|cffffcc00KickRotation|r you are kicker " .. DB().position .. ".")
			return
		end
	end

	if cmd == "spell" then
		-- Accepts a name or an ID, so no interrupt IDs have to be hardcoded.
		local info = C_Spell.GetSpellInfo(tonumber(rest) or rest)
		if not info then
			print("|cffffcc00KickRotation|r no spell found for '" .. rest .. "'.")
			return
		end
		DB().spellID = info.spellID
		RefreshAll()
		print("|cffffcc00KickRotation|r your interrupt: " .. info.name .. " (" .. info.spellID .. ").")
		return
	end

	if msg == "mode global" or msg == "mode mob" then
		DB().mode = (msg == "mode global") and "global" or "per-mob"
		KickRotation_Reset()
		print("|cffffcc00KickRotation|r mode: " .. Mode() .. ".")
		return
	end
	if msg == "reset" then
		KickRotation_Reset()
		print("|cffffcc00KickRotation|r reset to 1.")
		return
	end
	local me = DB().position and ("kicker " .. DB().position) or "not set"
	local spell = DB().spellID and (C_Spell.GetSpellInfo(DB().spellID) or {}).name or "not set"
	print("|cffffcc00KickRotation|r kickers: " .. Kickers() .. ", mode: " .. Mode()
		.. ", you: " .. me .. ", your interrupt: " .. spell)
	print("  /kickrot <n>  kicker count   |  /kickrot me <n>  your own position")
	print("  /kickrot spell <name|id>  your interrupt, for the cooldown display")
	print("  /kickrot mode global|mob  |  /kickrot reset")
end
