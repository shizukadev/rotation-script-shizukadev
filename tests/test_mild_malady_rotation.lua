-- Penyakit ringan (Chicken Feet / Grumbleteeth) tidak boleh mematikan rotasi.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()
local a = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local z = assert(s:find('\nlocal farmLabel', a, true))
local code = s:sub(a, z - 1) .. '\nreturn checkAndDispatchHospital'

local function run(id, clear)
    local routed, toggles, pending = 0, 0, false
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = 20, name = 'T', say = function() end,
                isInWorld = function() return true end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function() return true, id end,
                checkNeedsHospital = function() return id == 1 or id == 2, id end,
                runCure = function() routed = routed + 1; return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return clear end,
        recoveryStatus = { active = false, known = clear, checking = false },
        hospitalPending = false, shouldResumeAfterCure = true,
        farmRunIntent = true, intentionalStop = false,
        beginSpamRecovery = function() end,
        resumeFarming = function() return true end,
        setRotationEnabled = function() toggles = toggles + 1 end,
        updateNativeMaladyForLevel = function() return true end,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 180, lastHospitalAttempt = 0,
        os = { time = function() return 1000 end },
        print = function() end,
    }, { __index = _G })
    local fn = assert(load(code, '@mild', 't', env))()
    local ok, res = pcall(fn)
    return routed, toggles, env.hospitalPending, ok, res
end

-- Chicken Feet (3) dengan status Recovering belum terverifikasi: rotasi tetap hidup.
local routed, toggles, pending, ok = run(3, false)
assert(ok, 'dispatcher tidak boleh error untuk penyakit ringan')
assert(routed == 0, 'penyakit ringan tidak boleh memicu perjalanan rumah sakit')
assert(toggles == 0, 'penyakit ringan tidak boleh mematikan rotasi')
assert(pending == false, 'penyakit ringan tidak boleh menandai hospitalPending')

-- Grumbleteeth (4) juga ringan.
routed, toggles, pending = run(4, false)
assert(routed == 0 and toggles == 0 and pending == false, 'Grumbleteeth tidak boleh menghentikan rotasi')

-- Kontrol: Torn (1) dengan status belum terverifikasi tetap menahan rotasi.
routed, toggles, pending = run(1, false)
assert(routed == 0 and toggles == 1 and pending == true, 'Torn + status UNKNOWN harus menahan rotasi')

print('PASS malady ringan (3/4) tidak mematikan rotasi; Torn tetap ditahan saat status UNKNOWN')
