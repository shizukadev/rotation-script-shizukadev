-- probe_rotation.lua
-- Diagnostik mandiri. Jalankan di konsol script Lucifer, lalu kirim SELURUH output.
-- Tujuan: membuktikan apakah `rotation.enabled = true` MENEMPEL, bukan menebak.

local bot = getBot()
if not bot then
    print("[Probe] getBot() nil — script tidak berjalan di konteks bot.")
    return
end

print("[Probe] bot = " .. tostring(bot.name) .. " | status = " .. tostring(bot.status))

-- Angka enum: engine membandingkan bot.status == BotStatus.online.
-- Tanpa ini kita tidak tahu apakah status 20 berarti online.
if type(BotStatus) == "table" then
    local names = {}
    for k, v in pairs(BotStatus) do names[#names + 1] = tostring(k) .. "=" .. tostring(v) end
    table.sort(names)
    print("[Probe] BotStatus: " .. table.concat(names, " "))
else
    print("[Probe] BotStatus type = " .. type(BotStatus))
end

-- Apakah bot benar-benar sudah masuk world?
pcall(function() print("[Probe] isInWorld = " .. tostring(bot:isInWorld())) end)
pcall(function() local w = bot:getWorld() print("[Probe] world = " .. tostring(w and w.name)) end)

local r = bot.rotation
print("[Probe] type(bot.rotation) = " .. type(r))
if not r then
    print("[Probe] bot.rotation nil — build ini tidak punya rotation.")
    return
end

-- 1. Daftar field yang benar-benar ada
local keys = {}
pcall(function()
    for k in pairs(r) do keys[#keys + 1] = tostring(k) end
end)
table.sort(keys)
print("[Probe] field (" .. #keys .. "): " .. table.concat(keys, ","))

-- 2. Nilai sebelum
local function read(key)
    local ok, v = pcall(function() return r[key] end)
    if not ok then return "<error>" end
    return tostring(v)
end
print("[Probe] SEBELUM: enabled=" .. read("enabled") .. " status=" .. read("status"))

-- 3. Tulis true
local okW, errW = pcall(function() r.enabled = true end)
print("[Probe] TULIS enabled=true ok=" .. tostring(okW) .. " err=" .. tostring(errW))

-- 4. Baca langsung
print("[Probe] SESUDAH (langsung): enabled=" .. read("enabled") .. " status=" .. read("status"))

-- 5. Baca lagi setelah 3 detik: kalau balik false, aplikasi menimpanya
sleep(3000)
print("[Probe] SESUDAH (3s): enabled=" .. read("enabled") .. " status=" .. read("status"))

-- 6. Apakah saklar lain tersedia sebagai global?
for _, name in ipairs({ "runInbuiltRotation", "getInbuiltRotationStatus", "setupInbuiltFarmList",
                        "disableBotRotation", "stopSuppliedRotation", "applyRotationSettings" }) do
    print("[Probe] global " .. name .. " = " .. type(rawget(_G, name)))
end

-- Apakah rotasi punya world untuk dikerjakan? enabled=true + status=3 tanpa
-- farm terdaftar = ON tapi diam.
pcall(function()
    local farms = r.farms
    print("[Probe] type(r.farms) = " .. type(farms))
    local n, first = 0, {}
    if type(farms) == "table" then
        for i, w in ipairs(farms) do
            n = n + 1
            if i <= 3 then first[#first + 1] = tostring(w) end
        end
    end
    print("[Probe] jumlah farm = " .. tostring(n) .. " | contoh: " .. table.concat(first, ","))
end)
pcall(function() print("[Probe] rotation.index = " .. tostring(r.index)) end)
pcall(function() print("[Probe] getWorldManager = " .. type(getWorldManager)) end)

print("[Probe] selesai. Kirim semua baris di atas.")
