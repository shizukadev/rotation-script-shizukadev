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
        BYPASS_LOGON = true,
        MAX_FAIL_ATTEMPTS = 15,
        MAX_FAIL_MINUTES = 5,
    },

    OFFLINE_ALERT = {
        ENABLED = true,
        TIMEOUT_MINUTES = 5,
        DISCORD_USER_ID = "922775541097066576",
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

local updateWebhook, sendWebhookNotification
local observedOfflineDuringWait = false
local loginFailCount = 0
local loginFailStartTime = nil
local lockoutTriggered = false
local lastObservedStatus = nil
local inLoginAttempt = false
local lastAttemptWasFailure = false

local function waitOnline(timeout)
    local tries = timeout or 30
    if updateWebhook then updateWebhook("Menunggu reconnect") end
    while true do
        if lockoutTriggered then
            if bot.auto_reconnect == true then
                lockoutTriggered = false
                loginFailCount = 0
                loginFailStartTime = nil
                lastAttemptWasFailure = false
                inLoginAttempt = false
                print("[Security] Sinyal reset manual dari owner terdeteksi pada runtime. Lockout direset.")
            else
                if bot.rotation then bot.rotation.enabled = false end
                bot.auto_reconnect = false
                bot.bypass_logon = false
            end
        end
        if updateWebhook then updateWebhook("Menunggu reconnect") end
        local reconCfg = CONFIG.AUTO_RECONNECT or {}
        local maxFailTries = reconCfg.MAX_FAIL_ATTEMPTS or 15
        local maxFailSecs = (reconCfg.MAX_FAIL_MINUTES or 5) * 60
        local now = os.time and os.time() or 0

        -- Deteksi transisi status kegagalan login terminal:
        -- Dihitung 1 kali per transisi masuk ke status error terminal (logon_fail, error_connecting, too_many_login, server_overload, http_block)
        local curStatus = bot.status
        if not lockoutTriggered and curStatus ~= BotStatus.online then
            if not loginFailStartTime then loginFailStartTime = now end

            -- Count only sampled attempt start followed by one terminal failure.
            if BotStatus.getting_server_data ~= nil and curStatus == BotStatus.getting_server_data
                and curStatus ~= lastObservedStatus then
                inLoginAttempt = true
            end
            local isTerminalFailure = inLoginAttempt and (
                (BotStatus.logon_fail ~= nil and curStatus == BotStatus.logon_fail) or
                (BotStatus.error_connecting ~= nil and curStatus == BotStatus.error_connecting) or
                (BotStatus.too_many_login ~= nil and curStatus == BotStatus.too_many_login) or
                (BotStatus.server_overload ~= nil and curStatus == BotStatus.server_overload) or
                (BotStatus.http_block ~= nil and curStatus == BotStatus.http_block)
            )
            if isTerminalFailure then inLoginAttempt = false end
            -- Unsampled native attempts use the duration-limit fallback.

            if isTerminalFailure then
                loginFailCount = loginFailCount + 1
            end

            -- Evaluasi ambang batas: hitungan transisi gagal login ATAU batas durasi gagal login
            local durationExceeded = (now - loginFailStartTime) >= maxFailSecs
            local countExceeded = loginFailCount >= maxFailTries

            if countExceeded or durationExceeded then
                lockoutTriggered = true
                bot.auto_reconnect = false
                bot.bypass_logon = false
                if bot.rotation then bot.rotation.enabled = false end
                local reason = countExceeded
                    and string.format("Transisi gagal login mencapai %d/%d kali", loginFailCount, maxFailTries)
                    or string.format("Durasi offline/gagal login mencapai %d/%d detik", (now - loginFailStartTime), maxFailSecs)
                print(string.format("[Security] %s. Mematikan bypass_logon dan auto_reconnect permanen sampai owner menyalakan manual.", reason))
                if type(sendWebhookNotification) == "function" then
                    sendWebhookNotification(string.format("🛑 **[Login Fail Lockout]** Bot **%s** %s! `bypass_logon` dan `auto_reconnect` telah DINONAKTIFKAN. Harap periksa dan nyalakan secara manual.", tostring(bot.name), reason))
                end
            end
        elseif curStatus == BotStatus.online then
            if not lockoutTriggered then
                loginFailCount = 0
                loginFailStartTime = nil
            end
        end

        lastObservedStatus = curStatus

        if bot.status == BotStatus.online then return true end
        observedOfflineDuringWait = true
        sleep(1000)
        tries = tries - 1
        if tries <= 0 then break end
    end
    return bot.status == BotStatus.online
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

-- ========================================================
-- DISCORD WEBHOOK MONITORING (webhook_monitor.lua)
-- Dikelola via modul terpadu webhook_monitor.
-- ========================================================
local webhookMonitor = nil
local function getWebhookMonitor()
    if not webhookMonitor then
        local ok, mod = pcall(require, "webhook_monitor")
        if not ok or type(mod) ~= "table" then
            local f = io.open("webhook_monitor.lua", "r") or io.open("lucifer-rotation-main/webhook_monitor.lua", "r")
            if f then
                local code = f:read("*a")
                f:close()
                local chunk = (loadstring or load)(code, "@webhook_monitor.lua")
                if chunk then mod = chunk() end
            end
        end
        if mod and type(mod.new) == "function" then
            webhookMonitor = mod.new(bot, CONFIG, { os = os, BotStatus = BotStatus, Webhook = Webhook, print = print })
        end
    end
    return webhookMonitor
end

updateWebhook = function(currentAction)
    local mon = getWebhookMonitor()
    if mon and type(mon.tick) == "function" then
        pcall(function() mon.tick(currentAction) end)
    end
end

sendWebhookNotification = function(msg)
    local mon = getWebhookMonitor()
    if mon and type(mon.notify) == "function" then
        pcall(function() mon.notify(msg) end)
    end
end

local function applyBotSettings()
    local recon = CONFIG.AUTO_RECONNECT or {}
    bot.auto_reconnect = recon.ENABLED ~= false
    if recon.INTERVAL then bot.reconnect_interval = recon.INTERVAL end
    if recon.BYPASS_LOGON ~= nil then
        bot.bypass_logon = recon.BYPASS_LOGON
    end

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

-- ========================================================
-- SETELAN ROTASI BAWAAN LUCIFER
-- ========================================================
local function applyRotationSettings()
    local rotation = bot.rotation
    if not rotation then
        print("[Error] Fitur rotasi bawaan (bot.rotation) tidak tersedia di build Lucifer ini.")
        return false
    end

    rotation.enabled = false
    if lockoutTriggered then return false end

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
        else
            rotation.pnb_world = nil
        end
    else
        rotation.pnb_in_home = false
        rotation.pnb_world = nil
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

local function startupStage(name, fn)
    print("[Setup] Mulai: " .. name)
    local ok, result = pcall(fn)
    if not ok then
        -- Do not print exception text: host exceptions may contain private config.
        print("[Setup] GAGAL: " .. name .. ". Periksa kompatibilitas API; hospital supervisor tetap dijalankan.")
        return false
    end
    print("[Setup] Selesai: " .. name)
    return result ~= false
end
local botSetupOK = startupStage("pengaturan bot", applyBotSettings)
local worldsSetupOK = startupStage("registrasi world", registerWorlds)
local rotationSetupOK = startupStage("pengaturan rotasi", applyRotationSettings)
local okStartup = botSetupOK and worldsSetupOK and rotationSetupOK
if okStartup and not lockoutTriggered then
    bot.rotation.enabled = true
    print("[Rotation Final] Rotasi bawaan Lucifer AKTIF. Panen/tanam/PNB/drop seed/beli pack dijalankan oleh Lucifer.")
else
    if bot.rotation then bot.rotation.enabled = false end
end
updateWebhook("Rotasi Bawaan Lucifer Aktif", "-")

-- ========================================================
-- AUTO MALADY 4AID DISPATCHER (TORN MUSCLE / GEM CUTS)
-- ========================================================
local hospitalMod = nil
local hospitalLoadAttempt = nil
local function getHospitalModule()
    local now = os.time()
    if hospitalMod == nil and hospitalLoadAttempt and now - hospitalLoadAttempt < 30 then return nil end
    if hospitalMod == nil then
        hospitalLoadAttempt = now
        local ok, mod = pcall(require, "auto_malady_4aid")
        if ok and type(mod) == "table" and type(mod.runCure) == "function" then
            hospitalMod = mod
        else
            local f = io.open("auto_malady_4aid.lua", "r") or io.open("lucifer-rotation-main/auto_malady_4aid.lua", "r")
            if f then
                local code = f:read("*a")
                f:close()
                local chunk = (loadstring or load)(code, "@auto_malady_4aid.lua")
                if chunk then
                    local res = chunk("module")
                    if type(res) == "table" and type(res.runCure) == "function" then
                        hospitalMod = res
                    end
                end
            end
        end
    end
    if not hospitalMod then
        -- Loader users may not have companion files in the host working directory.
        local ok, res = pcall(function()
            local client = HttpClient.new()
            client.url = "https://raw.githubusercontent.com/shizukadev/rotation-script-shizukadev/main/auto_malady_4aid.lua"
            client:setMethod(Method.get)
            client.timeout = 15
            return client:request()
        end)
        if ok and res and res.error == 0 and res.status == 200 then
            local chunk = (loadstring or load)(res.body, "@auto_malady_4aid.lua")
            if chunk then
                local loaded, mod = pcall(chunk, "module")
                if loaded and type(mod) == "table" and type(mod.runCure) == "function"
                    and type(mod.checkNeedsHospital) == "function" then hospitalMod = mod end
            end
        end
        if not hospitalMod then
            print("[Hospital] Modul auto_malady_4aid tidak tersedia. Periksa file lokal atau unduhan GitHub; retry 30 detik.")
        end
    end
    return hospitalMod
end

local lastHospitalAttempt = 0
local HOSPITAL_COOLDOWN = 180 -- Jeda 3 menit sebelum mengulang rute 4AID jika masih sakit
local hospitalPending = false -- Status pengobatan sedang berjalan/menunggu sembuh
local shouldResumeAfterCure = false -- Intent apakah rotasi harus dinyalakan kembali pasca sembuh
local intentionalStop = false -- user stop intent

local function checkAndDispatchHospital()
    local mod = getHospitalModule()
    if not mod then return false end

    local anySick, curId = false, 0
    if type(mod.hasAnyMalady) == "function" then
        anySick, curId = mod.hasAnyMalady(bot)
    else
        anySick, curId = mod.checkNeedsHospital(bot)
    end

    if anySick == false then
        if hospitalPending then
            hospitalPending = false
            if shouldResumeAfterCure and not intentionalStop and bot.rotation and bot.status == BotStatus.online then
                bot.rotation.enabled = true
                shouldResumeAfterCure = false
                print("[Rotation Final] Malady hilang terverifikasi. Rotasi bawaan dilanjutkan.")
                return true
            end
        end
        return false
    end

    if anySick == "unknown" then
        if hospitalPending and bot.rotation then bot.rotation.enabled = false end
        return false
    end

    local needsCure, mid = mod.checkNeedsHospital(bot)
    if not needsCure and not hospitalPending then
        return false
    end

    local now = os.time and os.time() or 0
    if hospitalPending and (now - lastHospitalAttempt) < HOSPITAL_COOLDOWN then
        if bot.rotation then bot.rotation.enabled = false end
        return false
    end

    lastHospitalAttempt = now
    if not hospitalPending then
        shouldResumeAfterCure = (bot.rotation and bot.rotation.enabled == true)
    end
    hospitalPending = true

    print(string.format("[Rotation Final] Terdeteksi Malady ID %s butuh pengobatan! Menjeda rotasi bawaan...", tostring(mid or curId)))
    if type(updateWebhook) == "function" then
        updateWebhook(string.format("Pengobatan Malady ID %s di 4AID", tostring(mid or curId)), "4AID")
    end
    if type(sendWebhookNotification) == "function" then
        sendWebhookNotification(string.format("⚠️ **[Malady Alert]** Bot **%s** terkena penyakit (ID: %s)! Menjeda rotasi dan menuju 4AID untuk pengobatan.", tostring(bot.name), tostring(mid or curId)))
    end

    if bot.rotation then
        bot.rotation.enabled = false
    end

    local status = mod.runCure(bot, updateWebhook)

    if status == "cured" then
        hospitalPending = false
        if shouldResumeAfterCure and not intentionalStop and bot.rotation and bot.status == BotStatus.online then
            bot.rotation.enabled = true
            print("[Rotation Final] Pengobatan selesai (sembuh total). Rotasi bawaan dilanjutkan.")
            if type(sendWebhookNotification) == "function" then
                sendWebhookNotification(string.format("✅ **[Malady Cured]** Penyakit pada bot **%s** berhasil disembuhkan di 4AID! Rotasi bawaan dilanjutkan.", tostring(bot.name)))
            end
            return true
        end
    else
        if bot.rotation then bot.rotation.enabled = false end
        return false
    end
end

local farmLabel = #(CONFIG.FARMS or {}) > 0 and farmWorldName(CONFIG.FARMS[1]) or "-"
local wasOnline = (bot.status == BotStatus.online)

local offlineStartTime = nil
local offlineAlertSent = false

while true do
    local isNowOnline = waitOnline(10)
    local now = os.time and os.time() or 0

    if not isNowOnline then
        wasOnline = false
        updateWebhook("Bot Offline — Menunggu Reconnect...")
        sleep(2000)
    else
        sleep(2000)

        local isOnline = (bot.status == BotStatus.online)

        if isOnline then
            local hadDisconnect = observedOfflineDuringWait or not wasOnline
            observedOfflineDuringWait = false

            if not lockoutTriggered and not hospitalPending and not hadDisconnect and wasOnline and bot.rotation and bot.rotation.enabled == false and not intentionalStop then
                intentionalStop = true
                print("[Rotation Final] Rotasi dimatikan secara manual oleh user. Watchdog menghormati perintah stop.")
            end

            -- Hospital maintenance remains available while farming is stopped.
            if not lockoutTriggered then
                local curedOk = false
                local okDisp, resDisp = pcall(checkAndDispatchHospital)
                if not okDisp then
                    print("[Hospital] Dispatcher gagal; periksa modul/API malady. Rotasi tidak dipulihkan oleh jalur ini.")
                end
                if okDisp and resDisp == true then
                    curedOk = true
                end

                isOnline = (bot.status == BotStatus.online)
                if not isOnline then
                    wasOnline = false
                elseif isOnline then
                    if lockoutTriggered then
                        if bot.rotation then bot.rotation.enabled = false end
                    elseif not intentionalStop and not hospitalPending and hadDisconnect and bot.rotation and bot.rotation.enabled ~= true then
                        bot.rotation.enabled = true
                        print("[Rotation Final] Bot pulih dari disconnect. Rotasi bawaan dinyalakan kembali.")
                    end
                end
            end
        end

        wasOnline = isOnline
        updateWebhook("Rotasi Bawaan Lucifer Berjalan")
    end
end
