-- Toolbag window, drawn inside RSE-Dock's shared window beside the inventory.
-- Top: the 10 toolbag slots (Shift+1..0). Below: tools in your bag and hotbar;
-- click one to store it, click a toolbag slot to take the tool out.
-- Plain UMG cells in the inventory's style with the game's own (invisible)
-- button on top for input and the click sound, as in RSE-Transmog.
local T = require('toolbag_core')
local Dock = require('rse_dock')

local W = { built = nil, actions = {} }
local DOCK_ID = 'toolbag'
local TAG = 'RSEToolbag_'
local BUTTON_CLASS = '/Game/UI/Common/WBP_DomButton_NoIcon.WBP_DomButton_NoIcon_C'
local FONTS = {
    regular = '/Game/UI/Fonts/Poppins-Regular_Font.Poppins-Regular_Font',
    medium = '/Game/UI/Fonts/Poppins-Medium_Font.Poppins-Medium_Font',
}
local VISIBLE, COLLAPSED, HIT_TEST_INVISIBLE, SELF_HIT_TEST_INVISIBLE = 0, 1, 3, 4
local H_FILL, H_LEFT, H_CENTER, H_RIGHT = 0, 1, 2, 3
local V_FILL, V_TOP, V_CENTER, V_BOTTOM = 0, 1, 2, 3
local FILL = { SizeRule = 1, Value = 1 }
local COLUMNS, CELL, ICON = 5, 86, 62
local BAG_CELLS = 20
-- Window spacing, shared with RSE-Transmog's ui.lua (keep both in sync). The
-- content sits at the inventory frame's own inset times 0.9 (RSE-Dock's
-- shared window; Transmog's FRAME_INSET), plus CONTENT_PAD.
local CONTENT_PAD = 0 -- window inset to the content
local ROW_GAP = 6     -- between rows: title/Close, hint, grids, footer
local CELL_PAD = 2    -- grid slot padding: cells are 2 * CELL_PAD apart
local BUTTON_W, BUTTON_H, TITLE_SIZE = 90, 34, 15 -- Close and footer buttons, title text
local COLOR = {
    -- Slots: the game's slot art underneath (see copySlotArt); `slot` only if
    -- that cannot be copied. Hover and selection are drawn over it.
    slot         = { R = 0.040, G = 0.036, B = 0.031, A = 0.92 },
    emptySlot    = { R = 0, G = 0, B = 0, A = 0.22 }, -- the inventory's empty slot over the panel texture
    slotHover    = { R = 0.150, G = 0.120, B = 0.075, A = 0.45 },
    slotSelected = { R = 0.190, G = 0.145, B = 0.070, A = 0.95 },
    hoverEdge    = { R = 0.520, G = 0.420, B = 0.240, A = 1 },
    clear        = { R = 0, G = 0, B = 0, A = 0 },
    gold         = { R = 0.96, G = 0.82, B = 0.50, A = 1 },
    text         = { R = 0.88, G = 0.85, B = 0.78, A = 1 },
    dim          = { R = 0.58, G = 0.55, B = 0.50, A = 1 },
}
local STR = {
    title = 'TOOLBAG', close = 'Close', storeAll = 'Store all', takeAll = 'Take all',
    bagTools = 'Tools in your bag - click to store',
    keys = '%s + number equips a slot',
    empty = 'Empty slot', none = 'No other tools in your bag',
    notReady = 'Toolbag storage is disabled, check toolbag_status in console.',
}

local function log(s) T.log('[window] ' .. tostring(s)) end
local function debugLog(s) T.debugLog('[window] ' .. tostring(s)) end -- only with Debug on
local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function fullName(o) return valid(o) and (get(function() return o:GetFullName() end) or '') or '' end
local function pathOf(o) return (fullName(o):match('^%S+%s+(.+)$')) or '' end

-- Game objects are never kept between calls. The engine unloads assets and
-- widgets that nothing of its own references, and a Lua table does not count:
-- a cached object can be freed memory by the next use, and touching it
-- crashes the game natively (RSE-Transmog, dumps 2026-09-30 15:57 to 18:50).
-- Caches hold object paths (strings); the object is looked up again each time.
local function loadObject(p)
    if type(p) ~= 'string' or p == '' then return nil end
    local o = get(function() return StaticFindObject(p) end)
    if valid(o) then return o end
    o = get(function() return LoadAsset(p) end)
    if valid(o) then return o end
    o = get(function() return StaticFindObject(p) end)
    return valid(o) and o or nil
