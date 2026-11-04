-- Offline unit test untuk auto_malady_4aid.lua
local f = assert(io.open('auto_malady_4aid.lua'))
local text = f:read('*a'); f:close()

local log = {}
local packets = {}

local bot
bot = {
    x = 0, y = 0,
    status = 1,
    malady = 1, -- Torn Muscle
    currentWorld = "",
    isInWorld = function(_, w)
        if w then return bot.currentWorld == w end
        return bot.currentWorld ~= ""
    end,
    warp = function(_, w)
        table.insert(log, "warp:" .. w)
        bot.currentWorld = w
    end,
    findPath = function(_, x, y)
        table.insert(log, string.format("path:%d,%d", x, y))
        bot.x, bot.y = x, y
        return true
    end,
    hit = function(_, x, y) table.insert(log, string.format("hit:%d,%d", x, y)) end,
    sendPacket = function(_, t, p) table.insert(packets, { type = t, text = p }) end,
    enter = function() table.insert(log, "enter") end,
}

local env = {
    getBot = function() return bot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1 },
    addEvent = function() end,
    sleep = function()
        if (bot.x == 66 and bot.y == 39) or (bot.x == 73 and bot.y == 29) then
            bot.malady = 0
        end
    end,
    print = function(s) table.insert(log, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(env, { __index = _G })

assert(load(text, '@auto_malady_4aid.lua', 't', env))()

-- Verifikasi urutan
local hasWarp = false
local hasPath22, hasHit22 = false, false
local hasPath61, hasHit61 = false, false
local hasPath64, hasHit64 = false, false
local hasPath50, hasHit50 = false, false
local hasPath66 = false

for _, entry in ipairs(log) do
    if entry:find("warp:4AID") then hasWarp = true end
    if entry == "path:22,16" then hasPath22 = true end
    if entry == "hit:22,16" or entry == "enter" then hasHit22 = true end
    if entry == "path:61,12" then hasPath61 = true end
    if entry == "hit:61,12" then hasHit61 = true end
    if entry == "path:58,15" or entry == "path:64,12" then hasPath64 = true end
    if entry == "hit:58,15" or entry == "hit:64,12" or entry == "enter" then hasHit64 = true end
    if entry == "path:50,15" then hasPath50 = true end
    if entry == "hit:50,15" or entry == "enter" then hasHit50 = true end
    if entry == "path:66,39" or entry == "path:73,29" then hasPath66 = true end
end

assert(hasWarp, "gagal warp ke 4AID")
assert(hasPath22 and hasHit22, "step 1 portal 22,16 gagal")
assert(hasPath61 and hasHit61, "step 2 adventure key 61,12 gagal")
assert(hasPath64 and hasHit64, "step 2 portal 64,12 gagal")
assert(hasPath50 and hasHit50, "step 3 door 50,15 gagal")
assert(hasPath66, "step 4 path surg area 66,39 gagal")

assert(#packets > 0, "packet adventure door tidak terkirim")
assert(packets[1].type == 2, "packet type harus 2")
assert(packets[1].text:find("action|dialog_return") and packets[1].text:find("button0"), "isi packet salah: " .. packets[1].text)

-- Uji eksklusi malady lain (misal ID 5 Chicken Feet / 0 Sehat)
bot.malady = 5
local outSkip = {}
local env2 = {
    getBot = function() return bot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1 },
    addEvent = function() end,
    sleep = function() end,
    print = function(s) table.insert(outSkip, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(env2, { __index = _G })
assert(load(text, '@auto_malady_4aid.lua', 't', env2))()
assert(outSkip[1]:find("Tidak perlu ke 4AID"), "malady non-target harus diskip")

-- Uji kegagalan pathfinding: tidak boleh kirim packet atau lapor sukses
local failPackets = {}
local failLog = {}
local failBot
failBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    currentWorld = "",
    isInWorld = function(_, w)
        if w then return failBot.currentWorld == w end
        return failBot.currentWorld ~= ""
    end,
    warp = function(_, w) failBot.currentWorld = w end,
    findPath = function() return false end,
    hit = function() end,
    sendPacket = function(_, t, p) table.insert(failPackets, { type = t, text = p }) end,
    enter = function() end,
}
local envFail = {
    getBot = function() return failBot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1 },
    addEvent = function() end,
    removeEvent = function() end,
    sleep = function() end,
    print = function(s) table.insert(failLog, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envFail, { __index = _G })
local mod = assert(load(text, '@auto_malady_4aid.lua', 't', envFail))("auto_malady_4aid")
local res = mod.runCure(failBot)
assert(res == false, "runCure harus return false jika findPath gagal")
assert(#failPackets == 0, "packet tidak boleh terkirim jika findPath gagal")
local logStr = table.concat(failLog, "\n")
assert(not logStr:find("Berhasil sembuh dari penyakit"), "tidak boleh mencetak sukses jika navigasi gagal")

-- Uji pengembalian status 'cured' saat malady benar-benar hilang (hasAnyMalady == false)
local cureSuccessBot
cureSuccessBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    currentWorld = "",
    isInWorld = function(_, w)
        if w then return cureSuccessBot.currentWorld == w end
        return cureSuccessBot.currentWorld ~= ""
    end,
    warp = function(_, w) cureSuccessBot.currentWorld = w end,
    findPath = function(_, x, y)
        cureSuccessBot.x, cureSuccessBot.y = x, y
        return true
    end,
    hit = function() end,
    sendPacket = function()
        return true
    end,
    enter = function() end,
}
local envCureSuccess = {
    getBot = function() return cureSuccessBot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1 },
    addEvent = function() end,
    removeEvent = function() end,
    sleep = function()
        -- Malady benar-benar hilang (menjadi 0) saat menunggu di bed
        if (cureSuccessBot.x == 66 and cureSuccessBot.y == 39) or (cureSuccessBot.x == 73 and cureSuccessBot.y == 29) then
            cureSuccessBot.malady = 0
        end
    end,
    print = function() end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envCureSuccess, { __index = _G })
local cureMod = assert(load(text, '@auto_malady_4aid.lua', 't', envCureSuccess))("auto_malady_4aid")
local cureRes = cureMod.runCure(cureSuccessBot)
assert(cureRes == "cured", "runCure harus mengembalikan 'cured' jika malady benar-benar hilang")
assert((cureSuccessBot.x == 66 and cureSuccessBot.y == 39) or (cureSuccessBot.x == 73 and cureSuccessBot.y == 29), "bot harus berada di koordinat bed")
print("PASS status sembuh 'cured' terverifikasi di (66, 39)")

-- Uji regresi: malady berubah ke non-target (misal ID 3) TIDAK BOLEH diklaim cured
local morphBot
morphBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    currentWorld = "",
    isInWorld = function(_, w)
        if w then return morphBot.currentWorld == w end
        return morphBot.currentWorld ~= ""
    end,
    warp = function(_, w) morphBot.currentWorld = w end,
    findPath = function(_, x, y)
        morphBot.x, morphBot.y = x, y
        return true
    end,
    hit = function() end,
    sendPacket = function() return true end,
    enter = function() end,
}
local morphSteps = 0
local envMorph = {
    getBot = function() return morphBot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1 },
    addEvent = function() end,
    removeEvent = function() end,
    sleep = function()
        morphSteps = morphSteps + 1
        if (morphBot.x == 66 and morphBot.y == 39) or (morphBot.x == 73 and morphBot.y == 29) then
            -- Penyakit bermutasi ke ID 3 (bukan hilang!)
            morphBot.malady = 3
            if morphSteps >= 3 then
                -- Putus koneksi agar loop keluar
                morphBot.status = 0
            end
        end
    end,
    print = function() end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envMorph, { __index = _G })
