-- Mirra's Group XP - Options
-- Settings panel under Options -> AddOns.

local _, ns = ...

local panel, category
local controls = {}

------------------------------------------------------------------------
-- Widgets. Every widget registers a Refresh function in `controls`, which
-- loads its value from ns.db when the panel is shown.
------------------------------------------------------------------------
local function AddTooltip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CreateHeader(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    return fs
end

local function CreateCheck(parent, label, tooltip, key, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)

    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    fs:SetText(label)
    cb:SetHitRectInsets(0, -260, 0, 0) -- label is clickable too

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        ns.db[key] = checked
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if onChange then onChange(checked) end
    end)
    AddTooltip(cb, label, tooltip)
    cb.Refresh = function() cb:SetChecked(ns.db[key] and true or false) end
    table.insert(controls, cb)
    return cb
end

local function Round(v, step)
    return math.floor(v / step + 0.5) * step
end

local function CreateSlider(parent, label, key, minV, maxV, step, fmt, onChange)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(280, 44)

    local title = holder:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    title:SetText(label)

    local function Set(v)
        v = Round(v, step)
        if ns.db[key] == v then return end
        ns.db[key] = v
        if onChange then onChange(v) end
    end

    -- Blizzard's settings slider; the plain slider below is a fallback in
    -- case the template is not available on this client.
    local steps = math.floor((maxV - minV) / step + 0.5)
    local ok, s = pcall(CreateFrame, "Frame", nil, holder, "MinimalSliderWithSteppersTemplate")
    if ok and s and s.Init and MinimalSliderWithSteppersMixin then
        s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        s:SetWidth(230)
        s:Init(ns.db[key], minV, maxV, steps, {
            [MinimalSliderWithSteppersMixin.Label.Right] = function(v) return fmt(Round(v, step)) end,
        })
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            if holder.updating then return end
            Set(v)
        end, holder)
        holder.Refresh = function()
            holder.updating = true -- don't write back while loading the value
            s:SetValue(ns.db[key])
            holder.updating = false
        end
    else
        local sl = CreateFrame("Slider", nil, holder)
        sl:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        sl:SetSize(200, 14)
        sl:SetOrientation("HORIZONTAL")
        sl:SetMinMaxValues(minV, maxV)
        sl:SetValueStep(step)
        sl:SetObeyStepOnDrag(true)
        local track = sl:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0, 0, 0, 0.6)
        track:SetPoint("LEFT") track:SetPoint("RIGHT") track:SetHeight(4)
        local thumb = sl:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(1, 0.82, 0, 1)
        thumb:SetSize(8, 14)
        sl:SetThumbTexture(thumb)
        local val = sl:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        val:SetPoint("LEFT", sl, "RIGHT", 10, 0)
        sl:SetScript("OnValueChanged", function(_, v)
            val:SetText(fmt(Round(v, step)))
            if holder.updating then return end
            Set(v)
        end)
        holder.Refresh = function()
            holder.updating = true
            sl:SetValue(ns.db[key])
            val:SetText(fmt(ns.db[key]))
            holder.updating = false
        end
    end
    table.insert(controls, holder)
    return holder
end

local function CreateButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateEditBox(parent, width, key)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(200)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEscapePressed", function(self) self:SetText(ns.db[key] or "") self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then ns.db[key] = self:GetText() end
    end)
    eb.Refresh = function() eb:SetText(ns.db[key] or "") eb:SetCursorPosition(0) end
    table.insert(controls, eb)
    return eb
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------
local function Relayout() ns.Layout() end

