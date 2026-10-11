-- Mirra's Group XP - Bars
-- The XP bars: one row per group member with name, level and a rounded bar.

local _, ns = ...
local plain = ns.plain

local PAD           = 6    -- padding around the rows
local LABEL_H       = 14   -- space above each bar for name and level
local LEVEL_W       = 26
local FONT          = "GameFontHighlightSmallOutline"
local MEDIA         = "Interface\\AddOns\\MirrasGroupXP\\media\\"
local OFFLINE_COLOR = { 0.45, 0.45, 0.45 }

local UNITS = { "player", "party1", "party2", "party3", "party4" }

-- Fake party members for /mgxp test
local TEST_DATA = {
    party1 = { name = "Brannoc Steinfaust",       class = "WARRIOR", level = 24, pct = 63.4, rested = 12 },
    party2 = { name = "Elyrienne Sonnenwanderer", class = "PRIEST",  level = 23, pct = 18.9, rested = 40 },
    party3 = { name = "Grimtusk",                 class = "HUNTER",  level = 24, pct = 91.2, rested = 0 },
    party4 = { name = "Mirelle Dornenhain",       class = "MAGE",    level = 22, pct = 47.0, rested = 25 },
}

local container
local rows = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function ClassColor(classFile)
    local c = plain(classFile) and C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Unknown (secret) counts as online.
-- Corner rounding in steps of 10 %; every step has its own frame_<n> and
-- fillcap_<n> texture (pre-rendered, so the gradient stays correct).
local function RoundnessSuffix()
    local r = tonumber(ns.db.roundness) or 100
    return tostring(math.max(0, math.min(100, math.floor(r / 10 + 0.5) * 10)))
end

local function UnitOnline(unit)
    local ok, online = pcall(UnitIsConnected, unit)
    return not ok or plain(online) ~= false
end

------------------------------------------------------------------------
-- Rounded bar. Frame and fill are each built from three pieces (left cap,
-- stretched middle, right cap), so the ends stay round at any width.
-- The textures are grayscale and colored in code.
------------------------------------------------------------------------
local function CreateFill(parent, level)
    local f = CreateFrame("Frame", nil, parent)
    f:SetFrameLevel(level)
    f.capL = f:CreateTexture(nil, "ARTWORK")
    f.capR = f:CreateTexture(nil, "ARTWORK")
    f.capR:SetTexCoord(1, 0, 0, 1)
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetFrameLevel(level)
    f.bar:SetStatusBarTexture(MEDIA .. "fill")
    f.bar:SetMinMaxValues(0, 100)

    function f:SetCapTexture(file)
        self.capL:SetTexture(file)
        self.capR:SetTexture(file)
    end

    function f:SetColor(r, g, b, a)
        a = a or 1
        self.capL:SetVertexColor(r, g, b, a)
        self.capR:SetVertexColor(r, g, b, a)
        self.bar:SetStatusBarColor(r, g, b, a)
    end

    -- The caps are only shown when the bar is (partly / completely) filled.
    function f:SetPercent(pct)
        pct = math.max(0, math.min(100, pct or 0))
        self.bar:SetValue(pct)
        self.capL:SetShown(pct > 0)
        self.capR:SetShown(pct >= 99.95)
    end

    function f:LayoutIn(owner, inset, h)
        local cap = h / 2
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", owner, "TOPLEFT", inset, -inset)
        self:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -inset, inset)
        self.capL:ClearAllPoints()
        self.capL:SetPoint("TOPLEFT", self, "TOPLEFT")
        self.capL:SetSize(cap, h)
        self.capR:ClearAllPoints()
        self.capR:SetPoint("TOPRIGHT", self, "TOPRIGHT")
        self.capR:SetSize(cap, h)
        self.bar:ClearAllPoints()
        self.bar:SetPoint("TOPLEFT", self, "TOPLEFT", cap, 0)
        self.bar:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -cap, 0)
    end
    return f
end

