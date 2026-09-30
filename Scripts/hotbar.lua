-- Toolbag quick row: the 10 toolbag slots shown above the health bars or above
-- the game's action bar (the 1-8 shortcut bar), each with its tool's icon and
-- its number, and the modifier key (SHIFT) boxed at the left: "SHIFT + number
-- takes this tool out". The equipped tool gets a gold outline, like the action
-- bar's selected slot. Display only: it takes no clicks.
--
-- Placement (QuickRowPosition): the anchor is looked up in the in-world HUD
-- (WBP_HUD_RootWidget), never in the inventory screen, which has its own copy of
-- the action bar (the first version latched onto that copy, then rebuilt every
-- time the inventory recreated it, which blanked the icons):
--   "Above health"      WBP_HUD_PlayerVitalsBars
--   "Above action bar"  the HUD's quick access bar
-- When the anchor sits directly on a canvas, the row goes on the same canvas
-- just above it and follows it. Otherwise the row is its own layer at the
-- bottom centre of the screen, at a height per position. QuickRowOffset moves it
-- up (+) or down (-), -300 to 300 UI units. With Debug on, the HUD's widget tree
-- (with canvas positions) is written to hud-dump.txt to calibrate those heights.
local T = require('toolbag_core')
local W = require('ui')

local H = {}
local CELL, ICON, GAP, BAR_GAP = 54, 40, 6, 8
-- Own-layer heights above the bottom of the screen (UI units, 1080p layout),
-- per position, set in game on CL-240163: above the health bars 180, below
-- them 30. The action bar's is used until the bar itself is found on a canvas.
local LAYER_HEIGHT = { health = 180, below = 30, actionbar = 265 }
-- The action bar has 8 slots: in that position only toolbag slots 1-8 show.
local ACTIONBAR_SLOTS = 8
-- Extra room above the action bar: at BAR_GAP alone the row sat on the bar; 10 more fits (in game, 2026-09-30).
local ACTIONBAR_LIFT = 10
local VISIBLE, COLLAPSED, HIT_TEST_INVISIBLE, SELF_HIT_TEST_INVISIBLE = 0, 1, 3, 4
local FONT = '/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font'
local COLOR = {
    -- A light, see-through square with a faint edge, like the action bar's empty slots.
    fill = { R = 0.80, G = 0.80, B = 0.80, A = 0.16 },
    edge = { R = 0.90, G = 0.90, B = 0.90, A = 0.28 },
    number = { R = 0.92, G = 0.90, B = 0.86, A = 0.9 },
    capEdge = { R = 0.86, G = 0.84, B = 0.80, A = 1 },
    capFill = { R = 0.04, G = 0.035, B = 0.03, A = 0.85 },
    capText = { R = 0.95, G = 0.93, B = 0.88, A = 1 },
}
-- Durability bar along the bottom of a slot, like the action bar's: a thin dark
-- track, filled light, red when low.
local DUR_W, DUR_H, DUR_LOW = CELL - 14, 3, 0.25
local DUR = {
    track = { R = 0, G = 0, B = 0, A = 0.55 },
    good = { R = 0.86, G = 0.86, B = 0.84, A = 0.95 },
    low = { R = 0.86, G = 0.22, B = 0.16, A = 1 },
}
local CAP_OPACITY = 0.6            -- the SHIFT box, faded so it is not the loudest thing on screen

local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function className(o) return get(function() return o:GetClass():GetFName():ToString() end) or '?' end
local function nameOf(o) return get(function() return o:GetFName():ToString() end) or '?' end

local view = nil          -- the built row, this world only
-- Every row widget ever made, by path: all are removed before a rebuild, so a
-- row that failed to go away can never stay stacked under the new one (2.3.0
-- testing: a misfiring validity check rebuilt 3 times a second, stacking rows
-- whose newest, still empty copy covered the icons, and made the game hitch).
local madeHosts = {}

local function pathOf(o)
    return (get(function() return o:GetFullName() end) or ''):match('^%S+%s+(.+)$')
end
local function lookUp(p)
    if not p then return nil end
    local o = get(function() return StaticFindObject(p) end)
    return valid(o) and o or nil
