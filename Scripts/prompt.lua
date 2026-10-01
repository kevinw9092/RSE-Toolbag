-- "Switch Tool [X]": a hint shown while you face a rock, tree, farm plot or
-- fishing spot and carry a better-suited tool than the one in your hand.
-- Pressing the tool key equips it.
--
-- Drawn like the game's own prompts ("Harvest [E]", the inventory's "Sort [V]"):
-- the game's input legend entry, a label and a boxed key, no frame. Its class is
-- taken from the instance the inventory already has (its asset path is not
-- known). Until one exists, or if it cannot be used, the hint falls back to a
-- small framed panel (WBP_Panel) with the same words.
local T = require('toolbag_core')

local P = {}
local WIDTH, HEIGHT = 420, 76
-- Text size (was 18). The cut-off letters were the panel's content slot, not
-- the size: the text now sits on the panel's root layer (see build).
local FONT_SIZE = 14
local H_CENTER, V_CENTER = 2, 2
local HIT_TEST_INVISIBLE, COLLAPSED = 3, 1
local GOLD = { R = 0.96, G = 0.82, B = 0.50, A = 1 }

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end

local LABEL = 'Switch Tool'
local SELF_HIT_TEST_INVISIBLE = 4
local view = nil        -- { frame, text, key, legend, shown, textShown }
local failed = false

-- ------------------------------------------------------ game-style prompt
-- The class of WBP_InputLegend_InputEntry, kept as its path (a kept class
-- object can go with its world). FindFirstOf walks objects: it looks every
-- 10 s, and every 60 s after 3 misses (the legend exists once a menu with key
-- hints has been open).
local legendClass = nil
local nextLegendLook, legendMisses = 0, 0

local function findLegendClass(now)
    if legendClass then
        local cls = get(function() return StaticFindObject(legendClass) end)
        if valid(cls) then return cls end
        legendClass = nil
    end
    if now < nextLegendLook then return nil end
    legendMisses = legendMisses + 1
    nextLegendLook = now + (legendMisses > 3 and 60 or 10)
    local inst = get(function() return FindFirstOf('WBP_InputLegend_InputEntry_C') end)
    local cls = valid(inst) and get(function() return inst:GetClass() end)
    if not valid(cls) then return nil end
    local path = T.pathOf(cls)
    if path == '' then return nil end
    legendClass, legendMisses = path, 0
    T.debugLog('equip prompt: using the game\'s input legend widget')
    return cls
end

local function findNamed(w, wanted, depth)
    if not valid(w) or depth > 10 then return nil end
    if get(function() return w:GetFName():ToString() end) == wanted then return w end
    local n = get(function() return w:GetChildrenCount() end)
    if type(n) == 'number' then
        for i = 0, n - 1 do
            local found = findNamed(get(function() return w:GetChildAt(i) end), wanted, depth + 1)
            if found then return found end
        end
    end
    local inner = get(function() return w.WidgetTree.RootWidget end)
    if valid(inner) and inner ~= w then return findNamed(inner, wanted, depth + 1) end
    return nil
end

-- The legend entry is LabelText, then the game's key icon (InputActionWidget).
-- That icon draws the key from the game's own input bindings and redraws itself,
-- so a key it has no binding for (the tool key) never shows. The label is kept;
-- the icon is hidden, and a key cap of our own goes in its place in the same row:
-- the icon's own key-cap background (IconBorder) when it has one, else a light
-- outlined box, with the key's name in the game's font.
local KEY_FONT = '/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font'
-- Matched to the game's own key caps (the E in "Harvest [E]"): a square about
-- twice the label's cap height, the letter a little smaller than the label.
local KEY_SIZE, KEY_FONT_SIZE = 30, 13
local KEY_EDGE = { R = 0.86, G = 0.84, B = 0.80, A = 1 }
local KEY_FILL = { R = 0.04, G = 0.035, B = 0.03, A = 0.85 }
local KEY_TEXT = { R = 0.95, G = 0.93, B = 0.88, A = 1 }