local morphMod = assert(load(text, '@auto_malady_4aid.lua', 't', envMorph))("auto_malady_4aid")
local morphRes = morphMod.runCure(morphBot)
assert(morphRes == false, "runCure TIDAK BOLEH mengembalikan 'cured' jika penyakit berubah ke ID non-target (masih sakit)")
print("PASS penolakan klaim sembuh saat malady bermutasi ke non-target")

-- Uji regresi: status malady tidak valid (nil / durasi gagal / data rusak) -> tidak boleh dianggap sehat
local invalidBot1 = { malady = nil }
local invalidBot2 = { malady = "invalid_string" }
local invalidBot3 = { malady = nil, getMaladyDuration = function() return nil end }
local invalidBot4 = { malady = "invalid", getMaladyDuration = function() return 0 end }
local invalidBot5 = { malady = nil, getMaladyDuration = function() return 0 end }
local validSickBot = { malady = 1 }
local validHealthyBot = { malady = 0, getMaladyDuration = function() return 0 end }

assert(mod.hasAnyMalady(invalidBot1) == "unknown", "malady nil harus unknown")
assert(mod.hasAnyMalady(invalidBot2) == "unknown", "malady invalid string harus unknown")
assert(mod.hasAnyMalady(invalidBot3) == "unknown", "malady nil + duration nil harus unknown")
assert(mod.hasAnyMalady(invalidBot4) == "unknown", "malady invalid string + duration 0 harus tetap unknown")
assert(mod.hasAnyMalady(invalidBot5) == "unknown", "malady nil + duration 0 harus tetap unknown")
assert(mod.hasAnyMalady(validSickBot) == true, "malady valid 1 harus true")
local okHealth, durHealth = mod.hasAnyMalady(validHealthyBot)
assert(okHealth == false and durHealth == 0, "malady valid 0 harus false")
print("PASS penanganan data malady tidak valid/unknown (termasuk durasi 0 pada ID nil/invalid)")

-- Uji pemuatan modul via require tidak memicu efek samping (clean require)
local requireLog = {}
local dummyBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    hit = function() table.insert(requireLog, "hit") end,
    enter = function() table.insert(requireLog, "enter") end,
}
local envRequire = {
    getBot = function() return dummyBot end,
    BotStatus = { online = 1 },
    print = function(s) table.insert(requireLog, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envRequire, { __index = _G })
-- Simulasi require("auto_malady_4aid"): argumen vararg = nama modul
local loadedMod = assert(load(text, '@auto_malady_4aid.lua', 't', envRequire))("auto_malady_4aid")
assert(type(loadedMod) == "table" and type(loadedMod.runCure) == "function", "harus mengekspor tabel modul")
assert(#requireLog == 0, "pemuatan modul melalui require TIDAK BOLEH memicu aksi/efek samping")
print("PASS pemuatan modul bersih tanpa efek samping")

print("PASS test_auto_malady_4aid")
