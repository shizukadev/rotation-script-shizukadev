-- auto_malady_4aid.lua
-- Alur otomatis navigasi malady / surg area di world 4AID untuk Lucifer v2.86
-- Bisa dijalankan mandiri atau dipanggil via require/include sebagai fungsi checkAndCureMalady4AID()

local M = {}

local TARGET_WORLD = "4AID"
local CURE_TARGET_IDS = { [1] = true, [2] = true } -- 1: Torn Muscle, 2: Gem Cuts

function M.checkNeedsHospital(botCtx)
    local b = botCtx or (type(getBot) == "function" and getBot())
    if not b then return false, 0 end
    local mid = tonumber(b.malady)
    if not mid or mid == 0 then
        if type(b.getMaladyDuration) == "function" and b:getMaladyDuration() > 0 then
            mid = tonumber(b.malady) or 0
        end
    end
    return (mid and CURE_TARGET_IDS[mid] == true), (mid or 0)
end

local function waitOnline(b)
    while b.status ~= BotStatus.online do sleep(1000) end
    return true
end

local function warpTo(b, world)
    if not waitOnline(b) then return false end
    if b:isInWorld(world) and b:isInWorld() then return true end
    b:warp(world)
    for _ = 1, 30 do
        sleep(1000)
        if b:isInWorld(world) and b:isInWorld() then sleep(1000); return true end
        if not waitOnline(b) then return false end
    end
    return false
end

local function walkTo(b, x, y)
    if not waitOnline(b) then return false end
    if b.x == x and b.y == y then return true end
    local ok = b:findPath(x, y)
    sleep(500)
    return (b.x == x and b.y == y) or (ok and (b.x == x and b.y == y))
end

local function enterPortal(b, x, y)
    if type(b.enter) == "function" then
        b:enter()
    end
    b:hit(x, y)
    sleep(400)
end

local function sendAdventureDoorPacket(b, tx, ty, btn)
    local pkt = string.format("action|dialog_return\ndialog_name|adventure_door\ntilex|%d|\ntiley|%d|\nbuttonClicked|%s\n", tx, ty, btn)
    if type(b.sendPacket) == "function" then
        b:sendPacket(2, pkt)
    end
end

function M.runCure(botCtx)
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

    local dialogHookRegistered = false
    local function dialogCallback(varlist)
        if not varlist or type(varlist.get) ~= "function" then return end
        local v0 = varlist:get(0)
        local name = v0 and (v0.getString and v0:getString() or tostring(v0)) or ""
        if name:find("OnDialogRequest") then
            local v1 = varlist:get(1)
            local content = v1 and (v1.getString and v1:getString() or tostring(v1)) or ""
            if content:find("adventure_door") and content:find("button0") then
                sendAdventureDoorPacket(b, 50, 15, "button0")
            end
        end
    end

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
    if not walkTo(b, 22, 16) then
        print("[Error] Gagal findPath ke portal (22, 16)")
        cleanup()
        return false
    end
    enterPortal(b, 22, 16)
    sleep(1500)

    print("[Step 2] Mengambil adventure key di (61, 12)...")
    if not walkTo(b, 61, 12) then
        print("[Error] Gagal findPath ke adventure key (61, 12)")
        cleanup()
        return false
    end
    b:hit(61, 12)
    sleep(800)

    print("[Step 2] Berjalan ke portal (64, 12)...")
    if not walkTo(b, 64, 12) then
        print("[Error] Gagal findPath ke portal (64, 12)")
        cleanup()
        return false
    end
    enterPortal(b, 64, 12)
    sleep(1500)

    print("[Step 3] Berjalan ke adventure door (50, 15)...")
    if not walkTo(b, 50, 15) then
        print("[Error] Gagal findPath ke adventure door (50, 15)")
        cleanup()
        return false
    end

    if type(b.enter) == "function" then
        b:enter()
    end
    b:hit(50, 15)
    sleep(500)
    sendAdventureDoorPacket(b, 50, 15, "button0")
    sleep(1000)

    cleanup()
    print("[Selesai] Berhasil masuk ke SURG AREA.")
    return true
end

-- Eksekusi otomatis jika dijalankan sebagai standalone script
if ... ~= "module" and type(getBot) == "function" and getBot() then
    M.runCure()
end

return M
