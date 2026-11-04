-- Regresi: kesepakatan resolver malady antara hasAnyMalady & checkNeedsHospital.
-- Bug: host yang melaporkan bot.malady sebagai nama (string) dianggap sehat oleh
-- checkNeedsHospital sehingga bot tidak pernah berangkat ke 4AID.
local f = assert(io.open('auto_malady_4aid.lua'))
local text = f:read('*a'); f:close()

local env = {
    BotStatus = { online = 1 },
    Event = { variantlist = 1 },
    addEvent = function() end,
    sleep = function() end,
    print = function() end,
}
setmetatable(env, { __index = _G })
local mod = assert(load(text, '@auto_malady_4aid.lua', 't', env))()

local function botWith(malady, dur)
    return {
        status = 1,
        malady = malady,
        getMaladyDuration = dur ~= nil and function() return dur end or nil,
        isInWorld = function() return false end,
    }
end

-- 1. Numerik: sudah benar sebelumnya, jangan sampai mundur.
local sick, id = mod.hasAnyMalady(botWith(1, 30))
assert(sick == true and id == 1, "numeric id 1 harus terbaca sakit")
assert(mod.checkNeedsHospital(botWith(1, 30)) == true, "numeric id 1 harus butuh hospital")

-- 2. String nama: ini kasus yang membuat bot diam saja.
local sSick, sId = mod.hasAnyMalady(botWith("Torn Punching Muscle", 30))
assert(sSick == true, "string malady harus terbaca sakit")
local sNeeds = mod.checkNeedsHospital(botWith("Torn Punching Muscle", 30))
assert(sNeeds == true, "string 'Torn Punching Muscle' harus memicu rute 4AID, dapat: " .. tostring(sNeeds))
assert(sId == 1, "id hasil resolve harus 1, dapat: " .. tostring(sId))

-- 3. Non-target tidak boleh memicu rute.
assert(mod.checkNeedsHospital(botWith("Grumbleteeth", 30)) == false, "Grumbleteeth (4) bukan target")
assert(mod.checkNeedsHospital(botWith(4, 30)) == false, "id 4 bukan target")

-- 4. Sehat & unknown tetap konsisten.
assert(mod.hasAnyMalady(botWith(0, 0)) == false, "id 0 + durasi 0 = sehat")
assert(mod.hasAnyMalady(botWith(nil, 0)) == "unknown", "nil + durasi 0 tetap unknown")
assert(mod.hasAnyMalady(botWith("bukan penyakit", 0)) == "unknown", "string asing tetap unknown")

-- 5. Kedua fungsi tidak boleh berbeda pendapat.
for _, case in ipairs({ { 1, 30 }, { 2, 30 }, { 4, 30 }, { 0, 0 }, { "Torn Punching Muscle", 30 }, { "Gem Cuts", 30 }, { "Grumbleteeth", 30 } }) do
    local b = botWith(case[1], case[2])
    local a = mod.hasAnyMalady(b)
    local needs = mod.checkNeedsHospital(b)
    if a == true and needs == true then
        -- target: keduanya sepakat sakit DAN butuh hospital -> konsisten
    elseif a == true and needs == false then
        local _, rid = mod.hasAnyMalady(b)
        assert(rid ~= 1 and rid ~= 2, string.format("kontradiksi untuk %s: sakit id %s tapi tidak butuh hospital", tostring(case[1]), tostring(rid)))
    end
end

print("PASS malady resolver sepakat (numeric + string) dan filter target 1/2 utuh")
