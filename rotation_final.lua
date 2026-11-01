-- rotation_final.lua
-- Driver rotasi standalone (offline mode) untuk Lucifer v2.86.
-- Semua kerja lapangan dijalankan fitur bawaan Lucifer:
--   rotasi   -> panen, tanam, PNB di home, drop seed, pindah world (custom tile mati)
--   AutoWear -> ambil & pakai Pickaxe (ID 98) dari wear_storage
--   AutoTrash / AutoCollect / AutoReconnect / AutoMalady (Grumbleteeth & Chicken Feet)
-- https://github.com/shizukadev/rotation-script-shizukadev

local CONFIG = {
    FARM_FROM_FILE = true,
    FARM_FILE = "",

    FARMS = {
        { world = "FARM1", door = "" },
        { world = "FARM2", door = "" },
    },

    STORAGE = {
        world = "MYSTORE",
        doorseed = "DOORSEED",
        doorpack = "DOORPACK",
    },

    BLOCK_ID = 4584,
    SEED_ID = 4585,

    STORE_SEED_MIN = 100,
    HARVEST_ROOTS = false,

    ACTION_INTERVALS = {
        hit = 0.18,
        place = 0.16,
    },

    PNB = {
        ENABLED = true,
        WORLD = "",   -- kosong = pakai home world
    },

    PICKAXE_WORLD = { world = "WORLDPICK", door = "" },
    AUTO_WEAR = true,

    AUTO_TRASH = {
        ENABLED = true,
        ITEMS = {},
    },

    AUTO_COLLECT = {
        ENABLED = true,
        RANGE = 3,
        ALL = false,
    },

    AUTO_RECONNECT = {
        ENABLED = true,
        INTERVAL = 5,
    },

    MALADY = {
        GRUMBLETEETH = true,
        CHICKEN_FEET = true,
    },

    WEBHOOK = {
        ENABLED = true,
        URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA",
        MESSAGE_ID = "",
    },

    AUTO_BUY_PACK = {
        ENABLED = true,
        PackName = "world_lock_10_pack",
        PricePack = 20000,
        ItemIDOfPack = { 242 },
    },
}

local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan. Script harus dijalankan di Lucifer bot.")
    return
end

bot.leave_world_before_warp = false

local intervals = CONFIG.ACTION_INTERVALS or {}
local hitInterval = intervals.hit or 0.18
local placeInterval = intervals.place or 0.16

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

local function farmBlockId(farm)
    local id = type(farm) == "table" and (farm.id or farm.blockId or farm.block_id) or nil
    return tonumber(id) or CONFIG.BLOCK_ID
end

local function loadFarmsFromFile(filePath)
    local content = nil
    if type(read) == "function" then
        local ok, data = pcall(read, filePath)
        if ok and data and data ~= "" then content = data end
    end
    if not content and io and io.open then
        local f = io.open(filePath, "r")
        if f then
            content = f:read("*a")
            f:close()
        end
    end
    if not content or content == "" then return nil end

    local list = {}
    for line in (content .. "\n"):gmatch("([^\r\n]+)") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and not line:match("^//") then
            local w, d, id = line:match("^([^:]+):([^:]+):(%d+)$")
            if not w then
                w, d = line:match("^([^:]+):([^:]+)$")
            end
            if not w then
                w = line:match("^([^:]+)$")
            end
            if w and w ~= "" then
                table.insert(list, { world = w, door = d or "", id = tonumber(id) })
            end
        end
    end
    return #list > 0 and list or nil
end