end
local failed = false
local nextLook = 0        -- FindFirstOf walks objects: look for the HUD at most every 10 s
local nextRefresh = 0
local dumped = false

local function position()
    local p = tostring(T.cfg.QuickRowPosition or 'Above health'):lower()
    if p:find('action', 1, true) then return 'actionbar' end
    if p:find('below', 1, true) then return 'below' end
    return 'health'
end
local function offset()
    local o = tonumber(T.cfg.QuickRowOffset) or 0
    return math.max(-300, math.min(300, o))
end

local function umg(kind, tree)
    return StaticConstructObject(StaticFindObject('/Script/UMG.' .. kind), tree)
end

local function text(tree, px, color)
    local t = umg('TextBlock', tree)
    pcall(function()
        -- Looked up each time (never keep engine objects), loaded only if not in memory yet.
        local f = get(function() return StaticFindObject(FONT) end)
        if not valid(f) then f = LoadAsset(FONT) end
        if valid(f) then t.Font.FontObject = f end
    end)
    pcall(function() t.Font.Size = px end)
    pcall(function() t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    return t
end

-- ------------------------------------------------------------------ the HUD
local function hudRoot()
    local w = get(function() return FindFirstOf('WBP_HUD_RootWidget_C') end)
    if valid(w) and not nameOf(w):find('^Default__') then return w end
    return nil
end

-- Walks a widget tree: children and the inner trees of user widgets.
local function walk(w, fn, depth)
    if not valid(w) or depth > 40 then return nil end
    local r = fn(w, depth)
    if r then return r end
    local n = get(function() return w:GetChildrenCount() end)
    if type(n) == 'number' then
        for i = 0, n - 1 do
            r = walk(get(function() return w:GetChildAt(i) end), fn, depth + 1)
            if r then return r end
        end
    end
    local inner = get(function() return w.WidgetTree.RootWidget end)
    if valid(inner) and inner ~= w then return walk(inner, fn, depth + 1) end
    return nil
end

-- The anchor, looked up by its own class (the HUD root found first was an
-- inactive copy, HUDWidgetAlwaysDeactive, with neither bar in it), skipping
-- copies that are not the in-world HUD: that inactive HUD and the inventory
-- screen's own action bar.
local ANCHOR_CLASS = { health = 'WBP_HUD_PlayerVitalsBars_C', below = 'WBP_HUD_PlayerVitalsBars_C',
    actionbar = 'WBP_Inventory_QuickAccesBar_C' }
local function notInWorldHud(full)
    return full:find('AlwaysDeactive', 1, true) or full:find('Inventory_MainPanel', 1, true)
        or full:find('VerticalNavigation', 1, true) or full:find('Default__', 1, true)
end
local function findAnchor(pos)
    local ok, all = pcall(FindAllOf, ANCHOR_CLASS[pos])
    for _, w in ipairs(ok and all or {}) do
        local full = valid(w) and (get(function() return w:GetFullName() end) or '') or ''
        if full ~= '' and not notInWorldHud(full) then return w end
    end
    return nil
end

-- For calibrating: every copy of the health bars and the action bar, with the
-- chain of panels each sits in and their positions (hud-dump.txt, Debug on).
local function describe(w)
    local line = nameOf(w) .. ' : ' .. className(w) .. ' vis=' .. tostring(get(function() return w:GetVisibility() end))
    local slot = get(function() return w.Slot end)
    if valid(slot) then
        line = line .. '  [' .. className(slot) .. ']'
        if get(function() return slot:IsA('/Script/UMG.CanvasPanelSlot') end) then
            local l = get(function() return slot:GetLayout() end)
            if l then
                line = line .. string.format(' anchors %.2f,%.2f-%.2f,%.2f align %.2f,%.2f offsets L%.0f T%.0f R%.0f B%.0f',
                    l.Anchors.Minimum.X, l.Anchors.Minimum.Y, l.Anchors.Maximum.X, l.Anchors.Maximum.Y,
                    l.Alignment.X, l.Alignment.Y, l.Offsets.Left, l.Offsets.Top, l.Offsets.Right, l.Offsets.Bottom)
            end
        end
    end
    return line
end
local function dumpHud()
    local dir = (debug.getinfo(1, 'S').source or ''):gsub('^@', ''):match('^(.*)[/\\]Scripts[/\\][^/\\]*$')
    -- Written to a temporary file, then renamed over the old dump.
    local path = dir and (dir .. '\\hud-dump.txt')
    local f = path and io.open(path .. '.tmp', 'w')
    if not f then return end
    -- The panels around every action-bar slot (the in-world 1-8 bar is not a
    -- QuickAccesBar: only the inventory screen's copy is), then the active HUD.
    for _, cls in ipairs({ 'WBP_HUD_RootWidget_C', 'WBP_HUD_PlayerVitalsBars_C', 'WBP_Inventory_QuickAccesBar_C',
                           'WBP_Inventory_QuickAccess_ItemSlot_C' }) do
        local ok, all = pcall(FindAllOf, cls)
        for _, w in ipairs(ok and all or {}) do
            if valid(w) then
                f:write('== ', get(function() return w:GetFullName() end) or '?', '\n')
                local cur, depth = w, 0
                while valid(cur) and depth < 14 do
                    f:write(string.rep('  ', depth), describe(cur), '\n')
                    cur = get(function() return cur:GetParent() end)
                    depth = depth + 1
                end
            end
        end
    end
    local active = nil
    for _, w in ipairs(get(function() return FindAllOf('WBP_HUD_RootWidget_C') end) or {}) do
        if valid(w) and nameOf(w):find('AlwaysActive', 1, true) then active = w end
    end
    if active then
        f:write('\n== full tree of ', nameOf(active), '\n')
        walk(active, function(w, depth)
            f:write(string.rep('  ', depth), describe(w), '\n')
        end, 0)
    end
    if not f:close() then os.remove(path .. '.tmp') return end
    os.remove(path)
    os.rename(path .. '.tmp', path)
    T.debugLog('quick row: HUD layout written to hud-dump.txt')
end

-- The anchor's own canvas slot (only the anchor itself: an ancestor box would
-- also hold other HUD parts, and "above it" would be above them too).
local function canvasSlotOf(w)
    local slot = get(function() return w.Slot end)
    if valid(slot) and get(function() return slot:IsA('/Script/UMG.CanvasPanelSlot') end) then return slot end
    return nil
end

-- ------------------------------------------------------------------ the row
local function keyCap(tree, label)
    local size = umg('SizeBox', tree)
    size:SetHeightOverride(28)
    size:SetMinDesiredWidth(28)
    local edge = umg('Border', tree)
    edge:SetBrushColor(COLOR.capEdge)
    edge:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 })
    local fill = umg('Border', tree)
    fill:SetBrushColor(COLOR.capFill)
    fill:SetPadding({ Left = 7, Top = 0, Right = 7, Bottom = 0 })
    pcall(function() fill:SetHorizontalAlignment(2) end)
    pcall(function() fill:SetVerticalAlignment(2) end)
    local t = text(tree, 11, COLOR.capText)
    pcall(function() t:SetText(FText(label)) end)
    fill:SetContent(t)
    edge:SetContent(fill)
    size:SetContent(edge)
    pcall(function() size:SetRenderOpacity(CAP_OPACITY) end)
    return size
