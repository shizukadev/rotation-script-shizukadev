-- 4AID jadi tujuan utama (tanpa batas level); BPJS hanya setelah >5 kegagalan.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()

local a = assert(s:find('local function hospitalForLevel', 1, true))
local z = assert(s:find('local function checkAndDispatchHospital', a, true))
local choose = assert(load(s:sub(a, z - 1) .. 'return hospitalForLevel'))()
assert(choose(16) == '4AID' and choose(35) == '4AID' and choose(36) == '4AID' and choose(120) == '4AID',
    'semua level >=16 harus memakai 4AID')
assert(choose(15) == nil and choose(11) == nil, 'level <16 tetap tanpa rute custom')
assert(choose(nil) == nil and choose('36') == nil and choose(35.5) == nil and choose(0 / 0) == nil,
    'level invalid tidak ditebak')

-- Dispatcher: 6 kegagalan 4AID berturut-turut -> BPJS; sembuh mereset hitungan.
local d = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local e = assert(s:find('\nlocal farmLabel', d, true))
local code = s:sub(d, e - 1) .. '\nreturn checkAndDispatchHospital'

local function run(rounds, cureOnRound)
    local now = 1000
    local world = nil
    local st = { pending = false, fails = 0 }
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
                    st.fails = st.fails + 1
                    if cureOnRound and st.fails >= cureOnRound then return 'cured' end
                    return false
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
    -- Jalankan fungsi produksi sekali per ronde; cooldown 0 agar bisa diulang.
    local fn = assert(load(code, '@fallback', 't', env))()
    local seen = {}
    for i = 1, rounds do
        now = now + 1000
        world = nil
        fn()
        seen[#seen + 1] = world
    end
    return seen
end

local seen = run(6)
for i = 1, 6 do
    assert(seen[i] == '4AID', 'ronde ' .. i .. ' harus 4AID, dapat ' .. tostring(seen[i]))
end
local seen7 = run(7)
assert(seen7[6] == '4AID', 'kegagalan ke-6 masih 4AID')
assert(seen7[7] == 'BPJS', 'setelah >5 kegagalan harus pindah ke BPJS, dapat ' .. tostring(seen7[7]))

print('PASS prioritas 4AID tanpa batas level; fallback BPJS hanya setelah lebih dari 5 kegagalan')
