-- World acak 5 huruf hanya untuk penyakit native (Chicken Feet/Grumbleteeth),
-- level <16, sekali per episode, dan tidak saat stop manual.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()

local a = assert(s:find('local RANDOM_WORLD_LEN', 1, true))
local z = assert(s:find('local function hospitalForLevel', a, true))
local gen = assert(load(s:sub(a, z - 1) .. '\nreturn randomWorldName'))()

for _ = 1, 200 do
    local name = gen()
    assert(#name == 5 and name:match('^[A-Z]+$'), 'nama world harus 5 huruf besar: ' .. tostring(name))
end
local seen, n = {}, 0
for _ = 1, 50 do seen[gen()] = true end
for _ in pairs(seen) do n = n + 1 end
assert(n > 1, 'generator tidak boleh konstan')

local d = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local e = assert(s:find('\nlocal farmLabel', d, true))
local code = s:sub(d, e - 1) .. '\nreturn checkAndDispatchHospital'

-- steps: daftar {sick=id} atau {healthy=true}
local function run(level, steps, opts)
    opts = opts or {}
    local warps, i = {}, 0
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = level, name = 'BOT_LVL',
                auto_malady = { enabled = true, auto_chicken_feet = true, auto_grumbleteeth = true },
                say = function() end, isInWorld = function() return true end,
                warp = function(_, w) warps[#warps + 1] = w end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function()
                    i = i + 1
                    local step = steps[i] or { healthy = true }
                    if step.healthy then return false, 0 end
                    return true, step.sick
                end,
                checkNeedsHospital = function()
                    local step = steps[i] or { healthy = true }
                    local id = step.sick
                    return (id == 1 or id == 2), id
                end,
                runCure = function() return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return true end,
        recoveryStatus = { active = false, known = true, checking = false },
        hospitalPending = false, shouldResumeAfterCure = true,
        farmRunIntent = opts.intent ~= false,
        intentionalStop = opts.manual == true,
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
    for _ = 1, #steps do fn() end
    return warps
end

-- 1. Chicken Feet -> Healthy, lalu Healthy berulang: tepat satu warp.
local w = run(12, { { sick = 3 }, { healthy = true }, { healthy = true }, { healthy = true } })
assert(#w == 1, 'harus tepat satu warp per episode, dapat ' .. #w)
assert(w[1] and w[1]:match('^[A-Z][A-Z][A-Z][A-Z][A-Z]$'), 'tujuan harus 5 huruf besar')

-- 2. Episode kedua memicu warp kedua.
w = run(12, { { sick = 3 }, { healthy = true }, { sick = 4 }, { healthy = true } })
assert(#w == 2, 'episode kedua harus warp lagi, dapat ' .. #w)

-- 3. Torn (custom hospital) tidak memicu warp.
w = run(12, { { sick = 1 }, { healthy = true }, { healthy = true } })
assert(#w == 0, 'penyakit target custom tidak boleh memicu world acak, dapat ' .. #w)

-- 4. Stop manual: tidak ada warp.
w = run(12, { { sick = 3 }, { healthy = true } }, { manual = true })
assert(#w == 0, 'stop manual tidak boleh memicu warp')

-- 5. Intent farming hilang: tidak ada warp.
w = run(12, { { sick = 3 }, { healthy = true } }, { intent = false })
assert(#w == 0, 'tanpa intent farming tidak boleh warp')

-- 6. Level >=16: tidak ada warp.
w = run(40, { { sick = 3 }, { healthy = true } })
assert(#w == 0, 'level >=16 tidak boleh dipindah')

-- 7. Healthy tanpa episode: tidak ada warp.
w = run(12, { { healthy = true }, { healthy = true } })
assert(#w == 0, 'tanpa episode penyakit tidak boleh warp')

-- 8. Chicken Feet -> Torn -> Healthy: episode native dibatalkan, tanpa warp.
w = run(12, { { sick = 3 }, { sick = 1 }, { healthy = true }, { healthy = true } })
assert(#w == 0, 'peralihan ke penyakit custom harus membatalkan episode native, dapat ' .. #w)

-- 9. Opsi native dimatikan: tidak dianggap episode native.
local function runOptsOff()
    local warps, i = {}, 0
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = 12, name = 'BOT_OFF',
                auto_malady = { enabled = true, auto_chicken_feet = false, auto_grumbleteeth = false },
                say = function() end, isInWorld = function() return true end,
                warp = function(_, x) warps[#warps + 1] = x end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function()
                    i = i + 1
                    if i == 1 then return true, 3 end
                    return false, 0
                end,
                checkNeedsHospital = function() return false, 3 end,
                runCure = function() return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return true end,
        recoveryStatus = { active = false, known = true, checking = false },
        hospitalPending = false, shouldResumeAfterCure = true,
        farmRunIntent = true, intentionalStop = false,
        beginSpamRecovery = function() end, resumeFarming = function() return true end,
        setRotationEnabled = function() end, updateNativeMaladyForLevel = function() return true end,
        randomWorldName = gen, RANDOM_WORLD_LEN = 5,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        nativeMaladyEpisode = false,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 0, lastHospitalAttempt = 0,
        os = { time = function() return 1000 end }, print = function() end,
    }, { __index = _G })
    local fn = assert(load(code, '@random-world', 't', env))()
    fn(); fn(); fn()
    return warps
end
w = runOptsOff()
assert(#w == 0, 'opsi native mati tidak boleh memicu warp, dapat ' .. #w)

local function runWithMaladyField(autoMalady, steps)
    local warps, i = {}, 0
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = 12, name = 'BOT_FLD',
                auto_malady = autoMalady,
                say = function() end, isInWorld = function() return true end,
                warp = function(_, w) warps[#warps + 1] = w end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function()
                    i = i + 1
                    local step = steps[i] or { healthy = true }
                    if step.healthy then return false, 0 end
                    return true, step.sick
                end,
                checkNeedsHospital = function()
                    local step = steps[i] or { healthy = true }
                    local id = step.sick
                    return (id == 1 or id == 2), id
                end,
                runCure = function() return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return true end,
        recoveryStatus = { active = false, known = true, checking = false },
        hospitalPending = false, shouldResumeAfterCure = true,
        farmRunIntent = true, intentionalStop = false,
        beginSpamRecovery = function() end, resumeFarming = function() return true end,
        setRotationEnabled = function() end, updateNativeMaladyForLevel = function() return true end,
        randomWorldName = gen, RANDOM_WORLD_LEN = 5,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        nativeMaladyEpisode = false,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 0, lastHospitalAttempt = 0,
        os = { time = function() return 1000 end }, print = function() end,
    }, { __index = _G })
    local fn = assert(load(code, '@random-world', 't', env))()
    for _ = 1, #steps do fn() end
    return warps
end

-- 10. Field native hilang (nil) bukan berarti aktif.
w = runWithMaladyField({}, { { sick = 3 }, { healthy = true } })
assert(#w == 0, 'field native hilang tidak boleh memicu warp, dapat ' .. #w)

-- 11. Getter field melempar error -> tidak dianggap episode.
local throwing = setmetatable({}, { __index = function() error('host menolak field') end })
w = runWithMaladyField(throwing, { { sick = 3 }, { healthy = true } })
assert(#w == 0, 'getter yang melempar error tidak boleh memicu warp, dapat ' .. #w)

-- 12. Opsi eksplisit false -> tidak dianggap episode.
w = runWithMaladyField({ enabled = true, auto_chicken_feet = false, auto_grumbleteeth = false },
    { { sick = 3 }, { healthy = true } })
assert(#w == 0, 'opsi native OFF tidak boleh memicu warp, dapat ' .. #w)

-- 13. Nilai aktif eksplisit true -> tetap warp.
w = runWithMaladyField({ enabled = true, auto_chicken_feet = true, auto_grumbleteeth = true },
    { { sick = 3 }, { healthy = true } })
assert(#w == 1, 'opsi native ON harus memicu warp, dapat ' .. #w)

print('PASS world acak: hanya penyakit native level <16, sekali per episode, hormati stop manual/intent')
