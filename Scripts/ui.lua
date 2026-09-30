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
local COLOR = {
    slot         = { R = 0.040, G = 0.036, B = 0.031, A = 0.92 },
    slotHover    = { R = 0.085, G = 0.072, B = 0.052, A = 0.95 },
    slotSelected = { R = 0.190, G = 0.145, B = 0.070, A = 0.95 },
    slotEdge     = { R = 0.150, G = 0.132, B = 0.105, A = 1 },
    hoverEdge    = { R = 0.520, G = 0.420, B = 0.240, A = 1 },
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
local function valid(o) local k = type(o) return (k == 'userdata' or k == 'table') and o:IsValid() == true end
local function get(fn) local ok, v = pcall(fn) if ok then return v end return nil end
local function fullName(o) return valid(o) and (get(function() return o:GetFullName() end) or '') or '' end

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

local fontCache = {}
local function newText(tree, px, color, weight)
    local tb = widget('TextBlock', tree)
    local kind = weight or 'regular'
    if fontCache[kind] == nil then
        local ok, f = pcall(LoadAsset, FONTS[kind])
        fontCache[kind] = ok and valid(f) and f or false
    end
    pcall(function() if fontCache[kind] then tb.Font.FontObject = fontCache[kind] end end)
    pcall(function() tb.Font.Size = px end)
    pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
    pcall(function() tb:SetTextOverflowPolicy(1) end)
    return tb
end
local function setText(tb, s, cache, key)
    if cache and cache[key] == s then return end
    if pcall(function() tb:SetText(FText(s)) end) and cache then cache[key] = s end
end

local buttonClass = nil
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
    if not valid(buttonClass) then
        buttonClass = LoadAsset(BUTTON_CLASS)
        assert(valid(buttonClass), 'game button class missing')
    end
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

local iconCache = {}
local function iconOf(data)
    if not valid(data) then return nil end
    local key = fullName(data)
    if iconCache[key] ~= nil then return iconCache[key] or nil end
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
    iconCache[key] = tex or false
    return tex
end

-- ------------------------------------------------------------------ cells
local function paint(c)
    local edge = c.selected and COLOR.gold or (c.hovered and COLOR.hoverEdge or COLOR.slotEdge)
    local fill = c.selected and COLOR.slotSelected or (c.hovered and COLOR.slotHover or COLOR.slot)
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
    local c = { edge = edge, bg = bg, image = image, box = sizeBox }
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

local function show(c, data)
    c.data = data
    local tex = data and iconOf(data) or nil
    if tex ~= c.tex then
        c.tex = tex
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
    local title = newText(tree, 15, COLOR.gold, 'medium')
    setText(title, STR.title)
    local ts = add(header, title)
    size(ts, FILL)
    align(ts, nil, V_CENTER)
    local _, closeSlot = gameButton(view, header, STR.close, function() Dock.close(DOCK_ID) end, 90, 34)
    align(closeSlot, nil, V_CENTER)

    local keys = newText(tree, 11, COLOR.dim)
    setText(keys, string.format(STR.keys, tostring(T.cfg.SlotKeys):upper()))
    pad(add(root, keys), 2, 6, 2, 6)

    local grid = widget('UniformGridPanel', tree)
    pcall(function() grid:SetSlotPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 }) end)
    add(root, grid)
    for k = 1, T.SLOTS do
        view.slots[k] = cell(view, grid, k - 1, function() W.clickSlot(k) end, tostring(k % 10))
    end

    view.details = newText(tree, 14, COLOR.gold, 'medium')
    pad(add(root, view.details), 2, 6, 2, 0)

    local sub = newText(tree, 11, COLOR.dim)
    setText(sub, STR.bagTools)
    pad(add(root, sub), 2, 10, 2, 4)

    local list = widget('ScrollBox', tree)
    local listSlot = add(root, list)
    size(listSlot, FILL)
    local bagGrid = widget('UniformGridPanel', tree)
    pcall(function() bagGrid:SetSlotPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 }) end)
    add(list, bagGrid)
    for j = 1, BAG_CELLS do
        view.bag[j] = cell(view, bagGrid, j - 1, function() W.clickBag(j) end)
    end
    view.none = newText(tree, 12, COLOR.dim)
    setText(view.none, STR.none)
    add(list, view.none)

    view.status = newText(tree, 11, COLOR.dim)
    pad(add(root, view.status), 2, 6, 2, 0)

    local footer = widget('HorizontalBox', tree)
    pad(add(root, footer), 0, 6, 0, 0)
    size(add(footer, widget('Spacer', tree)), FILL)
    gameButton(view, footer, STR.takeAll, function() T.takeAllOut() end, 90, 34)
    local _, s2 = gameButton(view, footer, STR.storeAll, function() T.storeAll() end, 90, 34)
    pad(s2, 6, 0, 0, 0)

    local rootSlot = host:AddChildToOverlay(root)
    align(rootSlot, H_FILL, V_FILL)
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
        show(view.slots[k], ready and T.dataAt(T.toolbagSlot(k)) or nil)
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
        show(view.bag[j], e and e.data or nil)
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
        if h and c.data then label = T.displayName(c.data) end
    end
    local held = T.heldName()
    for k = 1, T.SLOTS do
        local c = view.slots[k]
        local sel = c.data ~= nil and T.nameOf(c.data) == held
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
        if best[f] then item = (fullName(best[f].data):match('^%S+%s+(.+)$')) break end
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
        if open then lastRefresh, view.recenterTicks = 0, 3 end
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
