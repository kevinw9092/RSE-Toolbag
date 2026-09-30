local TAG = "[ExpandedInventory] "
local VERSION = "1.3.0"
local MODMENU_ID = "ExpandedInventory"

local cfg = {
    BagSlots = 152,
    TabSlots = 24,
    InventorySlots = 0,
    HideScrollBar = true,
    BagFirst = true,
    AutoTool = true,
    AutoToolFromWeapon = true,
    ToolKey = "U",
    ToolReach = 3.0,
    UseCompost = true,
}
local LIVE_KEYS = { "BagFirst", "AutoTool", "AutoToolFromWeapon", "ToolReach", "UseCompost" }

local PLAYER_CONTROLLER = "/Game/Gameplay/Character/Player/BP_PlayerController.BP_PlayerController_C"
local INVENTORY_TEMPLATE = PLAYER_CONTROLLER .. ":BP_Components_Inventory_GEN_VARIABLE"
local INVENTORY_PROPERTY = "BP_Components_Inventory"
local UI_PAGE_LIMIT = 72
local BAG_LIMIT = 152
local MIN_SLOTS = 24
local SLOT_COLUMNS = 8
local INVENTORY_BODY_WIDGET = "WBP_Inventory_InventoryBody_C"
local INVENTORY_BODY_CLASS = "/Script/Dominion.MainInventoryBodyBase"
local SLATE_COLLAPSED = 1
local SAFE_KINDS = {
    BoolProperty = true, FloatProperty = true, DoubleProperty = true, IntProperty = true, Int64Property = true,
    ByteProperty = true, EnumProperty = true, NameProperty = true, ObjectProperty = true, ClassProperty = true,
}
local NUMERIC = { FloatProperty = true, DoubleProperty = true, IntProperty = true, Int64Property = true }

local function log(msg)
    print(TAG .. tostring(msg) .. "\n")
end

local function modRoot()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    return src:match("^(.*)[/\\]Scripts[/\\][^/\\]*$")
end

local function clampConfig()
    local reach = tonumber(cfg.ToolReach) or 3.0
    cfg.ToolReach = math.max(1.5, math.min(6.0, reach))
end

local configKeys = {}