end

-- The action bar's own empty-slot look, copied from a HUD slot when one is found:
-- the brush its item slot draws (Background of the first Border/Image in it).
local function slotArtFrom(root)
    local slotWidget = walk(root, function(w)
        if className(w):find('QuickAccess_ItemSlot', 1, true) then return w end
    end, 0)
    if not slotWidget then return nil end
    local brushOwner = walk(slotWidget, function(w)
        if get(function() return w:IsA('/Script/UMG.Border') end) or get(function() return w:IsA('/Script/UMG.Image') end) then
            local b = get(function() return w.Background end) or get(function() return w.Brush end)
            if b and valid(get(function() return b.ResourceObject end)) then return w end
        end
    end, 0)
    if not brushOwner then return nil end
    return get(function() return brushOwner.Background end) or get(function() return brushOwner.Brush end)
end

local CLEAR = { R = 0, G = 0, B = 0, A = 0 }
-- The tool in your hand: a thin gold outline just inside the slot, like the
-- action bar's selected slot: its bronze (linear colour for #995316).
local OUTLINE = { R = 0.319, G = 0.087, B = 0.008, A = 1 }
local OUTLINE_W, OUTLINE_INSET = 2, 3

-- Four thin lines along the edges of an overlay, collapsed until selected.
-- (A Border draws a filled box, so the outline is made of lines.)
local function outline(tree, overlay)
    local layer = umg('Overlay', tree)
    local sides = { { 0, 1, nil, OUTLINE_W }, { 0, 3, nil, OUTLINE_W }, { 1, 0, OUTLINE_W, nil }, { 3, 0, OUTLINE_W, nil } }
    for _, s in ipairs(sides) do
        local box = umg('SizeBox', tree)
        if s[3] then box:SetWidthOverride(s[3]) end
        if s[4] then box:SetHeightOverride(s[4]) end
        local line = umg('Border', tree)
        line:SetBrushColor(OUTLINE)
        box:SetContent(line)
        local ls = layer:AddChildToOverlay(box)
        pcall(function() ls:SetHorizontalAlignment(s[1]) ls:SetVerticalAlignment(s[2]) end)
    end
    local os = overlay:AddChildToOverlay(layer)
    pcall(function()
        os:SetHorizontalAlignment(0) os:SetVerticalAlignment(0)
        os:SetPadding({ Left = OUTLINE_INSET, Top = OUTLINE_INSET, Right = OUTLINE_INSET, Bottom = OUTLINE_INSET })
    end)
    layer:SetVisibility(COLLAPSED)
    return layer
