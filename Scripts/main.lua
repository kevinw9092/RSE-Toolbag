-- RSE-Toolbag (RuneScape Enhanced): a 10-slot toolbag for RuneScape: Dragonwilds.
-- Based on Expanded Inventory by notto0606 (MIT).
--
-- The toolbag is 10 extra slots appended to the END of the player's last
-- inventory tab. Appending (instead of growing the bag) keeps every existing
-- slot index where it was, so no items move on existing characters. The
-- toolbag window lives in RSE-Dock's shared window beside the inventory.
local TAG = "[RSE-Toolbag] "
local VERSION = "2.3.0"
local MODMENU_ID = "RSE-Toolbag"

local cfg = {
    SlotKeys = "SHIFT",          -- modifier for 1-0 that equips toolbag slots: SHIFT, CTRL, ALT or NONE
    ToolKey = "X",               -- equip the right tool for what you face; "none" turns it off
    EquipPrompt = true,          -- "Switch Tool [X]" hint near a rock, tree, farm plot or fishing spot
    AutoTool = true,
    AutoToolFromWeapon = true,
    ToolReach = 3.0,
    UseCompost = true,
    VineTool = "axe",            -- tool for cuttable vines and choppable blockers
    BagFirst = false,
    ToolbagMode = "off",         -- toolbag storage: off, private or items (see README; restart after a change)
    QuickRow = true,             -- the toolbag slots shown above the hotbar
    QuickRowPosition = "Above health", -- "Above health", "Below health" or "Above action bar"
    QuickRowOffset = 0,          -- move that row up (+) or down (-), in UI units, -300 to 300
    Debug = false,
}
local LIVE_KEYS = { "QuickRow", "QuickRowPosition", "QuickRowOffset", "EquipPrompt", "AutoTool", "AutoToolFromWeapon", "ToolReach", "UseCompost", "VineTool", "BagFirst", "Debug" }

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

-- The toolbag is a FIFTH inventory tab appended after the four vanilla ones
-- (bag, runes, ammo, quest). Appending keeps every existing slot number where
-- it was. No tab button exists for it, so the inventory screen never draws it;
-- only the toolbag window shows its slots.
--
-- History: 2.0.0 grew the quest tab instead (72 -> 82). The quest tab's screen
-- holds exactly 72 slots and the game read slot 72, one past the end, and
-- crashed (dump 2026-09-30: access violation at 72 * 0x58 + 0x18).
--
-- ToolbagMode picks the new tab's type:
--   "off"     no tab is added (default until tested)
--   "private" type 64, a value the game does not use: pickups never go there
--             and nothing in the game looks for it. Untested: the game may
--             refuse items there or drop them on load.
--   "items"   the bag's own type: accepts every tool for certain, but pickups
--             may overflow into it once the bag is full.
local PRIVATE_TYPE = 64
local VANILLA_PAGES = 4

local function toolbagType(list)
    local mode = tostring(cfg.ToolbagMode or "off"):lower()
    if mode == "private" then return PRIVATE_TYPE end
    if mode == "items" then
        local t = nil
        for _, p in ipairs(list) do if not t or p.type < t then t = p.type end end
        return t
    end
    return nil
end

local function readPages(o)
    local pages, list = inventoryPages(o)
    if not pages then return nil end
    return pages, list
end

