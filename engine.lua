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

bot.leave_world_before_warp = false

-- Penanda build: muncul di log supaya ketahuan kalau yang jalan versi lama.
ENGINE_BUILD = "2026-11-02-r8"
 -- Langsung warp antar-world tanpa exit terlebih dahulu

-- Satu-satunya jalur menyalakan/mematikan rotasi.
-- Host bisa melempar error saat `enabled` diubah (mis. farm belum ter-assign);
-- dulu error itu membunuh script tepat setelah setup, sehingga toggle tidak
-- pernah menyala. Sekarang dilaporkan dan tidak mematikan supervisor.
local rotationEnableError = nil
-- True hanya setelah host benar-benar melaporkan rotation.enabled == true.
-- Script yang dijalankan sebelum bot login sering gagal menyalakan rotasi;
-- dulu bacaan `enabled == false` berikutnya disalahartikan sebagai stop manual
-- dan rotasi tidak pernah dinyalakan lagi.
local rotationConfirmedOn = false
local rotationDiagPrinted = false
local function setRotationEnabled(on)
    if not bot.rotation then return false end
    local ok, err = pcall(function() bot.rotation.enabled = on end)
    if not ok then
        rotationEnableError = tostring(err)
        if on then
            print("[Rotation] Gagal menyalakan rotasi: " .. rotationEnableError)
        end
        return false
    end
    rotationEnableError = nil
    return true
end

-- Baca status rotasi dengan aman. `bot.rotation` di sebagian build adalah
-- objek ketat: MEMBACA field yang tidak ada bisa melempar error, dan error itu
-- membunuh script tepat setelah setup -- persis gejala "rotasi tidak menyala".
-- Return: true / false / nil (tidak terbaca).
local function rotationIsOn()
    if not bot.rotation then return nil end
    local ok, value = pcall(function() return bot.rotation.enabled end)
    if not ok then return nil end
    return value == true
end


-- Interval aksi: satu tabel, satuan milidetik (setInterval memakai detik).
-- Nilai lama `hit`/`place` (detik) tetap diterima supaya config lama tidak pecah.
local intervals = CONFIG.ACTION_INTERVALS or {}
local function intervalSeconds(ms, defaultMs)
    local v = tonumber(ms)
    if not v or v <= 0 then v = defaultMs end
    return v / 1000
end
local hitInterval = intervals.hit or intervalSeconds(intervals.hitDelay, 160)
local placeInterval = intervals.place or intervalSeconds(intervals.placeDelay, 115)
local ACTION_DELAYS = {
    { "move", intervalSeconds(intervals.moveDelay, 110) },
    { "hit", hitInterval },
    { "place", placeInterval },
    { "harvest", intervalSeconds(intervals.harvestDelay, 150) },
    { "plant", intervalSeconds(intervals.plantDelay, 140) },
    { "warp", intervalSeconds(intervals.warpDelay, 7000) },
    { "drop", intervalSeconds(intervals.dropDelay, 4000) },
    { "trash", intervalSeconds(intervals.trashDelay, 4000) },
}

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
                if bot.rotation then setRotationEnabled(false) end
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

            -- Only an observed new server-data phase arms a new attempt.
            -- Error-to-error changes and offline polling never count as attempts.
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
            -- Native retries whose start/result is not sampled are uncounted;
            -- the independent duration limit remains the fallback.

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
                if bot.rotation then setRotationEnabled(false) end
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
                if bot.rotation then setRotationEnabled(false) end
            end
        end

        lastObservedStatus = curStatus -- latest sample release

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
local spamRecoveryUntil = 0
-- ponytail: satu file teks kecil di TEMP, cukup untuk satu timer. Ganti ke
-- config persisten kalau nanti butuh lebih dari satu nilai.
local SPAM_STATE_FILE = (os.getenv and (os.getenv("TEMP") or os.getenv("TMP")) or ".") .. "/lucifer_spam_recovery.txt"
local function loadSpamRecovery()
    local f = io.open(SPAM_STATE_FILE, "r")
    if not f then return 0 end
    local raw = f:read("*l")
    f:close()
    local untilTs = tonumber(raw)
    if untilTs and untilTs > (os.time() or 0) then return untilTs end
    return 0