end

local function cell(tree, row, k, art)
    local size = umg('SizeBox', tree)
    size:SetWidthOverride(CELL)
    size:SetHeightOverride(CELL)
    local overlay = umg('Overlay', tree)
    size:SetContent(overlay)
    -- The game's embroidered item slot frame, as the action bar and the inventory
    -- draw it (copied in refresh, see applyArt); hidden until it is found.
    local frame = umg('Image', tree)
    frame:SetVisibility(COLLAPSED)
    local fs0 = overlay:AddChildToOverlay(frame)
    pcall(function() fs0:SetHorizontalAlignment(0) fs0:SetVerticalAlignment(0) end)
    local edge = umg('Border', tree)
    local fill = umg('Border', tree)
    local copied = art and pcall(function() fill:SetBrush(art) end)
    if copied then
        edge:SetBrushColor(CLEAR)
    else
        edge:SetBrushColor(COLOR.edge)
        fill:SetBrushColor(COLOR.fill)
    end
    edge:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 })
    pcall(function() fill:SetHorizontalAlignment(2) end)
    pcall(function() fill:SetVerticalAlignment(2) end)
    edge:SetContent(fill)
    local es = overlay:AddChildToOverlay(edge)
    pcall(function() es:SetHorizontalAlignment(0) es:SetVerticalAlignment(0) end)
    local iconBox = umg('SizeBox', tree)
    iconBox:SetWidthOverride(ICON)
    iconBox:SetHeightOverride(ICON)
    local image = umg('Image', tree)
    image:SetVisibility(COLLAPSED)
    iconBox:SetContent(image)
    fill:SetContent(iconBox)
    -- The slot's number, top left like the action bar's.
    local num = text(tree, 12, COLOR.number)
    pcall(function() num:SetText(FText(tostring(k % 10))) end)
    local ns = overlay:AddChildToOverlay(num)
    pcall(function() ns:SetHorizontalAlignment(1) ns:SetVerticalAlignment(1) ns:SetPadding({ Left = 5, Top = 2, Right = 0, Bottom = 0 }) end)
    -- Durability: track, and a fill whose width follows the item's durability.
    local durBox = umg('SizeBox', tree)
    durBox:SetWidthOverride(DUR_W)
    durBox:SetHeightOverride(DUR_H)
    local durLayer = umg('Overlay', tree)
    durBox:SetContent(durLayer)
    local track = umg('Border', tree)
    track:SetBrushColor(DUR.track)
    local ts = durLayer:AddChildToOverlay(track)
    pcall(function() ts:SetHorizontalAlignment(0) ts:SetVerticalAlignment(0) end)
    local fillBox = umg('SizeBox', tree)
    fillBox:SetHeightOverride(DUR_H)
    fillBox:SetWidthOverride(DUR_W)
    local durFill = umg('Border', tree)
    durFill:SetBrushColor(DUR.good)
    fillBox:SetContent(durFill)
    local fs = durLayer:AddChildToOverlay(fillBox)
    pcall(function() fs:SetHorizontalAlignment(1) fs:SetVerticalAlignment(0) end)
    local ds = overlay:AddChildToOverlay(durBox)
    pcall(function() ds:SetHorizontalAlignment(2) ds:SetVerticalAlignment(3) ds:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 5 }) end)
    durBox:SetVisibility(COLLAPSED)
    local ring = outline(tree, overlay)
    local rs = row:AddChildToHorizontalBox(size)
    pcall(function() rs:SetPadding({ Left = GAP, Top = 0, Right = 0, Bottom = 0 }) rs:SetVerticalAlignment(2) end)
    return { box = size, ring = ring, edge = edge, fill = fill, frame = frame, image = image, copied = copied, durBox = durBox, fillBox = fillBox, durFill = durFill }