local function umg(kind, tree)
    return StaticConstructObject(StaticFindObject('/Script/UMG.' .. kind), tree)
end

-- A key cap: SizeBox > Border (edge) > Border (fill) > TextBlock.
local function keyCap(tree, iconBorder)
    local size = umg('SizeBox', tree)
    -- A fixed square for one-letter keys (see applyLegend); wider only for names like F10.
    size:SetWidthOverride(KEY_SIZE)
    size:SetHeightOverride(KEY_SIZE)
    local edge = umg('Border', tree)
    local fill = umg('Border', tree)
    local copied = false
    if valid(iconBorder) then
        -- The game's key-cap art, when the icon has one loaded.
        local brush = get(function() return iconBorder.Background end)
        copied = brush ~= nil and valid(get(function() return brush.ResourceObject end))
            and pcall(function() edge:SetBrush(brush) end)
    end
    if copied then
        edge:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        fill:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
        fill:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    else
        edge:SetBrushColor(KEY_EDGE)
        edge:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 })
        fill:SetBrushColor(KEY_FILL)
        fill:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    end
    pcall(function() fill:SetHorizontalAlignment(2) end)   -- centre
    pcall(function() fill:SetVerticalAlignment(2) end)
    local text = umg('TextBlock', tree)
    pcall(function()
        local f = LoadAsset(KEY_FONT)
        if valid(f) then text.Font.FontObject = f end
    end)
    pcall(function() text.Font.Size = KEY_FONT_SIZE end)
    pcall(function() text:SetColorAndOpacity({ SpecifiedColor = KEY_TEXT, ColorUseRule = 0 }) end)
    pcall(function() text:SetJustification(1) end)
    fill:SetContent(text)
    edge:SetContent(fill)
    size:SetContent(edge)
    return size, text, copied
end

-- One-letter keys get the fixed square; longer names (F10, HOME) a box that fits.
local function fitCap(size, key)
    if #key <= 1 then
        pcall(function() size:SetWidthOverride(KEY_SIZE) end)
    else
        pcall(function() size:ClearWidthOverride() end)
        pcall(function() size:SetMinDesiredWidth(KEY_SIZE) end)
        pcall(function() size:SetWidthOverride(KEY_SIZE + (#key - 1) * 9 + 8) end)
    end
end

-- The child of `row` that contains `w` (walking up from w), or nil.
local function childOf(row, w)
    local cur = w
    for _ = 1, 12 do
        local parent = valid(cur) and get(function() return cur:GetParent() end)
        if not valid(parent) then return nil end
        if parent == row or get(function() return parent:GetFullName() end) == get(function() return row:GetFullName() end) then
            return cur
        end
        cur = parent
    end
    return nil
end

local function buildLegend(pc, cls)
    local wbl = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local w = wbl:Create(pc, cls, pc)
    assert(valid(w), 'could not create the input legend widget')
    local label = get(function() return w.LabelText end) or findNamed(w, 'LabelText', 0)
    assert(valid(label), 'input legend widget has no label')
    local icon = get(function() return w.InputActionWidget end) or findNamed(w, 'InputActionWidget', 0)
    local row = findNamed(w, 'HorizontalContainer', 0)
    assert(valid(row) and get(function() return row:IsA('/Script/UMG.HorizontalBox') end), 'input legend row not found')
    -- Hide the game's key icon (the whole part of the row that holds it).
    local iconPart = valid(icon) and (childOf(row, icon) or icon) or nil
    if iconPart then pcall(function() iconPart:SetVisibility(COLLAPSED) end) end
    -- IconBorder is a field of the game's input icon widget (UDomInputIconWidget); the search is the fallback.
    local border = valid(icon) and get(function() return icon.IconBorder end)
    if not valid(border) then border = valid(icon) and findNamed(icon, 'IconBorder', 0) end
    local cap, keyText, copied = keyCap(w.WidgetTree, border)
    local slot = row:AddChildToHorizontalBox(cap)
    pcall(function() slot:SetVerticalAlignment(2) end)
    pcall(function() slot:SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 }) end)
    T.debugLog('equip prompt: key cap ' .. (copied and 'uses the game\'s key-cap art' or 'drawn as an outlined box'))
    w:AddToViewport(50)
    w:SetVisibility(COLLAPSED)
    local vw, vh = 1920, 1080
    pcall(function()
        local wll = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        local sz, scale = wll:GetViewportSize(pc), wll:GetViewportScale(pc)
        if sz and scale and scale > 0 and sz.X > 0 and sz.Y > 0 then vw, vh = sz.X / scale, sz.Y / scale end
    end)
    -- Centred on its own size, bottom centre above the health and stamina bars.
    pcall(function() w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 }) end)
    pcall(function() w:SetPositionInViewport({ X = vw / 2, Y = vh * 0.74 }, false) end)
    return { frame = w, text = label, key = keyText, cap = cap, legend = true, iconPart = iconPart }
