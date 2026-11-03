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
        moveDelay    = 115,
        hitDelay     = 160,
        placeDelay   = 110,
        harvestDelay = 160,
        plantDelay   = 110,
        warpDelay    = 7000,
        dropDelay    = 3500,
        trashDelay   = 3500,
        dynamicDelay = true,
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

    AUTO_SPAM = { ENABLED = true, RECOVERY_SECONDS = 3600 },
    MALADY = {
        GRUMBLETEETH = false,
        CHICKEN_FEET = false,
    },

    MULTI_BOT = { startbot = 1, endbot = 11 },
    WEBHOOK = {
        ENABLED = true,
        URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA", -- ganti dengan URL webhook Discord Anda (jangan di-commit ke publik)
        MESSAGE_ID = "1567025865047539856",
        UPDATE_INTERVAL_SECONDS = 15,
        EVENT_NOTIFICATIONS = true,
        MIN_EDIT_SECONDS = 5,
        PHASE_NOTIFY = false,
        GLOBAL = true,
        LEADER_BOT = "",
    },

    AUTO_BUY_PACK = {
        ENABLED = true,
        PackName = "vending_machine",
        PricePack = 8000,
        ItemIDOfPack = { 2978 },
    },
}

local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan. Script harus dijalankan di Lucifer bot.")
    return
end

bot.leave_world_before_warp = false

local rotationEnableError = nil
-- True hanya setelah host benar-benar melaporkan rotation.enabled == true.
local rotationConfirmedOn = false
local rotationDiagPrinted = false
local lastRotLog = nil
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

-- Baca status rotasi dengan aman; membaca field yang tidak ada bisa melempar error.
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
                if bot.rotation then setRotationEnabled(false) end
                bot.auto_reconnect = false
                bot.bypass_logon = false
            end
        end
        if updateWebhook then updateWebhook("Menunggu reconnect") end
        local reconCfg = CONFIG.AUTO_RECONNECT or {}
        local lockoutEnabled = reconCfg.LOCKOUT_ENABLED ~= false and reconCfg.LOCKOUT ~= false
        if not lockoutEnabled and lockoutTriggered then
            lockoutTriggered = false
        end
        local maxFailTries = reconCfg.MAX_FAIL_ATTEMPTS or 15
        local maxFailSecs = (reconCfg.MAX_FAIL_MINUTES or 5) * 60
        local now = os.time and os.time() or 0

        -- Deteksi transisi status kegagalan login terminal:
        -- Dihitung 1 kali per transisi masuk ke status error terminal (logon_fail, error_connecting, too_many_login, server_overload, http_block)
        local curStatus = bot.status
        if lockoutEnabled and not lockoutTriggered and curStatus ~= BotStatus.online then
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
local spamRecoveryUntil = 0
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
    if bot.auto_spam then pcall(function() bot.auto_spam.enabled = false end) end
    print("[Spam] Recovery setelah pengobatan: AutoSpam OFF selama " .. tostring(seconds) .. " detik.")
end
-- Recovering guard: unknown is OFF. No guessed native mod fields.
local recoveryStatus = { known = false, active = false, checking = false, nextCheck = 0 }
local function parseRecoveringSeconds(text)
    local body = text:lower():match("recovering%s*%((.-)%)")
    if not body then return nil end
    local h = tonumber(body:match("(%d+)%s*hour")) or 0
    local m = tonumber(body:match("(%d+)%s*min")) or 0
    local sec = tonumber(body:match("(%d+)%s*sec")) or 0
    local total = h * 3600 + m * 60 + sec
    if total <= 0 then return nil end
    return total
