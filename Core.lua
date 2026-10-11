-- Mirra's Group XP - Core
-- Saved settings, XP sync between group members, chat commands and
-- level-up announcements.

local ADDON, ns = ...

ns.TITLE  = "Mirra's Group XP"
ns.PREFIX = "MSGXP" -- kept from earlier versions so mixed versions still sync

ns.defaults = {
    dbVersion    = 5,
    visible      = true,
    showSelf     = true,
    showRested   = true,
    tooltip      = true,
    chatCommands = true,
    announce     = true,
    announceMsg  = "Ding! Leveled up to [level]!",
    width        = 200,
    height       = 14,
    scale        = 1.15,
    spacing      = 6,
    -- Colors as { r, g, b, a }; the textures are grayscale and tinted with these.
    barColor     = { 0.78, 0.22, 0.92, 1 },
    restedColor  = { 0.30, 0.55, 1.00, 0.65 },
    borderColor  = { 0.51, 0.51, 0.53, 1 },
    bgColor      = { 0.133, 0.133, 0.133, 1 },
    point        = { "CENTER", "CENTER", 0, 0 },
}

-- XP of other group members, keyed by GUID and by name key (see StoreData).
-- Values: { level, cur, max, rested, pct, maxed }
ns.data = {}
ns.testMode = false

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
-- WoW Forever uses the Midnight "secret value" restrictions: some values
-- can't be read, compared or used as keys by addon code.
local issecret = issecretvalue or function() return false end

-- Returns v if addon code may read it, otherwise nil.
local function plain(v)
    if issecret(v) then return nil end
    return v
end
ns.plain = plain

-- tostring() that never touches a secret value (for status/debug output).
local function Safe(v)
    if issecret(v) then return "<secret>" end
    return tostring(v)
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb04fe0Mirra's Group XP|r: " .. msg)
end
ns.Print = Print

local debugEnabled = false
local function Debug(msg)
    if debugEnabled then
        DEFAULT_CHAT_FRAME:AddMessage("|cff888888[Mirra's Group XP debug]|r " .. msg)
    end
end

local function Refresh()
    if ns.Layout then ns.Layout() end
end

