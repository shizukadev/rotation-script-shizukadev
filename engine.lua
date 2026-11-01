-- engine.lua
-- Driver rotasi untuk Lucifer v2.86.
-- Semua kerja lapangan dijalankan fitur bawaan Lucifer:
--   rotasi   -> panen, tanam, PNB di home, drop seed, pindah world
--   AutoWear -> ambil & pakai Pickaxe
--   AutoTrash / AutoCollect / AutoReconnect / AutoMalady
-- Script ini hanya memetakan CONFIG ke fitur itu, lalu memantau lewat webhook.
-- https://github.com/shizukadev/rotation-script-shizukadev

local CONFIG = ... or _G.CONFIG
if not CONFIG then
    print("[Error] CONFIG tidak ditemukan. Harap jalankan script melalui loader.lua")
    return
end

local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan. Script harus dijalankan di Lucifer bot.")
    return
end

bot.leave_world_before_warp = false -- Langsung warp antar-world tanpa exit terlebih dahulu

local intervals = CONFIG.ACTION_INTERVALS or {}
local hitInterval = intervals.hit or 0.18
local placeInterval = intervals.place or 0.16

-- ========================================================
-- HELPER
-- ========================================================
local function waitOnline(timeout)
    for _ = 1, (timeout or 30) do
        if bot.status == BotStatus.online then return true end
        sleep(1000)
    end
    return false
end

local function farmWorldName(farm)
    local name = type(farm) == "table" and (farm.world or farm.worldName) or farm
    return type(name) == "string" and name:upper() or ""
end

local function farmDoor(farm)
    return type(farm) == "table" and (farm.door or farm.worldDoor or "") or ""
end

-- ========================================================
-- DISCORD WEBHOOK MONITORING (EDIT PESAN REALTIME)
-- Tidak ada padanan bawaan Lucifer, jadi tetap di sini.
-- ========================================================
local webhookClient = nil
local lastWebhookSent = 0

local function updateWebhook(currentAction, activeFarm)
    local cfg = CONFIG.WEBHOOK
    if not cfg or not cfg.ENABLED or not cfg.URL or cfg.URL == "" or cfg.URL:find("MASUKKAN_URL") then
        return
    end

    local now = os.time and os.time() or 0
    if (now - lastWebhookSent) < 3 then return end
    lastWebhookSent = now

    if not webhookClient then
        webhookClient = Webhook.new(cfg.URL)
        webhookClient.username = "Lucifer Monitor (" .. tostring(bot.name) .. ")"
    end

    if cfg.MESSAGE_ID and cfg.MESSAGE_ID ~= "" then
        webhookClient.message_id = tostring(cfg.MESSAGE_ID)
    end

    local isOnline = (bot.status == BotStatus.online)
    local currentWorld = (bot:isInWorld() and bot:getWorld().name or "In Transit")
    local tilePos = string.format("(%d, %d)", bot.x or 0, bot.y or 0)
    local ping = tostring(bot:getPing()) .. " ms"
    local gems = tostring(bot.gem_count or 0)

    local inv = bot:getInventory()
    local slots = inv and (tostring(inv.itemcount) .. "/" .. tostring(inv.slotcount)) or "-"
    local emptySlots = inv and tostring(inv.emptyslots) or "-"

    local packItemStr = "-"
    local packCfg = CONFIG.AUTO_BUY_PACK
    if packCfg and packCfg.ENABLED and packCfg.ItemIDOfPack and inv then
        local parts = {}
        for _, id in ipairs(packCfg.ItemIDOfPack) do
            local c = inv:findItem(id)
            if c > 0 then table.insert(parts, string.format("ID %d: %d", id, c)) end
        end
        if #parts > 0 then packItemStr = table.concat(parts, ", ") end
    end

    local statusColor = isOnline and 3066993 or 15158332

    webhookClient.content = ""
    webhookClient.embed1.use = true
    webhookClient.embed1.color = statusColor
    webhookClient.embed1.title = "📊 Lucifer Rotation v2.86 — " .. tostring(bot.name)
    webhookClient.embed1.description = string.format("**Aktivitas:** %s\n**Target Farm:** %s", tostring(currentAction or "-"), tostring(activeFarm or "-"))

    webhookClient.embed1:addField("Status", isOnline and "🟢 ONLINE" or "🔴 OFFLINE", true)
    webhookClient.embed1:addField("World Sekarang", currentWorld, true)
    webhookClient.embed1:addField("Posisi Tile", tilePos, true)
    webhookClient.embed1:addField("Gems", gems, true)
    webhookClient.embed1:addField("Ping", ping, true)
    webhookClient.embed1:addField("Slot Tas (Isi/Kosong)", string.format("%s (Sisa %s)", slots, emptySlots), true)
    webhookClient.embed1:addField("Item Pack di Tas", packItemStr, false)

    if webhookClient.message_id and webhookClient.message_id ~= "" then
        webhookClient:edit()
    else
        webhookClient:send()
    end