local function CreatePill(parent)
    local p = CreateFrame("Frame", nil, parent)
    local base = p:GetFrameLevel()

    -- frame.tga: left quarter = left cap, middle half = stretched, right quarter = right cap
    p.bgL = p:CreateTexture(nil, "BACKGROUND")
    p.bgL:SetTexCoord(0, 0.25, 0, 1)
    p.bgM = p:CreateTexture(nil, "BACKGROUND")
    p.bgM:SetTexCoord(0.25, 0.75, 0, 1)
    p.bgR = p:CreateTexture(nil, "BACKGROUND")
    p.bgR:SetTexCoord(0.75, 1, 0, 1)

    p.rested = CreateFill(p, base + 1)
    p.fill = CreateFill(p, base + 2)

    -- Text inside the bar, above the fill
    p.textFrame = CreateFrame("Frame", nil, p)
    p.textFrame:SetAllPoints(p)
    p.textFrame:SetFrameLevel(base + 4)
    p.left = p.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.left:SetJustifyH("LEFT")
    p.left:SetShadowOffset(1, -1)
    p.left:SetShadowColor(0, 0, 0, 1)
    p.right = p.textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.right:SetJustifyH("RIGHT")
    p.right:SetShadowOffset(1, -1)
    p.right:SetShadowColor(0, 0, 0, 1)

    function p:LayoutPill(w, h)
        self:SetSize(w, h)
        local cap = h / 2
        self.bgL:ClearAllPoints()
        self.bgL:SetPoint("TOPLEFT", self, "TOPLEFT")
        self.bgL:SetSize(cap, h)
        self.bgR:ClearAllPoints()
        self.bgR:SetPoint("TOPRIGHT", self, "TOPRIGHT")
        self.bgR:SetSize(cap, h)
        self.bgM:ClearAllPoints()
        self.bgM:SetPoint("TOPLEFT", self.bgL, "TOPRIGHT")
        self.bgM:SetPoint("BOTTOMRIGHT", self.bgR, "BOTTOMLEFT")

        local inset = math.max(1, math.floor(h * 0.14 + 0.5))
        local ih = h - inset * 2
        self.rested:LayoutIn(self, inset, ih)
        self.fill:LayoutIn(self, inset, ih)

        -- Font size follows the bar height; no text on very thin bars
        local size = math.max(7, math.min(12, h - 5))
        local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        self.left:SetFont(font, size, "")
        self.right:SetFont(font, size, "")
        local pad = cap + 1
        self.left:ClearAllPoints()
        self.left:SetPoint("LEFT", self, "LEFT", pad, 0)
        self.right:ClearAllPoints()
        self.right:SetPoint("RIGHT", self, "RIGHT", -pad, 0)
        self.textFrame:SetShown(h >= 10)
    end

    -- Textures for the current corner rounding, and the bar colors.
    function p:ApplyStyle()
        local suffix = RoundnessSuffix()
        if self.suffix ~= suffix then
            self.suffix = suffix
            local frameFile = MEDIA .. "frame_" .. suffix
            self.bgL:SetTexture(frameFile)
            self.bgM:SetTexture(frameFile)
            self.bgR:SetTexture(frameFile)
            self.rested:SetCapTexture(MEDIA .. "fillcap_" .. suffix)
            self.fill:SetCapTexture(MEDIA .. "fillcap_" .. suffix)
        end
        self.rested:SetColor(unpack(ns.db.restedColor))
        self:SetGray(self.gray)
    end

    function p:SetGray(gray)
        self.gray = gray
        self.fill:SetColor(unpack(gray and OFFLINE_COLOR or ns.db.barColor))
    end
    return p
end

------------------------------------------------------------------------
-- Row: name and level above the bar
------------------------------------------------------------------------
local function CreateRow(unit)
    local row = CreateFrame("Frame", nil, container)
    row.unit = unit

    row.pill = CreatePill(row)
    row.pill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

    row.level = row:CreateFontString(nil, "ARTWORK", FONT)
    row.level:SetPoint("BOTTOMRIGHT", row.pill, "TOPRIGHT", -2, 2)
    row.level:SetJustifyH("RIGHT")
    row.level:SetWidth(LEVEL_W)
    row.level:SetTextColor(1, 0.82, 0)

    -- Fixed width without word wrap: long names are cut with "..."
    row.name = row:CreateFontString(nil, "ARTWORK", FONT)
    row.name:SetPoint("BOTTOMLEFT", row.pill, "TOPLEFT", 2, 2)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if ns.testMode and self.unit ~= "player" then
            GameTooltip:SetText(TEST_DATA[self.unit].name, 1, 1, 1)
            GameTooltip:AddLine("Test bar", 0.7, 0.7, 0.7)
        else
            GameTooltip:SetText(ns.UnitDisplayName(self.unit) or UnitName(self.unit) or "", 1, 1, 1)
            local text, r, g, b = ns.TooltipLine(self.unit)
            GameTooltip:AddLine(text, r, g, b)
        end
        GameTooltip:AddLine("Ctrl + drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then ns.StartMoving() end
    end)
    row:SetScript("OnMouseUp", function() ns.StopMoving() end)

    return row
end

local function ValueText(cur, max)
    if not cur or not max or max <= 0 then return "" end
    return ns.ShortNumber(cur) .. " / " .. ns.ShortNumber(max)
end