end
local function saveSpamRecovery(untilTs)
    local f = io.open(SPAM_STATE_FILE, "w")
    if not f then return end
    f:write(tostring(math.floor(untilTs)))
    f:close()
end
spamRecoveryUntil = loadSpamRecovery()
if spamRecoveryUntil > 0 then
    print(string.format("[Spam] Recovery pengobatan dipulihkan dari file; AutoSpam OFF sampai %s.",
        os.date and os.date("%H:%M:%S", spamRecoveryUntil) or tostring(spamRecoveryUntil)))
end
local function beginSpamRecovery()
    local seconds = tonumber((CONFIG.AUTO_SPAM or {}).RECOVERY_SECONDS) or 3600
    spamRecoveryUntil = os.time() + math.max(0, seconds)
    saveSpamRecovery(spamRecoveryUntil)
    if bot.auto_spam then bot.auto_spam.enabled = false end
    print("[Spam] Recovery setelah pengobatan: AutoSpam OFF selama " .. tostring(seconds) .. " detik.")
end
local lastSpamCheck = nil
local function updateSpamState()
    if not bot.auto_spam then return end
    if bot.status ~= BotStatus.online then
        bot.auto_spam.enabled = false
        lastSpamCheck = nil
        return
    end
    local now = os.time()
    if lastSpamCheck and now - lastSpamCheck < 5 then return end
    lastSpamCheck = now
    local cfg = CONFIG.AUTO_SPAM or {}
    local ok, healthyOutsideHospital = pcall(function()
        if bot.status ~= BotStatus.online then return false end
        local id = tonumber(bot.malady)
        return bot.status == BotStatus.online and id == 0 and os.time() >= spamRecoveryUntil and not bot:isInWorld("4AID")
    end)
    -- Preserve all owner-configured text, intervals and other spam options.
    bot.auto_spam.enabled = cfg.ENABLED ~= false and ok and healthyOutsideHospital == true
end

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
    updateSpamState()
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

    -- Collect: TIDAK disentuh. Rotasi bawaan Lucifer yang mengurus collect saat
    -- harvest; menimpa auto_collect/collect_range/collect_all membuat item tidak
    -- terambil (range dipaksa kecil, collect_all dipaksa false).

    -- Pickaxe: AutoWear ambil dari wear_storage kalau belum ada di tas
    bot.auto_wear = CONFIG.AUTO_WEAR ~= false
    bot.wear_id = tonumber(CONFIG.WEAR_ID) or 98
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
    -- Keep AutoMalady active for host status refresh; disable native disease actions.
    -- Opsi yang tidak dikenal build host diabaikan: dulu satu opsi asing
    -- menggagalkan seluruh startup sehingga rotasi tidak pernah menyala.
    if bot.auto_malady then
        for _, key in ipairs({ "auto_grumbleteeth", "auto_chicken_feet" }) do
            pcall(function() bot.auto_malady[key] = false end)
        end
        pcall(function() bot.auto_malady.enabled = true end)
    else
        print("[Setup] AutoMalady tidak tersedia di build host; status penyakit dibaca manual.")
    end
    local spamCfg = CONFIG.AUTO_SPAM or { ENABLED = true }
    if bot.auto_spam then
        updateSpamState()
    else
        print("[Setup] AutoSpam tidak tersedia; atur manual di host.")
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
    -- Sebagian build butuh farm di-assign ke bot ini sebelum rotation.enabled
    -- bisa dinyalakan. pcall: build v2.86 murni tidak punya apply().
    if type(manager.apply) == "function" then
        pcall(function() manager:apply(bot) end)
    end

    print(string.format("[Setup] %d world farm terdaftar di rotasi Lucifer.", registered))
    return true
end