end

-- ========================================================
-- SETELAN MODULE BAWAAN LUCIFER (AutoWear / AutoTrash / Collect / Reconnect / Malady)
-- ========================================================
local function applyBotSettings()
    -- Reconnect
    local recon = CONFIG.AUTO_RECONNECT or {}
    bot.auto_reconnect = recon.ENABLED ~= false
    if recon.INTERVAL then bot.reconnect_interval = recon.INTERVAL end

    -- Collect objek di sekitar (dipakai rotasi saat panen)
    local collect = CONFIG.AUTO_COLLECT or {}
    bot.auto_collect = collect.ENABLED ~= false
    if collect.RANGE then bot.collect_range = collect.RANGE end
    if collect.ALL ~= nil then bot.collect_all = collect.ALL end

    -- Pickaxe: AutoWear ambil dari wear_storage kalau belum ada di tas
    bot.auto_wear = CONFIG.AUTO_WEAR ~= false
    bot.wear_id = 98
    local pick = CONFIG.PICKAXE_WORLD
    if pick and pick.world and pick.world ~= "" then
        bot.wear_storage = pick.world
    end

    -- Sampah: AutoTrash + daftar ID yang dibuang (whitelist ada di trash.ITEMS)
    local trash = CONFIG.AUTO_TRASH or {}
    if trash.ENABLED ~= false and type(setTrashList) == "function" then
        pcall(setTrashList, trash.ITEMS or {})
        bot.auto_trash = true
    else
        bot.auto_trash = false
    end

    -- Malady: AutoMalady bawaan (Grumbleteeth / Chicken Feet)
    if bot.auto_malady then
        local m = CONFIG.MALADY or {}
        bot.auto_malady.auto_grumbleteeth = m.GRUMBLETEETH ~= false
        bot.auto_malady.auto_chicken_feet = m.CHICKEN_FEET == true
        bot.auto_malady.use_home = false
        bot.auto_malady.auto_disconnect = false
        bot.auto_malady.enabled = (m.GRUMBLETEETH ~= false) or (m.CHICKEN_FEET == true)
    end

    -- Matikan automation lain yang bisa berebut dengan rotasi
    for _, key in ipairs({ "auto_farm", "auto_harvest", "auto_plant" }) do
        local module = bot[key]
        if module then module.enabled = false end
    end
end

-- ========================================================
-- DAFTARKAN WORLD FARM & STORAGE KE WORLDMANAGER
-- Rotasi bawaan Lucifer membaca daftar world dari WorldManager, bukan dari CONFIG.
-- ========================================================
local function registerWorlds()
    if type(getWorldManager) ~= "function" or type(StorageType) ~= "table" then
        print("[Setup] Peringatan: WorldManager/StorageType tidak tersedia. Daftarkan world & storage manual di UI Lucifer.")
        return false
    end

    local ok, manager = pcall(getWorldManager)
    if not ok or not manager or type(manager.addFarm) ~= "function" then
        print("[Setup] Peringatan: WorldManager gagal diambil. Daftarkan world & storage manual di UI Lucifer.")
        return false
    end

    local registered = 0
    for _, farm in ipairs(CONFIG.FARMS or {}) do
        local world = farmWorldName(farm)
        if world ~= "" then
            local door = farmDoor(farm)
            local nameAndDoor = door ~= "" and (world .. ":" .. door) or world
            local farmOk = pcall(function()
                if type(manager.removeFarm) == "function" then
                    manager:removeFarm(world)
                end
                manager:addFarm(nameAndDoor, CONFIG.BLOCK_ID)
            end)
            if farmOk then
                registered = registered + 1
            else
                print("[Setup] Gagal mendaftarkan farm: " .. nameAndDoor)
            end
        end
    end

    local storage = CONFIG.STORAGE
    if type(storage) == "table" and storage.world and storage.world ~= "" then
        local seedDoor = storage.doorseed or storage.door or ""
        local seedName = seedDoor ~= "" and (storage.world .. ":" .. seedDoor) or storage.world
        pcall(function()
            if type(manager.removeStorage) == "function" then
                manager:removeStorage(storage.world, StorageType.seed)
            end
            manager:addStorage(seedName, StorageType.seed, CONFIG.SEED_ID)
        end)

        if CONFIG.AUTO_BUY_PACK and CONFIG.AUTO_BUY_PACK.ENABLED then
            local packDoor = storage.doorpack or storage.door or ""
            local packName = packDoor ~= "" and (storage.world .. ":" .. packDoor) or storage.world
            pcall(function()
                if type(manager.removeStorage) == "function" then
                    manager:removeStorage(storage.world, StorageType.pack)
                end
                manager:addStorage(packName, StorageType.pack, 0)
            end)
        end
    else
        print("[Setup] Peringatan: CONFIG.STORAGE kosong. Seed & pack tidak akan disimpan otomatis.")
    end

    if type(manager.selectAll) == "function" then
        pcall(function() manager:selectAll() end)
    end

    print(string.format("[Setup] %d world farm terdaftar di rotasi Lucifer.", registered))
    return true
