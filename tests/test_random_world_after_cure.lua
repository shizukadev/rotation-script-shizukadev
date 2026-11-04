-- Setelah sembuh, bot dengan AutoMalady native (level <16) pindah ke world acak 5 huruf.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()

local a = assert(s:find('local RANDOM_WORLD_LEN', 1, true))
local z = assert(s:find('local function hospitalForLevel', a, true))
local gen = assert(load(s:sub(a, z - 1) .. '\nreturn randomWorldName'))()

for _ = 1, 200 do
    local name = gen()
    assert(#name == 5, 'nama world harus 5 huruf, dapat ' .. tostring(name))
    assert(name:match('^[A-Z]+$'), 'nama world harus huruf besar, dapat ' .. tostring(name))
end
local seen = {}
for _ = 1, 50 do seen[gen()] = true end
local n = 0
for _ in pairs(seen) do n = n + 1 end
assert(n > 1, 'generator tidak boleh selalu menghasilkan nama sama')

local d = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local e = assert(s:find('\nlocal farmLabel', d, true))
local code = s:sub(d, e - 1) .. '\nreturn checkAndDispatchHospital'

local function run(level)
    local warped, resumed = nil, 0
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = level, name = 'BOT_LVL',
                say = function() end, isInWorld = function() return true end,
                warp = function(_, w) warped = w end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function() return true, 1 end,
                checkNeedsHospital = function() return true, 1 end,
                runCure = function() return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return true end,
        recoveryStatus = { active = false, known = true, checking = false },
        hospitalPending = true, shouldResumeAfterCure = true,
        farmRunIntent = true, intentionalStop = false,
        beginSpamRecovery = function() end,
        resumeFarming = function() resumed = resumed + 1; return true end,
        setRotationEnabled = function() end,
        updateNativeMaladyForLevel = function() return true end,
        randomWorldName = gen, RANDOM_WORLD_LEN = 5, RANDOM_WORLD_MIN_LEVEL = 16,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 0, lastHospitalAttempt = 0,
        os = { time = function() return 1000 end },
        print = function() end,
    }, { __index = _G })
    assert(load(code, '@random-world', 't', env))()()
    return warped, resumed
end

local warped, resumed = run(12)
assert(warped and warped:match('^[A-Z][A-Z][A-Z][A-Z][A-Z]$'), 'level 12 harus warp ke world acak 5 huruf, dapat ' .. tostring(warped))
assert(resumed == 1, 'setelah warp rotasi tetap harus dilanjutkan')

warped = run(40)
assert(warped == nil, 'level >=16 tidak boleh dipindah ke world acak')

print('PASS world acak 5 huruf: dibuat setelah sembuh hanya untuk level <16, rotasi tetap dilanjutkan')
