-- probe_rotation.lua
-- Diagnostik mandiri. Jalankan di konsol script Lucifer, lalu kirim SELURUH output.
-- Tujuan: membuktikan apakah `rotation.enabled = true` MENEMPEL, bukan menebak.

local bot = getBot()
if not bot then
    print("[Probe] getBot() nil — script tidak berjalan di konteks bot.")
    return
end

print("[Probe] bot = " .. tostring(bot.name) .. " | status = " .. tostring(bot.status))

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

print("[Probe] selesai. Kirim semua baris di atas.")