local function BuildPanel()
    panel = CreateFrame("Frame")
    panel.name = ns.TITLE

    -- Header without icon, version or author (same style as the other Mirra's addons)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText(ns.TITLE)

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    sub:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.8, 0.8, 0.8)
    sub:SetText("See your party's experience at a glance and answer !xp, !count and !roll in chat.")

    -- Left column: behaviour
    local left = CreateHeader(panel, "General")
    left:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)

    local y = -8
    local prev = left
    local function Check(label, tip, key, onChange)
        local cb = CreateCheck(panel, label, tip, key, onChange)
        cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == left and -2 or 0, y)
        prev, y = cb, -4
        return cb
    end

    Check("Show XP bars", "Show or hide the group XP bars.", "visible", Relayout)
    Check("Include my own XP", "Show a bar for your own character above your party members.", "showSelf", Relayout)
    Check("Show rested XP", "Show rested experience as a blue overlay on the bars.", "showRested", Relayout)
    Check("XP on party tooltips", "Add a line with the XP of party members to their unit tooltip.", "tooltip")
    Check("Answer chat commands", "Reply to !xp, !count <item> and !roll [max] in party, instance and whisper chat.", "chatCommands")
    Check("Announce level ups", "Post a message in group chat when you level up.", "announce")

    local msgLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    msgLabel:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 4, -8)
    msgLabel:SetText("Level up message ([level] = your new level)")
    msgLabel:SetTextColor(0.8, 0.8, 0.8)

    local msgBox = CreateEditBox(panel, 260, "announceMsg")
    msgBox:SetPoint("TOPLEFT", msgLabel, "BOTTOMLEFT", 4, -4)

    -- Right column: appearance
    local right = CreateHeader(panel, "Appearance")
    right:SetPoint("TOPLEFT", left, "TOPLEFT", 330, 0)

    local sy = -10
    local sprev = right
    local function Slider(label, key, minV, maxV, step, fmt)
        local s = CreateSlider(panel, label, key, minV, maxV, step, fmt, Relayout)
        s:SetPoint("TOPLEFT", sprev, "BOTTOMLEFT", 0, sy)
        sprev, sy = s, -6
        return s
    end
    local function Int(v) return format("%d", v) end
    Slider("Bar width", "width", 60, 400, 5, Int)
    Slider("Bar height", "height", 6, 40, 1, Int)
    Slider("Scale", "scale", 0.5, 2.5, 0.05, function(v) return format("%.2f", v) end)
    Slider("Spacing", "spacing", 0, 40, 1, Int)

    -- Buttons
    local testBtn = CreateButton(panel, "Toggle test bars", 150, function() ns.ToggleTest() end)
    testBtn:SetPoint("TOPLEFT", sprev, "BOTTOMLEFT", 0, -14)

    local moveHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    moveHint:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -40)
    moveHint:SetTextColor(0.7, 0.7, 0.7)
    moveHint:SetText("Hold Ctrl and drag the bars to move them.")

    local posBtn = CreateButton(panel, "Reset position", 120, function()
        ns.db.point = { "CENTER", "CENTER", 0, 0 }
        ns.ApplyPosition()
    end)
    posBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)

    local resetBtn = CreateButton(panel, "Reset all settings", 150, function() ns.ResetSettings() end)
    resetBtn:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -8)

    -- Footer: chat commands
    local help = CreateHeader(panel, "Chat commands")
    help:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", -8, -26)

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -8)
    helpText:SetJustifyH("LEFT")
    helpText:SetSpacing(3)
    helpText:SetText(
        "|cffffd100!xp|r - everyone with the addon posts their level and XP\n" ..
        "|cffffd100!count <item>|r - everyone posts how many of that item they have\n" ..
        "|cffffd100!roll|r - everyone rolls 1-100  (|cffffd100!roll 50|r = 1-50, |cffffd100!roll 10 50|r = 10-50)\n\n" ..
        "|cffffd100/mgxp|r opens this panel  -  |cffffd100/mgxp help|r lists all slash commands")

    panel:SetScript("OnShow", function() ns.RefreshOptions() end)
end

function ns.RefreshOptions()
    for _, c in ipairs(controls) do c.Refresh() end
end

function ns.InitOptions()
    BuildPanel()
    category = Settings.RegisterCanvasLayoutCategory(panel, ns.TITLE)
    Settings.RegisterAddOnCategory(category)
    ns.RefreshOptions()
end

function ns.OpenOptions()
    Settings.OpenToCategory(category:GetID())
end
