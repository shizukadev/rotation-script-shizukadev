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
            -- Reset lockout terjadi HANYA jika owner menyalakan kembali auto_reconnect secara manual saat bot offline/login
            -- atau secara sengaja menyetel auto_reconnect = true saat sedang terkunci
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

            local isTerminalFailure = false
            if BotStatus and (
                curStatus == BotStatus.logon_fail or
                curStatus == BotStatus.error_connecting or
                curStatus == BotStatus.too_many_login or
                curStatus == BotStatus.server_overload or
                curStatus == BotStatus.http_block
            ) then
                if curStatus ~= lastObservedStatus then
                    isTerminalFailure = true
                end
            end

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
            else
                if bot.rotation then bot.rotation.enabled = false end
            end
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
    for line in (content .. "\n"):gmatch("([^\n]+)") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") and not line:match("^//") then
            -- Format: WORLD:DOOR:BLOCK_ID atau WORLD:DOOR atau WORLD
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

-- ========================================================
-- SETELAN MODULE BAWAAN LUCIFER (AutoWear / AutoTrash / Collect / Reconnect / Malady)
-- ========================================================
local function applyBotSettings()
    -- Reconnect & Bypass Logon
    local recon = CONFIG.AUTO_RECONNECT or {}
    bot.auto_reconnect = recon.ENABLED ~= false
    if recon.INTERVAL then bot.reconnect_interval = recon.INTERVAL end
    if recon.BYPASS_LOGON ~= nil then
        bot.bypass_logon = recon.BYPASS_LOGON
    end

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

    rotation.enabled = false -- setel dulu dalam keadaan mati, baru dinyalakan
    if lockoutTriggered then return false end

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
        else
            rotation.pnb_world = nil
        end
    else
        rotation.pnb_in_home = false
        rotation.pnb_world = nil
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

local okStartup = applyRotationSettings()
if okStartup and not lockoutTriggered then
    bot.rotation.enabled = true
    print("[Engine] Rotasi bawaan Lucifer AKTIF. Panen/tanam/PNB/drop seed/beli pack dijalankan oleh Lucifer.")
else
    if bot.rotation then bot.rotation.enabled = false end
end
updateWebhook("Rotasi Bawaan Lucifer Aktif", "-")

-- ========================================================
-- AUTO MALADY 4AID DISPATCHER (TORN MUSCLE / GEM CUTS)
-- ========================================================
local hospitalMod = nil
local function getHospitalModule()
    if hospitalMod == nil then
        local ok, mod = pcall(require, "auto_malady_4aid")
        if ok and type(mod) == "table" and type(mod.runCure) == "function" then
            hospitalMod = mod
        else
            -- Fallback jika file berada di path relatif yang sama
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
    return hospitalMod
end

local lastHospitalAttempt = 0
local HOSPITAL_COOLDOWN = 180 -- Jeda 3 menit sebelum mengulang rute 4AID jika masih sakit
local hospitalPending = false -- Status pengobatan sedang berjalan/menunggu sembuh
local shouldResumeAfterCure = false -- Intent apakah rotasi harus dinyalakan kembali pasca sembuh
local intentionalStop = false

