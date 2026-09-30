-- RSE-Toolbag (RuneScape Enhanced): a 10-slot toolbag for RuneScape: Dragonwilds.
-- Based on Expanded Inventory by notto0606 (MIT).
--
-- The toolbag is 10 extra slots appended to the END of the player's last
-- inventory tab. Appending (instead of growing the bag) keeps every existing
-- slot index where it was, so no items move on existing characters. The
-- toolbag window lives in RSE-Dock's shared window beside the inventory.
local TAG = "[RSE-Toolbag] "
local VERSION = "2.0.0"
local MODMENU_ID = "RSE-Toolbag"

local cfg = {
    SlotKeys = "SHIFT",          -- modifier for 1-0 that equips toolbag slots: SHIFT, CTRL, ALT or NONE
    ToolKey = "X",               -- equip the right tool for what you face; "none" turns it off
    EquipPrompt = true,          -- "[X] Equip <tool>" hint near a rock, tree, farm plot or fishing spot
    AutoTool = true,
    AutoToolFromWeapon = true,
    ToolReach = 3.0,
    UseCompost = true,
    BagFirst = false,
    Debug = false,
}
local LIVE_KEYS = { "EquipPrompt", "AutoTool", "AutoToolFromWeapon", "ToolReach", "UseCompost", "BagFirst", "Debug" }

local PLAYER_CONTROLLER = "/Game/Gameplay/Character/Player/BP_PlayerController.BP_PlayerController_C"
local INVENTORY_TEMPLATE = PLAYER_CONTROLLER .. ":BP_Components_Inventory_GEN_VARIABLE"
local INVENTORY_PROPERTY = "BP_Components_Inventory"
local TOOLBAG_SLOTS = 10
-- Vanilla tab sizes seen on CL-240163 (bag, runes and ammo 24, quest 72). The
-- toolbag only grows a last tab that is exactly one of these (or one of these
-- plus the toolbag): anything else means another mod changed the layout, and
-- growing it could put items in the wrong place, so the toolbag stays off.
local VANILLA_SIZES = { [24] = true, [72] = true }
local SAFE_KINDS = {
    BoolProperty = true, FloatProperty = true, DoubleProperty = true, IntProperty = true, Int64Property = true,
    ByteProperty = true, EnumProperty = true, NameProperty = true, ObjectProperty = true, ClassProperty = true,
}
local NUMERIC = { FloatProperty = true, DoubleProperty = true, IntProperty = true, Int64Property = true, ByteProperty = true }

local function log(msg) print(TAG .. tostring(msg) .. "\n") end
local function debugLog(msg) if cfg.Debug then log(msg) end end

local function modRoot()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    return src:match("^(.*)[/\\]Scripts[/\\][^/\\]*$")
end

local function clampConfig()
    local reach = tonumber(cfg.ToolReach) or 3.0
    cfg.ToolReach = math.max(1.5, math.min(6.0, reach))
end

