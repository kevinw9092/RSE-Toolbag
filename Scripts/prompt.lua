-- "[X] Equip Rune pickaxe": a small framed hint shown while you face a rock,
-- tree, farm plot or fishing spot and carry a better-suited tool than the one
-- in your hand. Pressing the tool key equips it. Drawn with the game's own
-- panel (WBP_Panel) and text block, so it matches the game's art.
local T = require('toolbag_core')

local P = {}
local WIDTH, HEIGHT = 420, 76
-- Text size: 18 was taller than the panel's content area and the bottom of the
-- letters was cut off. 14 fits with a small margin; the text is also centred
-- vertically (and horizontally) in the panel.
local FONT_SIZE = 14
local H_CENTER, V_CENTER = 2, 2
local HIT_TEST_INVISIBLE, COLLAPSED = 3, 1
local GOLD = { R = 0.96, G = 0.82, B = 0.50, A = 1 }

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end

local view = nil        -- { frame, text, shown, textShown }
local failed = false

local function loadClass(pkg)
    local asset = pkg:match('([^/]+)$')
    pcall(function() LoadAsset(pkg) end)
    local c = get(function() return StaticFindObject(pkg .. '.' .. asset .. '_C') end)
    return valid(c) and c or nil
end

local function build(pc)
    local panelC = loadClass('/Game/UI/Panels/WBP_Panel')
    local textC = loadClass('/Game/UI/Common/WBP_DomTextBlock')
    assert(panelC and textC, "the game's panel widgets were not found")
    local wbl = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local frame = wbl:Create(pc, panelC, pc)
    assert(valid(frame), 'could not create the prompt panel')
    local text = StaticConstructObject(textC, frame.WidgetTree)
    pcall(function() local f = text.Font; f.Size = FONT_SIZE; text:SetFont(f) end)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = GOLD, ColorUseRule = 0 }) end)
    pcall(function() text:SetJustification(1) end) -- 1 = centre
    -- Centred in the panel through an invisible Border (the panel's content
    -- slot cannot align its child); the text goes in directly if that fails.
    local placed = pcall(function()
        local box = StaticConstructObject(StaticFindObject('/Script/UMG.Border'), frame.WidgetTree)
        box:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
        box:SetPadding({ Left = 12, Top = 2, Right = 12, Bottom = 2 })
        box:SetHorizontalAlignment(H_CENTER)
        box:SetVerticalAlignment(V_CENTER)
        box:SetContent(text)
        frame.PanelContent:AddChild(box)
    end)
    if not placed then
        pcall(function() text:RemoveFromParent() end)
        frame.PanelContent:AddChild(text)
    end
    frame:AddToViewport(50)
    frame:SetVisibility(COLLAPSED)
    -- Bottom centre, above the health and stamina bars.
    local vw, vh = 1920, 1080
    pcall(function()
        local wll = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        local sz, scale = wll:GetViewportSize(pc), wll:GetViewportScale(pc)
        if sz and scale and scale > 0 and sz.X > 0 and sz.Y > 0 then vw, vh = sz.X / scale, sz.Y / scale end
    end)
    pcall(function() frame:SetDesiredSizeInViewport({ X = WIDTH, Y = HEIGHT }) end)
    pcall(function() frame:SetPositionInViewport({ X = (vw - WIDTH) / 2, Y = vh * 0.74 }, false) end)
    return { frame = frame, text = text }
end

local function setShown(on)
    if not view or view.shown == on then return end
    view.shown = on
    -- Never takes input: clicks and keys go to the game as usual.
    pcall(function() view.frame:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED) end)
end

function P.forget()
    if view then pcall(function() view.frame:RemoveFromParent() end) end
    view = nil
end

function P.tick(now)
    local key = tostring(T.cfg.ToolKey or 'none')
    if not T.cfg.EquipPrompt or key == '' or key:lower() == 'none' or failed then
        setShown(false)
        return
    end
    local s = T.suggestion(now)
    if not s then setShown(false) return end
    local pc = T.pc()
    if not view or not valid(view.frame) then
        local ok, result = pcall(build, pc)
        if not ok then
            failed = true
            T.log('equip prompt off: ' .. tostring(result))
            return
        end
        view = result
    end
    local line = string.format('[%s]  Equip %s', key:upper(), s.tool.label or s.tool.name or '?')
    if line ~= view.textShown then
        view.textShown = line
        pcall(function() view.text:SetText(FText(line)) end)
    end
    setShown(true)
end

return P