end
-- Positive recognition only; unsupported entries keep the response UNKNOWN.
local recognizedStatusMods = {
    ["enhanced digging"] = true,
    ["torn punching muscle"] = true, ["gem cuts"] = true,
    ["chicken feet"] = true, ["grumbleteeth"] = true,
}
local function recoveryMessage(message)
    if not recoveryStatus.checking or type(message) ~= "string" then return end
    local text = message:match("msg|([^\r\n]*)")
    if not text then return end
    text = text:gsub("`.", ""):lower():match("^%s*(.-)%s*$")
    local ok, name = pcall(function() return tostring(bot.name or ""):lower() end)
    if text:find("'s status:", 1, true) then
        recoveryStatus.header = ok and name ~= "" and text == name .. "'s status:"
        recoveryStatus.expectedMods = nil
        recoveryStatus.receivedMods = 0
        recoveryStatus.seenMods = {}
        recoveryStatus.known = recoveryStatus.active == true
        return
    end
    if not recoveryStatus.header then return end
    local count = text:match("^(%d+)%s+mods? active:%s*$") or text:match("^mods? active:%s*(%d+)%s*$")
    if text == "no mods active" or text == "no mods active:" then count = "0" end
    if count then
        recoveryStatus.expectedMods = tonumber(count)
        recoveryStatus.receivedMods = 0
        recoveryStatus.seenMods = {}
        recoveryStatus.known = recoveryStatus.active == true or tonumber(count) == 0
        return
    end
    if text:match("^recovering%s*%(") then
        recoveryStatus.active = true
        recoveryStatus.known = true
        local seconds = parseRecoveringSeconds(text)
        recoveryStatus.untilTs = seconds and os.time() + seconds or nil
        print("[Recovering] " .. text:sub(1,300))
        return
    end
    -- Observed host format includes the Malady prefix, effect and timer.
    local modKey = text
    if text:match("^malady: torn punching muscle! reduced punch damage%s*%(") and text:match("secs? left%)$") then
        modKey = "torn punching muscle"
    end
    if recoveryStatus.expectedMods and recognizedStatusMods[modKey] and not recoveryStatus.seenMods[text] then
        recoveryStatus.seenMods[text] = true
        recoveryStatus.receivedMods = recoveryStatus.receivedMods + 1
    end
end
local recoveryEventsOK = pcall(function()
    assert(type(addEvent) == "function" and type(listenEvents) == "function")
    addEvent(Event.game_message, recoveryMessage)

end)
local function checkRecoveryStatus()
    local now = os.time()
    if bot.status ~= BotStatus.online then
        recoveryStatus.known = false
        recoveryStatus.checking = false
        recoveryStatus.nextCheck = 0
        return false
    end
    if not recoveryEventsOK then return false end
    if not recoveryStatus.checking and now >= recoveryStatus.nextCheck then
        recoveryStatus.known = false
        recoveryStatus.active = false
        recoveryStatus.header = false
        recoveryStatus.expectedMods = nil
        recoveryStatus.receivedMods = 0
        recoveryStatus.seenMods = {}
        recoveryStatus.untilTs = nil
        recoveryStatus.checking = true
        recoveryStatus.deadline = now + 8
        recoveryStatus.nextCheck = now + 60
        local ok = pcall(function()
            if bot:isInWorld() then bot:say("/status") else error("outside world") end
        end)
        if not ok then recoveryStatus.checking = false end
    end
    if recoveryStatus.checking then
        -- Bounded event pump; never install a second infinite loop/thread.
        local ok = pcall(listenEvents, 1)
        if not ok then recoveryStatus.known = false; recoveryStatus.checking = false end
        if os.time() >= recoveryStatus.deadline then
            recoveryStatus.checking = false
            if recoveryStatus.header and recoveryStatus.expectedMods ~= nil and (recoveryStatus.receivedMods or 0) == recoveryStatus.expectedMods then
                recoveryStatus.known = true
                if not recoveryStatus.active then
                    recoveryStatus.active = false
                end
            end
            if recoveryStatus.active and recoveryStatus.untilTs then
                recoveryStatus.nextCheck = recoveryStatus.untilTs
            end
            print("[Recovering] " .. (recoveryStatus.active and "aktif; AutoSpam OFF" or
                (recoveryStatus.known and not recoveryStatus.active) and "bebas recovering (Recovering tidak aktif)" or "status belum terverifikasi; AutoSpam OFF"))
        end
    end
    return not recoveryStatus.checking and recoveryStatus.known and not recoveryStatus.active