-- Adds one element to the InventoryPages array. UE4SS builds differ in how a
-- struct array can grow from Lua, so the known ways are tried in turn, and
-- each is verified by reading the array back. Page 1 must be unchanged after
-- (a copy that turned out to be a reference would be undone and rejected).
local function appendPage(o, slotType, slots)
    local pages, list = readPages(o)
    if not pages then return nil, "pages unreadable" end
    local n = #list
    local firstType, firstSlots = list[1].type, list[1].slots
    local attempts = {
        { "copy of page 1", function(p) p[n + 1] = p[1] end },
        { "table", function(p) p[n + 1] = { SlotType = slotType, NumSlots = slots } end },
    }
    local reasons = {}
    for _, a in ipairs(attempts) do
        local okA, errA = pcall(a[2], pages)
        local fresh, freshList = readPages(o)
        if fresh and #freshList == n + 1 then
            pcall(function() fresh[n + 1].SlotType = slotType end)
            pcall(function() fresh[n + 1].NumSlots = slots end)
            local _, check = readPages(o)
            local added, first = check and check[n + 1], check and check[1]
            if added and added.type == slotType and added.slots == slots
                and first.type == firstType and first.slots == firstSlots then
                return a[1]
            end
            reasons[#reasons + 1] = a[1] .. ": added but fields did not stick"
            -- Undo what can be undone: a 0-slot page holds nothing.
            pcall(function() fresh[n + 1].NumSlots = 0 end)
            pcall(function() fresh[1].SlotType = firstType; fresh[1].NumSlots = firstSlots end)
            return nil, table.concat(reasons, "; ")
        end
        reasons[#reasons + 1] = a[1] .. ": " .. (okA and "array did not grow" or tostring(errA))
    end
    return nil, table.concat(reasons, "; ")
end

local function describePages(list)
    local out = {}
    for i, p in ipairs(list) do out[i] = string.format("%d:%d", p.type, p.slots) end
    return table.concat(out, " ")
end

-- Adds the toolbag tab to `o` (the controller template or the live inventory
-- component). Idempotent. Returns the layout:
-- { first, total, qa, pageType, pages = { {type, start, slots} } } or nil.
local function growForToolbag(o, label)
    if not isValidObj(o) then return nil end
    local pages, list = readPages(o)
    if not pages or #list == 0 then return nil end
    local slotType = toolbagType(list)
    if not slotType then
        if not refused.off then
            refused.off = true
            debugLog("toolbag storage is off (ToolbagMode = off); the tool key, prompt and auto tool still work")
        end
        return nil
    end
    local qa = safeGet(o, "NumberOfQuickActionSlots")
    local maxBefore = safeGet(o, "MaxSlotCount")
    if type(qa) ~= "number" or type(maxBefore) ~= "number" then return nil end
    for i = 1, math.min(#list, VANILLA_PAGES) do
        if not VANILLA_SIZES[list[i].slots] then
            if not refused[label] then
                refused[label] = true
                log(string.format("%s: tabs are %s, not the vanilla layout; toolbag OFF so no item can move. "
                    .. "Another inventory-size mod is probably installed.", label, describePages(list)))
            end
            return nil
        end
    end
    local method = "already there"
    if #list == VANILLA_PAGES then
        local how, why = appendPage(o, slotType, TOOLBAG_SLOTS)
        if not how then
            if not refused[label .. "append"] then
                refused[label .. "append"] = true
                log(label .. ": could not add the toolbag tab (" .. tostring(why) .. "); toolbag OFF")
            end
            return nil
        end
        method = how
        pages, list = readPages(o)
    elseif not (#list == VANILLA_PAGES + 1 and list[#list].slots == TOOLBAG_SLOTS) then
        if not refused[label] then
            refused[label] = true
            log(string.format("%s: unexpected tabs %s; toolbag OFF", label, describePages(list)))
        end
        return nil
    elseif list[#list].type ~= slotType then
        -- ToolbagMode changed since this inventory was built: items stay in the same slot numbers.
        pcall(function() pages[#list].SlotType = slotType end)
        pages, list = readPages(o)
    end
    local result = { qa = qa, pages = {} }
    local total = qa
    for i, p in ipairs(list) do
        result.pages[i] = { type = p.type, start = total, slots = p.slots }
        total = total + p.slots
    end
    if maxBefore < total then pcall(function() o:SetPropertyValue("MaxSlotCount", total) end) end
    result.total, result.first, result.pageType = total, total - TOOLBAG_SLOTS, list[#list].type
    local logKey = label .. ":" .. describePages(list)
    if method ~= "already there" or (label ~= "template" and not refused[logKey]) then
        refused[logKey] = true
        debugLog(string.format("%s: toolbag tab (type %d) %s, tabs %s, toolbag = slots %d-%d, MaxSlotCount %s -> %s",
            label, result.pageType, method, describePages(list), result.first, total - 1,
            tostring(maxBefore), tostring(safeGet(o, "MaxSlotCount"))))
    end
    return result
end

-- For toolbag_probe: slot type names, and the fields of one inventory page.
local function slotTypeNames()
    local names = {}
    pcall(function()
        local e = StaticFindObject("/Script/Dominion.EInventorySlotType")
        e:ForEachName(function(n, v) names[v] = n:ToString() end)
    end)
    return names
end

local function pageFields(o)
    local out = {}
    pcall(function()
        local c = o:GetClass()
        while c do
            local found = false
            c:ForEachProperty(function(p)
                if not found and p:GetFName():ToString() == "InventoryPages" then
                    found = true
                    p:GetInner():GetStruct():ForEachProperty(function(sp)
                        out[#out + 1] = sp:GetFName():ToString() .. ":" .. sp:GetClass():GetFName():ToString()
                    end)
                end
            end)
            if found then break end
            c = superOf(c)
        end
    end)
    return out
end

local function patchInventoryTemplate()
    local tpl = StaticFindObject(INVENTORY_TEMPLATE)
    if isValidObj(tpl) then return growForToolbag(tpl, "template") end
    return nil
end

local lastPc = nil
local invChecked = false
local worldGen = 0

-- The world's network role for a controller: "standalone" (solo, offline),
-- "host" (listen server or dedicated server), "client" (joined someone else's
-- world) or "unknown".
local function netModeOf(pc)
    local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if not world then return "unknown" end
    local okA, alone = pcall(function() return kismet:IsStandalone(world) end)
    if okA and alone == true then return "standalone" end
    local okS, server = pcall(function() return kismet:IsServer(world) end)
    if okS and server == true then return "host" end
    if okS and server == false then return "client" end
    return "unknown"
end

-- Grows a loaded inventory's slot array to `total` (only on the side that owns
-- it: solo, the host, or a dedicated server). Never shrinks. Returns true when
-- the inventory has at least `total` slots afterwards.
local function growSlots(inv, total, label)
    local n = slotCount(inv)
    if type(n) ~= "number" then return false end
    if n >= total then return true end
    local fn = findFunction(inv, "SetMaxSlotCount")
    local ps = fn and inputParams(fn) or {}
    if not (fn and #ps >= 1 and NUMERIC[ps[1].kind]) then
        log(label .. ": SetMaxSlotCount was not found; toolbag off")
        return false
    end
    local ok, err = pcall(function()
        if #ps >= 2 and ps[2].kind == "BoolProperty" then inv:SetMaxSlotCount(total, false) else inv:SetMaxSlotCount(total) end
    end)
    debugLog(string.format("%s: inventory had %d < %d slots, SetMaxSlotCount -> %s%s", label, n, total,
        tostring(slotCount(inv)), ok and "" or (" ERROR: " .. tostring(err))))
    return ok and (slotCount(inv) or 0) >= total
end

-- Messages between the server's and the players' RSE-Toolbag, over two stock
-- engine RPCs every PlayerController has (the same channel RSE-Transmog uses):
--   server -> player  ClientMessage("rsetb1 ready <slots> <mode>")  the toolbag slots are in place
--   player -> server  ServerExec("rsetb1 hi")                      "I am waiting": the server answers
--                                                                   at once if it is already done
local PROTO = "rsetb1"
local GUEST_TIMEOUT = 60        -- s without a "ready": the host has no RSE-Toolbag
local READY_RETRIES = 10        -- the grown slot array can arrive a moment after the message
local guestWait = nil           -- { deadline, signalled, tries, nextTry } while a guest waits
local readySignal = nil         -- set by the ClientMessage hook, handled in the game-thread tick

-- FString parameters arrive as a Lua string or an FString object, depending on the UE4SS build.
local function textOf(param)
    local ok, v = pcall(function() return param:get() end)
    if ok and type(v) == "string" then return v end
    local okS, s = pcall(function() return v:ToString() end)
    if okS and type(s) == "string" then return s end
    okS, s = pcall(function() return param:ToString() end)
    return okS and type(s) == "string" and s or nil
end

local function tellPlayer(pc, message)
    pcall(function() pc:ClientMessage(message, FName("None"), 0.0) end)
end

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
        local net = netModeOf(lastPc)
        local okH, auth = pcall(function() return lastPc:HasAuthority() end)
        if (okH and auth == true) or net == "standalone" or net == "host" then
            if not growSlots(inv, l.total, "player") then return end
        else
            -- Guest: nothing to poll. The server says when the slots are in place (guestTick).
            if not guestWait then
                guestWait = { deadline = os.clock() + GUEST_TIMEOUT, tries = 0 }
                debugLog(string.format("co-op guest (net mode %s): %d of %d slots; waiting for the host's RSE-Toolbag", net, n, l.total))
                pcall(function() lastPc:ServerExec(PROTO .. " hi") end)
            end
            return
        end
    end
    if guestWait then debugLog("the host added the toolbag slots; toolbag ready") guestWait = nil end
    layout = l
end

-- Runs in the game-thread tick while a guest waits: re-checks only when the
-- server's "ready" arrived (a few quick retries, as the slots may trail the
-- message), or once when the timeout passes.
local function guestTick(now)
    local w = guestWait
    if not w or not isValidObj(lastPc) then return end
    if readySignal then
        if readySignal.mode ~= tostring(cfg.ToolbagMode):lower() then
            log("note: the host uses ToolbagMode = " .. readySignal.mode .. ", this game " .. tostring(cfg.ToolbagMode)
                .. "; the slots line up, but set the same mode on both")
        end
        readySignal = nil
        w.signalled, w.tries, w.nextTry = true, 0, now
    end
    local final = now >= w.deadline
    if not (final or (w.signalled and now >= w.nextTry)) then return end
    invChecked = false
    checkInventory()
    if layout or not guestWait then return end
    if w.signalled and w.tries < READY_RETRIES then
        w.tries, w.nextTry = w.tries + 1, now + 0.5
        return
    end
    log(w.signalled and "toolbag off: the host said ready, but the slots never arrived"
        or string.format("toolbag off: no answer from the host in %d s; the host or dedicated server needs RSE-Toolbag "
            .. "with the same ToolbagMode", GUEST_TIMEOUT))
    guestWait = nil
end

-- ------------------------------------------------------------- server mode
-- On a host or dedicated server, every OTHER player's inventory lives here too.
-- Each connected controller is checked every few seconds: once its pawn and
-- saved inventory have loaded, the toolbag tab is added and the slot array
-- grown. The check keeps running (every 30 s once done) because a later load
-- of the character's save could shrink the array again. Only ever grows.
local SERVER_SCAN = 5          -- seconds between scans of the connected controllers
local SERVER_SETTLE = 4        -- seconds after a controller appears before its first check
local SERVER_RECHECK = 30      -- seconds between checks once a player is done
local serverMode = nil         -- nil: not known yet for this world
local serverPlayers = {}       -- controller address -> { firstSeen, nextCheck, done, label }
local nextServerScan = 0

local function playerLabel(pc)
    local ok, name = pcall(function() return pc.PlayerState:GetPlayerName():ToString() end)
    if ok and type(name) == "string" and name ~= "" then return "player " .. name end
    return "player " .. nameOf(pc)
end

local function isLocal(pc)
    local ok, v = pcall(function() return pc:IsLocalController() end)
    return ok and v == true
end

local function serverPrepare(pc, st)
    st.total = nil
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not isPlayerCharacter(pawn) then return false end
    local inv = safeGet(pc, INVENTORY_PROPERTY)
    local n = isValidObj(inv) and slotCount(inv)
    if type(n) ~= "number" or n == 0 then return false end
    local l = growForToolbag(inv, st.label)
    if not l then return false end
    st.total = l.total
    return growSlots(inv, l.total, st.label)
end

-- New controllers are reported by the game as they are created (no object scan);
-- one full scan runs the first time server mode is confirmed, for players who
-- were already connected (a hot reload, or the mod starting late).
local newControllers = {}
pcall(NotifyOnNewObject, "/Script/Engine.PlayerController", function(pc)
    newControllers[#newControllers + 1] = pc
end)
local controllers = {}          -- address -> controller, this world's
local scannedOnce = false

local function serverTick(now)
    if serverMode == false or now < nextServerScan then return end
    nextServerScan = now + SERVER_SCAN
    while #newControllers > 0 do
        local pc = table.remove(newControllers)
        if isValidObj(pc) and not nameOf(pc):find("^Default__") then controllers[pc:GetAddress()] = pc end
    end
    if serverMode == nil then
        for _, pc in pairs(controllers) do
            if isValidObj(pc) then
                local net = netModeOf(pc)
                if net ~= "unknown" then serverMode = (net == "host") break end
            end
        end
        if serverMode == nil then return end
    end
    if not serverMode then return end
    if not scannedOnce then
        scannedOnce = true
        debugLog("server mode: adding the toolbag slots to joining players' inventories")
        local ok, all = pcall(FindAllOf, "PlayerController")
        for _, pc in ipairs(ok and all or {}) do
            if isValidObj(pc) and not nameOf(pc):find("^Default__") then controllers[pc:GetAddress()] = pc end
        end
    end
    for key, pc in pairs(controllers) do
        if not isValidObj(pc) then
            controllers[key], serverPlayers[key] = nil, nil      -- left the game
        elseif not isLocal(pc) then
            local st = serverPlayers[key]
            if not st then
                st = { firstSeen = now, nextCheck = now + SERVER_SETTLE }
                serverPlayers[key] = st
            end
            if now >= st.nextCheck then
                st.label = playerLabel(pc)
                local okP, done = pcall(serverPrepare, pc, st)
                if not okP then log(st.label .. ": " .. tostring(done)) done = false end
                if done and not st.done then
                    debugLog(st.label .. ": toolbag ready")
                    tellPlayer(pc, string.format("%s ready %d %s", PROTO, st.total or 0, tostring(cfg.ToolbagMode):lower()))
                end
                st.done = done
                st.nextCheck = now + (done and SERVER_RECHECK or SERVER_SCAN)
            end
        end
    end
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

-- Durability of the item in a slot, 0-1, or nil for items without durability.
-- Names from the game: the item's Durability, the item data's bHasDurability and
-- BaseDurability / GetMaxDurability. The first combination that works is logged
-- once with Debug on.
local durabilityLogged = false
local function durabilityOf(item, data)
    if not item or not isValidObj(data) then return nil end
    local okH, has = pcall(function() return data.bHasDurability end)
    if okH and has == false then return nil end
    local cur, curFrom = nil, nil
    for _, field in ipairs({ "Durability", "CurrentDurability" }) do
        local ok, v = pcall(function() return item[field] end)
        if ok and type(v) == "number" then cur, curFrom = v, "item." .. field break end
    end
    if not cur then return nil end
    local max, maxFrom = nil, nil
    for _, read in ipairs({
        { "data.BaseDurability", function() return data.BaseDurability end },
        { "data.MaxDurability", function() return data.MaxDurability end },
        { "data:GetMaxDurability()", function() return data:GetMaxDurability() end },
        { "data:GetBaseDurability()", function() return data:GetBaseDurability() end },
    }) do
        local ok, v = pcall(read[2])
        if ok and type(v) == "number" and v > 0 then max, maxFrom = v, read[1] break end
    end
    local frac
    if max then frac = cur / max
    elseif cur <= 1 then frac, maxFrom = cur, "none (value is already 0-1)"
    else return nil end
    if not durabilityLogged then
        durabilityLogged = true
        debugLog(string.format("durability read from %s / %s (%s: %.2f)", curFrom, tostring(maxFrom), nameOf(data), frac))
    end
    return math.max(0, math.min(1, frac))
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
-- Entries hold plain data only (slot, names, the item data's path), never the
-- item data object: a kept game object can be freed memory by the next use.
local function objectPathOf(o)
    if not isValidObj(o) then return "" end
    local ok, f = pcall(function() return o:GetFullName() end)
    return ok and type(f) == "string" and (f:match("^%S+%s+(.+)$") or "") or ""
end
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
                        local entry = { slot = i, power = power, name = name, label = displayName(data),
                            path = objectPathOf(data), family = family, toolbag = isToolbagSlot(i) }
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
            debugLog(string.format("move function %s.%s(%s)", c.owner, c.name, signature(params)))
            local test, why = argsFor(params, "inv", 1, 2, 1)
            if test then
                mover = { owner = c.owner, name = c.name, params = params }
                return mover
            end
            debugLog("  not usable: " .. tostring(why))
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
    debugLog(msg) -- also shown in the toolbag window
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
-- Cuttable vines and other choppable blockers (the thorny vines across entrances, the
-- vines over wells and pools): their blueprints, from the game's asset list (2026-09-30).
-- Any other class with "Vine" or "Choppable" in its name counts too, except the Wild
-- Jade Vine enemy and anything that is a pawn (a creature).
local VINE_CLASSES = { "BP_ThornyVine_C", "BP_InfectedThornyVine_C", "BP_CleansingPool_Vines_C",
    "BP_DragonImaru_Vines_C", "BP_Choppable_BloodwoodSap_C" }
local SCAN_CLASS = { rock = "DestructibleWorldActor", tree = "FellableTree", fish = "FishingNodeV2", vine = VINE_CLASSES }
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
-- Looked up by path each time, never cached: a kept game object can be freed
-- memory by the next use (RSE-Transmog crashes, 2026-09-30).
local function scriptClass(path)
    local ok, found = pcall(function() return StaticFindObject(path) end)
    if ok and isValidObj(found) then return found end
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

local function isVineClass(cls)
    if cls:find("WildJade", 1, true) or cls:find("WildVine", 1, true) or cls:find("AI_", 1, true) then return false end
    return cls:find("Vine", 1, true) ~= nil or cls:find("Choppable", 1, true) ~= nil
end

local function isPawn(actor)
    local ok, v = pcall(function() return actor:IsA("/Script/Engine.Pawn") end)
    return ok and v == true
end

-- The tool for vines: VineTool (config), one of the tool families; axe by default.
local function vineFamily()
    local f = tostring(cfg.VineTool or "axe"):lower()
    return TOOL_PREFIX[f] and f or "axe"
end
local function familyFor(kind) return kind == "vine" and vineFamily() or KIND_FAMILY[kind] end

local vineLogged = false
local function kindOf(actor)
    if componentOf(actor, FARM_SLOT_CLASS) then return "plot" end
    local cls = classNameOf(actor)
    if isVineClass(cls) and not isPawn(actor) then
        if not vineLogged then vineLogged = true debugLog("vine target: " .. cls .. " -> " .. vineFamily()) end
        return "vine"
    end
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
    local classes = SCAN_CLASS[kind]
    if type(classes) ~= "table" then classes = { classes } end
    for _, className in ipairs(classes) do
        local ok, all = pcall(FindAllOf, className)
        if ok and type(all) == "table" then
            for _, a in pairs(all) do
                if isValidObj(a) and not nameOf(a):find("^Default__") and (kind ~= "rock" or isRockClass(classNameOf(a)))
                    and (kind ~= "vine" or not isPawn(a)) then
                    local l = locationOf(a)
                    if l and math.sqrt((l.X - me.X) ^ 2 + (l.Y - me.Y) ^ 2) < SCAN_RADIUS then
                        list.items[#list.items + 1] = { actor = a, x = l.X, y = l.Y }
                    end
                end
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
    local best, bestKind, bestScore = nil, nil, nil
    for _, kind in ipairs({ "rock", "tree", "vine" }) do
        local a, score = nearestInFront(kind, pc, me, now)
        if a and (not bestScore or score < bestScore) then best, bestKind, bestScore = a, kind, score end
    end
    if best then return best, bestKind end
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
    local family = kind == "plot" and plotNeed(target, tools) or familyFor(kind)
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
    local family = kind == "plot" and plotNeed(target, tools) or familyFor(kind)
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
    if kind == "plot" or kind == "tree" or kind == "rock" or kind == "vine" then return aimed, kind end
    local me = locationOf(pawn)
    if not me then return nil end
    local reach = cfg.ToolReach * 100
    local facing = AUTO_TOOL_FACING
    if withWeapon then
        reach = math.min(AUTO_WEAPON_REACH, reach)
        facing = AUTO_WEAPON_FACING
    end
    local best, bestKind, bestScore = nil, nil, nil
    for _, kind in ipairs({ "rock", "tree", "vine" }) do
        local a, score = nearestInFront(kind, pc, me, now, reach, facing)
        if a and (not bestScore or score < bestScore) then best, bestKind, bestScore = a, kind, score end
    end
    return best, bestKind
end

local function handleAttackClick(now)
    local pc, pawn = localPawn()
    if not pc or menuOpen(pc) then return end
    local held = heldItemName(pc)
    local style = handStyle(held)
    if not style or (style == "weapon" and not cfg.AutoToolFromWeapon) then return end
    local target, kind = clickTarget(pc, pawn, now, style == "weapon")
    if not target then return end
    local family = kind == "plot" and plotNeed(target, nil) or familyFor(kind)
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
        if restored > 0 then debugLog(string.format("bag first off: %d item types go to the hotbar again", restored)) end
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
    if changed > 0 then debugLog(string.format("bag first (%s): %d item types now go to the bag first", reason, changed)) end
end

-- ------------------------------------------------------------------ keys
local requests = {}      -- keys are bound off the game thread; work runs in the game-thread tick

local function bindKeys()
    local name = tostring(cfg.ToolKey or "none")
    if name ~= "" and name:lower() ~= "none" then
        local key = Key and Key[name:upper()]
        if key and pcall(RegisterKeyBind, key, function() requests.tool = true end) then
            debugLog("tool key bound to " .. name:upper())
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
    debugLog(string.format("toolbag keys: %s+1..0 (%d bound)", mod, bound))
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
    cfg = cfg, log = log, debugLog = debugLog, SLOTS = TOOLBAG_SLOTS, FAMILY_ORDER = FAMILY_ORDER,
    isValid = isValidObj, nameOf = nameOf, displayName = displayName, pathOf = objectPathOf,
    pc = function() return lastPc end,
    ready = function() return layout ~= nil end,
    layout = function() return layout end,
    toolbagSlot = toolbagSlot,
    dataAt = function(slot) return itemDataAt(bag(), slot) end,
    durabilityAt = function(slot)
        local inv = bag()
        return durabilityOf(itemAt(inv, slot), itemDataAt(inv, slot))
    end,
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
local Hotbar = nil
do
    local ok, mod = pcall(require, "hotbar")
    if ok then Hotbar = mod else log("quick row unavailable: " .. tostring(mod)) end
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
    serverMode, serverPlayers, nextServerScan = nil, {}, 0
    guestWait, readySignal = nil, nil
    controllers, scannedOnce = {}, false
    forgetTools()
    if Prompt then pcall(Prompt.forget) end
    if Hotbar then pcall(Hotbar.forget) end
    if UI and UI.forget then pcall(UI.forget) end
end

pcall(RegisterLoadMapPreHook, function() forgetWorld() end)

-- Player side: the server's "ready". On a host the hook also fires for messages it sends
-- to other players; only the local controller's count.
pcall(RegisterHook, "/Script/Engine.PlayerController:ClientMessage", function(ctx, message)
    local text = textOf(message)
    if not text or text:sub(1, #PROTO + 1) ~= PROTO .. " " then return end
    local pc = ctx:get()
    if not isLocal(pc) then return end
    local total, mode = text:match("^" .. PROTO .. " ready (%d+) (%S+)")
    if total then readySignal = { total = tonumber(total), mode = mode } end
end)

-- Server side: a waiting player's "hi". Answer now if that player is done, else check them now.
pcall(RegisterHook, "/Script/Engine.PlayerController:ServerExec", function(ctx, message)
    local text = textOf(message)
    if text ~= PROTO .. " hi" then return end
    local pc = ctx:get()
    if not isValidObj(pc) then return end
    local key = pc:GetAddress()
    controllers[key] = pc
    local st = serverPlayers[key]
    if st and st.done then
        tellPlayer(pc, string.format("%s ready %d %s", PROTO, st.total or 0, tostring(cfg.ToolbagMode):lower()))
    elseif st then
        st.nextCheck = 0
    end
end)
pcall(RegisterInitGameStatePostHook, function()
    -- Game modes only exist on the server; serverTick then tells a host (other players can
    -- join) from a standalone world (nobody else, the local path is enough).
    pcall(patchInventoryTemplate)
end)
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

    -- "toolbag_probe" on the MAIN MENU (no character loaded): can a fifth inventory tab be added
    -- from Lua on this game and UE4SS build? It changes the inventory template the game builds
    -- characters from, so QUIT THE GAME AFTERWARDS instead of loading a character.
    pcall(RegisterConsoleCommandHandler, "toolbag_probe", function(_, _, ar)
        local function out(line) log("probe: " .. line) pcall(function() ar:Log(TAG .. "probe: " .. line) end) end
        local ok, err = pcall(function()
            -- The main menu has a player controller too (for the character preview), so "a character is
            -- loaded" means a controller that owns an inventory component.
            if isValidObj(lastPc) and isValidObj(safeGet(lastPc, INVENTORY_PROPERTY)) then
                out("a character is loaded: run this on the main menu, then quit without loading one")
                return
            end
            local tpl = StaticFindObject(INVENTORY_TEMPLATE)
            if not isValidObj(tpl) then out("inventory template not found (game not initialised yet?)") return end
            local names = slotTypeNames()
            local typeNames = {}
            for v, n in pairs(names) do typeNames[#typeNames + 1] = v .. "=" .. n end
            table.sort(typeNames)
            out("slot types: " .. (#typeNames > 0 and table.concat(typeNames, ", ") or "(enum not readable)"))
            out("page fields: " .. table.concat(pageFields(tpl), ", "))
            local _, list = readPages(tpl)
            if not list then out("InventoryPages not readable") return end
            for i, p in ipairs(list) do
                out(string.format("tab %d: type %d (%s), %d slots", i, p.type, names[p.type] or "?", p.slots))
            end
            out("quick action slots " .. tostring(safeGet(tpl, "NumberOfQuickActionSlots"))
                .. ", MaxSlotCount " .. tostring(safeGet(tpl, "MaxSlotCount")))
            if #list ~= VANILLA_PAGES then out("not 4 tabs: skipping the append test") return end
            local how, why = appendPage(tpl, PRIVATE_TYPE, TOOLBAG_SLOTS)
            if how then
                local _, after = readPages(tpl)
                out("APPEND WORKS (" .. how .. "): tabs now " .. describePages(after))
                -- Leave nothing usable behind in case a character is loaded anyway.
                local pages = readPages(tpl)
                pcall(function() pages[#after].NumSlots = 0 end)
                out("test tab emptied (0 slots). Now QUIT the game; then set ToolbagMode = private in config.txt "
                    .. "and try it on a throwaway character.")
            else
                out("APPEND FAILED: " .. tostring(why))
                out("a fifth tab cannot be added on this build; tell the RSE-Toolbag author")
            end
        end)
        if not ok then out("error: " .. tostring(err)) end
        return true
    end)
end

-- Fallback when ClientRestart never reaches us: ConsoleEnablerMod unregisters its own ClientRestart
-- hook at load, and on UE4SS 3.0.x that drops every Lua callback on that function (seen 2026-09-30:
-- the hook was removed and this mod never saw the player). Every 2 s without a player, ask UEHelpers
-- for the local controller; this is a cached lookup, not an object scan.
local UEH = nil
pcall(function() UEH = require("UEHelpers") end)
local function findPlayerFallback(now)
    if isValidObj(lastPc) then return end
    -- The controllers the game reported (see server mode) first: no lookup needed.
    local pc = nil
    for _, c in pairs(controllers) do
        if isValidObj(c) and isLocal(c) then pc = c break end
    end
    if not pc then
        -- A dedicated server has no local player: never ask UEHelpers there (it can scan objects).
        if serverMode or not UEH then return end
        local ok, found = pcall(UEH.GetPlayerController)
        if not ok or not isValidObj(found) or not isLocal(found) then return end   -- a host also holds other players' controllers
        pc = found
    end
    local pawn = nil
    pcall(function() pawn = pc.Pawn end)
    if not isPlayerCharacter(pawn) then return end
    lastPc = pc
    toolReadyAt = now + WORLD_SETTLE
    debugLog("player found without ClientRestart (fallback)")
    pcall(checkInventory)
    pcall(applyBagFirst, "world")
end

local ticks = 0
local function tick()
    ticks = ticks + 1
    pcall(modMenuSync)
    if ticks % 20 == 0 then pcall(findPlayerFallback, os.clock()) end
    local okSv, errSv = pcall(serverTick, os.clock())
    if not okSv and ticks % 50 == 0 then log("server mode: " .. tostring(errSv)) end
    if not invChecked and isValidObj(lastPc) and ticks % 50 == 0 then pcall(checkInventory) end
    if guestWait then
        local okG, errG = pcall(guestTick, os.clock())
        if not okG then log("guest wait: " .. tostring(errG)) guestWait = nil end
    end
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
    if Hotbar and ticks % 2 == 1 then
        local ok, err = pcall(Hotbar.tick, now)
        if not ok and ticks % 50 == 1 then log("quick row: " .. tostring(err)) end
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
