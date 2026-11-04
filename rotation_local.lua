-- LOCAL BUNDLE: no engine/module download. Edit CONFIG below.
-- loader.lua
-- Script ringkas untuk dieksekusi di bot Lucifer
-- Mengambil engine utama secara realtime dari GitHub Raw
-- https://github.com/shizukadev/rotation-script-shizukadev

-- ========================================================
-- 1. KONFIGURASI ROTASI & FITUR (Sesuaikan di sini)
-- ========================================================
local CONFIG = {
    -- Sumber daftar farm:
    -- Jika FARM_FROM_FILE = true, script otomatis membaca file rotation.txt di folder Downloads user
    -- (format per baris: WORLD:DOOR:ID atau WORLD:DOOR atau WORLD)
    FARM_FROM_FILE = true,
    FARM_FILE = "", -- Kosongkan agar auto-detect folder Downloads user, atau isi path lengkap rotation.txt

    -- Daftar world farm fallback (dipakai jika file tidak ditemukan / FARM_FROM_FILE = false)
    FARMS = {
        { world = "FARM1", door = "" },
        { world = "FARM2", door = "" },
    },

    -- World storage: doorseed = pintu drop seed, doorpack = pintu drop hasil pack
    STORAGE = {
        world = "MYSTORE",
        doorseed = "DOORSEED",
        doorpack = "DOORPACK",
        -- packworld = "MYPACKSTORE",  -- opsional: world khusus hasil pack
        -- door = "",  -- Fallback jika doorseed/doorpack tidak diisi
    },

    -- ID Item Target
    BLOCK_ID = 4584,       -- Contoh: Pepper Tree Block
    SEED_ID = 4585,        -- Contoh: Pepper Tree Seed

    -- Ambang seed di tas sebelum rotasi Lucifer men-drop ke storage
    STORE_SEED_MIN = 100,

    -- Panen akar pohon saat panen (opsional, default false)
    HARVEST_ROOTS = false,

    -- Interval Aksi Bot dalam MILIDETIK (disesuaikan untuk RDP Ping 50-100 ms)
    ACTION_INTERVALS = {
        moveDelay    = 115, -- 115ms: pergerakan lincah tanpa desync di ping 50-100
        hitDelay     = 160, -- 160ms: break / hit blok sesuai permintaan
        placeDelay   = 110, -- 110ms: place blok sesuai permintaan
        harvestDelay = 160, -- 160ms: panen pohon (hit) selaras dengan break
        plantDelay   = 110, -- 110ms: tanam pohon (place) selaras dengan place
        warpDelay    = 7000, -- 7s: cooldown warp world aman dari subserver lockout
        dropDelay    = 3500, -- 3.5s: jeda dialog & drop barang di storage
        trashDelay   = 3500, -- 3.5s: jeda dialog & trash barang
        dynamicDelay = true, -- true: Lucifer dynamic delay kompensasi jitter ping 50-100 ms
    },

    -- PNB (place & break blok) dijalankan fitur bawaan Lucifer: rotation.pnb_in_home
    -- Isi WORLD hanya kalau PNB dilakukan di world lain, bukan home.
    PNB = {
        ENABLED = true,
        WORLD = "",   -- kosong = pakai home world
    },

    -- Pickaxe diambil & dipakai otomatis oleh AutoWear Lucifer (ID 98).
    -- Isi world kalau pickaxe disimpan di world storage.
    PICKAXE_WORLD = { world = "WORLDPICK", door = "" },

    -- AutoWear: pakai pickaxe otomatis walau PICKAXE_WORLD kosong
    AUTO_WEAR = true,

    -- AutoTrash: daftar ID item yang DIBUANG (jangan masukkan pickaxe/blok/seed/hasil pack)
    AUTO_TRASH = {
        ENABLED = true,
        ITEMS = {},   -- contoh: { 18, 32 }
    },

    -- AutoCollect TIDAK diatur script ini. Rotasi bawaan Lucifer sudah
    -- mengumpulkan item saat harvest; menimpa auto_collect/collect_range/
    -- collect_all membuat hasil panen tidak terambil. Atur di UI Lucifer.

    -- AutoReconnect: tunggu & sambung ulang otomatis saat DC
    AUTO_RECONNECT = {
        ENABLED = true,
        INTERVAL = 5,
        BYPASS_LOGON = true, -- Gunakan bypass logon saat login/reconnect
        LOCKOUT_ENABLED = true, -- true = proteksi aktif (matikan reconnect jika gagal > 15x / > 5 menit); false = disable lockout (retry terus)
        MAX_FAIL_ATTEMPTS = 15, -- Matikan bypass & reconnect jika gagal login > 15x
        MAX_FAIL_MINUTES = 5, -- Matikan bypass & reconnect jika gagal login > 5 menit
    },

    -- Pengawasan Offline & Notifikasi Discord
    OFFLINE_ALERT = {
        ENABLED = true,
        TIMEOUT_MINUTES = 5, -- 5-10 menit sebelum ping Discord
        DISCORD_USER_ID = "922775541097066576", -- User ID yang di-tag jika offline lama
    },

    -- AutoMalady native: Grumbleteeth (ID 4) / Chicken Feet (ID 3).
    -- Torn Punching Muscle (ID 1) / Gem Cuts (ID 2) ditangani rute custom 4AID.
    AUTO_SPAM = { ENABLED = true, RECOVERY_SECONDS = 3600 },
    MALADY = {
        GRUMBLETEETH = false,
        CHICKEN_FEET = false,
    },

    -- Webhook Live Monitor (webhook_edit)
    MULTI_BOT = { startbot = 1, endbot = 11 },
    WEBHOOK = {
        ENABLED = true,
        URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA", -- ganti dengan URL webhook Discord Anda (jangan di-commit ke publik)
        MESSAGE_ID = "1567025865047539856", -- Jika diisi, bot akan edit pesan ini terus-menerus (Live Dashboard)
        UPDATE_INTERVAL_SECONDS = 15, -- jeda refresh dashboard
        EVENT_NOTIFICATIONS = false, -- live dashboard only; true mengaktifkan pesan alert terpisah
        MIN_EDIT_SECONDS = 5, -- gabungkan perubahan cepat ke edit berikutnya
        PHASE_NOTIFY = false, -- true = kirim pesan tiap fase rotasi berubah (bisa ramai)
        GLOBAL = true, -- true = satu dashboard global terpadu untuk semua bot jika beberapa/semua bot dijalankan bersamaan
    },

    -- Beli pack otomatis: rotasi Lucifer beli PackName saat gems mencapai PricePack,
    -- lalu drop hasilnya ke STORAGE (doorpack) lewat WorldManager.
    AUTO_BUY_PACK = {
        ENABLED = true,
        PackName = "vending_machine",
        PricePack = 8000,
        ItemIDOfPack = { 2978 },
    },
}

-- ========================================================