end

-- Places the row's host above the anchor. Returns how, for the log.
-- The in-world action bar IS the inventory panel's quick access bar: the panel
-- (WBP_Inventory_MainPanel) lives in the active HUD for good, and with the
-- inventory closed only its quick access bar stays visible, at the top of the
-- panel's grid frame (hud-dump.txt, 2026-09-30). So "above the action bar" is
-- measured from that frame: its canvas position, plus its content inset
-- (PanelContent padding), plus the bar's own padding, on the panel's canvas.
local function childNamed(parent, wanted)
    for i = 0, (get(function() return parent:GetChildrenCount() end) or 0) - 1 do
        local c = get(function() return parent:GetChildAt(i) end)
        if valid(c) and nameOf(c) == wanted then return c end
    end
    return nil
end

local function placeOverActionBar(host)
    local panel = nil
    for _, p in ipairs(get(function() return FindAllOf('WBP_Inventory_MainPanel_C') end) or {}) do
        local full = valid(p) and (get(function() return p:GetFullName() end) or '') or ''
        if full ~= '' and not full:find('Default__', 1, true) and full:find('Transient', 1, true) then panel = p break end
    end
    if not panel then return nil, 'inventory panel not found' end
    local canvas = get(function() return panel.WidgetTree.RootWidget end)
    local frame = valid(canvas) and childNamed(canvas, 'BackgroundPanel')
    local slot = frame and get(function() return frame.Slot end)
    local l = valid(slot) and get(function() return slot:GetLayout() end)
    if not l then return nil, 'inventory grid frame not found' end
    local content = walk(get(function() return frame.WidgetTree.RootWidget end), function(w)
        if nameOf(w) == 'PanelContent' then return w end
    end, 0)
    local inset = content and get(function() return content.Slot.Padding.Top end) or 0
    local bar = walk(content, function(w) if className(w):find('QuickAccesBar', 1, true) then return w end end, 0)
    local barPad = bar and get(function() return bar.Slot.Padding.Top end) or 0
    local o, a = l.Offsets, l.Alignment
    local top = o.Top - (a.Y or 0) * o.Bottom + inset + barPad
    local centre = o.Left - (a.X or 0) * o.Right + o.Right / 2
    local rs = canvas:AddChildToCanvas(host)
    rs:SetAnchors(l.Anchors)
    rs:SetAlignment({ X = 0.5, Y = 1 })
    rs:SetAutoSize(true)
    rs:SetPosition({ X = centre, Y = top - BAR_GAP - ACTIONBAR_LIFT - offset() })
    pcall(function() rs:SetZOrder((get(function() return slot:GetZOrder() end) or 0) + 1) end)
    return string.format('on the inventory panel above its quick access bar (bar top %.0f, inset %.0f)', top, inset)
end

