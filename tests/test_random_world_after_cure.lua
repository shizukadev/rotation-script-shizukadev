-- World acak 5 huruf dipicu transisi penyakit native (level <16) menjadi Healthy.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()

local a = assert(s:find('local RANDOM_WORLD_LEN', 1, true))
local z = assert(s:find('local function hospitalForLevel', a, true))
local gen = assert(load(s:sub(a, z - 1) .. '\nreturn randomWorldName'))()

for _ = 1, 200 do
    local name = gen()
    assert(#name == 5, 'nama world harus 5 huruf, dapat ' .. tostring(name))
    assert(name:match('^[A-Z]+$'), 'nama world harus huruf besar, dapat ' .. tostring(name))
end
local seen, n = {}, 0
for _ = 1, 50 do seen[gen()] = true end
for _ in pairs(seen) do n = n + 1 end
assert(n > 1, 'generator tidak boleh selalu menghasilkan nama sama')

local d = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local e = assert(s:find('\nlocal farmLabel', d, true))
local code = s:sub(d, e - 1) .. '\nreturn checkAndDispatchHospital'

-- urutan hasil hasAnyMalady: true,id  ->  false,0
local function run(level, sickId, healthyAfter)
    local warped, calls = nil, 0
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = level, name = 'BOT_LVL',
                say = function() end, isInWorld = function() return true end,
                warp = function(_, w) warped = w end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function()
                    calls = calls + 1
                    if calls <= healthyAfter then return true, sickId end
                    return false, 0
                end,
                checkNeedsHospital = function() return false, sickId end,
                runCure = function() return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return true end,
        recoveryStatus = { active = false, known = true, checking = false },
        hospitalPending = false, shouldResumeAfterCure = true,
        farmRunIntent = true, intentionalStop = false,
        beginSpamRecovery = function() end,
        resumeFarming = function() return true end,
        setRotationEnabled = function() end,
        updateNativeMaladyForLevel = function() return true end,
        randomWorldName = gen, RANDOM_WORLD_LEN = 5,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        nativeMaladyEpisode = false,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 0, lastHospitalAttempt = 0,
        os = { time = function() return 1000 end },
        print = function() end,
    }, { __index = _G })
    local fn = assert(load(code, '@random-world', 't', env))()
    for _ = 1, 3 do fn() end
    return warped
end

-- Sakit (Chicken Feet) lalu Healthy: warp sekali ke world acak 5 huruf.
local warped = run(12, 3, 1)
assert(warped and warped:match('^[A-Z][A-Z][A-Z][A-Z][A-Z]$'),
    'level 12 harus warp ke world acak 5 huruf, dapat ' .. tostring(warped))

-- Level >=16 tidak dipindah walau sembuh dari penyakit native.
assert(run(40, 3, 1) == nil, 'level >=16 tidak boleh dipindah ke world acak')

-- Selalu Healthy: tidak ada episode, tidak ada warp.
assert(run(12, 3, 0) == nil, 'tanpa episode penyakit tidak boleh warp')

print('PASS world acak 5 huruf: transisi native sakit -> Healthy pada level <16, sekali per episode')