function ns.ShortNumber(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return format("%.1fm", n / 1000000) end
    if n >= 1000 then return format("%.1fk", n / 1000) end
    return tostring(n)
end

------------------------------------------------------------------------
-- Identity
-- Forever characters have a first name and a surname. UnitName() returns
-- them as two values, while chat events report the sender as one string
-- ("First Surname", sometimes with "-Realm"). Data is therefore stored by
-- GUID (sent inside each message) and, as a fallback, by a "squashed"
-- name key: lower case without spaces, hyphens and apostrophes.
------------------------------------------------------------------------
local function Squash(s)
    s = plain(s)
    if type(s) ~= "string" or s == "" then return nil end
    return (s:lower():gsub("[%s%-']", ""))
end

-- All plausible name keys for a chat sender string.
local function SenderKeys(sender)
    sender = plain(sender)
    if type(sender) ~= "string" or sender == "" then return {} end
    local keys = { Squash(sender) }
    local noRealm = sender:match("^(.+)%-[^%-]+$")
    if noRealm then keys[#keys + 1] = Squash(noRealm) end
    return keys
end

local function UnitGUIDSafe(unit)
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and plain(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

-- "First Surname" (or just the first name if there is no surname).
function ns.UnitDisplayName(unit)
    local ok, name, surname = pcall(UnitName, unit)
    if not ok then return nil end
    name, surname = plain(name), plain(surname)
    if type(name) ~= "string" or name == "" then return nil end
    if type(surname) == "string" and surname ~= "" then
        return name .. " " .. surname
    end
    return name
end

local function UnitNameKey(unit)
    return Squash(ns.UnitDisplayName(unit))
end

local function IsMe(guid, sender)
    local myGUID = UnitGUIDSafe("player")
    if guid and guid ~= "" and myGUID then return guid == myGUID end
    local myName = UnitNameKey("player")
    for _, k in ipairs(SenderKeys(sender)) do
        if k == myName then return true end
    end
    return false
end

local function StoreData(guid, sender, d)
    if guid and guid ~= "" then ns.data[guid] = d end
    for _, k in ipairs(SenderKeys(sender)) do ns.data[k] = d end
end

------------------------------------------------------------------------
-- XP data
------------------------------------------------------------------------
local function IsMaxLevel()
    if IsXPUserDisabled() then return true end
    return UnitLevel("player") >= GetMaxPlayerLevel() or UnitXPMax("player") <= 0
end

local function GetMyXP()
    local cur    = plain(UnitXP("player")) or 0
    local max    = plain(UnitXPMax("player")) or 0
    local rested = plain(GetXPExhaustion()) or 0
    local maxed  = IsMaxLevel()
    return {
        level = plain(UnitLevel("player")) or 0,
        cur = cur, max = max, rested = rested, maxed = maxed,
        pct = maxed and 100 or (max > 0 and cur / max * 100 or 0),
    }
end

-- Reply to !xp. Same format as the original GroupXP, so LearnFromReply
-- can also read answers from people using the old addon.
local function XPString()
    local d = GetMyXP()
    if d.maxed then
        return "Level: " .. d.level .. " XP: max level"
    end
    return format("Level: %d XP: %s of %s [%.1f%%]",
        d.level, ns.ShortNumber(d.cur), ns.ShortNumber(d.max), d.pct)
end

-- XP data for a unit token, nil if unknown.
function ns.GetUnitData(unit)
    local ok, isMe = pcall(UnitIsUnit, unit, "player")
    if ok and plain(isMe) then return GetMyXP() end
    local guid = UnitGUIDSafe(unit)
    if guid and ns.data[guid] then return ns.data[guid] end
    local key = UnitNameKey(unit)
    return key and ns.data[key]
end

local function AnyMemberUnknown()
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) and plain(UnitIsConnected(unit)) and not ns.GetUnitData(unit) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Sending
------------------------------------------------------------------------
local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function ChatLocked()
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and plain(locked) and true or false
end

local function SendChat(msg, chatType, target)
    if not chatType or ChatLocked() then return end
    pcall(C_ChatInfo.SendChatMessage, msg, chatType, nil, target)
end

local function SendBNet(bnetID, msg)
    if not bnetID or ChatLocked() then return end
    pcall(C_BattleNet.SendWhisper, bnetID, msg)
end

-- Counters for /mgxp status
local stats = { sent = 0, sendFailed = 0, received = 0, chatLearned = 0 }

local commsWarned = false
local function SendAddon(msg, chatType)
    if not chatType then return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, msg, chatType)
    result = plain(result)
    -- Returns Enum.SendAddonMessageResult (0 = success); older clients return nothing
    local success = ok and (result == nil or result == true or result == 0)
    stats.lastResult = ok and tostring(result) or "error"
    if success then
        stats.sent = stats.sent + 1
    else
        stats.sendFailed = stats.sendFailed + 1
    end
    Debug(format("send %s via %s -> %s", msg, chatType, stats.lastResult))
    if not success and not commsWarned then
        commsWarned = true
        Print("Addon messages are blocked right now. Party members can still type |cffffff00!xp|r in party chat - their answers fill the bars too.")
    end
end

-- Message formats:
--   "R"                                       request: everybody answers with X
--   "X:level:cur:max:rested:maxed:guid"       XP data
local broadcastPending, lastBroadcast = false, 0
local function BroadcastXP()
    if broadcastPending or not GroupChannel() then return end
    broadcastPending = true
    -- Debounced: XP ticks in quick succession result in one message.
    local delay = math.max(1.5, 4 - (GetTime() - lastBroadcast))
    C_Timer.After(delay, function()
        broadcastPending = false
        local d = GetMyXP()
        lastBroadcast = GetTime()
        SendAddon(format("X:%d:%d:%d:%d:%d:%s", d.level, d.cur, d.max, d.rested,
            d.maxed and 1 or 0, UnitGUIDSafe("player") or ""), GroupChannel())
    end)
end

local requestPending = false
local function RequestXP()
    if requestPending or not GroupChannel() then return end
    requestPending = true
    C_Timer.After(1, function()
        requestPending = false
        SendAddon("R", GroupChannel())
    end)
end

------------------------------------------------------------------------
-- Receiving
------------------------------------------------------------------------
local function OnAddonMessage(prefix, text, channel, sender)
    if plain(prefix) ~= ns.PREFIX then return end
    text = plain(text)
    Debug(format("recv %s from %s (%s)", Safe(text), Safe(sender), Safe(channel)))
    if type(text) ~= "string" then return end

    if text == "R" then
        if not IsMe(nil, sender) then BroadcastXP() end
        return
    end
    -- The GUID part is optional (versions before 1.0.2 did not send it)
    local level, cur, max, rested, maxed, guid = text:match("^X:(%d+):(%d+):(%d+):(%d+):(%d):?(.*)$")
    if not level or IsMe(guid, sender) then return end

    stats.received = stats.received + 1
    stats.lastFrom = Safe(sender)
    cur, max, maxed = tonumber(cur), tonumber(max), maxed == "1"
    StoreData(guid, sender, {
        level = tonumber(level), cur = cur, max = max, rested = tonumber(rested), maxed = maxed,
        pct = maxed and 100 or (max > 0 and cur / max * 100 or 0),
    })
    Refresh()
end

local function ParseShort(s) -- "1.2k" -> 1200
    local n, suffix = s:match("^([%d%.]+)([km]?)$")
    n = tonumber(n) or 0
    if suffix == "k" then n = n * 1000 elseif suffix == "m" then n = n * 1000000 end
    return math.floor(n + 0.5)
end

-- Answers to !xp in group chat also fill the bars. This works when addon
-- messages are blocked and for people still using the old GroupXP.
local function LearnFromReply(msg, sender, guid)
    guid = plain(guid)
    if type(guid) ~= "string" then guid = nil end
    if IsMe(guid, sender) then return end

    local d
    local level, cur, max, pct = msg:match("^Level: (%d+) XP: ([%d%.km]+) of ([%d%.km]+) %[([%d%.]+)%%%]")
    if level then
        d = { level = tonumber(level), cur = ParseShort(cur), max = ParseShort(max),
              rested = 0, pct = tonumber(pct) or 0, maxed = false }
    else
        level = msg:match("^Level: (%d+) XP: max level")
        if level then
            d = { level = tonumber(level), cur = 0, max = 0, rested = 0, pct = 100, maxed = true }
        end
    end
    if d then
        stats.chatLearned = stats.chatLearned + 1
        Debug("learned from chat reply of " .. Safe(sender))
        StoreData(guid, sender, d)
        Refresh()
    end
end

------------------------------------------------------------------------
-- Chat commands: !xp, !count <item>, !roll [max | min max]
------------------------------------------------------------------------
-- Arguments like /roll: "" = 1-100, "50" = 1-50, "10 50" or "10-50" = 10-50.
-- Returns nil for anything else.
local function ParseRoll(args)
    args = strtrim(args or "")
    if args == "" then return 1, 100 end
    local low, high = args:match("^(%d+)%s*[%s%-]%s*(%d+)$")
    if not low then
        low, high = 1, args:match("^(%d+)$")
    end
    low, high = tonumber(low), tonumber(high)
    if not high or low > high or high > 1000000 then return nil end
    return low, high
end

-- replyType: "PARTY", "INSTANCE_CHAT", "WHISPER" or "BNET"
local function HandleChat(msg, replyType, sender, bnetID, guid)
    msg = plain(msg)
    if type(msg) ~= "string" then return end
    msg = strtrim(msg)

    local isWhisper = replyType == "WHISPER" or replyType == "BNET"
    if not isWhisper then LearnFromReply(msg, sender, guid) end
    if not ns.db.chatCommands then return end

    local function Reply(out)
        if replyType == "BNET" then
            SendBNet(bnetID, out)
        elseif replyType == "WHISPER" then
            SendChat(out, "WHISPER", plain(sender))
        else
            SendChat(out, replyType)
        end
    end

    local lower = msg:lower()
    if lower == "!xp" then
        if isWhisper then
            Print("|cff00ff00" .. (plain(sender) or "Someone") .. " requested your experience.|r")
        end
        Reply(XPString())
    elseif lower:sub(1, 7) == "!count " then
        local item = strtrim(msg:sub(8))
        if item == "" then return end
        local ok, count = pcall(C_Item.GetItemCount, item)
        Reply("I have " .. (ok and plain(count) or 0) .. "x " .. item)
    elseif not isWhisper and (lower == "!roll" or lower:sub(1, 6) == "!roll ") then
        local low, high = ParseRoll(lower:sub(7))
        if low then pcall(RandomRoll, low, high) end
    end
end

local function OnLevelUp(level)
    level = plain(level) or plain(UnitLevel("player"))
    if not ns.db.announce or not level then return end
    local text = ns.db.announceMsg
    if type(text) ~= "string" or strtrim(text) == "" then return end
    SendChat((text:gsub("%[level%]", tostring(level))), GroupChannel())
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------
function ns.TooltipLine(unit)
    local d = ns.GetUnitData(unit)
    if not d then return "XP: no data", 0.6, 0.6, 0.6 end
    if d.maxed then return "XP: max level", 0.8, 0.5, 1 end
    local line = format("XP: %s / %s (%.1f%%)", ns.ShortNumber(d.cur), ns.ShortNumber(d.max), d.pct)
    if d.rested and d.rested > 0 then
        line = line .. format("  |cff4f9fffRested %s|r", ns.ShortNumber(d.rested))
    end
    return line, 0.8, 0.5, 1
end

local function OnUnitTooltip(tooltip)
    if not ns.db.tooltip or tooltip ~= GameTooltip then return end
    pcall(function()
        local _, unit = tooltip:GetUnit()
        unit = plain(unit)
        if not unit or not UnitIsPlayer(unit) then return end
        if not (UnitIsUnit(unit, "player") or UnitInParty(unit) or UnitInRaid(unit)) then return end
        tooltip:AddLine(ns.TooltipLine(unit))
    end)
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Updates settings saved by an older version. Old default values are
-- replaced by the new ones; values the user changed are kept.
local function Migrate(db)
    if next(db) == nil then return end
    if (db.dbVersion or 1) < 4 then
        if db.width == 170 then db.width = 200 end
        if db.scale == 1 then db.scale = 1.15 end
    end
    db.locked, db.segments = nil, nil -- removed options
    db.dbVersion = ns.defaults.dbVersion
end

ns.COLOR_KEYS = { "barColor", "restedColor", "borderColor", "bgColor" }

function ns.ResetColors()
    for _, key in ipairs(ns.COLOR_KEYS) do
        ns.db[key] = nil
    end
    CopyDefaults(ns.defaults, ns.db)
    ns.Layout()
    ns.RefreshOptions()
end

function ns.ResetSettings()
    wipe(ns.db)
    CopyDefaults(ns.defaults, ns.db)
    ns.ApplyPosition()
    ns.Layout()
    ns.RefreshOptions()
    Print("Settings reset to defaults.")
end

local function PrintStatus()
    local ok, restricted = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
    Print(format("Group channel: %s | prefix registered: %s | outgoing restricted flag: %s",
        tostring(GroupChannel()), tostring(stats.prefixResult), ok and Safe(restricted) or "n/a"))
    Print(format("Sent: %d ok, %d failed (last result: %s) | received: %d (last from %s) | from chat replies: %d",
        stats.sent, stats.sendFailed, tostring(stats.lastResult), stats.received,
        tostring(stats.lastFrom), stats.chatLearned))
    Print("You: " .. Safe(ns.UnitDisplayName("player")) .. "  GUID " .. tostring(UnitGUIDSafe("player")))
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local d = ns.GetUnitData(unit)
            Print(format("%s: %s  GUID %s  online %s  -> %s", unit, Safe(ns.UnitDisplayName(unit)),
                tostring(UnitGUIDSafe(unit)), Safe(UnitIsConnected(unit)),
                d and format("%.1f%%", d.pct) or "|cffff5555no data|r"))
        end
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local wasInGroup = false
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    -- Created here, not at file scope, so saved data is never overwritten.
    if type(MirrasGroupXPDB) ~= "table" then MirrasGroupXPDB = {} end
    Migrate(MirrasGroupXPDB)
    CopyDefaults(ns.defaults, MirrasGroupXPDB)
    ns.db = MirrasGroupXPDB

    local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, ns.PREFIX)
    stats.prefixResult = ok and Safe(res) or "error"

    -- Keep asking while a party member has no data yet (lost messages,
    -- or someone installed the addon later).
    C_Timer.NewTicker(20, function()
        if IsInGroup() and AnyMemberUnknown() then RequestXP() end
    end)

    if TooltipDataProcessor then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
    end
    ns.InitBars()
    ns.InitOptions()
    frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_ENTERING_WORLD()
    wasInGroup = IsInGroup()
    if wasInGroup then
        BroadcastXP()
        RequestXP()
    end
    Refresh()
