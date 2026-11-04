-- 4AID tujuan utama (tanpa batas level); BPJS hanya setelah >5 kegagalan MASUK.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()

local a = assert(s:find('local function hospitalForLevel', 1, true))
local z = assert(s:find('local function checkAndDispatchHospital', a, true))
local choose = assert(load(s:sub(a, z - 1) .. 'return hospitalForLevel'))()
assert(choose(16) == '4AID' and choose(35) == '4AID' and choose(36) == '4AID' and choose(120) == '4AID',
    'semua level >=16 harus memakai 4AID')
assert(choose(15) == nil and choose(11) == nil, 'level <16 tetap tanpa rute custom')
assert(choose(nil) == nil and choose('36') == nil and choose(35.5) == nil and choose(0 / 0) == nil,
    'level invalid tidak ditebak')

local d = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local e = assert(s:find('\nlocal farmLabel', d, true))
local code = s:sub(d, e - 1) .. '\nreturn checkAndDispatchHospital'

-- results: daftar hasil runCure per ronde ('enter_failed' | false | 'cured' | 'recovering')
local function run(results)
    local now = 1000
    local world = nil
    local i = 0
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = 20, name = 'T', say = function() end,
                isInWorld = function() return true end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function() return true, 1 end,
                checkNeedsHospital = function() return true, 1 end,
                runCure = function(_, _, _, target)
                    world = target
                    i = i + 1
                    return results[i] or 'cured'
                end,
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
        hospitalForLevel = choose, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 0,
        lastHospitalAttempt = 0,
        os = { time = function() return now end },
        print = function() end,
    }, { __index = _G })
    local fn = assert(load(code, '@fallback', 't', env))()
    local seen = {}
    for _ = 1, #results do
        now = now + 1000
        world = nil
        fn()
        seen[#seen + 1] = world
    end
    return seen
end

-- Enam kegagalan masuk berturut-turut: ronde 1..6 tetap 4AID, ronde 7 BPJS.
local seen = run({ 'enter_failed', 'enter_failed', 'enter_failed', 'enter_failed', 'enter_failed', 'enter_failed', 'enter_failed' })
for i = 1, 6 do
    assert(seen[i] == '4AID', 'ronde ' .. i .. ' harus 4AID, dapat ' .. tostring(seen[i]))
end
assert(seen[7] == 'BPJS', 'setelah >5 gagal masuk harus BPJS, dapat ' .. tostring(seen[7]))

-- Gagal surgery (masuk berhasil) tidak dihitung: hitungan reset.
local mixed = run({ 'enter_failed', 'enter_failed', 'enter_failed', false, 'enter_failed', 'enter_failed', 'enter_failed' })
assert(mixed[4] == '4AID' and mixed[7] == '4AID', 'gagal surgery tidak boleh memicu fallback BPJS')

-- Sembuh mereset hitungan.
local cured = run({ 'enter_failed', 'enter_failed', 'enter_failed', 'cured', 'enter_failed', 'enter_failed', 'enter_failed' })
assert(cured[7] == '4AID', 'sembuh harus mereset hitungan kegagalan masuk')

print('PASS prioritas 4AID tanpa batas level; BPJS hanya setelah >5 kegagalan MASUK world')
