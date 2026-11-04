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
