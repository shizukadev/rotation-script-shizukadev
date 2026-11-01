-- auto_malady_4aid.lua
-- Alur otomatis navigasi malady / surg area di world 4AID untuk Lucifer v2.86
-- Alur:
-- 1. Warp ke 4AID -> jalan ke (22, 16) -> masuk portal
-- 2. Jalan ke (61, 12) -> hit adventure key -> jalan ke (64, 12) -> masuk portal
-- 3. Jalan ke (50, 15) -> buka adventure door -> pilih button0 (SURG AREA)

local bot = getBot()
if not bot then
    print("[Error] Bot context tidak ditemukan.")
    return
end

local TARGET_WORLD = "4AID"

local function waitOnline()
    while bot.status ~= BotStatus.online do
        sleep(1000)
    end
    return true
end

local function warpTo(world)
    if not waitOnline() then return false end
    if bot:isInWorld(world) and bot:isInWorld() then return true end

    bot:warp(world)
    for _ = 1, 30 do
        sleep(1000)
        if bot:isInWorld(world) and bot:isInWorld() then
            sleep(1000)
            return true
        end
        if not waitOnline() then return false end
    end
    return false
end

local function walkTo(x, y)
    if not waitOnline() then return false end
    if bot.x == x and bot.y == y then return true end

    local ok = bot:findPath(x, y)
    sleep(500)
    return ok or (bot.x == x and bot.y == y)
end

local function enterPortal(x, y)
    if type(bot.enter) == "function" then
        bot:enter()
    end
    bot:hit(x, y)
    sleep(400)
end

-- Hook dialog request untuk auto-submit packet adventure door
local function sendAdventureDoorPacket(tx, ty, btn)
    local pkt = string.format("action|dialog_return\ndialog_name|adventure_door\ntilex|%d|\ntiley|%d|\nbuttonClicked|%s\n", tx, ty, btn)
    if type(bot.sendPacket) == "function" then
        bot:sendPacket(2, pkt)
    elseif type(bot.enter) == "function" then
        pcall(function() bot:enter(btn) end)
    end
end

local function registerDialogHook()
    if type(addEvent) == "function" and type(Event) == "table" and Event.variantlist then
        pcall(function()
            addEvent(Event.variantlist, function(varlist)
                if not varlist or type(varlist.get) ~= "function" then return end
                local v0 = varlist:get(0)
                local name = v0 and (v0.getString and v0:getString() or tostring(v0)) or ""
                if name:find("OnDialogRequest") then
                    local v1 = varlist:get(1)
                    local content = v1 and (v1.getString and v1:getString() or tostring(v1)) or ""
                    if content:find("adventure_door") and content:find("button0") then
                        sendAdventureDoorPacket(50, 15, "button0")
                    end
                end
            end)
        end)
    end
end

local function run()
    registerDialogHook()

    print("[Step 1] Menuju world " .. TARGET_WORLD .. "...")
    if not warpTo(TARGET_WORLD) then
        print("[Error] Gagal warp ke " .. TARGET_WORLD)
        return false
    end

    print("[Step 1] Berjalan ke portal (22, 16)...")
    walkTo(22, 16)
    enterPortal(22, 16)
    sleep(1500)

    print("[Step 2] Mengambil adventure key di (61, 12)...")
    walkTo(61, 12)
    bot:hit(61, 12)
    sleep(800)

    print("[Step 2] Berjalan ke portal (64, 12)...")
    walkTo(64, 12)
    enterPortal(64, 12)
    sleep(1500)

    print("[Step 3] Berjalan ke adventure door (50, 15)...")
    walkTo(50, 15)

    -- Masuk adventure door via bot:enter() + kirim dialog packet pilihan button0
    if type(bot.enter) == "function" then
        bot:enter()
    end
    bot:hit(50, 15)
    sleep(500)
    sendAdventureDoorPacket(50, 15, "button0")
    sleep(1000)

    print("[Selesai] Berhasil masuk ke SURG AREA.")
    return true
end

run()