end

function handlers.GROUP_ROSTER_UPDATE()
    local inGroup = IsInGroup()
    if inGroup then
        if not wasInGroup then BroadcastXP() end
        if AnyMemberUnknown() then RequestXP() end
    end
    wasInGroup = inGroup
    Refresh()
end

function handlers.PLAYER_XP_UPDATE(unit)
    if plain(unit) ~= "player" then return end
    BroadcastXP()
    Refresh()
end

function handlers.UPDATE_EXHAUSTION()
    BroadcastXP()
    Refresh()
end

function handlers.PLAYER_LEVEL_UP(level)
    if IsInGroup() then OnLevelUp(level) end
    BroadcastXP()
    Refresh()
end

handlers.UNIT_CONNECTION  = Refresh
handlers.UNIT_LEVEL       = Refresh
handlers.UNIT_NAME_UPDATE = Refresh

function handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
    OnAddonMessage(prefix, text, channel, sender)
end

-- Chat events: arg1 = text, arg2 = sender, arg12 = sender GUID, arg13 = Battle.net ID
function handlers.CHAT_MSG_PARTY(msg, sender, ...)               HandleChat(msg, "PARTY", sender, nil, select(10, ...)) end
function handlers.CHAT_MSG_PARTY_LEADER(msg, sender, ...)        HandleChat(msg, "PARTY", sender, nil, select(10, ...)) end
function handlers.CHAT_MSG_INSTANCE_CHAT(msg, sender, ...)       HandleChat(msg, "INSTANCE_CHAT", sender, nil, select(10, ...)) end
function handlers.CHAT_MSG_INSTANCE_CHAT_LEADER(msg, sender, ...) HandleChat(msg, "INSTANCE_CHAT", sender, nil, select(10, ...)) end
function handlers.CHAT_MSG_WHISPER(msg, sender)                  HandleChat(msg, "WHISPER", sender) end
function handlers.CHAT_MSG_BN_WHISPER(msg, sender, ...)          HandleChat(msg, "BNET", sender, plain((select(11, ...)))) end