local function UpdateRow(row)
    local unit, pill = row.unit, row.pill

    if ns.testMode and unit ~= "player" then
        local t = TEST_DATA[unit]
        row.name:SetText(t.name)
        row.name:SetTextColor(ClassColor(t.class))
        row.level:SetText(t.level)
        pill:SetGray(false)
        pill.fill:SetPercent(t.pct)
        pill.rested:SetPercent(ns.db.showRested and math.min(100, t.pct + t.rested) or 0)
        pill.left:SetText(format("%.1f%%", t.pct))
        local max = 1000 + t.level * 220
        pill.right:SetText(ValueText(math.floor(max * t.pct / 100), max))
        row:SetAlpha(1)
        return
    end

    -- If the name is secret, UnitDisplayName returns nil; a FontString can
    -- still display the secret value from UnitName directly.
    row.name:SetText(ns.UnitDisplayName(unit) or UnitName(unit) or "")
    local _, classFile = UnitClass(unit)
    row.name:SetTextColor(ClassColor(classFile))

    if not UnitOnline(unit) then
        row.name:SetTextColor(0.6, 0.6, 0.6)
        row.level:SetText("")
        pill:SetGray(true)
        pill.fill:SetPercent(0)
        pill.rested:SetPercent(0)
        pill.left:SetText("Offline")
        pill.right:SetText("")
        row:SetAlpha(0.6)
        return
    end

    local d = ns.GetUnitData(unit)
    local level = plain(UnitLevel(unit)) or (d and d.level)
    row.level:SetText(level or "")
    pill:SetGray(false)

    if d then
        pill.fill:SetPercent(d.pct)
        if d.maxed then
            pill.rested:SetPercent(0)
            pill.left:SetText("Max level")
            pill.right:SetText("")
        else
            local restedPct = 0
            if ns.db.showRested and d.rested and d.max and d.max > 0 then
                restedPct = math.min(100, d.pct + d.rested / d.max * 100)
            end
            pill.rested:SetPercent(restedPct)
            pill.left:SetText(format("%.1f%%", d.pct))
            pill.right:SetText(ValueText(d.cur, d.max))
        end
        row:SetAlpha(1)
    else
        pill.fill:SetPercent(0)
        pill.rested:SetPercent(0)
        pill.left:SetText("No data")
        pill.right:SetText("")
        row:SetAlpha(0.85)
    end
end

------------------------------------------------------------------------
-- Container, layout, position
------------------------------------------------------------------------
function ns.ApplyPosition()
    local p = ns.db.point
    container:ClearAllPoints()
    container:SetPoint(p[1] or "CENTER", UIParent, p[2] or "CENTER", p[3] or 0, p[4] or 0)
end

-- The bars are moved by dragging a row while holding Ctrl.
function ns.StartMoving()
    if not IsControlKeyDown() then return end
    container.isMoving = true
    container:StartMoving()
end

function ns.StopMoving()
    if not container.isMoving then return end
    container.isMoving = false
    container:StopMovingOrSizing()
    local point, _, relPoint, x, y = container:GetPoint()
    ns.db.point = { point, relPoint, x, y }
end

local function RowVisible(unit)
    if unit == "player" then return ns.db.showSelf end
    if ns.testMode then return true end
    local ok, exists = pcall(UnitExists, unit)
    return ok and plain(exists) and true or false
end

function ns.Layout()
    if not container then return end
    local db = ns.db
    container:SetScale(db.scale)

    local y = -PAD
    local anything = false

    for _, unit in ipairs(UNITS) do
        local row = rows[unit]
        if RowVisible(unit) then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", PAD, y)
            row:SetSize(db.width, LABEL_H + db.height)
            row.pill:LayoutPill(db.width, db.height)
            row.pill:ApplyStyle()
            row.name:SetWidth(math.max(20, db.width - LEVEL_W - 8))
            row:Show()
            UpdateRow(row)
            y = y - (LABEL_H + db.height) - db.spacing
            anything = true
        else
            row:Hide()
        end
    end

    container:SetSize(db.width + PAD * 2, math.max(-y - db.spacing + PAD, 30))

    if db.visible and anything then
        container:Show()
    else
        container:Hide()
    end
end

function ns.ToggleTest()
    ns.testMode = not ns.testMode
    ns.Layout()
    ns.Print(ns.testMode and "Test bars shown." or "Test bars hidden.")
end

function ns.InitBars()
    container = CreateFrame("Frame", "MirrasGroupXPFrame", UIParent)
    container:SetClampedToScreen(true)
    container:SetMovable(true)

    for _, unit in ipairs(UNITS) do
        rows[unit] = CreateRow(unit)
    end

    ns.ApplyPosition()
    ns.Layout()

    -- Periodic refresh for changes that fire no event we listen to
    C_Timer.NewTicker(3, function()
        if container:IsShown() then
            for _, unit in ipairs(UNITS) do
                if rows[unit]:IsShown() then UpdateRow(rows[unit]) end
            end
        end
    end)
end