end

local lastSpamCheck = nil
local function updateSpamState()
    local okObj, spamObj = pcall(function() return bot.auto_spam end)
    if not okObj or not spamObj then return end
    if bot.status ~= BotStatus.online then
        pcall(function() spamObj.enabled = false end)
        checkRecoveryStatus()
        lastSpamCheck = nil
        return
    end
    -- Disable before requesting/pumping events; preserve ON between throttled checks.
    if recoveryStatus.checking or not recoveryStatus.known or recoveryStatus.active or os.time() >= recoveryStatus.nextCheck then setSpam(false) end
    local recoveryClear = checkRecoveryStatus()
    if not recoveryClear then setSpam(false) end
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
    pcall(function() spamObj.enabled = cfg.ENABLED ~= false and recoveryClear and ok and healthyOutsideHospital == true end)
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
            webhookMonitor = mod.new(bot, CONFIG, { os = os, BotStatus = BotStatus, RotationStatus = RotationStatus, Webhook = Webhook, io = io, print = print })
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

-- WAJIB: rotasi tidak boleh nyala selama modul pesaing masih hidup.
local function disableCompetingModules()
    local failed = {}
    for _, key in ipairs({ "auto_farm", "auto_harvest", "auto_plant" }) do
        local ok = pcall(function()
            local module = bot[key]
            if module then module.enabled = false end
        end)
        if not ok then failed[#failed + 1] = key end
    end
    if #failed > 0 then
        print("[Setup] GAGAL: modul pesaing tidak bisa dimatikan (" .. table.concat(failed, ", ") .. "). Rotasi ditahan.")
        return false
    end
    return true
end

-- OPSIONAL: tiap bagian diisolasi.
local function applyOptionalBotSettings()
    pcall(function()
        local recon = CONFIG.AUTO_RECONNECT or {}
        bot.auto_reconnect = recon.ENABLED ~= false
        if recon.INTERVAL then bot.reconnect_interval = recon.INTERVAL end
        if recon.BYPASS_LOGON ~= nil then bot.bypass_logon = recon.BYPASS_LOGON end
    end)

    pcall(function()
        bot.auto_wear = CONFIG.AUTO_WEAR ~= false
        bot.wear_id = tonumber(CONFIG.WEAR_ID) or 98
        local pick = CONFIG.PICKAXE_WORLD
        local pickWorld = type(pick) == "table" and pick.world or pick
        if type(pickWorld) == "string" and pickWorld ~= "" then
            bot.wear_storage = pickWorld
        end
    end)

    pcall(function()
        local trash = CONFIG.AUTO_TRASH or {}
        if trash.ENABLED ~= false and type(setTrashList) == "function" then
            pcall(setTrashList, trash.ITEMS or {})
            bot.auto_trash = true
        else
            bot.auto_trash = false
        end
    end)

    pcall(function()
        local malady = bot.auto_malady
        if malady then
            for _, key in ipairs({ "auto_grumbleteeth", "auto_chicken_feet" }) do
                pcall(function() malady[key] = false end)
            end
            pcall(function() malady.enabled = true end)
        else
            print("[Setup] AutoMalady tidak tersedia di build host; status penyakit dibaca manual.")
        end
    end)

    local okSpam, spamObj = pcall(function() return bot.auto_spam end)
    if okSpam and spamObj then
        pcall(updateSpamState)
    else
        print("[Setup] AutoSpam tidak tersedia; atur manual di host.")
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
            local itemToFarm = farmBlockId(farm)
            -- v2.86: addFarm hanya menerima SATU argumen nama, dan item id harus
            -- ikut di dalam nama (UI menampilkan "Name:DoorID:ItemID"). Dulu id
            -- dikirim sebagai argumen kedua yang diabaikan host, sehingga kolom
            -- Item di UI tampil "Unknown".
            local nameAndDoor = world
            if door ~= "" then nameAndDoor = nameAndDoor .. ":" .. door end
            if door ~= "" and itemToFarm then
                nameAndDoor = nameAndDoor .. ":" .. tostring(itemToFarm)
            end
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
            local packWorld = storage.packworld
            if type(packWorld) ~= "string" or packWorld == "" then packWorld = storage.world end
            local packDoor = storage.doorpack or storage.door or ""
            local packName = packDoor ~= "" and (packWorld .. ":" .. packDoor) or packWorld
            pcall(function()
                if type(manager.removeStorage) == "function" then
                    manager:removeStorage(packWorld, StorageType.pack)
                end
                manager:addStorage(packName, StorageType.pack, 0)
            end)
        end
    else
        print("[Setup] Peringatan: CONFIG.STORAGE kosong. Seed & pack tidak akan disimpan otomatis.")
    end

    -- Pilih farm dulu, baru verifikasi (dulu urutannya terbalik).
    local selectErr = nil
    if type(manager.selectAll) == "function" then
        local okSel, errSel = pcall(function() manager:selectAll() end)
        if not okSel then selectErr = tostring(errSel) end
    else
        selectErr = "manager.selectAll tidak tersedia"
    end
    if type(manager.apply) == "function" then
        pcall(function() manager:apply(bot) end)
    end

    local worldCount, selectedCount = 0, 0
    pcall(function()
        for _, w in pairs(manager.worlds or {}) do
            worldCount = worldCount + 1
            if w.selected then selectedCount = selectedCount + 1 end
        end
    end)
    if worldCount > 0 and selectedCount == 0 then
        print(string.format("[Setup] Peringatan: 0/%d farm terpilih setelah selectAll%s. Rotasi akan menyala tapi diam; centang farm di UI Lucifer.",
            worldCount, selectErr and (" (selectAll gagal: " .. selectErr .. ")") or ""))
    elseif worldCount > 0 then
        print(string.format("[Setup] Farm terpilih: %d/%d", selectedCount, worldCount))
    else
        print("[Setup] Peringatan: manager.worlds kosong; tidak ada farm yang bisa dibaca.")
    end

    print(string.format("[Setup] %d world farm terdaftar di rotasi Lucifer.", registered))
    return true
end

-- ========================================================
-- SETELAN ROTASI BAWAAN LUCIFER
-- ========================================================
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

    -- rotation.enabled TIDAK disentuh di sini; satu toggle saja oleh pemanggil.
    if lockoutTriggered then return false end

    setRotationField(rotation, "auto_rest", false)
    setRotationField(rotation, "harvest_roots", CONFIG.HARVEST_ROOTS == true)
    -- v2.86: dynamic_delay adalah properti bot, bukan rotation (legacy v1.8).
    local dynamicDelay = intervals.dynamicDelay ~= false
    if not pcall(function() bot.dynamic_delay = dynamicDelay end) then
        setRotationField(rotation, "dynamic_delay", dynamicDelay)
    end
    setRotationField(rotation, "visit_random_worlds", false)
    -- custom_position TIDAK ditulis: UI menampilkan "Custom Break Position" ON
    -- begitu field ini diisi (termasuk 0). Biarkan pilihan owner di UI.


    -- v2.86: interval lewat bot:setInterval(Action.*), bukan field rotation.*
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
        setRotationField(rotation, "harvest_interval", hitInterval)
        setRotationField(rotation, "plant_interval", placeInterval)
        setRotationField(rotation, "break_interval", placeInterval)
    end

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

    setRotationField(rotation, "seed_drop_amount", CONFIG.STORE_SEED_MIN or 100)

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

-- Nama fase rotasi dari enum terdokumentasi (RotationStatus.*), bukan angka.
local function rotationPhaseName(status)
    if type(RotationStatus) ~= "table" then return tostring(status) end
    for name, value in pairs(RotationStatus) do
        if value == status then return tostring(name) end
    end
    return tostring(status)
end
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
local multi = CONFIG.MULTI_BOT
local localIndex = tonumber(bot.index)
local inRange = not multi or (localIndex and localIndex >= multi.startbot and localIndex <= multi.endbot)
if not inRange then print("[Setup] Bot di luar rentang startbot/endbot; script dihentikan."); return end
if multi then
    print("[Setup] Menunggu slot startup index " .. tostring(localIndex))
    sleep((localIndex - multi.startbot) * 5000)
end
local competingOK = startupStage("matikan modul pesaing", disableCompetingModules)
local botSetupOK = startupStage("pengaturan bot opsional", applyOptionalBotSettings)
-- Only one instance mutates WorldManager during multi-bot startup.
local worldsSetupOK = true
if not multi or localIndex == multi.startbot then
    worldsSetupOK = startupStage("registrasi world", registerWorlds)
else
    print("[Setup] Registrasi world dilewati; hanya startbot yang mengubah WorldManager.")
end
local rotationSetupOK = startupStage("pengaturan rotasi", applyRotationSettings)
-- Hanya penyiapan ROTASI yang boleh menentukan rotasi menyala. Kegagalan
-- pengaturan bot (AutoWear/AutoTrash/AutoMalady yang tidak cocok dengan build
-- host) dulu mematikan rotasi seluruhnya: log berhenti di "GAGAL: pengaturan
-- bot" dan enabled tidak pernah ditulis true.
local okStartup = rotationSetupOK and competingOK
if not competingOK then
    print("[Setup] Rotasi TIDAK dinyalakan: modul pesaing masih aktif.")
end
if not botSetupOK then
    print("[Setup] Peringatan: sebagian pengaturan bot gagal diterapkan. Rotasi tetap dinyalakan.")
end
if not worldsSetupOK then
    print("[Setup] Peringatan: registrasi world gagal. Rotasi tetap dinyalakan; periksa daftar farm di UI Lucifer.")
end
if okStartup and not lockoutTriggered then
    if setRotationEnabled(true) then
        rotationConfirmedOn = (rotationIsOn() == true)
        print("[Rotation Final] Rotasi bawaan Lucifer AKTIF. Panen/tanam/PNB/drop seed/beli pack dijalankan oleh Lucifer.")
    elseif rotationEnableError then
        print("[Rotation Final] Rotasi GAGAL dinyalakan oleh host. Supervisor penyakit tetap berjalan; nyalakan toggle manual di UI Lucifer.")
    end
    if bot.rotation and rotationIsOn() ~= true then
        print("[Rotation Final] Rotasi belum aktif (bot mungkin belum login). Watchdog akan menyalakannya setelah online.")
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
local gemWaitActive = false
local gemWaitNextWarp = 0
local function waitGemCutsWorld()
    if bot.rotation then setRotationEnabled(false) end
    if bot.status ~= BotStatus.online or lockoutTriggered then return end
    local now = os.time()
    if now < gemWaitNextWarp then return end
    local ok, inside = pcall(function() return bot:isInWorld("luacid") end)
    if ok and inside then return end
    gemWaitNextWarp = now + 30
    print("[Hospital] Gem Cuts setelah gagal surgery: menunggu malady hilang di luacid; rotasi OFF.")
    pcall(function() bot:warp("luacid") end)
end
 -- user stop intent

-- Lanjut farming setelah pengobatan; rotationConfirmedOn direset agar watchdog
-- tidak salah membaca "mati padahal pernah nyala" sebagai stop manual.
local function resumeFarming(reason)
    if intentionalStop or lockoutTriggered or bot.status ~= BotStatus.online or not bot.rotation then return false end
    rotationConfirmedOn = false
    if setRotationEnabled(true) and rotationIsOn() == true then
        rotationConfirmedOn = true
        print("[Rotation Final] " .. reason)
        return true
    end
    print("[Rotation Final] Rotasi belum bisa dinyalakan setelah pengobatan; watchdog akan mencoba lagi.")
    return false
end
local function checkAndDispatchHospital()
    if bot.status ~= BotStatus.online then return false end
    local mod = getHospitalModule()
    if not mod then return false end

    local anySick, curId = false, 0
    if type(mod.hasAnyMalady) == "function" then
        anySick, curId = mod.hasAnyMalady(bot)
    else
        anySick, curId = mod.checkNeedsHospital(bot)
    end

    if gemWaitActive then
        if anySick == false then
            gemWaitActive = false
            gemWaitNextWarp = 0
        else
            local recoveryClear = checkRecoveryStatus()
            if recoveryClear and anySick == true and curId == 2 then
                gemWaitActive = false
                gemWaitNextWarp = 0
                lastHospitalAttempt = 0 -- permit a new treatment after verified recovery expiry
                print("[Hospital] Recovering hilang terverifikasi; Gem Cuts masih aktif, kembali ke 4AID.")
            else
                waitGemCutsWorld()
                return false
            end
        end
    end

    if anySick == false then
        if hospitalPending then
            beginSpamRecovery()
            hospitalPending = false
            if shouldResumeAfterCure and bot.status == BotStatus.online then
                shouldResumeAfterCure = false
                if resumeFarming("Malady hilang terverifikasi. Rotasi bawaan dilanjutkan.") then
                    if type(sendWebhookNotification) == "function" then
                        sendWebhookNotification(string.format("✅ **[Malady Cured]** Penyakit pada bot **%s** hilang terverifikasi! Rotasi bawaan dilanjutkan.", tostring(bot.name)))
                    end
                    return true
                end
                return false
            end
        end
        return false
    end

    -- Gem Cuts never permits farming, including during Recovering.
    if anySick == true and curId == 2 then
        if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
        hospitalPending = true
        if bot.rotation then setRotationEnabled(false) end
    end
    checkRecoveryStatus()
    if recoveryStatus.active == true then
        if anySick == true and curId == 1 then
            hospitalPending = false
            shouldResumeAfterCure = false
            if farmRunIntent and not intentionalStop then
                resumeFarming("Torn Punching Muscle + Recovering: pengobatan ditunda, rotasi dilanjutkan.")
            end
        end
        return false
    end
    if not recoveryStatus.known or recoveryStatus.checking then return false end

    if anySick == "unknown" then
        if hospitalPending and bot.rotation then setRotationEnabled(false) end
        return false
    end

    local needsCure, mid = mod.checkNeedsHospital(bot)
    if needsCure ~= true or (mid ~= 1 and mid ~= 2) then
        if hospitalPending and bot.rotation then setRotationEnabled(false) end
        return false
    end

    local now = os.time and os.time() or 0
    if hospitalPending and (now - lastHospitalAttempt) < HOSPITAL_COOLDOWN then
        if bot.rotation then setRotationEnabled(false) end
        return false
    end

    lastHospitalAttempt = now
    -- Niat farming, bukan bacaan toggle: rotasi bisa belum pernah menyala.
    if not hospitalPending then
        shouldResumeAfterCure = farmRunIntent and not intentionalStop
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
        setRotationEnabled(false)
    end

    if multi then
        print("[Hospital] Menunggu slot admission index " .. tostring(localIndex))
        sleep((localIndex - multi.startbot) * 10000)
        if bot.status ~= BotStatus.online or lockoutTriggered then return false end
        local stillNeeds, currentId = mod.checkNeedsHospital(bot)
        if stillNeeds ~= true or (currentId ~= 1 and currentId ~= 2) then return false end
    end
    recoveryStatus.nextCheck = 0 -- obtain fresh surgery result during hospital wait
    local status = mod.runCure(bot, updateWebhook, function()
        checkRecoveryStatus()
        return recoveryStatus.active == true
    end)
    if status == "recovering" then
        local sick, id = mod.hasAnyMalady(bot)
        if sick == true and id == 2 then
            gemWaitActive = true
            hospitalPending = true
            waitGemCutsWorld()
            return false
        end
        if sick == false or (sick == true and id == 1) then
            hospitalPending = false
            shouldResumeAfterCure = false
            if farmRunIntent and not intentionalStop then resumeFarming("Pengobatan berakhir dengan Recovering; rotasi diizinkan untuk Healthy/Torn.") end
        else
            hospitalPending = true
            if bot.rotation then setRotationEnabled(false) end
        end
        return false
    end

    if status == "cured" then
        beginSpamRecovery()
        hospitalPending = false
        if shouldResumeAfterCure and bot.status == BotStatus.online then
            shouldResumeAfterCure = false
            local okResumed = resumeFarming("Pengobatan selesai (sembuh total). Rotasi bawaan dilanjutkan.")
            if okResumed then
                if type(sendWebhookNotification) == "function" then
                    sendWebhookNotification(string.format("✅ **[Malady Cured]** Penyakit pada bot **%s** berhasil disembuhkan di 4AID! Rotasi bawaan dilanjutkan.", tostring(bot.name)))
                end
                return true
            end
            return false
        end
    else
        if bot.rotation then setRotationEnabled(false) end
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
        sleep(5000)

        local isOnline = (bot.status == BotStatus.online)

        if isOnline then
            local hadDisconnect = observedOfflineDuringWait or not wasOnline
            observedOfflineDuringWait = false

            if not lockoutTriggered and not hospitalPending and not hadDisconnect and wasOnline and farmRunIntent and rotationConfirmedOn and bot.rotation and rotationIsOn() == false and not intentionalStop then
                intentionalStop = true
                print("[Rotation Final] Rotasi dimatikan secara manual oleh user. Watchdog menghormati perintah stop.")
            end

            -- Script dijalankan sebelum login: coba nyalakan lagi sampai terkonfirmasi.
            if not lockoutTriggered and not intentionalStop and not hospitalPending and farmRunIntent and not rotationConfirmedOn and bot.rotation then
                if setRotationEnabled(true) and rotationIsOn() == true then
                    rotationConfirmedOn = true
                    print("[Rotation Final] Rotasi terkonfirmasi AKTIF setelah bot online.")
                elseif not rotationDiagPrinted then
                    rotationDiagPrinted = true
                    print("[Rotation Final] Rotasi tetap OFF walau sudah dinyalakan.")
                    dumpRotationDiagnostics()
                end
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
                        if bot.rotation then setRotationEnabled(false) end
                    elseif not intentionalStop and not hospitalPending and hadDisconnect and bot.rotation and rotationIsOn() ~= true then
                        if setRotationEnabled(true) then
                            rotationConfirmedOn = (rotationIsOn() == true)
                        end
                        print("[Rotation Final] Bot pulih dari disconnect. Rotasi bawaan dinyalakan kembali.")
                    end
                end
            end
        end

        wasOnline = isOnline

        -- Satu baris per menit: apakah rotasi benar-benar bergerak.
        -- status adalah angka terdokumentasi; perubahannya menunjukkan aktivitas.
        if not lastRotLog or (now - lastRotLog) >= 60 then
            lastRotLog = now
            pcall(function()
                print(string.format("[Rot] enabled=%s status=%s world=%s",
                    tostring(rotationIsOn()), rotationPhaseName(bot.rotation.status),
                    tostring(bot:isInWorld() and bot:getWorld().name or "-")))
            end)
        end
        updateWebhook("Rotasi Bawaan Lucifer Berjalan")
    end
end