local function place(host, anchor, pc, pos)
    if pos == 'actionbar' then
        local ok, how, why = pcall(placeOverActionBar, host)
        if ok and how then return how end
        T.debugLog('quick row: action bar placement failed (' .. tostring(ok and why or how) .. '); using the fixed height')
        anchor = nil
    end
    local slot = anchor and pos ~= 'below' and canvasSlotOf(anchor)
    local canvas = anchor and get(function() return anchor:GetParent() end)
    local l = slot and get(function() return slot:GetLayout() end)
    if l and valid(canvas) then
        local o, a = l.Offsets, l.Alignment
        local stretched = math.abs(l.Anchors.Minimum.X - l.Anchors.Maximum.X) > 0.001
            or math.abs(l.Anchors.Minimum.Y - l.Anchors.Maximum.Y) > 0.001
        if not stretched then
            local top = o.Top - (a.Y or 0) * o.Bottom
            local centre = o.Left - (a.X or 0) * o.Right + o.Right / 2
            local rs = canvas:AddChildToCanvas(host)
            rs:SetAnchors(l.Anchors)
            rs:SetAlignment({ X = 0.5, Y = 1 })
            rs:SetAutoSize(true)
            rs:SetPosition({ X = centre, Y = top - BAR_GAP - offset() })
            pcall(function() rs:SetZOrder((get(function() return slot:GetZOrder() end) or 0) + 1) end)
            return 'on the HUD canvas above ' .. nameOf(anchor)
        end
    end
    -- Own layer: bottom centre, at this position's height.
    host:AddToViewport(40)
    local vw, vh = 1920, 1080
    pcall(function()
        local wll = StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        local sz, scale = wll:GetViewportSize(pc), wll:GetViewportScale(pc)
        if sz and scale and scale > 0 and sz.X > 0 and sz.Y > 0 then vw, vh = sz.X / scale, sz.Y / scale end
    end)
    pcall(function() host:SetAlignmentInViewport({ X = 0.5, Y = 1 }) end)
    pcall(function() host:SetPositionInViewport({ X = vw / 2, Y = vh - LAYER_HEIGHT[pos] - offset() }, false) end)
    return 'own layer, ' .. (anchor and ('anchor ' .. nameOf(anchor) .. ' is not on a canvas') or 'anchor not found')
end

