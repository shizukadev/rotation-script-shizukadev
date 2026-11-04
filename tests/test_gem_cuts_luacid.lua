-- Gem Cuts: tanpa Recovering -> 4AID; dengan Recovering (gagal surgery) -> tunggu di luacid.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()
local a = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local z = assert(s:find('\nlocal farmLabel', a, true))
local code = s:sub(a, z - 1) .. '\nreturn checkAndDispatchHospital'

local function run(opts)
    local warps, routed, toggles = {}, 0, 0
    local gemWaitNext = 0
    local botMock = { status = 1, rotation = {}, level = 20, name = 'BOT_GEM',
                auto_malady = { enabled = true },
                say = function() end,
                isInWorld = function(_, w) return w == nil or w == 'HOME' end,
                warp = function(_, w) warps[#warps + 1] = w end }
    local function waitGemCutsWorld()
        if botMock.status ~= 1 then return end
        local now = 1000
        if now < gemWaitNext then return end
        if botMock:isInWorld('luacid') then return end
        gemWaitNext = now + 30
        botMock:warp('luacid')
    end
    local env = setmetatable({
        bot = botMock,
        waitGemCutsWorld = waitGemCutsWorld,
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function() return true, 2 end,
                checkNeedsHospital = function() return true, 2 end,
                runCure = function() routed = routed + 1; return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return opts.clear == true end,
        recoveryStatus = { active = opts.active == true, known = true, checking = false },
        hospitalPending = false, shouldResumeAfterCure = true,
        farmRunIntent = true, intentionalStop = opts.manual == true,
        gemWaitActive = false, gemWaitNextWarp = 0,
        beginSpamRecovery = function() end,
        resumeFarming = function() return true end,
        setRotationEnabled = function() toggles = toggles + 1 end,
        updateNativeMaladyForLevel = function() return true end,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        nativeMaladyEpisode = false, randomWorldName = function() return 'ABCDE' end,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 0, lastHospitalAttempt = 0,
        lockoutTriggered = false,
        os = { time = function() return 1000 end },
        print = function() end,
    }, { __index = _G })
    local fn = assert(load(code, '@gem-recovering', 't', env))()
    fn()
    return warps, routed, toggles, env
end

-- 1. Gem Cuts + Recovering: warp ke luacid, tidak ke 4AID, rotasi OFF.
local warps, routed, toggles, env = run({ active = true })
assert(#warps == 1 and warps[1] == 'luacid', 'harus warp ke luacid, dapat ' .. tostring(warps[1]))
assert(routed == 0, 'Gem Cuts + Recovering tidak boleh dispatch surgery')
assert(toggles == 1, 'rotasi harus dimatikan saat menunggu di luacid')
assert(env.gemWaitActive == true, 'gemWaitActive harus aktif agar retry luacid berjalan')
assert(env.hospitalPending == true, 'hospitalPending harus tetap ditahan')

-- 2. Stop manual: tidak boleh warp.
warps = run({ active = true, manual = true })
assert(#warps == 0, 'stop manual tidak boleh memicu perjalanan ke luacid')

-- 3. Gem Cuts tanpa Recovering: tetap ke 4AID (surgery), bukan luacid.
warps, routed = run({ active = false, clear = true })
assert(routed == 1, 'Gem Cuts tanpa Recovering harus dispatch ke rumah sakit')
for _, w in ipairs(warps) do
    assert(w ~= 'luacid', 'Gem Cuts tanpa Recovering tidak boleh menunggu di luacid')
end

print('PASS Gem Cuts: +Recovering menunggu di luacid (hormati stop manual), tanpa Recovering ke 4AID')