end

local tagCount = 0
local function widget(kind, outer, tag)
    local cls = StaticFindObject('/Script/UMG.' .. kind)
    assert(valid(cls), 'missing UMG class ' .. kind)
    if tag then
        tagCount = tagCount + 1
        return StaticConstructObject(cls, outer, FName(string.format('%s%s_%d_%d_%d',
            TAG, tag, os.time(), math.floor(os.clock() * 1000), tagCount)))
    end
    return StaticConstructObject(cls, outer)
end

local function removeStale(parent)
    local n = valid(parent) and (get(function() return parent:GetChildrenCount() end) or 0) or 0
    for i = n - 1, 0, -1 do
        local child = get(function() return parent:GetChildAt(i) end)
        local name = valid(child) and (get(function() return child:GetFName():ToString() end) or '') or ''
        if name:sub(1, #TAG) == TAG then pcall(function() child:RemoveFromParent() end) end
    end
end

local function align(slot, h, v)
    if h then pcall(function() slot:SetHorizontalAlignment(h) end) end
    if v then pcall(function() slot:SetVerticalAlignment(v) end) end
end
local function pad(slot, l, t, r, b) pcall(function() slot:SetPadding({ Left = l, Top = t, Right = r, Bottom = b }) end) end
local function size(slot, rule) pcall(function() slot:SetSize(rule) end) end
local function add(parent, child)
    if parent:IsA('/Script/UMG.VerticalBox') then return parent:AddChildToVerticalBox(child) end
    if parent:IsA('/Script/UMG.HorizontalBox') then return parent:AddChildToHorizontalBox(child) end
    if parent:IsA('/Script/UMG.Overlay') then return parent:AddChildToOverlay(child) end
    if parent:IsA('/Script/UMG.UniformGridPanel') then return parent:AddChildToUniformGrid(child, 0, 0) end
    return parent:AddChild(child)
end

local function newText(tree, px, color, weight)
    local tb = widget('TextBlock', tree)
    local f = loadObject(FONTS[weight or 'regular']) -- by path, never cached
    pcall(function() if f then tb.Font.FontObject = f end end)
    pcall(function() tb.Font.Size = px end)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    pcall(function() tb:SetTextOverflowPolicy(1) end)
    return tb
end
local function setText(tb, s, cache, key)
    if cache and cache[key] == s then return end
    if pcall(function() tb:SetText(FText(s)) end) and cache then cache[key] = s end
end

local UEH = nil
pcall(function() UEH = require('UEHelpers') end)
-- The game button left-aligns its label (a left padding plus a spacer taking
-- the rest of the row) and re-applies that inset when it is first drawn.
-- Centre the label and let the row span the button, as RSE-Transmog does;
-- re-applied for a few ticks after the window opens (see W.tick).
local H_FILL_ALIGN = 0
local function centerLabel(b)
    pcall(function() b.bCenterAlignText = true end)
    pcall(function() b.LeftAlignTextPadding = 0 end)
    local label = get(function() return b.LabelText end)
    if not valid(label) then return end
    pcall(function() label:SetJustification(1) end)
    pcall(function() label.Slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
    pcall(function() label.Slot:SetHorizontalAlignment(H_CENTER) end)
    local box = get(function() return label:GetParent() end)
    if valid(box) then
        pcall(function() box.Slot:SetSize(FILL) end)
        pcall(function() box.Slot:SetHorizontalAlignment(H_CENTER) end)
        local row = get(function() return box:GetParent() end)
        if valid(row) then pcall(function() row.Slot:SetHorizontalAlignment(H_FILL_ALIGN) end) end
    end
end

-- Width that fits a label in the game button's font (Transmog's measurement:
-- about 11 units per character plus 32 of padding).
local function fitWidth(label, minW)
    local n = utf8 and utf8.len(label) or #label
    return math.max(minW or 0, (n or #label) * 11 + 32)
end

local function gameButton(view, parent, label, action, minW, minH)
    local buttonClass = loadObject(BUTTON_CLASS) -- by path, never cached
    assert(valid(buttonClass), 'game button class missing')
    local library = StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local b = get(function() return library:Create(UEH and UEH.GetWorld(), buttonClass, T.pc()) end)
    assert(valid(b), 'could not create a game button')
    local slot = add(parent, b)
    local width = label ~= '' and fitWidth(label, minW) or (minW or 10)
    pcall(function() b:SetMinDimensions(width, minH or 10) end)
    if label ~= '' then
        pcall(function() b:SetLabelText(FText(label)) end)
        centerLabel(b)
        view.buttons = view.buttons or {}
        view.buttons[#view.buttons + 1] = b
    end
    if action then
        local key = fullName(b)
        W.actions[key] = action
        view.actionKeys[#view.actionKeys + 1] = key
    end
    return b, slot
end

-- ------------------------------------------------------------------ icons
local function softPath(soft)
    for _, read in ipairs({
        function() return soft.ObjectID.AssetPath end,
        function() return soft.AssetPath end,
        function() return soft:get().AssetPath end,
    }) do
        local ap = get(read)
        if ap then
            local pkg = get(function() return ap.PackageName:ToString() end)
            local asset = get(function() return ap.AssetName:ToString() end)
            if pkg and asset and pkg ~= '' and asset ~= 'None' then return pkg .. '.' .. asset end
        end
    end
    return nil
end

-- Icon texture PATH of an item data asset (by the data's path), or nil.
-- Only paths are cached; the texture is looked up when it is drawn.
local iconCache = {} -- item data path -> texture path, or false
local function iconPathOf(dataPath)
    if type(dataPath) ~= 'string' or dataPath == '' then return nil end
    if iconCache[dataPath] ~= nil then return iconCache[dataPath] or nil end
    local data = loadObject(dataPath)
    if not data then return nil end -- not cached: may load later
    local tex = nil
    local soft = get(function() return data.Icon end)
    if soft then
        local path = softPath(soft)
        if path then
            local t = get(function() return LoadAsset(path) end)
            if valid(t) then tex = t end
        end
        if not tex then
            local kismet = StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
            local t = get(function() return kismet:LoadAsset_Blocking(soft) end)
            if valid(t) then tex = t end
        end
    end
    local texPath = tex and pathOf(tex) or ''
    iconCache[dataPath] = texPath ~= '' and texPath or false
    return iconCache[dataPath] or nil
end

-- --------------------------------------------------------------- slot art
-- The game's inventory slot art for the square cells, copied from live
-- inventory slots (WBP_Inventory_ItemSlot_C, a CommonUI button that draws its
-- background from its button style). Two looks:
--   cell  (look grid) what an EMPTY inventory slot draws: the brush its root
--         button draws now (WidgetStyle.Disabled while disabled, else
--         .Normal), else its NormalStyle.Normal; then the tab chain.
--   tab   (tab column) the slot style's NormalBase (the item slot frame),
--         else NormalStyle.Normal, else CommonSlotBackground.
-- Only brush data is copied (a struct holding the texture or material); the
-- slot widget itself, with its hover particles (NS_InventoryHighlight), is
-- never created. Same code as RSE-Transmog
-- (its `transmog_slotart` console command logs every candidate brush).
local SLOT_CLASS = 'WBP_Inventory_ItemSlot_C'
-- The source slots are remembered by path (strings) and looked up again on
-- each use, never kept as objects.
local slotSource, emptySource, slotSearched = nil, nil, -math.huge -- paths
local slotArtLogged = {}

local function paintable(brush)
    return get(function()
        if brush.DrawAs == 0 or not valid(brush.ResourceObject) then return false end -- 0 = no draw
        return brush.TintColor.ColorUseRule ~= 0 or brush.TintColor.SpecifiedColor.A > 0.01
    end) == true
end

local function isEmpty(s) return not valid(get(function() return s.ContainedItem end)) end

-- Any live inventory slot, and an empty one (main grid first, then any), both
-- searched again (at most every 2 s) once gone or no longer empty.
local function lookUp(p)
    if not p then return nil end
    local o = get(function() return StaticFindObject(p) end)
    return valid(o) and o or nil
end
local function findSlots()
    local slot, empty = lookUp(slotSource), lookUp(emptySource)
    local emptyOk = empty ~= nil and isEmpty(empty)
    if slot and emptyOk then return slot, empty end
    if os.clock() - slotSearched >= 2 then
        slotSearched = os.clock()
        local any, emptyAny, emptyGrid
        for _, s in ipairs(get(function() return FindAllOf(SLOT_CLASS) end) or {}) do
            local n = valid(s) and fullName(s) or ''
            if n ~= '' and not n:find('Default__', 1, true) then
                any = any or s
                if not emptyGrid and isEmpty(s) then
                    -- The main grid's slots, not the quick-access bar's.
                    if n:find('InventoryBody', 1, true) then emptyGrid = s else emptyAny = emptyAny or s end
                end
            end
        end
        local e = emptyGrid or emptyAny
        slotSource = any and pathOf(any) or nil
        emptySource = e and pathOf(e) or nil
        slot, empty, emptyOk = any, e, e ~= nil
    end
    return slot, emptyOk and empty or nil
end

-- The brush a slot's root button (InternalRootButtonBase) draws now.
local function drawnBrush(s)
    local button = get(function() return s.WidgetTree.RootWidget end)
    if not (valid(button) and get(function() return button:IsA('/Script/UMG.Button') end)) then return nil end
    if get(function() return button:GetIsEnabled() end) == false then
        return get(function() return button.WidgetStyle.Disabled end)
    end
    return get(function() return button.WidgetStyle.Normal end)
end

-- Copies the `kind` look onto `image`; returns the source slot and what was
-- copied, or nil.
local function copySlotArt(image, kind)
    local any, empty = findSlots()
    local sources = {}
    if kind ~= 'tab' and empty then
        sources[#sources + 1] = { empty, 'empty slot button', function() return drawnBrush(empty) end }
        sources[#sources + 1] = { empty, 'empty slot NormalStyle.Normal', function() return empty.NormalStyle.Normal end }
    end
    if any then
        local style = get(function() return any:GetStyle() end)
        sources[#sources + 1] = { any, 'style NormalBase', function() return style.NormalBase end }
        sources[#sources + 1] = { any, 'NormalStyle.Normal', function() return any.NormalStyle.Normal end }
    end
    for _, source in ipairs(sources) do
        local brush = get(source[3])
        if brush and paintable(brush) and pcall(function() image:SetBrush(brush) end)
            and valid(get(function() return image.Brush.ResourceObject end)) then
            return source[1], source[2]
        end
    end
    local resource = any and get(function() return any.CommonSlotBackground end)
    if valid(resource) then
        if get(function() return resource:IsA('/Script/Engine.Texture2D') end)
            and pcall(function() image:SetBrushFromTexture(resource, false) end) then
            return any, 'CommonSlotBackground'
        elseif get(function() return resource:IsA('/Script/Engine.MaterialInterface') end)
            and pcall(function() image:SetBrushFromMaterial(resource) end) then
            return any, 'CommonSlotBackground'
        end
    end
    return nil
end

-- Gives a square cell its slot art once it can be found (flat `slot` till then).
local function slotArt(c)
    if c.artCopied or not valid(c.art) then return end
    local kind = c.artKind or 'cell'
    if kind == 'cell' then
        -- Grid cells look like the inventory's empty slots: those draw no
        -- texture of their own (every slot brush is empty, transmog_slotart
        -- 2026-09-30), only a slightly darker square over the panel's grain,
        -- measured at about 79% of the panel's brightness.
        pcall(function() c.art:SetColorAndOpacity(COLOR.emptySlot) end)
        c.artCopied = true
        return
    end
    local from, copied = copySlotArt(c.art, kind)
    if copied then
        pcall(function() c.art:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 1 }) end)
        c.artCopied = true
        if not slotArtLogged[kind] then
            slotArtLogged[kind] = true
            debugLog(kind .. ' slot art copied from ' .. fullName(from) .. ' (' .. copied .. ')')
        end
    end
end

-- ------------------------------------------------------------------ cells
local function paint(c)
    local edge = c.selected and COLOR.gold or (c.hovered and COLOR.hoverEdge or COLOR.clear)
    local fill = c.selected and COLOR.slotSelected or (c.hovered and COLOR.slotHover or COLOR.clear)
    if c.paintedEdge ~= edge then c.paintedEdge = edge; pcall(function() c.edge:SetBrushColor(edge) end) end
    if c.paintedFill ~= fill then c.paintedFill = fill; pcall(function() c.bg:SetBrushColor(fill) end) end
end

local function cell(view, grid, index, action, corner)
    local tree = view.tree
    local sizeBox = widget('SizeBox', tree)
    sizeBox:SetHeightOverride(CELL)
    pcall(function() sizeBox:SetClipping(1) end)
    local overlay = widget('Overlay', tree)
    sizeBox:SetContent(overlay)
    -- The slot art underneath; hover and selection outline and fill over it.
    local art = widget('Image', tree)
    pcall(function() art:SetColorAndOpacity(COLOR.slot) end)
    art:SetVisibility(HIT_TEST_INVISIBLE)
    align(overlay:AddChildToOverlay(art), H_FILL, V_FILL)
    local edge = widget('Border', tree)
    edge:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 })
    local bg = widget('Border', tree)
    pcall(function() bg:SetHorizontalAlignment(H_CENTER) end)
    pcall(function() bg:SetVerticalAlignment(V_CENTER) end)
    edge:SetContent(bg)
    edge:SetVisibility(HIT_TEST_INVISIBLE)
    align(overlay:AddChildToOverlay(edge), H_FILL, V_FILL)
    local iconBox = widget('SizeBox', tree)
    iconBox:SetWidthOverride(ICON)
    iconBox:SetHeightOverride(ICON)
    local image = widget('Image', tree)
    image:SetVisibility(COLLAPSED)
    iconBox:SetContent(image)
    bg:SetContent(iconBox)
    local c = { art = art, edge = edge, bg = bg, image = image, box = sizeBox }
    slotArt(c)
    if corner then
        local label = newText(tree, 11, COLOR.dim, 'medium')
        setText(label, corner)
        label:SetVisibility(HIT_TEST_INVISIBLE)
        local s = overlay:AddChildToOverlay(label)
        align(s, H_RIGHT, V_BOTTOM)
        pad(s, 0, 0, 6, 3)
    end
    local hit, hitSlot = gameButton(view, overlay, '', action, 10, 10)
    align(hitSlot, H_FILL, V_FILL)
    hit:SetRenderOpacity(0)
    c.hit = hit
    local slot = add(grid, sizeBox)
    pcall(function() slot:SetRow(index // COLUMNS) end)
    pcall(function() slot:SetColumn(index % COLUMNS) end)
    align(slot, H_FILL, V_FILL)
    paint(c)
    view.cells[#view.cells + 1] = c
    return c
end

-- Plain data of an item data object, read now: { name, label, path }.
local function itemInfo(data)
    if not valid(data) then return nil end
    return { name = T.nameOf(data), label = T.displayName(data), path = pathOf(data) }
end

-- `item` is plain data { name, label, path } (see itemInfo), or nil. Cells
-- keep only these strings, never the item data object.
local function show(c, item)
    c.data = item
    local texPath = item and iconPathOf(item.path) or nil
    if texPath ~= c.texPath then
        local tex = texPath and loadObject(texPath)
        c.texPath = tex and texPath or nil
        if tex then
            pcall(function() c.image:SetBrushFromTexture(tex, false) end)
            c.image:SetVisibility(HIT_TEST_INVISIBLE)
        else
            c.image:SetVisibility(COLLAPSED)
        end
    end
end

-- ------------------------------------------------------------------ build
local function build(host, panel)
    local tree = panel.WidgetTree
    pcall(removeStale, host)
    local view = { host = host, tree = tree, cells = {}, actionKeys = {}, cache = {}, bag = {}, slots = {} }
    local root = widget('VerticalBox', tree, 'Root')
    view.root = root

    local header = widget('HorizontalBox', tree)
    add(root, header)
    local title = newText(tree, TITLE_SIZE, COLOR.gold, 'medium')
    setText(title, STR.title)
    local ts = add(header, title)
    size(ts, FILL)
    align(ts, nil, V_CENTER)
    local _, closeSlot = gameButton(view, header, STR.close, function() Dock.close(DOCK_ID) end, BUTTON_W, BUTTON_H)
    align(closeSlot, nil, V_CENTER)

    local keys = newText(tree, 11, COLOR.dim)
    setText(keys, string.format(STR.keys, tostring(T.cfg.SlotKeys):upper()))
    pad(add(root, keys), 2, ROW_GAP, 2, ROW_GAP)

    local grid = widget('UniformGridPanel', tree)
    pcall(function() grid:SetSlotPadding({ Left = CELL_PAD, Top = CELL_PAD, Right = CELL_PAD, Bottom = CELL_PAD }) end)
    add(root, grid)
    for k = 1, T.SLOTS do
        view.slots[k] = cell(view, grid, k - 1, function() W.clickSlot(k) end, tostring(k % 10))
    end

    view.details = newText(tree, 14, COLOR.gold, 'medium')
    pad(add(root, view.details), 2, ROW_GAP, 2, 0)

    local sub = newText(tree, 11, COLOR.dim)
    setText(sub, STR.bagTools)
    pad(add(root, sub), 2, 10, 2, 4)

    local list = widget('ScrollBox', tree)
    local listSlot = add(root, list)
    size(listSlot, FILL)
    local bagGrid = widget('UniformGridPanel', tree)
    pcall(function() bagGrid:SetSlotPadding({ Left = CELL_PAD, Top = CELL_PAD, Right = CELL_PAD, Bottom = CELL_PAD }) end)
    add(list, bagGrid)
    for j = 1, BAG_CELLS do
        view.bag[j] = cell(view, bagGrid, j - 1, function() W.clickBag(j) end)
    end
    view.none = newText(tree, 12, COLOR.dim)
    setText(view.none, STR.none)
    add(list, view.none)

    view.status = newText(tree, 11, COLOR.dim)
    pad(add(root, view.status), 2, ROW_GAP, 2, 0)

    local footer = widget('HorizontalBox', tree)
    pad(add(root, footer), 0, ROW_GAP, 0, 0)
    size(add(footer, widget('Spacer', tree)), FILL)
    gameButton(view, footer, STR.takeAll, function() T.takeAllOut() end, BUTTON_W, BUTTON_H)
    local _, s2 = gameButton(view, footer, STR.storeAll, function() T.storeAll() end, BUTTON_W, BUTTON_H)
    pad(s2, 6, 0, 0, 0)

    local rootSlot = host:AddChildToOverlay(root)
    align(rootSlot, H_FILL, V_FILL)
    pad(rootSlot, CONTENT_PAD, CONTENT_PAD, CONTENT_PAD, CONTENT_PAD)
    root:SetVisibility(COLLAPSED)
    return view
end

-- ---------------------------------------------------------------- actions
function W.clickSlot(k)
    local v = W.built
    if not v then return end
    local c = v.slots[k]
    if c and c.data then T.takeOut(T.toolbagSlot(k)) end
end

function W.clickBag(j)
    local v = W.built
    local e = v and v.bagEntries and v.bagEntries[j]
    if e then T.storeTool(e.slot) end
end

-- ---------------------------------------------------------------- refresh
local function refresh(view)
    local ready = T.ready()
    for k = 1, T.SLOTS do
        show(view.slots[k], ready and itemInfo(T.dataAt(T.toolbagSlot(k))) or nil)
    end
    local entries = {}
    if ready then
        for _, e in ipairs(T.tools().all) do
            if not e.toolbag then entries[#entries + 1] = e end
        end
    end
    view.bagEntries = entries
    for j = 1, BAG_CELLS do
        local e = entries[j]
        show(view.bag[j], e and { name = e.name, label = e.label, path = e.path } or nil)
        local visible = e ~= nil
        if view.bag[j].visible ~= visible then
            view.bag[j].visible = visible
            view.bag[j].box:SetVisibility(visible and SELF_HIT_TEST_INVISIBLE or COLLAPSED)
        end
    end
    local noneVisible = #entries == 0
    if view.noneVisible ~= noneVisible then
        view.noneVisible = noneVisible
        view.none:SetVisibility(noneVisible and HIT_TEST_INVISIBLE or COLLAPSED)
    end
    if not ready then setText(view.status, STR.notReady, view.cache, 'status')
    elseif view.message and os.clock() < view.message.expires then setText(view.status, view.message.text, view.cache, 'status')
    else setText(view.status, T.busy() and 'Moving...' or '', view.cache, 'status') end
end

local function hover(view)
    local label = nil
    for _, c in ipairs(view.cells) do
        local h = get(function() return c.hit:IsHovered() end) == true
        if h ~= c.hovered then c.hovered = h; paint(c) end
        if h and c.data then label = c.data.label end
    end
    local held = T.heldName()
    for k = 1, T.SLOTS do
        local c = view.slots[k]
        local sel = c.data ~= nil and c.data.name == held
        if sel ~= c.selected then c.selected = sel; paint(c) end
        if c.hovered and not c.data then label = STR.empty end
    end
    setText(view.details, label or '', view.cache, 'details')
end

-- ------------------------------------------------------------------- tick
local registered, iconItem = false, nil
local lastRefresh = 0

-- A pickaxe's item data for the icon when you carry no tool yet (or storage is
-- off): searched once among the loaded item data, the first time it is needed.
local fallbackItem = nil
local function anyPickaxe()
    if fallbackItem ~= nil then return fallbackItem or nil end
    fallbackItem = false
    local ok, all = pcall(FindAllOf, 'ItemData')
    for _, d in ipairs(ok and all or {}) do
        local n = T.nameOf(d)
        if n:find('ITEM_Pickaxe_', 1, true) == 1 then
            fallbackItem = (fullName(d):match('^%S+%s+(.+)$')) or false
            if n == 'ITEM_Pickaxe_Bronze' then break end
        end
    end
    return fallbackItem or nil
end

local function register()
    if not Dock.present() then return end
    -- The icon: the best tool you carry (pickaxe first), else any pickaxe the game has loaded.
    local item = nil
    local best = T.tools().best
    for _, f in ipairs(T.FAMILY_ORDER) do
        if best[f] and best[f].path ~= '' then item = best[f].path break end
    end
    if not item and Dock.inventoryOpen() then item = anyPickaxe() end
    if registered and (item == nil or item == iconItem) then return end
    Dock.register(DOCK_ID, { order = 20, label = 'Toolbag', item = item, window = 'host',
        desc = 'Keep your tools out of your bag. ' .. tostring(T.cfg.SlotKeys):upper()
            .. ' + 1-0 equips a toolbag slot; ' .. tostring(T.cfg.ToolKey):upper() .. ' equips the right tool for what you face.' })
    registered, iconItem = true, item
end

local warnedNoDock = false
function W.tick(now)
    if not Dock.present() then
        if not warnedNoDock and Dock.inventoryOpen() == false and T.ready() then
            warnedNoDock = true
            log('RSE-Dock is not installed: the toolbag window is unavailable. Toolbag keys and the tool key still work.')
        end
        return
    end
    register()
    local host, panel = Dock.host(), Dock.panel()
    local view = W.built
    if view and (not valid(view.root) or not valid(view.host) or (host and fullName(host) ~= fullName(view.host))) then
        for _, k in ipairs(view.actionKeys) do W.actions[k] = nil end
        W.built, view = nil, nil
    end
    if not view and host and panel then
        local ok, result = pcall(build, host, panel)
        if ok then W.built, view = result, result
        else log('build: ' .. tostring(result)) return end
    end
    if not view then return end
    local open = Dock.isOpen(DOCK_ID)
    if open ~= view.open then
        view.open = open
        view.root:SetVisibility(open and SELF_HIT_TEST_INVISIBLE or COLLAPSED)
        if open then
            lastRefresh, view.recenterTicks = 0, 3
            -- Cells built before any inventory slot existed get the slot art now.
            for _, c in ipairs(view.cells) do slotArt(c) end
        end
    end
    if not open then return end
    if (view.recenterTicks or 0) > 0 then
        view.recenterTicks = view.recenterTicks - 1
        for _, b in ipairs(view.buttons or {}) do if valid(b) then centerLabel(b) end end
    end
    hover(view)
    if now - lastRefresh >= 0.3 then
        lastRefresh = now
        refresh(view)
    end
end

-- Map loads: drop the cached inventory slots (slot art source) unread.
-- Shared with the quick row (hotbar.lua): icon texture path of an item data path.
W.iconPathOf = function(dataPath) return iconPathOf(dataPath) end
-- Also shared: copies the game's slot art onto an Image (kind 'tab': the embroidered item slot frame).
W.copySlotArt = function(image, kind) return copySlotArt(image, kind) end

function W.forget()
    slotSource, emptySource, slotSearched = nil, nil, -math.huge
    iconCache = {} -- paths only; cleared on map load anyway, belt and braces
end

function W.start()
    T.onStatus(function(msg)
        if W.built then W.built.message = { text = msg, expires = os.clock() + 5 } end
    end)
    RegisterHook('/Script/CommonUI.CommonButtonBase:HandleButtonClicked', function(ctx)
        if next(W.actions) == nil then return end
        local action = W.actions[fullName(ctx:get())]
        if action then
            local ok, err = pcall(action)
            if not ok then log('button: ' .. tostring(err)) end
        end
    end)
end

return W