local function build(root, pc)
    local pos = position()
    local wbl = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local host = get(function() return wbl:Create(pc, StaticFindObject('/Script/UMG.UserWidget'), pc) end)
    assert(valid(host), 'could not create the quick row')
    local tree = get(function() return host.WidgetTree end)
    if not valid(tree) then
        -- A plain UserWidget made at runtime has no widget tree: give it one.
        tree = get(function() return StaticConstructObject(StaticFindObject('/Script/UMG.WidgetTree'), host) end)
        assert(valid(tree) and pcall(function() host.WidgetTree = tree end), 'no widget tree for the quick row')
    end
    local row = umg('HorizontalBox', tree)
    local mod = tostring(T.cfg.SlotKeys or 'SHIFT'):upper()
    local cs = row:AddChildToHorizontalBox(keyCap(tree, mod == 'CONTROL' and 'CTRL' or mod))
    pcall(function() cs:SetVerticalAlignment(2) cs:SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 }) end)
    local art = root and slotArtFrom(root)
    local cells = {}
    for k = 1, T.SLOTS do cells[k] = cell(tree, row, k, art) end
    if pos == 'actionbar' then
        for k = ACTIONBAR_SLOTS + 1, T.SLOTS do pcall(function() cells[k].box:SetVisibility(COLLAPSED) end) end
    end
    tree.RootWidget = row
    local anchor = findAnchor(pos)
    local how = place(host, anchor, pc, pos)
    T.debugLog(string.format('quick row placed (%s): %s; slot backing %s', pos, how,
        cells[1].copied and "copied from the action bar" or "drawn (action bar slot art not found)"))
    if T.cfg.Debug and not dumped then dumped = true pcall(dumpHud) end
    local hostPath = pathOf(host)
    if hostPath then madeHosts[#madeHosts + 1] = hostPath end
    return { host = host, hostPath = hostPath, cells = cells, shown = nil, pos = pos, offset = offset() }
end

local function setShown(on)
    if not view or view.shown == on then return end
    view.shown = on
    pcall(function() view.host:SetVisibility(on and HIT_TEST_INVISIBLE or COLLAPSED) end)
end

-- Icons: a slot counts as done only once its icon is drawn, so a texture that
-- was not loaded yet is simply tried again on the next refresh.
local function refresh()
    local held = T.heldName()
    for k, c in ipairs(view.cells) do
        local data = T.dataAt(T.toolbagSlot(k))
        local dataPath = data and T.pathOf(data) or nil
        if dataPath ~= c.drawn then
            if not dataPath then
                c.image:SetVisibility(COLLAPSED)
                c.drawn = nil
            else
                local texPath = W.iconPathOf and W.iconPathOf(dataPath)
                local tex = texPath and (get(function() return StaticFindObject(texPath) end) or get(function() return LoadAsset(texPath) end))
                if valid(tex) and pcall(function() c.image:SetBrushFromTexture(tex, false) end) then
                    c.image:SetVisibility(HIT_TEST_INVISIBLE)
                    c.drawn = dataPath
                end
            end
        end
        -- Durability, rounded to whole pixels so the bar only redraws when it moves.
        local frac = data and T.durabilityAt and T.durabilityAt(T.toolbagSlot(k)) or nil
        local px = frac and math.floor(frac * DUR_W + 0.5) or nil
        if px ~= c.durPx then
            c.durPx = px
            if px then
                pcall(function() c.fillBox:SetWidthOverride(math.max(px, 0.01)) end)
                pcall(function() c.durFill:SetBrushColor(frac < DUR_LOW and DUR.low or DUR.good) end)
                c.durBox:SetVisibility(HIT_TEST_INVISIBLE)
            else
                c.durBox:SetVisibility(COLLAPSED)
            end
        end
        -- The embroidered frame, tried each refresh until the game's slot art is found.
        if not c.framed and W.copySlotArt and W.copySlotArt(c.frame, 'tab') then
            c.framed = true
            c.frame:SetVisibility(HIT_TEST_INVISIBLE)
            pcall(function() c.edge:SetBrushColor(CLEAR) end)
            pcall(function() c.fill:SetBrushColor(CLEAR) end)
            if k == 1 then T.debugLog("quick row: slots use the game's item slot frame") end
        end
        local sel = data ~= nil and T.nameOf(data) == held
        if sel ~= c.selected then
            c.selected = sel
            pcall(function() c.ring:SetVisibility(sel and HIT_TEST_INVISIBLE or COLLAPSED) end)
        end
    end
end

-- Removes every row widget made so far (looked up by path, not by a kept object).
local function removeAll()
    for _, p in ipairs(madeHosts) do
        local o = lookUp(p)
        if o then pcall(function() o:RemoveFromParent() end) end
    end
    madeHosts = {}
end

function H.forget()
    removeAll()
    view, nextLook = nil, 0
end

function H.tick(now)
    if T.cfg.QuickRow == false or failed or not T.ready() then setShown(false) return end
    local pc = T.pc()
    if not T.isValid(pc) then setShown(false) return end
    -- Rebuild when the position setting changed (at once), or when the row's
    -- widget is really gone: looked up by path every 2 s, rebuilt at most every 10 s.
    if view and (view.pos ~= position() or view.offset ~= offset()) then
        H.forget()
    elseif view and now >= (view.nextCheck or 0) then
        view.nextCheck = now + 2
        if not lookUp(view.hostPath) then
            T.debugLog('quick row: its widget is gone; building it again in 10 s')
            removeAll()
            view, nextLook = nil, now + 10
        end
    end
    if not view then
        if now < nextLook then return end
        nextLook = now + 10
        local ok, result = pcall(build, hudRoot(), pc)
        if not ok then
            failed = true
            T.log('quick row off: ' .. tostring(result))
            return
        end
        view, nextRefresh = result, 0
    end
    local menu = get(function() return pc.bShowMouseCursor end) == true
    setShown(not menu)
    if not menu and now >= nextRefresh then
        nextRefresh = now + 0.5
        local ok, err = pcall(refresh)
        if not ok then T.debugLog('quick row: ' .. tostring(err)) end
    end
end

return H
