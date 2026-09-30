-- rse_dock.lua: client helper for RSE-Dock. Copy into your mod's Scripts\ folder
-- and `local Dock = require('rse_dock')`. It only reads and writes UE4SS shared
-- variables, so it is safe to load whether or not RSE-Dock is installed.
-- Protocol version 1 (see RSE-Dock\README.md).
local D = {}
local PREFIX = 'RSEDock.'

local function getv(name)
    local ok, v = pcall(function() return ModRef:GetSharedVariable(PREFIX .. name) end)
    if ok then return v end
    return nil
end
local function setv(name, v)
    return pcall(function() ModRef:SetSharedVariable(PREFIX .. name, v) end)
end
local function find(path)
    if type(path) ~= 'string' or path == '' then return nil end
    local ok, o = pcall(StaticFindObject, path)
    if ok and o and o:IsValid() then return o end
    return nil
end

-- Dock version string, or nil when RSE-Dock is not loaded. Mods load in folder
-- order, so ask after startup (for example when the inventory is created).
function D.version()
    local v = getv('version')
    if type(v) == 'string' and v ~= '' then return v end
    return nil
end
function D.present() return D.version() ~= nil end

-- Adds or updates this mod's icon. spec: order (number, lower is further left),
-- label (tooltip title), desc (tooltip text), icon (Texture2D object path) or item (item data asset path,
-- its icon is used), window ('host' = content goes in the dock's shared window,
-- 'own' = the mod places its own window). Call again to change the icon.
function D.register(id, spec)
    assert(type(id) == 'string' and id:match('^[%w_%-]+$'), 'dock id must be letters, digits, _ or -')
    local parts = {}
    for _, k in ipairs({ 'order', 'label', 'desc', 'icon', 'item', 'window' }) do
        if spec[k] ~= nil then parts[#parts + 1] = k .. '=' .. (tostring(spec[k]):gsub('[;=\r\n]', ' ')) end
    end
    setv('item.' .. id, table.concat(parts, ';'))
    local ids = getv('ids')
    if type(ids) ~= 'string' then ids = '' end
    if not (',' .. ids .. ','):find(',' .. id .. ',', 1, true) then
        setv('ids', ids == '' and id or (ids .. ',' .. id))
    end
end

-- Removes this mod's icon (for example before a hot reload).
function D.unregister(id)
    setv('item.' .. id, '')
    if D.active() == id then setv('active', '') end
end

function D.active()
    local v = getv('active')
    return type(v) == 'string' and v or ''
end
function D.isOpen(id) return D.active() == id end
function D.open(id) setv('active', id) end
function D.close(id) if D.active() == id then setv('active', '') end end

function D.inventoryOpen() return getv('inventoryOpen') == true end
-- The live WBP_Inventory_MainPanel, or nil.
function D.panel() return find(getv('panel')) end
-- The shared window's content Overlay, or nil (no inventory, or the dock could
-- not build its window: then place your own).
function D.host() return find(getv('host')) end

return D
