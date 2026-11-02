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

-- Status rotasi: enum terdokumentasi (bukan tebakan).
if type(RotationStatus) == "table" then
    local names = {}
    for k, v in pairs(RotationStatus) do names[#names + 1] = tostring(v) .. "=" .. tostring(k) end
    table.sort(names)
    local cur = read("status")
    local label = "?"
    for k, v in pairs(RotationStatus) do
        if tostring(v) == cur then label = tostring(k) end
    end
    print("[Probe] RotationStatus: " .. table.concat(names, " "))
    print("[Probe] status sekarang = " .. cur .. " (" .. label .. ")")
else
    print("[Probe] RotationStatus type = " .. type(RotationStatus))
end

-- Daftar farm yang SEBENARNYA dipakai rotasi: getWorldManager().worlds
pcall(function()
    local inst = getWorldManager()
    print("[Probe] type(inst.worlds) = " .. type(inst.worlds))
    local total, selected, shown = 0, 0, 0
    for _, w in pairs(inst.worlds) do
        total = total + 1
        if w.selected then selected = selected + 1 end
        if shown < 3 then
            shown = shown + 1
            local okR, rdy = pcall(function() return w:ready() end)
            local okS, st = pcall(function() return w:getStatus() end)
            print(string.format("[Probe] world %s door=%s item=%s status=%s selected=%s ready=%s",
                tostring(w.name), tostring(w.doorid), tostring(w.itemid),
                tostring(okS and st or w.status), tostring(w.selected), tostring(okR and rdy or "?")))
        end
    end
    print("[Probe] worlds total=" .. total .. " selected=" .. selected)
end)

pcall(function()
    local inst = getWorldManager()
    local ss, ps = 0, 0
    for _ in pairs(inst.seed_storages or {}) do ss = ss + 1 end
    for _ in pairs(inst.pack_storages or {}) do ps = ps + 1 end
    print("[Probe] seed_storages=" .. ss .. " pack_storages=" .. ps)
end)

print("[Probe] selesai. Kirim semua baris di atas.")