-- ========================================================
-- SETELAN ROTASI BAWAAN LUCIFER
-- ========================================================
-- Satu field rotasi yang tidak dikenal build host dulu melempar error dan
-- membatalkan SELURUH pengaturan rotasi, sehingga rotasi tidak pernah menyala.
-- Sekarang tiap field berdiri sendiri: yang gagal dilewati, namanya dicatat.
-- Field yang tidak ada di build host dilewati diam-diam (bukan error: banyak
-- nama field hanya ada di v1.8). Yang ada tapi menolak tulisan baru dilaporkan.
local rotationFieldFailures = {}
local function setRotationField(rotation, key, value)
    local existed = rotation[key] ~= nil
    local ok = pcall(function() rotation[key] = value end)
    if not ok and existed then
        rotationFieldFailures[#rotationFieldFailures + 1] = key
    end
    return ok
end

local function applyRotationSettings()
    local rotation = bot.rotation
    if not rotation then
        print("[Error] Fitur rotasi bawaan (bot.rotation) tidak tersedia di build Lucifer ini.")
        return false
    end

    -- rotation.enabled TIDAK disentuh di sini. Dulu rotasi dimatikan lalu
    -- dinyalakan pada tick yang sama; sebagian build mengabaikan toggle kedua,
    -- jadi rotasi tidak pernah aktif saat start. Satu toggle saja, oleh pemanggil.
    if lockoutTriggered then return false end

    setRotationField(rotation, "auto_rest", false)
    setRotationField(rotation, "harvest_roots", CONFIG.HARVEST_ROOTS == true)
    -- v2.86: dynamic_delay adalah properti bot, bukan rotation (itu legacy v1.8
    -- yang ditolak build host).
    local dynamicDelay = intervals.dynamicDelay ~= false
    if not pcall(function() bot.dynamic_delay = dynamicDelay end) then
        setRotationField(rotation, "dynamic_delay", dynamicDelay)
    end
    setRotationField(rotation, "visit_random_worlds", false)
    -- custom_position TIDAK ditulis. Nilainya bitwise dan UI menampilkan toggle
    -- "Custom Break Position" ON begitu field ini diisi (termasuk 0). Biarkan
    -- sesuai pilihan owner di UI Lucifer.

    -- v2.86: interval adalah API bot:setInterval(Action.*), bukan field
    -- rotation.harvest_interval/plant_interval/break_interval. Field lama
    -- ditolak build host dan dulu ikut menggagalkan seluruh setup.
    if type(Action) == "table" and type(bot.setInterval) == "function" then
        for _, pair in ipairs(ACTION_DELAYS) do
            local key, seconds = pair[1], pair[2]
            if Action[key] ~= nil then
                local ok = pcall(function() bot:setInterval(Action[key], seconds) end)
                if not ok then
                    print("[Setup] Peringatan: setInterval(Action." .. key .. ") ditolak host.")
                end
            end
        end
    else
        -- Fallback build lama yang masih memakai field rotation.*
        setRotationField(rotation, "harvest_interval", hitInterval)
        setRotationField(rotation, "plant_interval", placeInterval)
        setRotationField(rotation, "break_interval", placeInterval)
    end

    -- PNB di home dijalankan fitur bawaan Lucifer, bukan script ini
    if CONFIG.PNB and CONFIG.PNB.ENABLED ~= false then
        setRotationField(rotation, "pnb_in_home", true)
        if CONFIG.PNB.WORLD and CONFIG.PNB.WORLD ~= "" then
            setRotationField(rotation, "pnb_world", CONFIG.PNB.WORLD)
        else
            setRotationField(rotation, "pnb_world", "")
        end
    else
        setRotationField(rotation, "pnb_in_home", false)
        setRotationField(rotation, "pnb_world", "")
    end

    -- Ambang drop seed ke storage (rotasi yang menjatuhkan, bukan script ini)
    setRotationField(rotation, "seed_drop_amount", CONFIG.STORE_SEED_MIN or 100)

    -- Beli pack otomatis: rotasi berhenti memanen saat gems mencapai gem_limit lalu membeli PackName
    local packCfg = CONFIG.AUTO_BUY_PACK
    if packCfg and packCfg.ENABLED and packCfg.PricePack and packCfg.PackName then
        pcall(function() bot.gem_limit = packCfg.PricePack end)
        if type(bot.setPack) == "function" then
            local ok = pcall(function() bot:setPack(packCfg.PackName) end)
            if not ok then
                print("[Setup] Peringatan: gagal setPack '" .. tostring(packCfg.PackName) .. "'. Atur pack di UI Lucifer.")
            end
        end
    end

    if #rotationFieldFailures > 0 then
        print("[Setup] Peringatan: field rotasi tidak dikenal build host dilewati: " .. table.concat(rotationFieldFailures, ", "))
    end

    return true
end

-- ========================================================
-- EKSEKUSI
-- ========================================================
-- Diagnostik satu kali: cetak apa yang sebenarnya ada di build host.
-- Build ini bukan Lucifer stock (punya runInbuiltRotation / getInbuiltRotationStatus),
-- jadi tebakan nama field tidak berguna. Satu baris log ini menjawab semuanya.
local function dumpRotationDiagnostics()
    pcall(function()
        local r = bot.rotation
        print("[Diag] type(bot.rotation) = " .. type(r))
        local keys = {}
        if type(r) == "table" then
            for k in pairs(r) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            print("[Diag] field rotation = " .. (#keys > 0 and table.concat(keys, ",") or "(kosong)"))
        end
        for _, name in ipairs({ "runInbuiltRotation", "getInbuiltRotationStatus", "setupInbuiltFarmList",
                                "disableBotRotation", "stopSuppliedRotation", "applyRotationSettings" }) do
            print("[Diag] global " .. name .. " = " .. type(rawget(_G, name)))
        end
        print(string.format("[Diag] enabled=%s status=%s", tostring(r and r.enabled), tostring(r and r.status)))
    end)
end
print("[Engine] Memulai driver rotasi Lucifer v2.86... (build " .. ENGINE_BUILD .. ")")
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
    if setRotationEnabled(true) then
        rotationConfirmedOn = (rotationIsOn() == true)
        print("[Engine] Rotasi bawaan Lucifer AKTIF. Panen/tanam/PNB/drop seed/beli pack dijalankan oleh Lucifer.")
    elseif rotationEnableError then
        print("[Engine] Rotasi GAGAL dinyalakan oleh host. Supervisor penyakit tetap berjalan; nyalakan toggle rotasi manual di UI Lucifer.")
    end
    if bot.rotation and rotationIsOn() ~= true then
        print("[Engine] Rotasi belum aktif (bot mungkin belum login). Watchdog akan menyalakannya setelah online.")
        dumpRotationDiagnostics()
    end
else
    if bot.rotation then setRotationEnabled(false) end
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
local intentionalStop = false
local farmRunIntent = okStartup == true

local function checkAndDispatchHospital()
    if bot.status ~= BotStatus.online then return false end
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
                    beginSpamRecovery()
                    hospitalPending = false
            if shouldResumeAfterCure and not intentionalStop and bot.rotation and bot.status == BotStatus.online then
                setRotationEnabled(true)
                shouldResumeAfterCure = false
                print("[Engine] Malady hilang terverifikasi. Rotasi bawaan dilanjutkan.")
                return true
            end
        end
        return false
    end

    -- Jika data penyakit tidak valid / unknown: tahan rotasi dan jangan bersihkan pending
    if anySick == "unknown" then
        if hospitalPending and bot.rotation then setRotationEnabled(false) end
        return false
    end

    -- Memeriksa apakah penyakit merupakan target pengobatan ke 4AID (ID 1 / ID 2)
    local needsCure, mid = mod.checkNeedsHospital(bot)
    if needsCure ~= true or (mid ~= 1 and mid ~= 2) then
            if hospitalPending and bot.rotation then setRotationEnabled(false) end
            return false
        end

    local now = os.time and os.time() or 0
    if hospitalPending and (now - lastHospitalAttempt) < HOSPITAL_COOLDOWN then
        -- Masih dalam cooldown pengobatan sebelumnya dan belum sembuh: tahan rotasi tetap mati
        if bot.rotation then setRotationEnabled(false) end
        return false
    end

    lastHospitalAttempt = now
    -- Simpan intent resume saat pertama kali memasuki siklus pengobatan.
    -- Memakai niat farming, bukan bacaan toggle saat itu: kalau rotasi belum
    -- pernah berhasil menyala (mis. script dijalankan sebelum login), bacaan
    -- `enabled == false` membuat bot tidak pernah kembali farming setelah sembuh.
    if not hospitalPending then
        shouldResumeAfterCure = farmRunIntent and not intentionalStop
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
        setRotationEnabled(false)
    end

    local status = mod.runCure(bot, updateWebhook)

    -- Resume rotasi bawaan HANYA jika bot benar-benar sembuh ("cured") dan online
    if status == "cured" then
        beginSpamRecovery()
        hospitalPending = false
        if shouldResumeAfterCure and not intentionalStop and bot.rotation and bot.status == BotStatus.online then
            if setRotationEnabled(true) then
                rotationConfirmedOn = (rotationIsOn() == true)
            end
            print("[Engine] Pengobatan selesai (sembuh total). Rotasi bawaan dilanjutkan.")
            if type(sendWebhookNotification) == "function" then
                sendWebhookNotification(string.format("✅ **[Malady Cured]** Penyakit pada bot **%s** berhasil disembuhkan di 4AID! Rotasi bawaan dilanjutkan.", tostring(bot.name)))
            end
            return true
        end
    else
        -- Jika gagal atau belum sembuh, rotasi tetap ditahan mati
        if bot.rotation then setRotationEnabled(false) end
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
        sleep(5000)

        local isOnline = (bot.status == BotStatus.online)

        if isOnline then
            local hadDisconnect = observedOfflineDuringWait or not wasOnline
            observedOfflineDuringWait = false

            -- Deteksi stop manual: HANYA jika rotasi pernah benar-benar menyala,
            -- bot terus-menerus online (tanpa fase disconnect), dan BUKAN karena
            -- rotasi sedang dijeda internal oleh modul pengobatan (hospitalPending).
            if not lockoutTriggered and not hospitalPending and not hadDisconnect and wasOnline
                and farmRunIntent and rotationConfirmedOn and bot.rotation
                and rotationIsOn() == false and not intentionalStop then
                intentionalStop = true
                print("[Engine] Rotasi dimatikan secara manual oleh user. Watchdog menghormati perintah stop.")
            end

            -- Script dijalankan sebelum login: coba nyalakan lagi sampai host
            -- benar-benar melaporkan enabled == true.
            if not lockoutTriggered and not intentionalStop and not hospitalPending
                and farmRunIntent and not rotationConfirmedOn and bot.rotation then
                if setRotationEnabled(true) and rotationIsOn() == true then
                    rotationConfirmedOn = true
                    print("[Engine] Rotasi terkonfirmasi AKTIF setelah bot online.")
                elseif not rotationDiagPrinted then
                    rotationDiagPrinted = true
                    print("[Engine] Rotasi tetap OFF walau sudah dinyalakan.")
                    dumpRotationDiagnostics()
                end
            end

            -- Hospital is maintenance, independent of farm run intent.
            -- intentionalStop still prevents every farm resume path.
            if not lockoutTriggered then
                -- Cek malady target secara berkala (setiap siklus watchdog)
                local curedOk = false
                local okDisp, resDisp = pcall(checkAndDispatchHospital)
                if not okDisp then
                    print("[Hospital] Dispatcher gagal; periksa modul/API malady. Rotasi tidak dipulihkan oleh jalur ini.")
                end
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
                        if bot.rotation then setRotationEnabled(false) end
                    elseif not intentionalStop and not hospitalPending and hadDisconnect and bot.rotation and rotationIsOn() ~= true then
                        -- Bot reconnect dari DC (bukan dari proses pengobatan yang masih sakit)
                        if setRotationEnabled(true) then
                            rotationConfirmedOn = (rotationIsOn() == true)
                        end
                        print("[Engine] Bot pulih dari disconnect. Rotasi bawaan dinyalakan kembali.")
                    end
                end
            end
        end

        wasOnline = isOnline
        updateWebhook("Rotasi Bawaan Lucifer Berjalan")
    end
end