local function checkAndDispatchHospital()
    local mod = getHospitalModule()
    if not mod then return false end

    -- Evaluasi status penyakit terkini
    local anySick, curId = false, 0
    if type(mod.hasAnyMalady) == "function" then
        anySick, curId = mod.hasAnyMalady(bot)
    else
        anySick, curId = mod.checkNeedsHospital(bot)
    end

    -- Jika bot sudah benar-benar sembuh (anySick == false): bersihkan state pending
    if anySick == false then
        if hospitalPending then
            hospitalPending = false
            if shouldResumeAfterCure and not intentionalStop and bot.rotation and bot.status == BotStatus.online then
                bot.rotation.enabled = true
                shouldResumeAfterCure = false
                print("[Engine] Malady hilang terverifikasi. Rotasi bawaan dilanjutkan.")
                return true
            end
        end
        return false
    end

    -- Jika data penyakit tidak valid / unknown: tahan rotasi dan jangan bersihkan pending
    if anySick == "unknown" then
        if hospitalPending and bot.rotation then bot.rotation.enabled = false end
        return false
    end

    -- Memeriksa apakah penyakit merupakan target pengobatan ke 4AID (ID 1 / ID 2)
    local needsCure, mid = mod.checkNeedsHospital(bot)
    if not needsCure and not hospitalPending then
        return false
    end

    local now = os.time and os.time() or 0
    if hospitalPending and (now - lastHospitalAttempt) < HOSPITAL_COOLDOWN then
        -- Masih dalam cooldown pengobatan sebelumnya dan belum sembuh: tahan rotasi tetap mati
        if bot.rotation then bot.rotation.enabled = false end
        return false
    end

    lastHospitalAttempt = now
    -- Simpan intent resume saat pertama kali memasuki siklus pengobatan
    if not hospitalPending then
        shouldResumeAfterCure = (bot.rotation and bot.rotation.enabled == true)
    end
    hospitalPending = true

    print(string.format("[Engine] Terdeteksi Malady ID %s butuh pengobatan! Menjeda rotasi bawaan...", tostring(mid or curId)))
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

    -- Resume rotasi bawaan HANYA jika bot benar-benar sembuh ("cured") dan online
    if status == "cured" then
        hospitalPending = false
        if shouldResumeAfterCure and not intentionalStop and bot.rotation and bot.status == BotStatus.online then
            bot.rotation.enabled = true
            print("[Engine] Pengobatan selesai (sembuh total). Rotasi bawaan dilanjutkan.")
            if type(sendWebhookNotification) == "function" then
                sendWebhookNotification(string.format("✅ **[Malady Cured]** Penyakit pada bot **%s** berhasil disembuhkan di 4AID! Rotasi bawaan dilanjutkan.", tostring(bot.name)))
            end
            return true
        end
    else
        -- Jika gagal atau belum sembuh, rotasi tetap ditahan mati
        if bot.rotation then bot.rotation.enabled = false end
        return false
    end
end

local farmLabel = #(CONFIG.FARMS or {}) > 0 and farmWorldName(CONFIG.FARMS[1]) or "-"
local wasOnline = (bot.status == BotStatus.online)

local offlineStartTime = nil
local offlineAlertSent = false

while true do
    -- Tunggu sampai bot online (penantian berulang tanpa mematikan loop supervisor)
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

            -- Deteksi stop manual: HANYA jika bot terus-menerus online (tanpa ada fase disconnect)
            -- dan BUKAN karena rotasi sedang dijeda internal oleh modul pengobatan (hospitalPending)
            if not lockoutTriggered and not hospitalPending and not hadDisconnect and wasOnline and bot.rotation and bot.rotation.enabled == false and not intentionalStop then
                intentionalStop = true
                print("[Engine] Rotasi dimatikan secara manual oleh user. Watchdog menghormati perintah stop.")
            end

            if not intentionalStop and not lockoutTriggered then
                -- Cek malady target secara berkala (setiap siklus watchdog)
                local curedOk = false
                local okDisp, resDisp = pcall(checkAndDispatchHospital)
                if okDisp and resDisp == true then
                    curedOk = true
                end

                -- Baca ulang status online terkini pasca-dispatcher
                isOnline = (bot.status == BotStatus.online)
                if not isOnline then
                    wasOnline = false
                elseif isOnline then
                    -- Bot pulih kembali online saat watchdog
                    if lockoutTriggered then
                        -- Jika akun dalam status lockout, jangan pernah memulihkan rotasi otomatis
                        if bot.rotation then bot.rotation.enabled = false end
                    elseif not intentionalStop and not hospitalPending and hadDisconnect and bot.rotation and bot.rotation.enabled ~= true then
                        -- Bot reconnect dari DC (bukan dari proses pengobatan yang masih sakit)
                        bot.rotation.enabled = true
                        print("[Engine] Bot pulih dari disconnect. Rotasi bawaan dinyalakan kembali.")
                    end
                end
            end
        end

        wasOnline = isOnline
        updateWebhook("Rotasi Bawaan Lucifer Berjalan")
    end
end