local function loadConfig()
    local root = modRoot()
    local f = root and io.open(root .. "\\config.txt", "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then configKeys[k] = true end
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

local function roundSlots(v, limit)
    local n = math.floor(tonumber(v) or MIN_SLOTS)
    n = math.max(MIN_SLOTS, math.min(limit, n))
    return n - n % SLOT_COLUMNS
end

local function pageTargets()
    local bag, tab = cfg.BagSlots, cfg.TabSlots
    local old = tonumber(cfg.InventorySlots) or 0
    if old > 0 and not configKeys.BagSlots and not configKeys.TabSlots then bag, tab = old, old end
    bag, tab = roundSlots(bag, BAG_LIMIT), roundSlots(tab, UI_PAGE_LIMIT)
    return { [1] = bag, [2] = tab, [3] = tab, [4] = tab }
end

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

local function isPlayerCharacter(pawn)
    return isValidObj(pawn) and (classPath(pawn:GetClass()) or ""):find("BP_PlayerCharacter", 1, true) ~= nil
end

local logged = {}

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

local function growInventory(o, label)
    local targets = pageTargets()
    if not isValidObj(o) then return nil end
    local pages, list = inventoryPages(o)
    if not pages or #list == 0 then return nil end
    local qa = safeGet(o, "NumberOfQuickActionSlots")
    local maxBefore = safeGet(o, "MaxSlotCount")
    if type(qa) ~= "number" or type(maxBefore) ~= "number" then return nil end
    local before, after = {}, {}
    local total = qa
    for i, p in ipairs(list) do
        before[i] = p.slots
        local want = targets[p.type]
        if want and p.slots < want then
            pcall(function() pages[i].NumSlots = want end)
            local okN, s = pcall(function() return pages[i].NumSlots end)
            if okN and type(s) == "number" then p.slots = s end
        end
        after[i] = p.slots
        total = total + p.slots
    end
    if maxBefore < total then pcall(function() o:SetPropertyValue("MaxSlotCount", total) end) end
    local maxAfter = safeGet(o, "MaxSlotCount")
    local b, a = table.concat(before, "/"), table.concat(after, "/")
    local key = label .. ":" .. tostring(o:GetAddress())
    if b ~= a or maxBefore ~= maxAfter or not logged[key] then
        logged[key] = true
        log(string.format("%s inventory: tabs %s -> %s, MaxSlotCount %s -> %s, slots %s",
            label, b, a, tostring(maxBefore), tostring(maxAfter), tostring(slotCount(o))))
    end
    return maxAfter
end

local function widenInventoryBody(w)
    local path = classPath(w:GetClass()) or ""
    if path:find("WorldActor", 1, true) then return end
    local targets = pageTargets()
    local st = safeGet(w, "SlotType")
    local want = type(st) == "number" and targets[st] or nil
    if not want then
        local name = nameOf(w)
        if name:find("Rune", 1, true) or name:find("Ammo", 1, true) or name:find("Quest", 1, true) then want = targets[2]
        else want = math.max(targets[1], targets[2]) end
    end
    local rows = math.ceil(want / SLOT_COLUMNS)
    local cur = w:GetPropertyValue("RowCount")
    if type(cur) == "number" and cur < rows then
        w:SetPropertyValue("RowCount", rows)
        log(string.format("inventory screen %s: rows %d -> %s", w:GetFName():ToString(), cur, tostring(w:GetPropertyValue("RowCount"))))
    end
end

local function patchInventoryTemplate()
    local tpl = StaticFindObject(INVENTORY_TEMPLATE)
    if isValidObj(tpl) then return growInventory(tpl, "template") end
    return nil
end

local function widgetParent(w)
    local slot = safeGet(w, "Slot")
    if not isValidObj(slot) then return nil end
    local parent = safeGet(slot, "Parent")
    if isValidObj(parent) then return parent end
    return nil
end

local function hideInventoryScrollBars(widgets)
    local done = {}
    for _, w in pairs(widgets) do
        local okF, full = pcall(function() return w:GetFullName() end)
        if isValidObj(w) and okF and type(full) == "string" and not full:find(":WidgetTree.", 1, true) then
            local starts = { w }
            local grid = safeGet(w, "SlotGridContainer")
            if isValidObj(grid) then starts[#starts + 1] = grid end
            for _, start in ipairs(starts) do
                local cur = start
                for _ = 1, 8 do
                    cur = widgetParent(cur)
                    if not cur then break end
                    local short = (classPath(cur:GetClass()) or "?"):match("([^%.]+)$") or "?"
                    if short == "ScrollBox" then
                        local addr = cur:GetAddress()
                        if not done[addr] then
                            done[addr] = true
                            pcall(function() cur:SetScrollBarVisibility(SLATE_COLLAPSED) end)
                        end
                        break
                    end
                end
            end
        end
    end
    local n = 0
    for _ in pairs(done) do n = n + 1 end
    log(string.format("scroll bar hidden on %d inventory scroll box(es)", n))
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
        log("inventory component not found")
        return
    end
    if cfg.HideScrollBar then
        local okW, widgets = pcall(FindAllOf, INVENTORY_BODY_WIDGET)
        if okW and widgets then
            local okH, errH = pcall(hideInventoryScrollBars, widgets)
            if not okH then log("scroll bar error: " .. tostring(errH)) end
        end
    end
    local max = growInventory(inv, "player")
    local n = slotCount(inv)
    if type(max) ~= "number" or type(n) ~= "number" or n >= max then return end
    local okH, auth = pcall(function() return lastPc:HasAuthority() end)
    if not okH or auth ~= true then
        log(string.format("WARNING: %d slots < %d on a client; the host decides the layout", n, max))
        return
    end
    local fn = findFunction(inv, "SetMaxSlotCount")
    local ps = fn and inputParams(fn) or {}
    if not (fn and #ps >= 1 and NUMERIC[ps[1].kind]) then
        log(string.format("WARNING: %d slots < %d and SetMaxSlotCount was not found", n, max))
        return
    end
    local ok, err = pcall(function()
        if #ps >= 2 and ps[2].kind == "BoolProperty" then inv:SetMaxSlotCount(max, false) else inv:SetMaxSlotCount(max) end
    end)
    log(string.format("loaded inventory had %d < %d slots, SetMaxSlotCount -> %s%s", n, max, tostring(slotCount(inv)),
        ok and "" or (" ERROR: " .. tostring(err))))
end

local HOTBAR_FLAG = "bGoIntoHotbarOnPickup"
local ITEM_DATA_CLASS = "ItemData"
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
    local ok, all = pcall(FindAllOf, ITEM_DATA_CLASS)
    if not ok or type(all) ~= "table" then return end
    local seen, changed = 0, 0
    for _, item in pairs(all) do
        if isValidObj(item) and not nameOf(item):find("^Default__") then
            seen = seen + 1
            local okR, cur = pcall(function() return item[HOTBAR_FLAG] end)
            if okR and cur == true and pcall(function() item[HOTBAR_FLAG] = false end) then
                bagFirstChanged[item:GetAddress()] = item
                changed = changed + 1
            end
        end
    end
    if changed > 0 or reason == "world" then
        log(string.format("bag first (%s): %d of %d item types now go to the bag first", reason, changed, seen))
    end
end

local TOOL_PREFIX = {
    pickaxe = "ITEM_Pickaxe_",
    axe = "ITEM_Logging_Axe_",
    spade = "ITEM_Spade_",
    water = "ITEM_WateringCan_",
    compost = "ITEM_Bucket_Compost",
    rod = "ITEM_FishingRod_",
    net = "ITEM_FishingNet_",
}
local KIND_FAMILY = { rock = "pickaxe", tree = "axe", rod = "rod", net = "net" }
local SCAN_CLASS = { rock = "DestructibleWorldActor", tree = "FellableTree", fish = "FishingNodeV2" }
local DETECTOR_CLASS = "/Script/Dominion.InteractableDetectorComponent"
local FARM_SLOT_CLASS = "/Script/Dominion.FarmSlotComponent"
local RESPAWN_CLASS = "/Script/Dominion.ResourceRespawnComponent"
local RIGHT_HAND_SLOT = 7
local SCAN_RADIUS = 3000
local FISH_REACH = 2000
local RESCAN_DISTANCE = 800
local RESCAN_SECONDS = 20
local FACING_MIN = 0.34
local EQUIP_GAP = 0.5
local WORLD_SETTLE = 2

local toolRequest = false
local toolLists = {}
local toolReadyAt = nil
local lastEquipAt = -100
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

local function itemDataAt(comp, slot)
    if not isValidObj(comp) then return nil end
    local ok, item = pcall(function() return comp:GetItemFromSlot(slot) end)
    if not ok or item == nil then return nil end
    local okD, data = pcall(function() return item.ItemData end)
    if okD and isValidObj(data) then return data end
    return nil
end

local function heldItemName(pc)
    local data = itemDataAt(safeGet(pc, "BP_Components_Loadout"), RIGHT_HAND_SLOT)
    return data and nameOf(data) or ""
end

local function scanTools(pc)
    local found = {}
    local bag = safeGet(pc, INVENTORY_PROPERTY)
    if not isValidObj(bag) then return found end
    local count = tonumber((safeGet(bag, "MaxSlotCount"))) or 0
    for i = 0, count - 1 do
        local data = itemDataAt(bag, i)
        if data then
            local name = nameOf(data)
            for family, prefix in pairs(TOOL_PREFIX) do
                if name:find(prefix, 1, true) == 1 then
                    local power = tonumber((safeGet(data, "PowerLevel"))) or 0
                    local cur = found[family]
                    if not cur or power > cur.power then found[family] = { slot = i, power = power } end
                    break
                end
            end
        end
    end
    return found
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

local function plotNeed(actor, tools)
    local slot = componentOf(actor, FARM_SLOT_CLASS)
    if not slot then return nil end
    if callOn(slot, "GetSoilState") == 0 then return "spade" end
    if callOn(slot, "CanHarvest") == true or callOn(slot, "CanHealDisease") == true then return nil end
    if callOn(slot, "IsFullyWatered") == false and tools.water then return "water" end
    if cfg.UseCompost and callOn(slot, "IsFullyFertilized") == false and tools.compost then return "compost" end
    return nil
end

local function equipFamily(pc, family, tools, now)
    if heldItemName(pc):find(TOOL_PREFIX[family], 1, true) == 1 then return "already in hand" end
    if now - lastEquipAt < EQUIP_GAP then return "busy" end
    local tool = tools[family]
    if not tool then return "not in the bag" end
    local bag = safeGet(pc, INVENTORY_PROPERTY)
    local controller = safeGet(pc, "BP_Components_InventoryController")
    if not (isValidObj(bag) and isValidObj(controller)) then return "inventory not ready" end
    lastEquipAt = now
    local ok = pcall(function() controller:UseItemFromInventory(bag, tool.slot) end)
    return ok and ("equipped from slot " .. tool.slot) or "equip failed"
end

local function handleToolKey(now)
    local pc = lastPc
    if not isValidObj(pc) then return end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not isPlayerCharacter(pawn) then return end
    local menuOpen = false
    pcall(function() menuOpen = pc.bShowMouseCursor == true end)
    if menuOpen then return end
    local target, kind = findWorkTarget(pc, pawn, now)
    if not target then
        log("tool key: no rock, tree, farm plot or fishing spot in front of you")
        return
    end
    local tools = scanTools(pc)
    local family = nil
    if kind == "plot" then family = plotNeed(target, tools) else family = KIND_FAMILY[kind] end
    if not family then
        log("tool key: this farm plot needs no tool right now")
        return
    end
    log(string.format("tool key: %s -> %s (%s)", kind, family, equipFamily(pc, family, tools, now)))
end

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

local function toolFamilyOf(name)
    for family, prefix in pairs(TOOL_PREFIX) do
        if name:find(prefix, 1, true) == 1 then return family end
    end
    return nil
end

local function handStyle(name)
    if name == "" or name:find("ITEM_Torch", 1, true) == 1 then return "free" end
    if toolFamilyOf(name) then return "tool" end
    for _, prefix in ipairs(MELEE_PREFIXES) do
        if name:find(prefix, 1, true) == 1 then return "weapon" end
    end
    return nil
end

local function plotWant(actor)
    local slot = componentOf(actor, FARM_SLOT_CLASS)
    if not slot then return nil end
    if callOn(slot, "GetSoilState") == 0 then return "spade" end
    if callOn(slot, "CanHarvest") == true or callOn(slot, "CanHealDisease") == true then return nil end
    if callOn(slot, "IsFullyWatered") == false then return "water" end
    if cfg.UseCompost and callOn(slot, "IsFullyFertilized") == false then return "compost" end
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
    local pc = lastPc
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not isPlayerCharacter(pawn) then return end
    local menuOpen = false
    pcall(function() menuOpen = pc.bShowMouseCursor == true end)
    if menuOpen then return end
    local held = heldItemName(pc)
    local style = handStyle(held)
    if not style or (style == "weapon" and not cfg.AutoToolFromWeapon) then return end
    local target, kind = clickTarget(pc, pawn, now, style == "weapon")
    if not target then return end
    local family = nil
    if kind == "plot" then family = plotWant(target) else family = KIND_FAMILY[kind] end
    if not family or toolFamilyOf(held) == family then return end
    if pendingSwap and pendingSwap.family == family then
        pendingSwap.deadline = now + SWAP_TIMEOUT
        return
    end
    local tool = scanTools(pc)[family]
    if not tool then
        log(string.format("auto tool: %s needs a %s, none in the bag", kind, family))
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
    if not s then return end
    local pc = lastPc
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not isPlayerCharacter(pawn) then
        pendingSwap = nil
        return
    end
    if heldItemName(pc):find(TOOL_PREFIX[s.family], 1, true) == 1 then
        log(string.format("auto tool: %s with %s -> %s out (%d tries)", s.kind, s.from, s.family, s.tries))
        pendingSwap = nil
        return
    end
    if now > s.deadline then
        log(string.format("auto tool: %s with %s -> %s gave up after %d tries", s.kind, s.from, s.family, s.tries))
        pendingSwap = nil
        return
    end
    if now < s.nextTry or now - lastClickAt < SWAP_AFTER_CLICK then return end
    if leftMouseKey then
        local okD, down = pcall(function() return pc:IsInputKeyDown(leftMouseKey) end)
        if okD and down == true then return end
    end
    if isAnimating(pawn) and now < s.deadline - 1.0 then return end
    local bag = safeGet(pc, INVENTORY_PROPERTY)
    local controller = safeGet(pc, "BP_Components_InventoryController")
    if not (isValidObj(bag) and isValidObj(controller)) then return end
    s.tries = s.tries + 1
    s.nextTry = now + SWAP_SETTLE
    lastEquipAt = now
    pcall(function() controller:UseItemFromInventory(bag, s.slot) end)
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

local function bindToolKey()
    local name = tostring(cfg.ToolKey or "none")
    if name == "" or name:lower() == "none" then
        log("tool key off")
        return
    end
    local key = Key and Key[name:upper()]
    if not key then
        log("tool key '" .. name .. "' is not a UE4SS key name; tool key off")
        return
    end
    local ok = pcall(RegisterKeyBind, key, function() toolRequest = true end)
    log(ok and ("tool key bound to " .. name:upper()) or "tool key could not be bound")
end

local function toolTick()
    if not toolRequest then return end
    local now = os.clock()
    if not toolReadyAt or now < toolReadyAt then return end
    toolRequest = false
    local okT, typing = pcall(function() return ModRef:GetSharedVariable("ChestLabels.typing") end)
    if okT and typing == true then return end
    local ok, err = pcall(handleToolKey, now)
    if not ok then log("tool key error: " .. tostring(err)) end
end

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

local function forgetWorld()
    worldGen = worldGen + 1
    lastPc = nil
    invChecked = false
    toolReadyAt = nil
    toolLists = {}
    pendingSwap = nil
end

pcall(RegisterLoadMapPreHook, function()
    forgetWorld()
end)

local okBody, errBody = pcall(NotifyOnNewObject, INVENTORY_BODY_CLASS, function(w)
    pcall(widenInventoryBody, w)
end)
if not okBody then log("could not watch the inventory screen: " .. tostring(errBody)) end

pcall(RegisterInitGameStatePostHook, function()
    pcall(patchInventoryTemplate)
end)

pcall(RegisterLoadMapPostHook, function()
    pcall(patchInventoryTemplate)
end)

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self, NewPawn)
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
    ExecuteInGameThreadWithDelay(30000, function()
        ExecuteInGameThread(function()
            if gen == worldGen then pcall(applyBagFirst, "late items") end
        end)
    end)
end)

local ticks = 0
local function tick()
    ticks = ticks + 1
    pcall(modMenuSync)
    if not invChecked and isValidObj(lastPc) and ticks % 5 == 0 then pcall(checkInventory) end
end

if not pcall(LoopInGameThreadWithDelay, 1000, tick) then
    LoopAsync(1000, function() tick(); return false end)
end

if not pcall(LoopInGameThreadWithDelay, 100, toolTick) then
    LoopAsync(100, function() ExecuteInGameThread(toolTick); return false end)
end

if not pcall(LoopInGameThreadWithDelay, 1, pollAttack) then
    log("auto tool needs LoopInGameThreadWithDelay; auto tool off")
end

bindToolKey()

local loadedTargets = pageTargets()
log(string.format("v%s loaded: bag %d slots, runes/ammo %d slots, bag first %s, auto tool %s%s, tool key %s", VERSION, loadedTargets[1], loadedTargets[2],
    cfg.BagFirst and "on" or "off", cfg.AutoTool and "on" or "off",
    (cfg.AutoTool and cfg.AutoToolFromWeapon) and " (also from melee weapons)" or "", tostring(cfg.ToolKey)))
