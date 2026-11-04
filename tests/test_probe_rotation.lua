-- Regresi probe_rotation.lua: harus selesai dan mencetak status sebelum/sesudah.
local f = assert(io.open('probe_rotation.lua'))
local text = f:read('*a'); f:close()

local log = {}
local rot = { enabled = false, status = 0, pnb_in_home = true }
local bot = { name = "PROBEBOT", status = 1, rotation = rot }

local env = {
    getBot = function() return bot end,
    sleep = function() end,
    print = function(s) log[#log + 1] = tostring(s) end,
}
setmetatable(env, { __index = _G })
assert(load(text, '@probe_rotation.lua', 't', env))()

local joined = table.concat(log, "\n")
assert(joined:find("SEBELUM: enabled=false", 1, true), "harus mencetak nilai sebelum")
assert(joined:find("SESUDAH (langsung): enabled=true", 1, true), "harus mencetak nilai sesudah tulis")
assert(joined:find("SESUDAH (3s): enabled=true", 1, true), "harus mencetak nilai setelah jeda")
assert(joined:find("pnb_in_home", 1, true), "harus mencetak daftar field")
assert(joined:find("selesai", 1, true), "probe harus selesai")

-- Kalau host menimpa balik, probe harus tetap jujur melaporkannya.
local rot2 = { enabled = false }
local bot2 = { name = "B", status = 1, rotation = rot2 }
local log2 = {}
local env2 = {
    getBot = function() return bot2 end,
    sleep = function() rot2.enabled = false end, -- aplikasi menimpa
    print = function(s) log2[#log2 + 1] = tostring(s) end,
}
setmetatable(env2, { __index = _G })
assert(load(text, '@probe_rotation.lua', 't', env2))()
assert(table.concat(log2, "\n"):find("SESUDAH (3s): enabled=false", 1, true),
    "probe harus melaporkan kalau nilai ditimpa balik")

print("PASS probe_rotation mencetak sebelum/sesudah dan mendeteksi nilai yang ditimpa")