end

-- Label and key, re-applied each time the hint appears: the widget's own set-up
-- can reset the label and show its icon again.
local function applyLegend(v, key)
    pcall(function() v.text:SetText(FText(LABEL)) end)
    pcall(function() v.key:SetText(FText(key:upper())) end)
    if valid(v.cap) then fitCap(v.cap, key) end
    if valid(v.iconPart) then pcall(function() v.iconPart:SetVisibility(COLLAPSED) end) end
end

local function loadClass(pkg)
    local asset = pkg:match('([^/]+)$')
    pcall(function() LoadAsset(pkg) end)
    local c = get(function() return StaticFindObject(pkg .. '.' .. asset .. '_C') end)
    return valid(c) and c or nil
end

-- The game's panel plays its own effects (rising embers, flourishes), made for
-- big windows; on a small hint they look like stray sparks. Hides every
-- effect widget in the panel: Niagara/particle widgets by class, and anything
-- whose class or name says ember, spark, particle, flourish or FX. With Debug
-- on, every widget seen is logged once so a missed one can be named.
local EFFECT = { 'niagara', 'particle', 'ember', 'spark', 'flourish', 'vfx', 'fx_', '_fx' }
local function isEffect(w)
    local cls = (get(function() return w:GetClass():GetFName():ToString() end) or ''):lower()
    local nm = (get(function() return w:GetFName():ToString() end) or ''):lower()
    for _, key in ipairs(EFFECT) do
        if cls:find(key, 1, true) or nm:find(key, 1, true) then return true, cls, nm end
    end
    return false, cls, nm