end

-- ========================================================
-- SETELAN ROTASI BAWAAN LUCIFER
-- ========================================================
local function applyRotationSettings()
    local rotation = bot.rotation
    if not rotation then
        print("[Error] Fitur rotasi bawaan (bot.rotation) tidak tersedia di build Lucifer ini.")
        return false
    end

    rotation.enabled = false -- setel dulu dalam keadaan mati, baru dinyalakan

    rotation.auto_rest = false
    rotation.harvest_roots = CONFIG.HARVEST_ROOTS == true
    rotation.dynamic_delay = true
    rotation.visit_random_worlds = false
    rotation.custom_position = false -- pakai tile default, bukan custom break tile
    rotation.harvest_interval = hitInterval
    rotation.plant_interval = placeInterval
    rotation.break_interval = placeInterval

    -- PNB di home dijalankan fitur bawaan Lucifer, bukan script ini
    if CONFIG.PNB and CONFIG.PNB.ENABLED ~= false then
        rotation.pnb_in_home = true
        if CONFIG.PNB.WORLD and CONFIG.PNB.WORLD ~= "" then
            rotation.pnb_world = CONFIG.PNB.WORLD
        end
    end

    -- Ambang drop seed ke storage (rotasi yang menjatuhkan, bukan script ini)
    rotation.seed_drop_amount = CONFIG.STORE_SEED_MIN or 100

    -- Beli pack otomatis: rotasi berhenti memanen saat gems mencapai gem_limit lalu membeli PackName
    local packCfg = CONFIG.AUTO_BUY_PACK
    if packCfg and packCfg.ENABLED and packCfg.PricePack and packCfg.PackName then
        bot.gem_limit = packCfg.PricePack
        if type(bot.setPack) == "function" then
            local ok = pcall(function() bot:setPack(packCfg.PackName) end)
            if not ok then
                print("[Setup] Peringatan: gagal setPack '" .. tostring(packCfg.PackName) .. "'. Atur pack di UI Lucifer.")
            end
        end
    end

    return true
end

-- ========================================================
-- EKSEKUSI
-- ========================================================
print("[Engine] Memulai driver rotasi Lucifer v2.86...")
updateWebhook("Engine Dimulai", "-")

applyBotSettings()
registerWorlds()

if not applyRotationSettings() then
    return
end

bot.rotation.enabled = true
print("[Engine] Rotasi bawaan Lucifer AKTIF. Panen/tanam/PNB/drop seed/beli pack dijalankan oleh Lucifer.")
updateWebhook("Rotasi Bawaan Lucifer Aktif", "-")

local farmLabel = #(CONFIG.FARMS or {}) > 0 and farmWorldName(CONFIG.FARMS[1]) or "-"

while waitOnline() do
    sleep(2000)

    -- Lucifer mematikan rotasi saat disconnect / stop manual: nyalakan lagi kalau bot sudah online
    if bot.rotation and bot.rotation.enabled ~= true then
        bot.rotation.enabled = true
        print("[Engine] Rotasi bawaan mati (DC/stop). Dinyalakan kembali.")
    end

    updateWebhook("Rotasi Bawaan Lucifer Berjalan", farmLabel)
end

updateWebhook("Bot Offline — Rotasi Berhenti", "-")
print("[Engine] Bot offline. Rotasi berhenti.")