local function loadConfig()
    local root = modRoot()
    local f = root and io.open(root .. "\\config.txt", "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k and cfg[k] ~= nil then
            v = v:gsub("%s+[#;].*$", "")
            if type(cfg[k]) == "boolean" then cfg[k] = v:lower() == "true"
            elseif type(cfg[k]) == "number" then cfg[k] = tonumber(v) or cfg[k]
            else cfg[k] = v end
        end
    end
    f:close()
end
loadConfig()
clampConfig()

-- ------------------------------------------------------------ reflection
local function isValidObj(x)
    if x == nil or type(x) ~= "userdata" then return false end
    local ok, v = pcall(function() return x:IsValid() end)
    return ok and v == true
end

local function classPath(cls)
    local ok, full = pcall(function() return cls:GetFullName() end)
    if not ok or not full then return nil end
    return full:match("^%S+%s+(.+)$")
end

local function superOf(cls)
    local ok, sup = pcall(function() return cls:GetSuperStruct() end)
    if ok and sup and sup:IsValid() then return sup end
    return nil
end

local function nameOf(o)
    if not isValidObj(o) then return "" end
    local ok, n = pcall(function() return o:GetFName():ToString() end)
    return ok and tostring(n) or ""
end

local function classNameOf(o)
    if not isValidObj(o) then return "" end
    local ok, c = pcall(function() return o:GetClass() end)
    if not ok then return "" end
    return nameOf(c)
end

local kindCache = {}
local function propKind(obj, name)
    local key = (classPath(obj:GetClass()) or "?") .. ":" .. name
    local cached = kindCache[key]
    if cached ~= nil then return cached or nil end
    local found = nil
    local c = obj:GetClass()
    while c and not found do
        pcall(function()
            c:ForEachProperty(function(p)
                if not found and p:GetFName():ToString() == name then found = p:GetClass():GetFName():ToString() end
            end)
        end)
        c = superOf(c)
    end
    kindCache[key] = found or false
    return found
end

local function safeGet(obj, name)
    if not isValidObj(obj) then return nil end
    local kind = propKind(obj, name)
    if not kind or not SAFE_KINDS[kind] then return nil, kind end
    local ok, v = pcall(function() return obj:GetPropertyValue(name) end)
    if ok then return v, kind end
    return nil, kind
end

local function findFunction(obj, name)
    if not isValidObj(obj) then return nil end
    local cls = obj:GetClass()
    while cls do
        local path = classPath(cls)
        if path then
            local fn = StaticFindObject(path .. ":" .. name)
            if fn and fn:IsValid() then return fn end
        end
        cls = superOf(cls)
    end
    return nil
end

local function inputParams(fn)
    local list = {}
    pcall(function()
        fn:ForEachProperty(function(p)
            local name = p:GetFName():ToString()
            if name ~= "ReturnValue" then
                list[#list + 1] = { name = name, kind = p:GetClass():GetFName():ToString() }
            end
        end)
    end)
    return list
end

local function signature(params)
    local out = {}
    for _, p in ipairs(params) do out[#out + 1] = p.name .. ":" .. p.kind end
    return table.concat(out, ", ")
end

local function isPlayerCharacter(pawn)
    return isValidObj(pawn) and (classPath(pawn:GetClass()) or ""):find("BP_PlayerCharacter", 1, true) ~= nil
end

-- ---------------------------------------------------------------- layout
local function inventoryPages(o)
    local okA, pages = pcall(function() return o:GetPropertyValue("InventoryPages") end)
    if not okA or not pages then return nil end
    local okL, n = pcall(function() return #pages end)
    if not okL or type(n) ~= "number" then return nil end
    local list = {}
    for i = 1, n do
        local okT, t = pcall(function() return pages[i].SlotType end)
        local okN, s = pcall(function() return pages[i].NumSlots end)
        if not (okT and okN and type(t) == "number" and type(s) == "number") then return nil end
        list[i] = { type = t, slots = s }
    end
    return pages, list
end

local function slotCount(o)
    local ok, n = pcall(function() return #o:GetPropertyValue("ItemSlots") end)
    if ok and type(n) == "number" then return n end
    return nil
end

local layout = nil     -- toolbag layout of the local player's inventory, see growForToolbag
local refused = {}

-- Appends the toolbag to the last tab of `o` (the controller template or the
-- live inventory component). Idempotent: an already-grown tab stays as it is.
-- Returns the layout: { first, total, qa, pages = { {type, start, slots} } }.
local function growForToolbag(o, label)
    if not isValidObj(o) then return nil end
    local pages, list = inventoryPages(o)
    if not pages or #list == 0 then return nil end
    local qa = safeGet(o, "NumberOfQuickActionSlots")
    local maxBefore = safeGet(o, "MaxSlotCount")
    if type(qa) ~= "number" or type(maxBefore) ~= "number" then return nil end
    local last = #list
    local cur = list[last].slots
    local vanilla
    if VANILLA_SIZES[cur] then vanilla = cur
    elseif VANILLA_SIZES[cur - TOOLBAG_SLOTS] then vanilla = cur - TOOLBAG_SLOTS
    else
        if not refused[label] then
            refused[label] = true
            log(string.format("%s: last tab has %d slots, not a vanilla size; toolbag OFF so no item can move. "
                .. "Another inventory-size mod is probably installed.", label, cur))
        end
        return nil
    end
    local want = vanilla + TOOLBAG_SLOTS
    if cur < want then
        pcall(function() pages[last].NumSlots = want end)
        local okN, s = pcall(function() return pages[last].NumSlots end)
        if okN and type(s) == "number" then list[last].slots = s end
    end
    if list[last].slots ~= want then
        log(label .. ": could not add the toolbag slots to the last tab")
        return nil
    end
    local result = { qa = qa, pages = {} }
    local total = qa
    for i, p in ipairs(list) do
        result.pages[i] = { type = p.type, start = total, slots = p.slots }
        total = total + p.slots
    end
    if maxBefore < total then pcall(function() o:SetPropertyValue("MaxSlotCount", total) end) end
    result.total, result.first, result.pageType = total, total - TOOLBAG_SLOTS, list[last].type
    if cur ~= want or label ~= "template" then
        log(string.format("%s: last tab (type %d) %d -> %d slots, toolbag = slots %d-%d, MaxSlotCount %s -> %s",
            label, list[last].type, cur, want, result.first, total - 1, tostring(maxBefore), tostring(safeGet(o, "MaxSlotCount"))))
    end
    return result
end

local function patchInventoryTemplate()
    local tpl = StaticFindObject(INVENTORY_TEMPLATE)
    if isValidObj(tpl) then return growForToolbag(tpl, "template") end
    return nil
end

local lastPc = nil
local invChecked = false
local worldGen = 0

local function checkInventory()
    if invChecked or not isValidObj(lastPc) then return end
    local pawn = nil
    pcall(function() pawn = lastPc.Pawn end)
    if not isPlayerCharacter(pawn) then return end
    invChecked = true
    local inv = safeGet(lastPc, INVENTORY_PROPERTY)
    if not isValidObj(inv) then
        log("inventory component not found; toolbag off")
        return
    end
    local l = growForToolbag(inv, "player")
    if not l then return end
    local n = slotCount(inv)
    if type(n) == "number" and n < l.total then
        local okH, auth = pcall(function() return lastPc:HasAuthority() end)
        if not okH or auth ~= true then
            -- Co-op guest: the host decides the layout and must run the mod too.
            log(string.format("toolbag off: %d slots < %d on a co-op guest; the host needs RSE-Toolbag too", n, l.total))
            return
        end
        local fn = findFunction(inv, "SetMaxSlotCount")
        local ps = fn and inputParams(fn) or {}
        if not (fn and #ps >= 1 and NUMERIC[ps[1].kind]) then
            log("toolbag off: SetMaxSlotCount was not found")
            return
        end
        local ok, err = pcall(function()
            if #ps >= 2 and ps[2].kind == "BoolProperty" then inv:SetMaxSlotCount(l.total, false) else inv:SetMaxSlotCount(l.total) end
        end)
        log(string.format("loaded inventory had %d < %d slots, SetMaxSlotCount -> %s%s", n, l.total, tostring(slotCount(inv)),
            ok and "" or (" ERROR: " .. tostring(err))))
        if not ok or (slotCount(inv) or 0) < l.total then return end
    end
    layout = l
end

-- ------------------------------------------------------------------ items
local TOOL_PREFIX = {
    pickaxe = "ITEM_Pickaxe_",
    axe = "ITEM_Logging_Axe_",
    spade = "ITEM_Spade_",
    water = "ITEM_WateringCan_",
    compost = "ITEM_Bucket_Compost",
    rod = "ITEM_FishingRod_",
    net = "ITEM_FishingNet_",
}
local FAMILY_ORDER = { "pickaxe", "axe", "spade", "water", "compost", "rod", "net" }
local RIGHT_HAND_SLOT = 7

local function toolFamilyOf(name)
    for family, prefix in pairs(TOOL_PREFIX) do
        if name:find(prefix, 1, true) == 1 then return family end
    end
    return nil
end

local function itemAt(comp, slot)
    if not isValidObj(comp) then return nil end
    local ok, item = pcall(function() return comp:GetItemFromSlot(slot) end)
    if not ok or item == nil then return nil end
    return item
end

local function itemDataAt(comp, slot)
    local item = itemAt(comp, slot)
    if not item then return nil end
    local okD, data = pcall(function() return item.ItemData end)
    if okD and isValidObj(data) then return data end
    return nil
end

local function stackOf(item)
    for _, field in ipairs({ "Quantity", "Count", "StackSize", "Amount" }) do
        local ok, v = pcall(function() return item[field] end)
        if ok and type(v) == "number" and v >= 1 then return math.floor(v) end
    end
    return 1
end

local function displayName(data)
    local ok, s = pcall(function() return data.Name:ToString() end)
    if ok and type(s) == "string" and s ~= "" then return s end
    return (nameOf(data):gsub("^ITEM_", ""):gsub("_", " "))
end

local function heldItemName(pc)
    local data = itemDataAt(safeGet(pc, "BP_Components_Loadout"), RIGHT_HAND_SLOT)
    return data and nameOf(data) or ""
end

local function bag(pc) return safeGet(pc or lastPc, INVENTORY_PROPERTY) end
local function toolbagSlot(k) return layout and (layout.first + k - 1) or nil end
local function isToolbagSlot(i) return layout ~= nil and i >= layout.first and i < layout.total end

-- The main bag tab (lowest slot type among the pages, the vanilla bag) for moving tools out.
local function bagPage()
    if not layout then return nil end
    local best = nil
    for _, p in ipairs(layout.pages) do
        if not best or p.type < best.type then best = p end
    end
    return best
end

-- Every slot the bag scan covers: hotbar, bag tab and the toolbag. Other tabs
-- (runes, ammo, quest) never hold tools.
local function scanRanges()
    local ranges = {}
    if layout then
        ranges[#ranges + 1] = { 0, layout.qa - 1 }
        local b = bagPage()
        if b then ranges[#ranges + 1] = { b.start, b.start + b.slots - 1 } end
        ranges[#ranges + 1] = { layout.first, layout.total - 1 }
    else
        local count = tonumber((safeGet(bag(), "MaxSlotCount"))) or 0
        ranges[1] = { 0, count - 1 }
    end
    return ranges
end

-- Tools the player carries, cached for a second (the prompt asks 4 times a second).
local toolCache, toolCacheAt = nil, -10
local function scanTools(pc, now)
    now = now or os.clock()
    if toolCache and now - toolCacheAt < 1.0 then return toolCache end
    local found, all = {}, {}
    local comp = bag(pc)
    if isValidObj(comp) then
        for _, r in ipairs(scanRanges()) do
            for i = r[1], r[2] do
                local data = itemDataAt(comp, i)
                if data then
                    local name = nameOf(data)
                    local family = toolFamilyOf(name)
                    if family then
                        local power = tonumber((safeGet(data, "PowerLevel"))) or 0
                        local entry = { slot = i, power = power, data = data, name = name, family = family, toolbag = isToolbagSlot(i) }
                        all[#all + 1] = entry
                        local cur = found[family]
                        -- Best tool per family, the toolbag's copy first on a tie.
                        if not cur or power > cur.power or (power == cur.power and entry.toolbag and not cur.toolbag) then
                            found[family] = entry
                        end
                    end
                end
            end
        end
    end
    toolCache, toolCacheAt = { best = found, all = all }, now
    return toolCache
end
local function forgetTools() toolCache = nil end

-- ------------------------------------------------------------------ moves
-- The game moves items with MoveItemBetweenInventories (found in the game's
-- executable). Its parameters are read at runtime and matched by name; if they
-- do not match what we expect, moving is switched off and the signature is
-- logged, instead of guessing.
local MOVE_CANDIDATES = {
    { owner = "controller", name = "MoveItemBetweenInventories" },
    { owner = "bag", name = "MoveItemBetweenInventories" },
    { owner = "controller", name = "Server_MoveItemBetweenInventories" },
    { owner = "bag", name = "MoveItem" },
}
local mover = nil          -- { owner, name, params } once resolved, false when none fits

local function argsFor(params, inv, from, to, qty)
    local args = {}
    for i, p in ipairs(params) do
        local n = p.name:lower()
        if p.kind == "ObjectProperty" then
            args[i] = inv                      -- source and target inventory are both the player's
        elseif NUMERIC[p.kind] then
            if n:find("from") or n:find("source") or n:find("src") then args[i] = from
            elseif n:find("amount") or n:find("quantity") or n:find("count") or n:find("stack") or n:find("num") then args[i] = qty
            elseif n:find("^to") or n:find("target") or n:find("dest") or n:find("to_") or n:find("toslot") or n:find("toindex") then args[i] = to
            else return nil, "unknown number parameter " .. p.name end
        elseif p.kind == "BoolProperty" then
            args[i] = false
        else
            return nil, "unsupported parameter " .. p.name .. " (" .. p.kind .. ")"
        end
    end
    return args
end

local function resolveMover(pc)
    if mover ~= nil then return mover end
    local owners = { controller = safeGet(pc, "BP_Components_InventoryController"), bag = bag(pc) }
    for _, c in ipairs(MOVE_CANDIDATES) do
        local fn = findFunction(owners[c.owner], c.name)
        if fn then
            local params = inputParams(fn)
            log(string.format("move function %s.%s(%s)", c.owner, c.name, signature(params)))
            local test, why = argsFor(params, "inv", 1, 2, 1)
            if test then
                mover = { owner = c.owner, name = c.name, params = params }
                return mover
            end
            log("  not usable: " .. tostring(why))
        end
    end
    log("no usable move function; the toolbag window can show tools but not move them. Please send UE4SS.log.")
    mover = false
    return mover
end

local function moveNow(pc, from, to)
    local m = resolveMover(pc)
    if not m then return false, "moving is unavailable" end
    local inv = bag(pc)
    local owner = m.owner == "controller" and safeGet(pc, "BP_Components_InventoryController") or inv
    if not (isValidObj(inv) and isValidObj(owner)) then return false, "inventory not ready" end
    local item = itemAt(inv, from)
    if not item then return false, "nothing there" end
    local args, why = argsFor(m.params, inv, from, to, stackOf(item))
    if not args then return false, why end
    local ok, err = pcall(function() owner[m.name](owner, table.unpack(args, 1, #m.params)) end)
    forgetTools()
    if not ok then return false, tostring(err) end
    return true
end

-- Moves run one at a time with a short gap, and each is checked afterwards:
-- a tab can refuse items (the game filters what each tab accepts).
local MOVE_GAP, MOVE_CHECK = 0.35, 0.6
local moveQueue, moveBusy, moveReadyAt = {}, nil, 0
local statusListeners = {}
local function status(msg)
    log(msg)
    for _, fn in ipairs(statusListeners) do pcall(fn, msg) end
end

local function queueMove(from, to, label)
    moveQueue[#moveQueue + 1] = { from = from, to = to, label = label }
end

local function processMoves(now)
    local pc = lastPc
    if not isValidObj(pc) then moveQueue, moveBusy = {}, nil return end
    if moveBusy then
        if now < moveBusy.checkAt then return end
        local inv = bag(pc)
        local arrived = itemDataAt(inv, moveBusy.to)
        if arrived and nameOf(arrived) == moveBusy.name then
            debugLog("moved " .. moveBusy.name .. " " .. moveBusy.from .. " -> " .. moveBusy.to)
        else
            status(string.format("The game did not accept %s in slot %d. %s", moveBusy.label, moveBusy.to,
                isToolbagSlot(moveBusy.to) and "This tab may not accept tools; see README." or ""))
            moveQueue = {}
        end
        moveBusy, moveReadyAt = nil, now + MOVE_GAP
        return
    end
    if now < moveReadyAt or #moveQueue == 0 then return end
    local job = table.remove(moveQueue, 1)
    local data = itemDataAt(bag(pc), job.from)
    if not data then return end
    if itemDataAt(bag(pc), job.to) then return end      -- target filled meanwhile: skip
    local ok, err = moveNow(pc, job.from, job.to)
    if not ok then
        status("Could not move " .. job.label .. ": " .. tostring(err))
        moveQueue = {}
        return
    end
    moveBusy = { from = job.from, to = job.to, name = nameOf(data), label = job.label, checkAt = now + MOVE_CHECK }
end

local function firstEmpty(from, to)
    local inv = bag()
    for i = from, to do
        if not itemAt(inv, i) or not itemDataAt(inv, i) then return i end
    end
    return nil
end

local reserved = {}
local function freeToolbagSlot()
    if not layout then return nil end
    for k = 1, TOOLBAG_SLOTS do
        local s = toolbagSlot(k)
        if not reserved[s] and not itemDataAt(bag(), s) then return s end
    end
    return nil
end

-- Public actions (used by the window).
local function storeTool(slot)
    if not layout then return status("The toolbag is not ready") end
    if isToolbagSlot(slot) then return end
    local data = itemDataAt(bag(), slot)
    if not data then return end
    local to = freeToolbagSlot()
    if not to then return status("The toolbag is full") end
    reserved[to] = true
    queueMove(slot, to, displayName(data))
end

local function takeOut(slot)
    if not layout or not isToolbagSlot(slot) then return end
    local data = itemDataAt(bag(), slot)
    if not data then return end
    local b = bagPage()
    local to = b and firstEmpty(b.start, b.start + b.slots - 1)
    if not to then return status("Your bag is full") end
    queueMove(slot, to, displayName(data))
end

local function storeAll()
    forgetTools()
    local t = scanTools(lastPc)
    for _, e in ipairs(t.all) do
        if not e.toolbag then storeTool(e.slot) end
    end
end

-- ---------------------------------------------------------------- equip
local EQUIP_GAP = 0.5
local lastEquipAt = -100

local function useSlot(pc, slot, now)
    if now - lastEquipAt < EQUIP_GAP then return "busy" end
    local inv = bag(pc)
    local controller = safeGet(pc, "BP_Components_InventoryController")
    if not (isValidObj(inv) and isValidObj(controller)) then return "inventory not ready" end
    lastEquipAt = now
    local ok = pcall(function() controller:UseItemFromInventory(inv, slot) end)
    forgetTools()
    return ok and ("equipped from slot " .. slot) or "equip failed"
end

local function equipFamily(pc, family, tools, now)
    if heldItemName(pc):find(TOOL_PREFIX[family], 1, true) == 1 then return "already in hand" end
    local tool = tools[family]
    if not tool then return "not carried" end
    return useSlot(pc, tool.slot, now)
end

-- ----------------------------------------------------------- work targets
local KIND_FAMILY = { rock = "pickaxe", tree = "axe", rod = "rod", net = "net" }
local SCAN_CLASS = { rock = "DestructibleWorldActor", tree = "FellableTree", fish = "FishingNodeV2" }
local DETECTOR_CLASS = "/Script/Dominion.InteractableDetectorComponent"
local FARM_SLOT_CLASS = "/Script/Dominion.FarmSlotComponent"
local RESPAWN_CLASS = "/Script/Dominion.ResourceRespawnComponent"
local SCAN_RADIUS = 3000
local FISH_REACH = 2000
local RESCAN_DISTANCE = 800
local RESCAN_SECONDS = 20
local FACING_MIN = 0.34
local WORLD_SETTLE = 2

local toolLists = {}
local toolReadyAt = nil
local scriptClasses = {}

local function scriptClass(path)
    local c = scriptClasses[path]
    if isValidObj(c) then return c end
    local ok, found = pcall(function() return StaticFindObject(path) end)
    if ok and isValidObj(found) then
        scriptClasses[path] = found
        return found
    end
    return nil
end

local function componentOf(actor, path)
    if not isValidObj(actor) then return nil end
    local cls = scriptClass(path)
    if not cls then return nil end
    local ok, c = pcall(function() return actor:GetComponentByClass(cls) end)
    if ok and isValidObj(c) then return c end
    return nil
end

local function callOn(o, fn)
    if not isValidObj(o) then return nil end
    local ok, v = pcall(function() return o[fn](o) end)
    if ok then return v end
    return nil
end

local function locationOf(actor)
    if not isValidObj(actor) then return nil end
    local ok, l = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and l then return { X = l.X, Y = l.Y } end
    return nil
end

local function isRockClass(name)
    return name:find("Rock", 1, true) ~= nil or name:find("OreNode", 1, true) ~= nil
end

local function isDepleted(actor)
    local rc = componentOf(actor, RESPAWN_CLASS)
    if not rc then return false end
    local ok, left = pcall(function() return rc.ResourcesAvailable end)
    return ok and tonumber(left) ~= nil and tonumber(left) <= 0
end

local function kindOf(actor)
    if componentOf(actor, FARM_SLOT_CLASS) then return "plot" end
    local cls = classNameOf(actor)
    if cls:find("FishingNode", 1, true) then return cls:find("_Net_", 1, true) and "net" or "rod" end
    if cls:find("Tree", 1, true) then return "tree" end
    if isRockClass(cls) then return "rock" end
    return nil
end

local function aimedActor(pawn)
    local det = componentOf(pawn, DETECTOR_CLASS)
    if not det then return nil end
    local ok, a = pcall(function() return det.CurrentWorldActor end)
    if ok and isValidObj(a) then return a end
    return nil
end

local function candidates(kind, me, now)
    local list = toolLists[kind]
    if list and now - list.at < RESCAN_SECONDS then
        local moved = math.sqrt((me.X - list.x) ^ 2 + (me.Y - list.y) ^ 2)
        if moved < RESCAN_DISTANCE then return list.items end
    end
    list = { at = now, x = me.X, y = me.Y, items = {} }
    toolLists[kind] = list
    local ok, all = pcall(FindAllOf, SCAN_CLASS[kind])
    if not ok or type(all) ~= "table" then return list.items end
    for _, a in pairs(all) do
        if isValidObj(a) and not nameOf(a):find("^Default__") and (kind ~= "rock" or isRockClass(classNameOf(a))) then
            local l = locationOf(a)
            if l and math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2) < SCAN_RADIUS then
                list.items[#list.items + 1] = { actor = a, x = l.X, y = l.Y }
            end
        end
    end
    return list.items
end

local function nearestInFront(kind, pc, me, now, reach, facingMin)
    local okR, rot = pcall(function() return pc:GetControlRotation() end)
    if not okR or not rot then return nil end
    local yaw = math.rad(tonumber(rot.Yaw) or 0)
    local fx, fy = math.cos(yaw), math.sin(yaw)
    reach = reach or (kind == "fish" and FISH_REACH or cfg.ToolReach * 100)
    facingMin = facingMin or FACING_MIN
    local best, bestScore = nil, nil
    for _, c in ipairs(candidates(kind, me, now)) do
        if isValidObj(c.actor) then
            local dx, dy = c.x - me.X, c.y - me.Y
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= reach then
                local facing = d < 1 and 1 or (dx * fx + dy * fy) / d
                local score = d * (2 - facing)
                if facing >= facingMin and (bestScore == nil or score < bestScore) and not (kind == "tree" and isDepleted(c.actor)) then
                    best, bestScore = c.actor, score
                end
            end
        end
    end
    return best, bestScore
end

local function findWorkTarget(pc, pawn, now)
    local aimed = aimedActor(pawn)
    local kind = aimed and kindOf(aimed)
    if kind then return aimed, kind end
    local me = locationOf(pawn)
    if not me then return nil end
    local rock, rockScore = nearestInFront("rock", pc, me, now)
    local tree, treeScore = nearestInFront("tree", pc, me, now)
    if rock and (not tree or rockScore <= treeScore) then return rock, "rock" end
    if tree then return tree, "tree" end
    local spot = nearestInFront("fish", pc, me, now)
    if spot then return spot, classNameOf(spot):find("_Net_", 1, true) and "net" or "rod" end
    return nil
end

-- What a farm plot needs next; `have` limits it to tools the player carries.
local function plotNeed(actor, have)
    local slot = componentOf(actor, FARM_SLOT_CLASS)
    if not slot then return nil end
    if callOn(slot, "GetSoilState") == 0 then return "spade" end
    if callOn(slot, "CanHarvest") == true or callOn(slot, "CanHealDisease") == true then return nil end
    if callOn(slot, "IsFullyWatered") == false and (not have or have.water) then return "water" end
    if cfg.UseCompost and callOn(slot, "IsFullyFertilized") == false and (not have or have.compost) then return "compost" end
    return nil
end

local function menuOpen(pc)
    local open = false
    pcall(function() open = pc.bShowMouseCursor == true end)
    return open
end

local function localPawn()
    local pc = lastPc
    if not isValidObj(pc) then return nil end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not isPlayerCharacter(pawn) then return nil end
    return pc, pawn
end

-- What the tool key would do right now: { family, tool, kind } or nil.
local function suggestion(now)
    local pc, pawn = localPawn()
    if not pc or menuOpen(pc) then return nil end
    local target, kind = findWorkTarget(pc, pawn, now)
    if not target then return nil end
    local tools = scanTools(pc, now).best
    local family = kind == "plot" and plotNeed(target, tools) or KIND_FAMILY[kind]
    if not family then return nil end
    local tool = tools[family]
    if not tool then return nil end
    if heldItemName(pc):find(TOOL_PREFIX[family], 1, true) == 1 then return nil end
    return { family = family, tool = tool, kind = kind }
end

local function handleToolKey(now)
    local pc, pawn = localPawn()
    if not pc or menuOpen(pc) then return end
    local target, kind = findWorkTarget(pc, pawn, now)
    if not target then
        debugLog("tool key: no rock, tree, farm plot or fishing spot in front of you")
        return
    end
    local tools = scanTools(pc, now).best
    local family = kind == "plot" and plotNeed(target, tools) or KIND_FAMILY[kind]
    if not family then
        debugLog("tool key: this farm plot needs no tool right now")
        return
    end
    debugLog(string.format("tool key: %s -> %s (%s)", kind, family, equipFamily(pc, family, tools, now)))
end

local function handleSlotKey(k, now)
    local pc = localPawn()
    if not pc or menuOpen(pc) or not layout then return end
    local slot = toolbagSlot(k)
    if not itemDataAt(bag(pc), slot) then
        debugLog("toolbag slot " .. k .. " is empty")
        return
    end
    debugLog(string.format("toolbag key %d: %s", k, useSlot(pc, slot, now)))
end

-- ------------------------------------------------------------- auto tool
local MELEE_PREFIXES = {
    "ITEM_Sword_", "ITEM_GreatSword_", "ITEM_Greatsword_", "ITEM_Masterworks_GreatSword_", "ITEM_GreatAxe_",
    "ITEM_Greataxe_", "ITEM_Dagger_", "ITEM_Scimitar_", "ITEM_Club_", "ITEM_Mace_", "ITEM_Hammer_",
}
local AUTO_WEAPON_REACH = 200
local AUTO_WEAPON_FACING = 0.9
local AUTO_TOOL_FACING = 0.7
local SWAP_TIMEOUT = 5.0
local SWAP_SETTLE = 1.6
local SWAP_AFTER_CLICK = 0.5
local leftMouseKey = nil
local pendingSwap = nil
local lastClickAt = -100

local function handStyle(name)
    if name == "" or name:find("ITEM_Torch", 1, true) == 1 then return "free" end
    if toolFamilyOf(name) then return "tool" end
    for _, prefix in ipairs(MELEE_PREFIXES) do
        if name:find(prefix, 1, true) == 1 then return "weapon" end
    end
    return nil
end

local function clickTarget(pc, pawn, now, withWeapon)
    local aimed = aimedActor(pawn)
    local kind = aimed and kindOf(aimed)
    if kind == "plot" or kind == "tree" or kind == "rock" then return aimed, kind end
    local me = locationOf(pawn)
    if not me then return nil end
    local reach = cfg.ToolReach * 100
    local facing = AUTO_TOOL_FACING
    if withWeapon then
        reach = math.min(AUTO_WEAPON_REACH, reach)
        facing = AUTO_WEAPON_FACING
    end
    local rock, rockScore = nearestInFront("rock", pc, me, now, reach, facing)
    local tree, treeScore = nearestInFront("tree", pc, me, now, reach, facing)
    if rock and (not tree or rockScore <= treeScore) then return rock, "rock" end
    if tree then return tree, "tree" end
    return nil
end

local function handleAttackClick(now)
    local pc, pawn = localPawn()
    if not pc or menuOpen(pc) then return end
    local held = heldItemName(pc)
    local style = handStyle(held)
    if not style or (style == "weapon" and not cfg.AutoToolFromWeapon) then return end
    local target, kind = clickTarget(pc, pawn, now, style == "weapon")
    if not target then return end
    local family = kind == "plot" and plotNeed(target, nil) or KIND_FAMILY[kind]
    if not family or toolFamilyOf(held) == family then return end
    if pendingSwap and pendingSwap.family == family then
        pendingSwap.deadline = now + SWAP_TIMEOUT
        return
    end
    local tool = scanTools(pc, now).best[family]
    if not tool then
        debugLog(string.format("auto tool: %s needs a %s, none carried", kind, family))
        return
    end
    pendingSwap = { family = family, slot = tool.slot, kind = kind, from = held ~= "" and held or "empty hands",
        deadline = now + SWAP_TIMEOUT, nextTry = now, tries = 0 }
end

local function isAnimating(pawn)
    local ok, m = pcall(function() return pawn:GetCurrentMontage() end)
    return ok and isValidObj(m)
end

local function processPendingSwap(now)
    local s = pendingSwap
    local pc, pawn = localPawn()
    if not pc then pendingSwap = nil return end
    if heldItemName(pc):find(TOOL_PREFIX[s.family], 1, true) == 1 then
        debugLog(string.format("auto tool: %s with %s -> %s out (%d tries)", s.kind, s.from, s.family, s.tries))
        pendingSwap = nil
        return
    end
    if now > s.deadline then
        debugLog(string.format("auto tool: %s with %s -> %s gave up after %d tries", s.kind, s.from, s.family, s.tries))
        pendingSwap = nil
        return
    end
    if now < s.nextTry or now - lastClickAt < SWAP_AFTER_CLICK then return end
    if leftMouseKey then
        local okD, down = pcall(function() return pc:IsInputKeyDown(leftMouseKey) end)
        if okD and down == true then return end
    end
    if isAnimating(pawn) and now < s.deadline - 1.0 then return end
    s.tries = s.tries + 1
    s.nextTry = now + SWAP_SETTLE
    lastEquipAt = -100
    useSlot(pc, s.slot, now)
end

local function pollAttack()
    if not cfg.AutoTool or not toolReadyAt or not isValidObj(lastPc) then return end
    local now = os.clock()
    if now < toolReadyAt then return end
    if pendingSwap then
        local okS, errS = pcall(processPendingSwap, now)
        if not okS then
            pendingSwap = nil
            log("auto tool error: " .. tostring(errS))
        end
    end
    if not leftMouseKey then
        local ok, key = pcall(function() return { KeyName = FName("LeftMouseButton") } end)
        if not ok then return end
        leftMouseKey = key
    end
    local ok, pressed = pcall(function() return lastPc:WasInputKeyJustPressed(leftMouseKey) end)
    if ok and pressed == true then
        lastClickAt = now
        local okH, err = pcall(handleAttackClick, now)
        if not okH then log("auto tool error: " .. tostring(err)) end
    end
end

-- ------------------------------------------------------------- bag first
local HOTBAR_FLAG = "bGoIntoHotbarOnPickup"
local bagFirstChanged = {}

local function applyBagFirst(reason)
    if not cfg.BagFirst then
        local restored = 0
        for _, item in pairs(bagFirstChanged) do
            if isValidObj(item) and pcall(function() item[HOTBAR_FLAG] = true end) then restored = restored + 1 end
        end
        bagFirstChanged = {}
        if restored > 0 then log(string.format("bag first off: %d item types go to the hotbar again", restored)) end
        return
    end
    local ok, all = pcall(FindAllOf, "ItemData")
    if not ok or type(all) ~= "table" then return end
    local changed = 0
    for _, item in pairs(all) do
        if isValidObj(item) and not nameOf(item):find("^Default__") then
            local okR, cur = pcall(function() return item[HOTBAR_FLAG] end)
            if okR and cur == true and pcall(function() item[HOTBAR_FLAG] = false end) then
                bagFirstChanged[item:GetAddress()] = item
                changed = changed + 1
            end
        end
    end
    if changed > 0 then log(string.format("bag first (%s): %d item types now go to the bag first", reason, changed)) end
end

-- ------------------------------------------------------------------ keys
local requests = {}      -- keys are bound off the game thread; work runs in the game-thread tick

local function bindKeys()
    local name = tostring(cfg.ToolKey or "none")
    if name ~= "" and name:lower() ~= "none" then
        local key = Key and Key[name:upper()]
        if key and pcall(RegisterKeyBind, key, function() requests.tool = true end) then
            log("tool key bound to " .. name:upper())
        else
            log("tool key '" .. name .. "' is not a UE4SS key name; tool key off")
        end
    end
    local mod = tostring(cfg.SlotKeys or "none"):upper()
    local modifiers = { SHIFT = "SHIFT", CTRL = "CONTROL", CONTROL = "CONTROL", ALT = "ALT" }
    local modKey = modifiers[mod] and ModifierKey and ModifierKey[modifiers[mod]]
    if not modKey then
        if mod ~= "NONE" then log("SlotKeys '" .. mod .. "' is not SHIFT, CTRL, ALT or NONE; slot keys off") end
        return
    end
    local digits = { "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "ZERO" }
    local bound = 0
    for k, d in ipairs(digits) do
        local key = Key and Key[d]
        if key and pcall(RegisterKeyBind, key, { modKey }, function() requests.slot = k end) then bound = bound + 1 end
    end
    log(string.format("toolbag keys: %s+1..0 (%d bound)", mod, bound))
end

local function keyTick(now)
    if not toolReadyAt or now < toolReadyAt then requests = {} return end
    local okT, typing = pcall(function() return ModRef:GetSharedVariable("ChestLabels.typing") end)
    if okT and typing == true then requests = {} return end
    local r = requests
    requests = {}
    if r.slot then
        local ok, err = pcall(handleSlotKey, r.slot, now)
        if not ok then log("toolbag key error: " .. tostring(err)) end
    elseif r.tool then
        local ok, err = pcall(handleToolKey, now)
        if not ok then log("tool key error: " .. tostring(err)) end
    end
end

-- -------------------------------------------------------------- mod menu
local mmRev = nil
local function modMenuSync()
    local ok, rev = pcall(function() return ModRef:GetSharedVariable("ModMenu." .. MODMENU_ID .. ".rev") end)
    if not ok or type(rev) ~= "number" or rev == mmRev then return end
    local first = mmRev == nil
    mmRev = rev
    local bagBefore = cfg.BagFirst
    for _, k in ipairs(LIVE_KEYS) do
        local okV, v = pcall(function() return ModRef:GetSharedVariable("ModMenu." .. MODMENU_ID .. "." .. k) end)
        if okV and v ~= nil and type(v) == type(cfg[k]) then cfg[k] = v end
    end
    clampConfig()
    if not first and cfg.BagFirst ~= bagBefore then pcall(applyBagFirst, "menu") end
end

-- --------------------------------------------------------------- the API
-- What ui.lua and prompt.lua may use.
local T = {
    cfg = cfg, log = log, SLOTS = TOOLBAG_SLOTS, FAMILY_ORDER = FAMILY_ORDER,
    isValid = isValidObj, nameOf = nameOf, displayName = displayName,
    pc = function() return lastPc end,
    ready = function() return layout ~= nil end,
    layout = function() return layout end,
    toolbagSlot = toolbagSlot,
    dataAt = function(slot) return itemDataAt(bag(), slot) end,
    tools = function() return scanTools(lastPc) end,
    storeTool = storeTool, takeOut = takeOut, storeAll = storeAll,
    takeAllOut = function()
        if not layout then return end
        for k = 1, TOOLBAG_SLOTS do takeOut(toolbagSlot(k)) end
    end,
    busy = function() return moveBusy ~= nil or #moveQueue > 0 end,
    onStatus = function(fn) statusListeners[#statusListeners + 1] = fn end,
    suggestion = suggestion,
    heldName = function() return isValidObj(lastPc) and heldItemName(lastPc) or "" end,
}
package.loaded["toolbag_core"] = T
local UI = nil
do
    local ok, mod = pcall(require, "ui")
    if ok then UI = mod else log("window unavailable: " .. tostring(mod)) end
end
local Prompt = nil
do
    local ok, mod = pcall(require, "prompt")
    if ok then Prompt = mod else log("prompt unavailable: " .. tostring(mod)) end
end

-- --------------------------------------------------------------- lifecycle
local function forgetWorld()
    worldGen = worldGen + 1
    lastPc = nil
    invChecked = false
    layout = nil
    toolReadyAt = nil
    toolLists = {}
    pendingSwap = nil
    moveQueue, moveBusy, reserved = {}, nil, {}
    forgetTools()
    if Prompt then pcall(Prompt.forget) end
end

pcall(RegisterLoadMapPreHook, function() forgetWorld() end)
pcall(RegisterInitGameStatePostHook, function() pcall(patchInventoryTemplate) end)
pcall(RegisterLoadMapPostHook, function() pcall(patchInventoryTemplate) end)

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self)
    local pc = self:get()
    local okL, isLocal = pcall(function() return pc:IsLocalController() end)
    if okL and isLocal == false then return end
    local gen = worldGen
    ExecuteInGameThreadWithDelay(3000, function()
        ExecuteInGameThread(function()
            if gen ~= worldGen or not isValidObj(pc) then return end
            lastPc = pc
            toolReadyAt = os.clock() + WORLD_SETTLE
            local ok, err = pcall(checkInventory)
            if not ok then log("ERROR: " .. tostring(err)) end
            pcall(applyBagFirst, "world")
        end)
    end)
end)

if type(RegisterConsoleCommandHandler) == "function" then
    -- "toolbag_status" in the game console: what the mod sees, for bug reports.
    pcall(RegisterConsoleCommandHandler, "toolbag_status", function(_, _, ar)
        local function out(line) log(line) pcall(function() ar:Log(TAG .. line) end) end
        local inv = bag()
        out("v" .. VERSION .. ", layout " .. (layout and "ready" or "not ready"))
        local list = isValidObj(inv) and select(2, inventoryPages(inv)) or nil
        for i, p in ipairs(list or {}) do out(string.format("  tab %d: type %d, %d slots", i, p.type, p.slots)) end
        if layout then
            out(string.format("  quick action %d, toolbag slots %d-%d (tab type %d), total %d",
                layout.qa, layout.first, layout.total - 1, layout.pageType, layout.total))
            for k = 1, TOOLBAG_SLOTS do
                local d = itemDataAt(inv, toolbagSlot(k))
                out(string.format("  toolbag %d: %s", k, d and nameOf(d) or "empty"))
            end
        end
        local m = isValidObj(lastPc) and resolveMover(lastPc)
        out("  move function: " .. (m and (m.owner .. "." .. m.name .. "(" .. signature(m.params) .. ")") or "none"))
        out("  held: " .. (isValidObj(lastPc) and heldItemName(lastPc) or "?"))
        return true
    end)
end

local ticks = 0
local function tick()
    ticks = ticks + 1
    pcall(modMenuSync)
    if not invChecked and isValidObj(lastPc) and ticks % 50 == 0 then pcall(checkInventory) end
    local now = os.clock()
    keyTick(now)
    local okM, errM = pcall(processMoves, now)
    if not okM then log("move error: " .. tostring(errM)) moveQueue, moveBusy = {}, nil end
    if next(reserved) and not moveBusy and #moveQueue == 0 then reserved = {} end
    if UI then
        local ok, err = pcall(UI.tick, now)
        if not ok and ticks % 50 == 0 then log("window: " .. tostring(err)) end
    end
    if Prompt and ticks % 2 == 0 then
        local ok, err = pcall(Prompt.tick, now)
        if not ok and ticks % 50 == 0 then log("prompt: " .. tostring(err)) end
    end
end

if not pcall(LoopInGameThreadWithDelay, 100, tick) then
    LoopAsync(100, function() ExecuteInGameThread(tick) return false end)
end
if not pcall(LoopInGameThreadWithDelay, 1, pollAttack) then
    log("auto tool needs LoopInGameThreadWithDelay; auto tool off")
end

if UI then pcall(UI.start) end
bindKeys()

log(string.format("v%s loaded: toolbag %d slots, %s+1..0, tool key %s, prompt %s, auto tool %s", VERSION,
    TOOLBAG_SLOTS, tostring(cfg.SlotKeys), tostring(cfg.ToolKey), cfg.EquipPrompt and "on" or "off", cfg.AutoTool and "on" or "off"))