frame:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)

-- On Forever, registering an event the client does not know raises an
-- error and would abort the whole file.
for event in pairs(handlers) do
    pcall(frame.RegisterEvent, frame, event)
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_MIRRASGROUPXP1 = "/mgxp"
SLASH_MIRRASGROUPXP2 = "/groupxp"
SLASH_MIRRASGROUPXP3 = "/gxp"
SlashCmdList.MIRRASGROUPXP = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "test" then
        ns.ToggleTest()
    elseif msg == "show" or msg == "hide" then
        ns.db.visible = (msg == "show")
        ns.Layout()
        ns.RefreshOptions()
    elseif msg == "request" then
        RequestXP()
        Print("Requested XP from your group.")
    elseif msg == "status" then
        PrintStatus()
    elseif msg == "debug" then
        debugEnabled = not debugEnabled
        Print("Debug output " .. (debugEnabled and "on" or "off") .. ".")
    elseif msg == "reset" then
        ns.ResetSettings()
    elseif msg == "help" then
        Print("/mgxp - open settings (Ctrl + drag the bars to move them)")
        Print("/mgxp test - toggle test bars")
        Print("/mgxp show | hide - show or hide the bars")
        Print("/mgxp request - ask your group for their XP")
        Print("/mgxp status - show sync status of your group")
        Print("/mgxp debug - toggle sync debug messages")
        Print("/mgxp reset - reset all settings")
    else
        ns.OpenOptions()
    end
end