local function resolveFarmList()
    local path = CONFIG.FARM_FILE
    if (not path or path == "") and CONFIG.FARM_FROM_FILE then
        local username = (os and os.getenv and (os.getenv("USERNAME") or os.getenv("USER")))
            or (type(getUsername) == "function" and getUsername())
            or "Administrator"
        path = string.format("C:\\Users\\%s\\Downloads\\rotation.txt", username)
    end

    if path and path ~= "" then
        local fromFile = loadFarmsFromFile(path)
        if fromFile then
            print(string.format("[Setup] Berhasil memuat %d farm dari file: %s", #fromFile, path))
            return fromFile
        else
            print(string.format("[Setup] Peringatan: Gagal membaca file farm '%s'. Memakai CONFIG.FARMS fallback.", path))
        end
    end
    return CONFIG.FARMS or {}
end

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

local function applyBotSettings()
    local recon = CONFIG.AUTO_RECONNECT or {}
    bot.auto_reconnect = recon.ENABLED ~= false
    if recon.INTERVAL then bot.reconnect_interval = recon.INTERVAL end

    local collect = CONFIG.AUTO_COLLECT or {}
    bot.auto_collect = collect.ENABLED ~= false
    if collect.RANGE then bot.collect_range = collect.RANGE end
    if collect.ALL ~= nil then bot.collect_all = collect.ALL end

    bot.auto_wear = CONFIG.AUTO_WEAR ~= false
    bot.wear_id = 98
    local pick = CONFIG.PICKAXE_WORLD
    local pickWorld = type(pick) == "table" and pick.world or pick
    if type(pickWorld) == "string" and pickWorld ~= "" then
        bot.wear_storage = pickWorld
    end

    local trash = CONFIG.AUTO_TRASH or {}
    if trash.ENABLED ~= false and type(setTrashList) == "function" then
        pcall(setTrashList, trash.ITEMS or {})
        bot.auto_trash = true
    else
        bot.auto_trash = false
    end

    if bot.auto_malady then
        local m = CONFIG.MALADY or {}
        bot.auto_malady.auto_grumbleteeth = m.GRUMBLETEETH ~= false
        bot.auto_malady.auto_chicken_feet = m.CHICKEN_FEET == true
        bot.auto_malady.use_home = false
        bot.auto_malady.auto_disconnect = false
        bot.auto_malady.enabled = (m.GRUMBLETEETH ~= false) or (m.CHICKEN_FEET == true)
    end

    for _, key in ipairs({ "auto_farm", "auto_harvest", "auto_plant" }) do
        local module = bot[key]
        if module then module.enabled = false end
    end
end

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
    local farmList = resolveFarmList()
    for _, farm in ipairs(farmList) do
        local world = farmWorldName(farm)
        if world ~= "" then
            local door = farmDoor(farm)
            local nameAndDoor = door ~= "" and (world .. ":" .. door) or world
            local itemToFarm = farmBlockId(farm)
            local farmOk = pcall(function()
                if type(manager.removeFarm) == "function" then
                    manager:removeFarm(world)
                end
                manager:addFarm(nameAndDoor, itemToFarm)
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

local function applyRotationSettings()
    local rotation = bot.rotation
    if not rotation then
        print("[Error] Fitur rotasi bawaan (bot.rotation) tidak tersedia di build Lucifer ini.")
        return false
    end

    rotation.enabled = false

    rotation.auto_rest = false
    rotation.harvest_roots = CONFIG.HARVEST_ROOTS == true
    rotation.dynamic_delay = true
    rotation.visit_random_worlds = false
    rotation.custom_position = false
    rotation.harvest_interval = hitInterval
    rotation.plant_interval = placeInterval
    rotation.break_interval = placeInterval

    if CONFIG.PNB and CONFIG.PNB.ENABLED ~= false then
        rotation.pnb_in_home = true
        if CONFIG.PNB.WORLD and CONFIG.PNB.WORLD ~= "" then
            rotation.pnb_world = CONFIG.PNB.WORLD
        end
    end

    rotation.seed_drop_amount = CONFIG.STORE_SEED_MIN or 100

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

print("[Rotation Final] Memulai rotasi Lucifer v2.86...")
updateWebhook("Engine Dimulai", "-")

applyBotSettings()
registerWorlds()

if not applyRotationSettings() then
    return
end

bot.rotation.enabled = true
print("[Rotation Final] Rotasi bawaan Lucifer AKTIF. Panen/tanam/PNB/drop seed/beli pack dijalankan oleh Lucifer.")
updateWebhook("Rotasi Bawaan Lucifer Aktif", "-")

local farmLabel = #(CONFIG.FARMS or {}) > 0 and farmWorldName(CONFIG.FARMS[1]) or "-"

while waitOnline() do
    sleep(2000)

    if bot.rotation and bot.rotation.enabled ~= true then
        bot.rotation.enabled = true
        print("[Rotation Final] Rotasi bawaan mati (DC/stop). Dinyalakan kembali.")
    end

    updateWebhook("Rotasi Bawaan Lucifer Berjalan", farmLabel)
end

updateWebhook("Bot Offline — Rotasi Berhenti", "-")
print("[Rotation Final] Bot offline. Rotasi berhenti.")
