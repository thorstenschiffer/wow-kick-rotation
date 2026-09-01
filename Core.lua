-- Shows the group's current kick-rotation number above every raid-marked nameplate.
--
-- Why it is built this way (Midnight 12.x secret values):
--   * GetRaidTargetIndex() returns an OPAQUE secret for a marked unit and plain
--     nil for an unmarked one. A presence test (~= nil) is legal; reading which
--     marker it is, is not. So any marker qualifies -- we cannot tell them apart.
--   * The unit's NPC ID is unreachable (unit identity is secret), so mobs cannot
--     be filtered by type. The marker, set by a human, is the filter.
--   * notInterruptible is a secret boolean and cannot be tested. UNIT_SPELLCAST_
--     INTERRUPTIBLE firing is the substitute: the event itself is the information.
--   * The counter is our own local number, so displaying it is unrestricted.
--
-- No addon communication: every client derives the same number from the same
-- events. A client that misses an event stays one behind until the next pull,
-- which is why the counter resets when combat ends.

local DEFAULT_KICKERS = 3
local BOX_SIZE, BOX_OFFSET_Y = 36, 18

-- The box sits on top of whatever the world looks like, so contrast comes from
-- a near-opaque dark plate; the border colour carries the cast state.
local BACKDROP = { 0.04, 0.04, 0.05, 0.92 }
local IDLE = { 0.60, 0.45, 0.15, 1 }
local ACTIVE = { 1.00, 0.75, 0.20, 1 }

local current = 1
local boxes = {}    -- unit token -> frame
local tracked = {}  -- unit token -> true
local casting = {}  -- unit token -> true while an interruptible cast is up

local function Kickers()
	local n = KickRotationDB and tonumber(KickRotationDB.kickers)
	return (n and n >= 1) and n or DEFAULT_KICKERS
end

local function IsNameplate(unit)
	return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function AcquireBox(unit)
	local box = boxes[unit]
	if box then return box end

	box = CreateFrame("Frame", nil, UIParent)
	box:SetSize(BOX_SIZE, BOX_SIZE)
	box:SetFrameStrata("HIGH")

	box.border = box:CreateTexture(nil, "BACKGROUND", nil, -2)
	box.border:SetPoint("TOPLEFT", -2, 2)
	box.border:SetPoint("BOTTOMRIGHT", 2, -2)

	box.bg = box:CreateTexture(nil, "BACKGROUND", nil, -1)
	box.bg:SetAllPoints()
	box.bg:SetColorTexture(unpack(BACKDROP))

	box.label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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

	local c = casting[unit] and ACTIVE or IDLE
	box.border:SetColorTexture(c[1], c[2], c[3], c[4])
	box.label:SetText(current)
	box:Show()
end

local function RefreshAll()
	for unit in pairs(tracked) do
		Refresh(unit)
	end
end

local function Advance()
	current = current % Kickers() + 1
	RefreshAll()
end

function KickRotation_Reset()
	current = 1
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
	tracked[unit], casting[unit] = nil, nil
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
		Advance()
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
function handlers.PLAYER_REGEN_ENABLED()
	KickRotation_Reset()
end

function handlers.ADDON_LOADED(name)
	if name ~= "KickRotation" then return end
	KickRotationDB = KickRotationDB or {}
	KickRotationDB.kickers = tonumber(KickRotationDB.kickers) or DEFAULT_KICKERS
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
		KickRotationDB.kickers = floor(n)
		KickRotation_Reset()
		print("|cffffcc00KickRotation|r kickers set to " .. KickRotationDB.kickers .. ".")
		return
	end
	if msg == "reset" then
		KickRotation_Reset()
		print("|cffffcc00KickRotation|r reset to 1.")
		return
	end
	print("|cffffcc00KickRotation|r /kickrot <n> sets the number of kickers (now "
		.. Kickers() .. "), /kickrot reset sets the counter back to 1.")
end