local bundledModules = {}
bundledModules["auto_malady_4aid"] = (function(...)
-- auto_malady_4aid.lua
-- Alur otomatis navigasi malady / surg area di world 4AID untuk Lucifer v2.86
-- Bisa dijalankan mandiri atau dipanggil via require/include sebagai fungsi checkAndCureMalady4AID()

local M = {}


local CURE_TARGET_IDS = { [1] = true, [2] = true } -- 1: Torn Muscle, 2: Gem Cuts

local MALADY_NAMES = {
    [0] = "Healthy",
    [1] = "Torn Punching Muscle",
    [2] = "Gem Cuts",
    [3] = "Chicken Feet",
    [4] = "Grumbleteeth",
    [5] = "Broken Heart",
    [6] = "Chaos Infection",
    [7] = "Moldy Guts",
    [8] = "Brainworms",
    [9] = "Lupus",
    [10] = "Ecto-Bones",
    [11] = "Fatty Liver",
}

function M.getMaladyName(id)
    return MALADY_NAMES[tonumber(id)] or ("Unknown Malady (" .. tostring(id) .. ")")
end

-- Satu-satunya tempat yang mengubah bot.malady menjadi ID.
-- Host bisa melaporkan angka ("1") atau nama ("Torn Punching Muscle");
-- kalau kedua fungsi menebak sendiri-sendiri, hasilnya berbeda dan bot
-- diam saja saat sakit. Semua pemanggil wajib lewat sini.
function M.resolveMaladyId(botCtx)
    local b = botCtx or (type(getBot) == "function" and getBot())
    if not b then return nil end
    local raw = b.malady
    local id = tonumber(raw)
    if id then return id end
    if type(raw) == "string" then
        local name = raw:lower()
        for known, label in pairs(MALADY_NAMES) do
            if label:lower() == name then return known end
        end
    end
    return nil
end

-- Memeriksa apakah bot benar-benar memiliki malady apapun (bebas penyakit = false)
function M.hasAnyMalady(botCtx)
    local b = botCtx or (type(getBot) == "function" and getBot())
    if not b then return "unknown" end
    local mid = M.resolveMaladyId(b)
    -- A positive duration is not a disease identifier: the host may retain
    -- a timer after surgery. Never turn explicit Healthy ID 0 into sick ID 0.
    if mid == 0 then return false, 0 end
    if mid and MALADY_NAMES[mid] and mid > 0 then return true, mid end
    return "unknown"
end

function M.checkNeedsHospital(botCtx)
    local b = botCtx or (type(getBot) == "function" and getBot())
    if not b then return false, 0 end
    local mid = M.resolveMaladyId(b)
    if not mid or mid == 0 then
        if type(b.getMaladyDuration) == "function" and b:getMaladyDuration() > 0 then
            mid = mid or 0
        end
    end
    return (mid and CURE_TARGET_IDS[mid] == true), (mid or 0)
end

local function waitOnline(b, timeout)
    local tries = timeout or 30
    while tries > 0 do
        if b.status == BotStatus.online then return true end
        sleep(1000)
        tries = tries - 1
    end
    return b.status == BotStatus.online
end

local function isHealthyState(b, targetWorld)
    if b.status ~= BotStatus.online then return false end
    if targetWorld then
        if type(b.isInWorld) == "function" and not b:isInWorld(targetWorld) then
            return false
        end
    end
    return true
end

local function warpTo(b, world)
    if not waitOnline(b, 10) then return false end
    if b:isInWorld(world) and b:isInWorld() then return true end
    b:warp(world)
    -- Warp is asynchronous; temporary non-online status is not a terminal failure.
    -- Require two consecutive destination observations before pathfinding.
    local stable = 0
    for _ = 1, 30 do
        sleep(1000)
        if b.status == BotStatus.online and b:isInWorld(world) and b:isInWorld() then
            stable = stable + 1
            if stable >= 2 then return true end
        else
            stable = 0
        end
    end
    print("[Hospital] Timeout warp: tujuan belum stabil setelah 30 detik.")
    return false
end

local function walkTo(b, x, y, targetWorld)
    if not waitOnline(b, 5) then return false end
    if not isHealthyState(b, targetWorld) then return false end
    if b.x == x and b.y == y then return true end

    local ok = b:findPath(x, y)
    sleep(500)
    -- Validasi ulang koneksi, world, dan posisi pasca-delay blocking
    if not isHealthyState(b, targetWorld) then return false end
    return (b.x == x and b.y == y)
end

local function enterPortal(b, x, y, targetWorld)
    if not isHealthyState(b, targetWorld) then return false end
    if type(b.enter) == "function" then
        b:enter()
    end
    b:hit(x, y)
    sleep(400)
    return isHealthyState(b)
end

local function sendAdventureDoorPacket(b, tx, ty, btn)
    if b.status ~= BotStatus.online then return false end
    local pkt = string.format("action|dialog_return\ndialog_name|adventure_door\ntilex|%d|\ntiley|%d|\nbuttonClicked|%s\n", tx, ty, btn)
    if type(b.sendPacket) == "function" then
        b:sendPacket(2, pkt)
        return true
    end
    return false
end

function M.runCure(botCtx, onProgress, recoveryProbe, hospitalWorld)
    local TARGET_WORLD = hospitalWorld or "4AID"
    if TARGET_WORLD ~= "4AID" and TARGET_WORLD ~= "BPJS" then return false end
    local b = botCtx or (type(getBot) == "function" and getBot())
    if not b then
        print("[Error] Bot context tidak ditemukan.")
        return false
    end

    local needsCure, mid = M.checkNeedsHospital(b)
    if not needsCure then
        local desc = (mid and mid ~= 0) and ("Malady ID " .. mid .. " bukan target") or "Bot bebas penyakit"
        print("[Check] Tidak perlu ke 4AID: " .. desc)
        return false
    end

    print(string.format("[Check] Terdeteksi penyakit ID %d (Torn Muscle / Gem Cuts). Memulai pengobatan ke %s...", mid, TARGET_WORLD))

    if TARGET_WORLD == "BPJS" then
        -- World may be full: retry only while online, never walk before arrival.
        while b.status == BotStatus.online and not b:isInWorld(TARGET_WORLD) do
            b:warp(TARGET_WORLD)
            sleep(4000)
        end
        if b.status ~= BotStatus.online or not b:isInWorld(TARGET_WORLD) then return false end
        -- Confirm destination remains valid after arrival before starting the route.
        sleep(1000)
        if not isHealthyState(b, TARGET_WORLD) then return false end
        local function door(x, y, button, destX, destY)
            if not walkTo(b, x, y, TARGET_WORLD) then return false end
            if not isHealthyState(b, TARGET_WORLD) then return false end
            b:enter() -- no adventure-key hit in BPJS
            sleep(500)
            if not isHealthyState(b, TARGET_WORLD) then return false end
            if not sendAdventureDoorPacket(b, x, y, button) then return false end
            for _ = 1, 10 do
                sleep(1000)
                if not isHealthyState(b, TARGET_WORLD) then return false end
                if b.x == destX and b.y == destY then return true end
            end
            print("[BPJS] Timeout konfirmasi perpindahan adventure door.")
            return false
        end
        if not door(8, 20, "button3", 4, 18) then return false end
        if not door(8, 18, "button0", 62, 29) then return false end
    else
    local dialogReceived = false
    local function dialogCallback(varlist)
        if not varlist or type(varlist.get) ~= "function" then return end
        local v0 = varlist:get(0)
        local name = v0 and (v0.getString and v0:getString() or tostring(v0)) or ""
        if name:find("OnDialogRequest") then
            local v1 = varlist:get(1)
            local content = v1 and (v1.getString and v1:getString() or tostring(v1)) or ""
            if content:find("adventure_door") and content:find("button0") then
                dialogReceived = true
                sendAdventureDoorPacket(b, 50, 15, "button0")
            end
        end
    end

    local dialogHookRegistered = false
    if type(addEvent) == "function" and type(Event) == "table" and Event.variantlist then
        pcall(function()
            addEvent(Event.variantlist, dialogCallback)
            dialogHookRegistered = true
        end)
    end

    local function cleanup()
        if dialogHookRegistered and type(removeEvent) == "function" and type(Event) == "table" and Event.variantlist then
            pcall(function() removeEvent(Event.variantlist) end)
        end
    end

    print("[Step 1] Menuju world " .. TARGET_WORLD .. "...")
    if not warpTo(b, TARGET_WORLD) then
        -- Gagal MASUK world (bukan gagal surgery): engine memakai penanda ini
        -- untuk menghitung fallback ke BPJS.
        print("[Error] Gagal warp ke " .. TARGET_WORLD)
        cleanup()
        return "enter_failed"
    end

    print("[Step 1] Berjalan ke portal (22, 16)...")
    if not walkTo(b, 22, 16, TARGET_WORLD) then
        print("[Error] Gagal findPath ke portal (22, 16) atau terputus.")
        cleanup()
        return false
    end
    if not enterPortal(b, 22, 16, TARGET_WORLD) then
        print("[Error] Terputus saat interaksi portal (22, 16)")
        cleanup()
        return false
    end
    sleep(1500)

    print("[Step 2] Mengambil adventure key di (61, 12)...")
    if not walkTo(b, 61, 12, TARGET_WORLD) then
        print("[Error] Gagal findPath ke adventure key (61, 12) atau salah world/terputus.")
        cleanup()
        return false
    end
    if not isHealthyState(b, TARGET_WORLD) then
        print("[Error] Salah world atau offline saat di posisi key (61, 12)")
        cleanup()
        return false
    end
    b:hit(61, 12)
    sleep(800)

    print("[Step 2] Berjalan ke portal (58, 15)...")
    if not walkTo(b, 58, 15, TARGET_WORLD) then
        print("[Error] Gagal findPath ke portal (58, 15) atau salah world/terputus.")
        cleanup()
        return false
    end
    if not enterPortal(b, 58, 15, TARGET_WORLD) then
        print("[Error] Terputus saat interaksi portal (58, 15)")
        cleanup()
        return false
    end
    sleep(1500)

    print("[Step 3] Berjalan ke adventure door (50, 15)...")
    if not walkTo(b, 50, 15, TARGET_WORLD) then
        print("[Error] Gagal findPath ke adventure door (50, 15) atau salah world/terputus.")
        cleanup()
        return false
    end

    if not isHealthyState(b, TARGET_WORLD) then
        print("[Error] Bot offline atau salah world sebelum interaksi adventure door.")
        cleanup()
        return false
    end

    if type(b.enter) == "function" then
        b:enter()
    end
    b:hit(50, 15)
    sleep(500)

    if not isHealthyState(b, TARGET_WORLD) then
        print("[Error] Bot offline atau salah world saat mencoba dialog adventure door.")
        cleanup()
        return false
    end

    local sent = sendAdventureDoorPacket(b, 50, 15, "button0")
    if not sent and not dialogReceived then
        print("[Error] sendPacket tidak tersedia atau gagal mengirim dialog packet.")
        cleanup()
        return false
    end

    sleep(1000)
    cleanup()

    end
    local bedX, bedY = TARGET_WORLD == "BPJS" and 73 or 66, TARGET_WORLD == "BPJS" and 29 or 39
    print(string.format("[Hospital] %s: menuju bed (%d,%d)", TARGET_WORLD, bedX, bedY))
    if not walkTo(b, bedX, bedY, TARGET_WORLD) then
        print("[Error] Gagal findPath ke area operasi (66, 39) atau terputus.")
        return false
    end

    print("[Step 4] Menunggu hingga status malady benar-benar hilang...")
    -- Loop menunggu sampai status malady benar-benar hilang (hasAnyMalady == false)
    -- Jika koneksi putus atau terlempar dari 4AID, hentikan dan laporkan false
    -- Read fresh malady state immediately on arrival, then every five seconds.
    while true do
        if type(onProgress) == "function" then
            pcall(onProgress, string.format("Menunggu sembuh di %s (%d,%d)", TARGET_WORLD, bedX, bedY))
        end

        if not isHealthyState(b, TARGET_WORLD) then
            print("[Error] Bot offline atau terlempar saat menunggu sembuh di (66, 39).")
            return false
        end

        -- /status is owner-requested refresh; say() acceptance is not proof
        -- that the server has updated malady. Keep valid-clearance checks.
        local refreshOK, recovering = pcall(function()
            if type(recoveryProbe) == "function" then
                recoveryProbe("request")
            elseif type(b.say) == "function" then
                b:say("/status")
            end
            -- Tunggu balasan /status seperlunya; bisa dipercepat lewat CONFIG.
            local waitMs = tonumber(_G.CONFIG and _G.CONFIG.HOSPITAL_STATUS_WAIT_MS) or 5000
            sleep(waitMs)
            if not isHealthyState(b, TARGET_WORLD) then error("hospital state changed") end
            if type(recoveryProbe) == "function" then return recoveryProbe("read") end
            return false
        end)
        if refreshOK and recovering == true then
            print("[Hospital] Recovering terdeteksi; keluar dari penantian untuk evaluasi rotasi.")
            return "recovering"
        end
        if not refreshOK then
            print("[Hospital] Refresh /status gagal atau koneksi/world berubah; hentikan attempt tanpa klaim sembuh.")
            return false
        end
        local anySick, curId = M.hasAnyMalady(b)
        print("[Hospital] Malady saat ini: ID=" .. tostring(curId) .. ", nama=" .. M.getMaladyName(curId) .. ", status=" .. tostring(anySick))
        if anySick == false then
            print("[Selesai] Status malady benar-benar hilang! Bot sembuh total di (66, 39).")
            return "cured"
        elseif anySick == "unknown" then
            print("[Warning] Status malady tidak valid/unknown, menunggu kepastian data...")
        end

        -- Next cycle requests /status immediately; the wait is before API reads.
    end
end

-- Eksekusi otomatis HANYA jika dipanggil langsung sebagai script mandiri utama
-- (Bukan saat dimuat via require("auto_malady_4aid") atau loadfile/dofile)
if ... == nil and type(getBot) == "function" and getBot() then
    M.runCure()
end

return M

end)("module")
bundledModules["webhook_monitor"] = (function(...)
-- Native Lucifer webhook monitor. No network activity until tick()/notify().
local MALADY_NAMES = {
    [0] = "Healthy",
    [1] = "Torn Punching Muscle",
    [2] = "Gem Cuts",
    [3] = "Chicken Feet",
    [4] = "Grumbleteeth",
    [5] = "Broken Heart",
    [6] = "Chaos Infection",
    [7] = "Moldy Guts",
    [8] = "Brainworms",
    [9] = "Lupus",
    [10] = "Ecto-Bones",
    [11] = "Fatty Liver",
}

local function maladyLabel(id)
    return MALADY_NAMES[tonumber(id)] or ("ID " .. tostring(id))
end

local M = {}
function M.new(bot, config, api)
    api = api or _G
    local cfg = config.WEBHOOK or {}
    local range = config.MULTI_BOT
    local alert = config.OFFLINE_ALERT or {}
    local offlineSince, offlineSent, lastMalady, lastDashboard = nil, false, nil, nil
    local dashLogged = false
    local lastPhase = nil
    local messageId = cfg.MESSAGE_ID
    local lastRequest, lastBody = nil, nil
    local retryAfter = 0

    local function now() return api.os.time() end
    local function enabled()
        return cfg.ENABLED == true and type(cfg.URL) == "string" and cfg.URL ~= ""
            and not cfg.URL:find("MASUKKAN_URL", 1, true)
    end

    local createAttempted = false

    local function deliver(content, dashboard)
        if not enabled() then return false end
        if range and tonumber(bot.index) ~= range.startbot then return false end
        if not dashboard and cfg.EVENT_NOTIFICATIONS ~= true then return true end

        local t = now()
        if t < retryAfter then return false end

        if dashboard then
            if content == lastBody then return true end
            local minEdit = math.max(5, tonumber(cfg.MIN_EDIT_SECONDS) or 5)
            if minEdit and minEdit > 0 and lastRequest and (t - lastRequest) < minEdit then return false end
            lastRequest = t
        end

        local id = messageId and tostring(messageId) or ""
        local isGlobal = cfg.GLOBAL == true

        if dashboard and isGlobal and id == "" then
            if not createAttempted and api.print then
                createAttempted = true
                api.print("[Webhook] Mode global WAJIB mengisi CONFIG.WEBHOOK.MESSAGE_ID agar pesan tidak duplikat.")
            end
            return false
        end

        local usedEdit = dashboard and id ~= ""
        if dashboard and not usedEdit then
            if isGlobal then return false end
            -- Single-bot tanpa ID: hanya SATU percobaan pembuatan pesan.
            -- Hasil ambigu (tanpa ID) tidak boleh memicu pengiriman berulang.
            if createAttempted then return false end
            createAttempted = true
        end

        local hookUser = (dashboard and (cfg.GLOBAL == true or cfg.ALL_BOTS == true))
            and "Lucifer Global Monitor"
            or ("Lucifer Monitor (" .. tostring(bot.name) .. ")")

        local deliverSuccess = false
        local hook = nil
        local ok = pcall(function()
            hook = api.Webhook.new(cfg.URL)
            hook.username = hookUser
            hook.content = tostring(content)
            if usedEdit then
                hook.message_id = id
                local okEdit, resEdit = pcall(function() return hook:edit() end)
                if okEdit and resEdit ~= false then
                    deliverSuccess = (resEdit == true) and "confirmed" or "unconfirmed"
                else
                    deliverSuccess = false
                    error("Webhook:edit failed")
                end
            else
                local resSend = hook:send()
                if resSend == false then
                    deliverSuccess = false
                    error("Webhook:send failed")
                end
                local newId = hook.message_id
                if newId and tostring(newId) ~= "" then
                    if dashboard then messageId = tostring(newId) end
                    deliverSuccess = "confirmed"
                elseif dashboard then
                    -- Terkirim tanpa ID: pemanggilan jalan, penerimaan tidak terbukti.
                    deliverSuccess = "unconfirmed"
                else
                    deliverSuccess = "confirmed"
                end
            end
        end)

        if ok and deliverSuccess then
            -- Hanya cache lastBody saat terkonfirmasi; hasil unconfirmed dicoba lagi.
            if dashboard and deliverSuccess == "confirmed" then
                lastBody = content
            end
            return deliverSuccess
        else
            if dashboard then retryAfter = now() + 15 end
            if api.print then api.print("[Webhook] Request failed; delivery unverified.") end
            return false
        end
    end

    -- World saat ini: HANYA membaca bot lokal (self).
    -- Hindari akses native lintas bot; akar crash host belum terkonfirmasi.
    local function currentWorld()
        local ok, world = pcall(function()
            if bot:isInWorld() then return bot:getWorld().name end
        end)
        return (ok and world and world ~= "") and world or "In Transit"
    end

    -- Status rotasi: HANYA membaca bot lokal (self).
    local function rotationState()
        local okR, rot = pcall(function() return bot.rotation end)
        if not okR or not rot then return "UNKNOWN" end
        local okE, enabled = pcall(function() return rot.enabled end)
        if not okE or type(enabled) ~= "boolean" then return "UNKNOWN" end
        if enabled ~= true then return "OFF" end
        local okS, status = pcall(function() return rot.status end)
        if not okS or status == nil then return "ON UNKNOWN" end
        if type(api.RotationStatus) == "table" then
            for name, value in pairs(api.RotationStatus) do
                if value == status then return "ON " .. tostring(name) end
            end
        end
        return "ON " .. tostring(status)
    end

    -- Komunikasi status antar-bot berbasis file I/O lokal (%TEMP%).
    -- Snapshot tervalidasi; file hilang/parsial/kedaluwarsa ditampilkan UNKNOWN.
    local snapshotIO = api.io or io
    local startedAt = now()
    local autoNames = {}
    local function slotPath(index)
        local tmp = api.os.getenv and (api.os.getenv("TEMP") or api.os.getenv("TMP")) or "."
        return tmp .. "/lucifer_monitor_slot_" .. tostring(index) .. ".txt"
    end
    local function discoverParticipants()
        local names, seen = {}, {}
        for i = (range and range.startbot or 0), (range and range.endbot or 511) do
            local ok, f = pcall(snapshotIO.open, slotPath(i), "r")
            if ok and f then
                local line = f:read("*l"); f:close()
                local name, stamp, target = tostring(line or ""):match("^([%w_%-]+)|(%d+)|(%d+)$")
                stamp = tonumber(stamp)
                if name and target == tostring(messageId) and stamp <= now() and now() - stamp < 20 and not seen[name] then
                    seen[name] = true; names[#names + 1] = name
                end
            end
        end
        table.sort(names)
        return names
    end
    local function saveLocalStatus(rotState)
        local tmp = api.os.getenv and (api.os.getenv("TEMP") or api.os.getenv("TMP")) or "."
        local safeName = tostring(bot.name):gsub("[^%w_%-]", "")
        if safeName == "" then return end
        local f = snapshotIO.open(tmp .. "/lucifer_bot_" .. safeName .. ".txt", "w")
        if f then
            local w = currentWorld()
            local online = (bot.status == api.BotStatus.online) and "ONLINE" or "OFFLINE"
            local gems = tostring(bot.gem_count or 0)
            local mid = "unknown"
            if bot.status == api.BotStatus.online then
                local ok, value = pcall(function() return tonumber(bot.malady) end)
                if ok and value then mid = tostring(value) end
            end
            f:write(string.format("%s|%s|%s|%s|%s|%s|%d\n",
                safeName, online, tostring(w), tostring(rotState), gems, mid, now()))
            f:close()
            local index = tonumber(bot.index)
            if index and index % 1 == 0 and index >= 0 and index <= 511 and tostring(messageId or ""):match("^%d+$") then
                local slot = snapshotIO.open(slotPath(index), "w")
                if slot then slot:write(safeName .. "|" .. tostring(now()) .. "|" .. tostring(messageId)); slot:close() end
            end
        end
    end

    local function readRemoteBotStatus(name)
        local safeName = tostring(name):gsub("[^%w_%-]", "")
        if safeName == "" then return nil end
        local tmp = api.os.getenv and (api.os.getenv("TEMP") or api.os.getenv("TMP")) or "."
        local okOpen, f = pcall(snapshotIO.open, tmp .. "/lucifer_bot_" .. safeName .. ".txt", "r")
        if not okOpen then return nil end
        if not f then return nil end
        local line = f:read("*l")
        f:close()
        if not line then return nil end
        local bname, online, wName, rot, gems, mid, timestamp = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(%d+)$")
        if bname == safeName and tonumber(timestamp) <= now() and (now() - tonumber(timestamp)) < 60 then
            return {
                name = bname,
                online = (online == "ONLINE"),
                world = wName,
                rot = rot,
                gems = tonumber(gems) or 0,
                malady = tonumber(mid) or 0,
            }
        end
        return nil
    end

    local function isLeader(myBot, allBots)
        -- LEADER_BOT eksplisit menang atas index startbot.
        if cfg.LEADER_BOT and tostring(cfg.LEADER_BOT) ~= "" then
            return myBot.name == cfg.LEADER_BOT
        end
        if range then return tonumber(myBot.index) == range.startbot end
        return autoNames[1] == tostring(myBot.name)
    end

    local function buildGlobalDashboard(allBots)
        local totalBots = #allBots
        local onlineStatus = (api.BotStatus and api.BotStatus.online) or 1
        local onlineCount, unknownCount = 0, 0
        local totalGems = 0
        local lines = {}
        for i, b in ipairs(allBots) do
            local bName = tostring(b.name)
            local isOnline, wName, rot, gems, mid
            if bName == tostring(bot.name) then
                isOnline = (bot.status == onlineStatus)
                wName = currentWorld()
                rot = rotationState()
                gems = tonumber(bot.gem_count) or 0
                mid = nil
                if isOnline then mid = tonumber(bot.malady) end
            else
                local st = readRemoteBotStatus(bName)
                if st then
                    isOnline = st.online
                    wName = st.world
                    rot = st.rot
                    gems = st.gems
                    mid = st.malady
                elseif type(allBotsList) == "table" or type(api.getBots) == "function" then
                    -- Fallback jika dalam lingkungan test/mock yang menyediakan objek bot di allBots
                    local targetB = nil
                    if type(api.getBots) == "function" then
                        local okB, bots = pcall(api.getBots)
                        if okB and type(bots) == "table" then
                            for _, tb in ipairs(bots) do
                                if tostring(tb.name) == bName then targetB = tb; break end
                            end
                        end
                    end
                    if targetB then
                        isOnline = (targetB.status == onlineStatus)
                        local okW, gw = pcall(function() return targetB:getWorld() end)
                        wName = (okW and gw and gw.name) or "In Transit"
                        local okR, gr = pcall(function() return targetB.rotation end)
                        if okR and gr and gr.enabled then
                            local phaseName = tostring(gr.status or "")
                            if type(api.RotationStatus) == "table" then
                                for k, v in pairs(api.RotationStatus) do
                                    if v == gr.status then phaseName = tostring(k); break end
                                end
                            end
                            rot = "ON " .. phaseName
                        else
                            rot = "OFF"
                        end
                        gems = tonumber(targetB.gem_count) or 0
                        mid = isOnline and tonumber(targetB.malady) or nil
                    else
                        isOnline = false
                        wName = "In Transit"
                        rot = "UNKNOWN"
                        gems = 0
                        mid = 0
                    end
                else
                    isOnline = false
                    wName = "In Transit"
                    rot = "UNKNOWN"
                    gems = 0
                    mid = 0
                end
            end
            if isOnline then onlineCount = onlineCount + 1 end
            totalGems = totalGems + gems
            local statusLabel = isOnline and "ONLINE" or "OFFLINE"
            if bName ~= tostring(bot.name) and not readRemoteBotStatus(bName) and (not api.getBots) then statusLabel = "UNKNOWN"; unknownCount = unknownCount + 1 end
            local maladyBadge = ""
            if isOnline and mid and mid > 0 then
                maladyBadge = " | ⚠️ " .. maladyLabel(mid)
            end
            lines[#lines + 1] = string.format("%d. **%s** [%s] | `%s` | Rot: `%s` | 💎 %d%s",
                i, bName, statusLabel, tostring(wName), tostring(rot), gems, maladyBadge)
        end
        local offlineCount = totalBots - onlineCount - unknownCount
        local header = string.format("🌐 **[Lucifer Global Dashboard]**\n**Total:** %d Bot (%d Online, %d Offline, %d Unknown) | **Total Gems:** %d\n\n",
            totalBots, onlineCount, offlineCount, unknownCount, totalGems)
        local body = header .. table.concat(lines, "\n")
        if #body > 1950 then
            body = body:sub(1, 1900) .. "\n... (dipotong karena batas pesan Discord)"
        end
        return body
    end

    local lastDiseaseCheck = nil
    local obj = {}
    function obj.notify(message) return deliver(tostring(message), false) end
    function obj.tick(action)
        local t = now()
        local online = bot.status == api.BotStatus.online
        if online then
            offlineSince, offlineSent = nil, false
        else
            offlineSince = offlineSince or t
            local minutes = tonumber(alert.TIMEOUT_MINUTES) or 5
            if minutes <= 0 then minutes = 5 end
            if alert.ENABLED ~= false and not offlineSent and t - offlineSince >= minutes * 60 then
                local user = tostring(alert.DISCORD_USER_ID or "922775541097066576")
                if not user:match("^%d+$") then user = "922775541097066576" end
                offlineSent = deliver(string.format("<@%s> Bot **%s** offline selama %d detik. World saat ini: %s.", user, tostring(bot.name), t-offlineSince, currentWorld()), false)
            end
        end

        if not online then lastDiseaseCheck = nil end
        if online and (not lastDiseaseCheck or t - lastDiseaseCheck >= 5) then
            lastDiseaseCheck = t
            local id = tonumber(bot.malady)
            if id and id >= 0 and id % 1 == 0 then
                if id > 0 and id ~= lastMalady then
                    if deliver(string.format("Bot **%s** terkena penyakit **%s** (ID %d). World saat ini: %s.", tostring(bot.name), maladyLabel(id), id, currentWorld()), false) then lastMalady = id end
                elseif id == 0 then
                    local durationOk, duration = true, 0
                    if type(bot.getMaladyDuration) == "function" then durationOk, duration = pcall(function() return bot:getMaladyDuration() end) end
                    if durationOk and type(duration) == "number" and duration == 0 then
                        if lastMalady and lastMalady > 0 then
                            if deliver(string.format("Bot **%s**: status penyakit sudah hilang (ID 0). World saat ini: %s.", tostring(bot.name), currentWorld()), false) then lastMalady = 0 end
                        else lastMalady = 0 end
                    end
                end
            end
        end

        local interval = tonumber(cfg.UPDATE_INTERVAL_SECONDS) or 15
        local isGlobal = cfg.GLOBAL == true
        -- Publish SELF before leader gate. Never enumerate native bot objects.
        local phaseNow = rotationState()
        if isGlobal then pcall(saveLocalStatus, phaseNow) end
        local allBots = nil
        if isGlobal then
            local ok, names = pcall(discoverParticipants)
            autoNames = ok and names or {}
            if #autoNames == 0 and type(api.getBots) == "function" then
                local okB, bots = pcall(api.getBots)
                if okB and type(bots) == "table" then
                    for _, b in ipairs(bots) do
                        if b.name then autoNames[#autoNames + 1] = tostring(b.name) end
                    end
                end
            end
            -- Grace hanya relevan bila snapshot disk tersedia (menunggu peserta daftar).
            if (api.io or (api.os and api.os.getenv)) and now() - startedAt < 10 then return end
            if #autoNames == 0 then return end
        end
        if isGlobal then
            if not isLeader(bot) then return end
            allBots = {}
            local seen = {}
            for _, name in ipairs(autoNames) do
                name = tostring(name)
                if name:match("^[%w_%-]+$") and not seen[name] then
                    seen[name] = true
                    allBots[#allBots + 1] = {name = name}
                end
            end
        end

        if allBots then
            local phases = {}
            for _, b in ipairs(allBots) do
                local bName = tostring(b.name)
                if bName == tostring(bot.name) then
                    phases[#phases + 1] = bName .. ":" .. phaseNow .. ":" .. tostring(bot.status)
                else
                    local st = readRemoteBotStatus(bName)
                    if st then
                        phases[#phases + 1] = bName .. ":" .. tostring(st.rot) .. ":" .. (st.online and "1" or "0")
                    end
                end
            end
            phaseNow = table.concat(phases, "|")
        end
        if phaseNow ~= lastPhase then
            if lastPhase ~= nil then
                lastDashboard = nil
                if cfg.PHASE_NOTIFY == true then
                    deliver(string.format("Bot **%s**: fase rotasi **%s** → **%s** (%s).",
                        tostring(bot.name), tostring(lastPhase), tostring(phaseNow), currentWorld()), false)
                end
            end
            lastPhase = phaseNow
        end

        if not lastDashboard or t-lastDashboard >= math.max(3, interval) then
            local body
            if allBots then
                body = buildGlobalDashboard(allBots)
            else
                local rotText = phaseNow
                body = string.format("**Bot:** %s\n**Status:** %s\n**World saat ini:** %s\n**Rotasi:** %s\n**Aktivitas:** %s\n**Gems:** %s", tostring(bot.name), online and "ONLINE" or "OFFLINE", currentWorld(), rotText, tostring(action or "-"), tostring(bot.gem_count or 0))
            end

            local dashOk = deliver(body, true)
            if dashOk then
                lastDashboard = t
                if not dashLogged and api.print then
                    dashLogged = true
                    local modeDesc = allBots and string.format("global %d bot", #allBots) or "single bot"
                    local target = messageId and ("edit id " .. tostring(messageId)) or "pesan baru"
                    if dashOk == "confirmed" then
                        api.print("[Webhook] dashboard terkirim (" .. modeDesc .. ", " .. target .. ")")
                    else
                        api.print("[Webhook] dashboard terkirim tanpa konfirmasi (" .. modeDesc .. ", " .. target .. ")")
                    end
                end
            end
        end
    end
    return obj
end
return M

end)("module")
local hostRequire = require
local function require(name)
 if bundledModules[name] then return bundledModules[name] end
 if hostRequire then return hostRequire(name) end
 error("Module unavailable: " .. tostring(name))
end
local function runEngine(...)
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
    recoveryStatus.events = (recoveryStatus.events or 0) + 1
    local text = message:match("msg|([^\r\n]*)")
    if not text then return end
    text = text:gsub("`.", ""):lower():match("^%s*(.-)%s*$")
    local ok, name = pcall(function() return tostring(bot.name or ""):lower() end)
    if text:find("'s status:", 1, true) then
        recoveryStatus.header = ok and name ~= "" and text == name .. "'s status:"
        recoveryStatus.foreign = not recoveryStatus.header
        recoveryStatus.expectedMods = nil
        recoveryStatus.receivedMods = 0
        recoveryStatus.seenMods = {}
        recoveryStatus.complete = false
        recoveryStatus.known = recoveryStatus.active == true
        return
    end
    if recoveryStatus.foreign or not recoveryStatus.header then return end
    local count = text:match("^(%d+)%s+mods? active:?%s*$") or text:match("^mods? active:?%s*(%d+)%s*$")
    if text == "no mods active" or text == "no mods active:" then count = "0" end
    if count then
        -- Count baru = konteks baru: completion lama tidak boleh dipertahankan.
        recoveryStatus.complete = false
        recoveryStatus.expectedMods = tonumber(count)
        recoveryStatus.receivedMods = 0
        recoveryStatus.seenMods = {}
        recoveryStatus.known = recoveryStatus.active == true or tonumber(count) == 0
        -- Daftar sudah lengkap (mis. "0 mods active"): tandai selesai, tetap
        -- proses baris berikutnya dalam pump yang sama sebelum menyimpulkan.
        if recoveryStatus.receivedMods == recoveryStatus.expectedMods then
            recoveryStatus.complete = true
        end
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
local recoveryNoEventsLogged = false
local function checkRecoveryStatus()
    local now = os.time()
    if bot.status ~= BotStatus.online then
        recoveryStatus.known = false
        recoveryStatus.checking = false
        recoveryStatus.nextCheck = 0
        return false
    end
    if not recoveryEventsOK then
        -- Tidak ada fasilitas event: status TIDAK BISA diverifikasi. Jangan pernah
        -- menganggapnya bebas Recovering; admission custom ditahan.
        recoveryStatus.known = false
        recoveryStatus.checking = false
        if not recoveryNoEventsLogged then
            recoveryNoEventsLogged = true
            print("[Recovering] Event game_message tidak tersedia; status tidak dapat diverifikasi, admission hospital ditahan.")
        end
        return false
    end
    if not recoveryStatus.checking and now >= recoveryStatus.nextCheck then
        recoveryStatus.known = false
        recoveryStatus.active = false
        recoveryStatus.header = false
        recoveryStatus.foreign = false
        recoveryStatus.expectedMods = nil
        recoveryStatus.receivedMods = 0
        recoveryStatus.seenMods = {}
        recoveryStatus.untilTs = nil
        recoveryStatus.events = 0
        recoveryStatus.complete = false
        recoveryStatus.checking = true
        recoveryStatus.deadline = now + 3 -- cukup untuk balasan /status; jangan blokir admission lama
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
        if recoveryStatus.complete and recoveryStatus.checking and recoveryStatus.header and not recoveryStatus.foreign then
            -- Daftar mod lengkap dari bot sendiri: verifikasi selesai tanpa menunggu deadline.
            recoveryStatus.checking = false
            recoveryStatus.known = true
        end
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
                (recoveryStatus.known and not recoveryStatus.active) and "bebas recovering (Recovering tidak aktif)" or string.format("status belum terverifikasi; AutoSpam OFF | bot=%s events=%s header=%s mods=%s/%s", tostring(bot.name), tostring(recoveryStatus.events or 0), tostring(recoveryStatus.header), tostring(recoveryStatus.receivedMods or 0), tostring(recoveryStatus.expectedMods))))
        end
    end
    return not recoveryStatus.checking and recoveryStatus.known and not recoveryStatus.active
end

local lastSpamCheck = nil
local function updateNativeMaladyForLevel()
    local ok, result = pcall(function()
        local level = bot.level
        if type(level) ~= "number" or level ~= level or level < 0 or level % 1 ~= 0 then return false end
        local native = bot.auto_malady
        if not native then return false end
        local low = level < 16
        native.auto_grumbleteeth = low
        native.auto_chicken_feet = low
        native.enabled = true
        return native.auto_grumbleteeth == low and native.auto_chicken_feet == low and native.enabled == true
    end)
    if not ok or result ~= true then
        print("[AutoMalady] Level/native tidak terbaca; keputusan hospital ditahan (tidak ditebak).")
        return false
    end
    return true
end


local function updateSpamState()
    -- Getter juga bisa melempar error di build ketat; dulu ini menghentikan
    -- engine sebelum setup dimulai.
    local okObj, spamObj = pcall(function() return bot.auto_spam end)
    if not okObj or not spamObj then return end
    -- AutoSpam bisa read-only di sebagian build; jangan sampai mematikan script
    -- (dulu error di sini muncul sebelum setup dan seluruh engine berhenti).
    local function setSpam(on)
        pcall(function() spamObj.enabled = on end)
    end
    if bot.status ~= BotStatus.online then
        setSpam(false)
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
        return bot.status == BotStatus.online and id == 0 and os.time() >= spamRecoveryUntil and not bot:isInWorld("4AID") and not bot:isInWorld("BPJS")
    end)
    -- Preserve all owner-configured text, intervals and other spam options.
    setSpam(cfg.ENABLED ~= false and recoveryClear and ok and healthyOutsideHospital == true)
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

-- ========================================================
-- SETELAN MODULE BAWAAN LUCIFER (AutoWear / AutoTrash / Collect / Reconnect / Malady)
-- ========================================================
-- WAJIB: rotasi tidak boleh dinyalakan selama modul pesaing masih hidup.
-- Dulu ini bagian ekor applyBotSettings, jadi kegagalan setter AutoWear di
-- tengah membuat auto_farm/auto_harvest/auto_plant tidak pernah dimatikan --
-- lalu rotasi dinyalakan dan dua automation berebut tile.
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

-- OPSIONAL: tiap bagian diisolasi supaya satu API yang tidak cocok tidak
-- melewati bagian lain. Kegagalan di sini tidak menghalangi rotasi.
local function applyOptionalBotSettings()
    pcall(function()
        local recon = CONFIG.AUTO_RECONNECT or {}
        bot.auto_reconnect = recon.ENABLED ~= false
        if recon.INTERVAL then bot.reconnect_interval = recon.INTERVAL end
        if recon.BYPASS_LOGON ~= nil then bot.bypass_logon = recon.BYPASS_LOGON end
    end)

    -- Collect: TIDAK disentuh. Rotasi bawaan Lucifer yang mengurus collect saat
    -- harvest; menimpa auto_collect/collect_range/collect_all membuat item tidak
    -- terambil (range dipaksa kecil, collect_all dipaksa false).

    pcall(function()
        bot.auto_wear = CONFIG.AUTO_WEAR ~= false
        bot.wear_id = tonumber(CONFIG.WEAR_ID) or 98
        local pick = CONFIG.PICKAXE_WORLD
        if pick and pick.world and pick.world ~= "" then
            bot.wear_storage = pick.world
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

    -- AutoMalady: tetap aktif untuk refresh status, aksi penyakit bawaan dimatikan.
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
            -- Pack boleh punya world sendiri (STORAGE.packworld), terpisah dari
            -- world seed. Fallback ke STORAGE.world seperti sebelumnya.
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

    -- Pilih farm SETELAH semua terdaftar, lalu verifikasi lewat API terdokumentasi
    -- manager.worlds[i].selected. Dulu pengecekan dilakukan sebelum selectAll,
    -- jadi selalu melaporkan "tidak ada farm terpilih".
    local selectErr = nil
    if type(manager.selectAll) == "function" then
        local okSel, errSel = pcall(function() manager:selectAll() end)
        if not okSel then selectErr = tostring(errSel) end
    else
        selectErr = "manager.selectAll tidak tersedia"
    end
    -- Sebagian build butuh farm di-assign ke bot ini sebelum rotation.enabled
    -- bisa dinyalakan. pcall: build v2.86 murni tidak punya apply().
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
-- Urutan penting: modul pesaing dimatikan lebih dulu dan WAJIB berhasil.
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
local fourAidFails = 0       -- Kegagalan berturut-turut masuk 4AID (fallback ke BPJS)
local nativeMaladyEpisode = false -- episode penyakit native (level <16) sudah tercatat
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


-- Melanjutkan farming setelah pengobatan. rotationConfirmedOn direset dulu:
-- tanpa itu, kalau enable gagal / bot belum online, watchdog membaca
-- "rotasi mati padahal pernah nyala" sebagai stop manual dan mengunci mati.
local function resumeFarming(reason)
    if intentionalStop or lockoutTriggered or bot.status ~= BotStatus.online or not bot.rotation then return false end
    rotationConfirmedOn = false
    if setRotationEnabled(true) and rotationIsOn() == true then
        rotationConfirmedOn = true
        print(string.format("[Engine] %s: %s", tostring(bot.name), reason))
        return true
    end
    print("[Engine] Rotasi belum bisa dinyalakan setelah pengobatan; watchdog akan mencoba lagi.")
    return false
end
-- 4AID tidak lagi dibatasi level: default untuk semua level >= 16.
-- BPJS hanya dipakai sebagai fallback setelah 4AID gagal dimasuki berulang.
local FOUR_AID_MAX_FAILS = 5
-- Bot yang memakai AutoMalady native (level <16) dipindah ke world acak
-- setelah sembuh, supaya tidak menetap di world rumah sakit.
local RANDOM_WORLD_LEN = 5
local RANDOM_WORLD_MIN_LEVEL = 16
local function randomWorldName()
    local out = {}
    for i = 1, RANDOM_WORLD_LEN do
        out[i] = string.char(65 + math.random(0, 25))
    end
    return table.concat(out)
end
local function hospitalForLevel(level)
    if type(level) ~= "number" or level ~= level or level == math.huge or level < 0 or level % 1 ~= 0 then return nil end
    -- 4AID terbuka untuk semua level; BPJS hanya fallback setelah gagal masuk.
    return "4AID"
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


    -- AutoMalady native (level <16) hanya menangani Chicken Feet (3) dan
    -- Grumbleteeth (4). Setelah penyakit itu hilang, pindah ke world acak satu
    -- kali per episode; penyakit target custom tidak memicu perpindahan.
    local nativeLevel = type(bot.level) == "number" and bot.level < 16
    if nativeLevel and (curId == 3 or curId == 4) then
        nativeMaladyEpisode = true
    elseif targetMalady then
        nativeMaladyEpisode = false
    end
    if anySick == false and nativeMaladyEpisode then
        nativeMaladyEpisode = false
        -- Jangan bepergian otomatis saat owner stop atau intent farming hilang.
        if nativeLevel and farmRunIntent and not intentionalStop and bot.status == BotStatus.online then
            local target = randomWorldName()
            local okWarp = pcall(function() bot:warp(target) end)
            print(string.format("[Hospital] %s: sembuh (native), pindah ke world acak %s (%s).",
                tostring(bot.name), target, okWarp and "dikirim" or "gagal kirim"))
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

    -- Recovering: Torn boleh lanjut farming, Gem Cuts tetap ditahan.
    local recoveryClear = checkRecoveryStatus()

    -- Hanya malady target (1/2) yang boleh menahan rotasi; penyakit ringan
    -- seperti Chicken Feet (ID 3) tidak boleh mematikan farming.
    local targetMalady = (curId == 1 or curId == 2)
    -- Pelepasan jeda hanya untuk ID non-target yang VALID; UNKNOWN bukan izin.
    local mildMalady = type(curId) == "number" and curId > 0 and not targetMalady
    if recoveryStatus.active == true then
        if mildMalady then
            if hospitalPending then
                hospitalPending = false
                print(string.format("[Hospital] %s: penyakit non-target (ID %s); jeda pengobatan dilepas.", tostring(bot and bot.name), tostring(curId)))
                if shouldResumeAfterCure and farmRunIntent and not intentionalStop then
                    resumeFarming("Penyakit non-target; rotasi dilanjutkan sesuai intent.")
                end
                shouldResumeAfterCure = false
            end
            return false
        end
        if curId == 2 then
            if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
            hospitalPending = true
            if bot and bot.rotation then setRotationEnabled(false) end
            return false
        end
        -- Hanya Torn (ID 1) yang boleh farming selama Recovering. ID nil hanya
        -- muncul pada potongan kode yang diuji terpisah, bukan dispatcher produksi.
        if curId == 1 and not recoveryStatus.checking then
            hospitalPending = false
            shouldResumeAfterCure = false
            if farmRunIntent and not intentionalStop then
                resumeFarming("Torn Punching Muscle + Recovering: pengobatan ditunda, rotasi dilanjutkan.")
            end
        end
        return false
    end
    -- Hanya malady target (1/2) yang boleh menahan rotasi; penyakit ringan
    -- seperti Chicken Feet (ID 3) tidak boleh mematikan farming.
    if not recoveryClear and targetMalady then
        -- UNKNOWN / respons parsial / timeout: admission ditahan (fail-closed).
        -- Penyakit ringan tidak melewati gate ini agar tidak ikut tertahan.
        if targetMalady then
            if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
            hospitalPending = true
            if bot and bot.rotation then setRotationEnabled(false) end
        end
        return false
    end

    -- Evaluasi status penyakit terkini
    if gemWaitActive then
        if anySick == false then
            gemWaitActive = false
            gemWaitNextWarp = 0
        else
            local recoveryNow = checkRecoveryStatus()
            if recoveryNow and anySick == true and curId == 2 then
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
        -- Healthy setelah menunggu: tidak ada yang perlu ditahan.
        return false
    end

    -- Gem Cuts never permits farming, including during Recovering.
    if anySick == true and curId == 2 then
        if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
        hospitalPending = true
        if bot.rotation then setRotationEnabled(false) end
    end

    if anySick == "unknown" then
        if hospitalPending and bot.rotation then setRotationEnabled(false) end
        print(string.format("[Hospital] %s: status malady tidak terbaca; admission ditahan.", tostring(bot.name)))
        return false
    end

    -- Memeriksa apakah penyakit merupakan target pengobatan ke 4AID (ID 1 / ID 2)
    local needsCure, mid = mod.checkNeedsHospital(bot)
    if needsCure ~= true or (mid ~= 1 and mid ~= 2) then
        -- Penyakit ringan / berubah jadi non-target: lepaskan jeda pengobatan
        -- dan lanjutkan farming sesuai intent, tanpa menimpa stop manual.
        if mildMalady and hospitalPending then
            hospitalPending = false
            print(string.format("[Hospital] %s: penyakit non-target (ID %s); jeda pengobatan dilepas.", tostring(bot and bot.name), tostring(curId)))
            if shouldResumeAfterCure and farmRunIntent and not intentionalStop then
                resumeFarming("Penyakit non-target; rotasi dilanjutkan sesuai intent.")
            end
            shouldResumeAfterCure = false
        end
        return false
    end

    local now = os.time and os.time() or 0
    if hospitalPending and (now - lastHospitalAttempt) < HOSPITAL_COOLDOWN then
        -- Masih dalam cooldown pengobatan sebelumnya dan belum sembuh: tahan rotasi tetap mati
        if bot.rotation then setRotationEnabled(false) end
        return false
    end

    -- Best effort: kegagalan setter native tidak boleh memblokir pengobatan.
    updateNativeMaladyForLevel()
    if type(bot.level) ~= "number" then
        -- Level tak terbaca: jangan menebak rute, tapi tetap tahan rotasi.
        if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
        hospitalPending = true
        if bot.rotation then setRotationEnabled(false) end
        lastHospitalAttempt = now
        return false
    end
    local levelOK, currentLevel = pcall(function() return bot.level end)
    local hospitalWorld = levelOK and hospitalForLevel(currentLevel) or nil
    if hospitalWorld == "4AID" and fourAidFails > FOUR_AID_MAX_FAILS then
        hospitalWorld = "BPJS"
        print(string.format("[Hospital] 4AID gagal %d kali berturut-turut; beralih ke BPJS.", fourAidFails))
    end
    if hospitalWorld == "BPJS" then
        -- Jeda rotasi dulu; level ini tidak boleh memakai rute 4AID.
        if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
        hospitalPending = true
        if bot.rotation then setRotationEnabled(false) end
    end
    if not hospitalWorld then
        if not hospitalPending then shouldResumeAfterCure = farmRunIntent and not intentionalStop end
        hospitalPending = true
        if bot.rotation then setRotationEnabled(false) end
        lastHospitalAttempt = now
        print("[Hospital] Level di bawah 12 atau tidak valid: pengobatan ditahan.")
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

    if multi then
        print("[Hospital] Menunggu slot admission index " .. tostring(localIndex))
        sleep(math.min((localIndex - multi.startbot) * 10000, 10000))
        if bot.status ~= BotStatus.online or lockoutTriggered then return false end
        local stillNeeds, currentId = mod.checkNeedsHospital(bot)
        if stillNeeds ~= true or (currentId ~= 1 and currentId ~= 2) then return false end
    end
    recoveryStatus.nextCheck = 0 -- obtain fresh surgery result during hospital wait
    local status = mod.runCure(bot, updateWebhook, function()
        checkRecoveryStatus()
        return recoveryStatus.active == true
    end, hospitalWorld)
    if status == "recovering" then
        -- /status is asynchronous: hasil operasi belum terbaca sampai server
        -- menjawab. Minta, tunggu, lalu baca API hanya jika jawabannya terverifikasi.
        recoveryStatus.nextCheck = 0
        checkRecoveryStatus()
        sleep(5000)
        local sick, id
        if recoveryStatus.known and not recoveryStatus.checking then
            sick, id = mod.hasAnyMalady(bot)
        else
            hospitalPending = true
            if bot.rotation then setRotationEnabled(false) end
            return false
        end
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

    -- Resume rotasi bawaan HANYA jika bot benar-benar sembuh ("cured") dan online
    if status == "cured" then
        fourAidFails = 0
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
        -- Jika gagal atau belum sembuh, rotasi tetap ditahan mati
        if status == "enter_failed" and hospitalWorld == "4AID" then
            -- Hanya gagal MASUK world yang dihitung untuk fallback BPJS.
            fourAidFails = fourAidFails + 1
            print(string.format("[Hospital] Gagal masuk 4AID (%d/%d).", fourAidFails, FOUR_AID_MAX_FAILS))
        elseif status ~= "recovering" then
            -- Masuk berhasil (atau route berjalan): hitungan direset.
            fourAidFails = 0
        end
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

end
runEngine(CONFIG)
