-- auto_malady_4aid.lua
-- Alur otomatis navigasi malady / surg area di world 4AID untuk Lucifer v2.86
-- Bisa dijalankan mandiri atau dipanggil via require/include sebagai fungsi checkAndCureMalady4AID()

local M = {}

local TARGET_WORLD = "4AID"
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
    if mid and mid > 0 then return true, mid end
    if type(b.getMaladyDuration) == "function" then
        local dur = b:getMaladyDuration()
        if dur and dur > 0 then
            return true, mid or 1
        elseif dur == 0 and mid == 0 then
            return false, 0
        end
    end
    if mid == 0 then return false, 0 end
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

function M.runCure(botCtx, onProgress)
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

    print(string.format("[Check] Terdeteksi penyakit ID %d (Torn Muscle / Gem Cuts). Memulai pengobatan ke 4AID...", mid))

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
        print("[Error] Gagal warp ke " .. TARGET_WORLD)
        cleanup()
        return false
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

    print("[Step 2] Berjalan ke portal (64, 12)...")
    if not walkTo(b, 64, 12, TARGET_WORLD) then
        print("[Error] Gagal findPath ke portal (64, 12) atau salah world/terputus.")
        cleanup()
        return false
    end
    if not enterPortal(b, 64, 12, TARGET_WORLD) then
        print("[Error] Terputus saat interaksi portal (64, 12)")
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

    print("[Step 4] Berjalan ke area operasi (66, 39)...")
    if not walkTo(b, 66, 39, TARGET_WORLD) then
        print("[Error] Gagal findPath ke area operasi (66, 39) atau terputus.")
        return false
    end

    print("[Step 4] Menunggu hingga status malady benar-benar hilang...")
    -- Loop menunggu sampai status malady benar-benar hilang (hasAnyMalady == false)
    -- Jika koneksi putus atau terlempar dari 4AID, hentikan dan laporkan false
    -- Read fresh malady state immediately on arrival, then every five seconds.
    while true do
        if type(onProgress) == "function" then
            pcall(onProgress, "Menunggu sembuh di (66,39)")
        end

        if not isHealthyState(b, TARGET_WORLD) then
            print("[Error] Bot offline atau terlempar saat menunggu sembuh di (66, 39).")
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

        sleep(5000)
    end
end

-- Eksekusi otomatis HANYA jika dipanggil langsung sebagai script mandiri utama
-- (Bukan saat dimuat via require("auto_malady_4aid") atau loadfile/dofile)
if ... == nil and type(getBot) == "function" and getBot() then
    M.runCure()
end

return M