end
local function hideEffects(frame, root)
    local seen, hidden = {}, 0
    local function walk(w, depth)
        if not valid(w) or depth > 12 then return end
        local effect, cls, nm = isEffect(w)
        if T.cfg.Debug then seen[#seen + 1] = string.rep(' ', depth) .. nm .. ':' .. cls end
        if effect then
            if pcall(function() w:SetVisibility(COLLAPSED) end) then hidden = hidden + 1 end
            return
        end
        local n = get(function() return w:GetChildrenCount() end)
        if type(n) == 'number' then
            for i = 0, n - 1 do walk(get(function() return w:GetChildAt(i) end), depth + 1) end
        end
        local inner = get(function() return w.WidgetTree.RootWidget end)
        if valid(inner) and inner ~= w then walk(inner, depth + 1) end
    end
    walk(root, 0)
    if T.cfg.Debug then
        T.debugLog('equip prompt: ' .. hidden .. ' effect widget(s) hidden; panel widgets: ' .. table.concat(seen, ', '))
    end
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
    -- Centred through an invisible Border. The panel's content slot sits
    -- inside the frame art's thick padding and is shorter than a line of
    -- text at this panel height, which cut the letters off at any font size
    -- (2.2.4). So the Border goes on the panel's root layer, over the whole
    -- frame; the content slot is only the fallback.
    local box = StaticConstructObject(StaticFindObject('/Script/UMG.Border'), frame.WidgetTree)
    box:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
    box:SetPadding({ Left = 12, Top = 0, Right = 12, Bottom = 0 })
    box:SetHorizontalAlignment(H_CENTER)
    box:SetVerticalAlignment(V_CENTER)
    pcall(function() box:SetClipping(0) end)
    box:SetContent(text)
    local root = get(function() return frame.WidgetTree.RootWidget end)
    local rootClass = valid(root) and (get(function() return root:GetClass():GetFName():ToString() end) or '?') or 'none'
    local where
    if valid(root) and get(function() return root:IsA('/Script/UMG.Overlay') end) then
        where = pcall(function()
            local slot = root:AddChildToOverlay(box)
            slot:SetHorizontalAlignment(0) -- fill
            slot:SetVerticalAlignment(0)
        end) and 'root overlay' or nil
    elseif valid(root) and get(function() return root:IsA('/Script/UMG.CanvasPanel') end) then
        where = pcall(function()
            local slot = root:AddChildToCanvas(box)
            slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
            slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
            slot:SetZOrder(100)
        end) and 'root canvas' or nil
    end
    if not where then
        pcall(function() box:RemoveFromParent() end)
        -- PanelContent is a NamedSlot (one child): SetContent, as the game's header dump shows.
        where = pcall(function() frame.PanelContent:SetContent(box) end) and 'panel content' or nil
    end
    if not where then
        pcall(function() text:RemoveFromParent() end)
        frame.PanelContent:SetContent(text)
        where = 'panel content, uncentred'
    end
    T.debugLog('equip prompt text placed in the ' .. where .. ' (panel root: ' .. rootClass .. ')')
    hideEffects(frame, root)
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

local function setShown(on, key)
    if not view or view.shown == on then return end
    view.shown = on
    if on and view.legend then applyLegend(view, key) end
    -- Never takes input: clicks and keys go to the game as usual.
    pcall(function() view.frame:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED) end)
end

-- A prompt the game destroyed is rebuilt at most every REBUILD seconds (a
-- rebuild on every tick stacked copies of the 2.3.0 toolbag row).
local REBUILD = 10
local lastBuildAt = -math.huge

function P.forget()
    if view then pcall(function() view.frame:RemoveFromParent() end) end
    view = nil
    legendClass, nextLegendLook, legendMisses = nil, 0, 0
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
    -- The game-style prompt as soon as its class is known; the framed panel until then.
    local cls = findLegendClass(now)
    if view and not view.legend and cls and not view.legendFailed then
        pcall(function() view.frame:RemoveFromParent() end)
        view = nil
    end
    if view and not valid(view.frame) then
        if now - lastBuildAt < REBUILD then return end
        view = nil
    end
    if not view then
        lastBuildAt = now
        local ok, result = false, nil
        if cls then
            ok, result = pcall(buildLegend, pc, cls)
            if not ok then
                T.log('equip prompt: the game-style prompt failed (' .. tostring(result) .. '); using the framed one')
                legendClass = nil
                nextLegendLook = math.huge          -- do not try again this session
            end
        end
        if not ok then
            ok, result = pcall(build, pc)
            if ok then result.legendFailed = nextLegendLook == math.huge end
        end
        if not ok then
            failed = true
            T.log('equip prompt off: ' .. tostring(result))
            return
        end
        view = result
    end
    if not view.legend then
        local line = string.format('%s  [%s]', LABEL, key:upper())
        if line ~= view.textShown then
            view.textShown = line
            pcall(function() view.text:SetText(FText(line)) end)
        end
    end
    setShown(true, key)
end

return P
