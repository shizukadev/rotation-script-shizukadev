-- Transisi: jeda pengobatan internal -> penyakit non-target -> resume sesuai intent.
local f = assert(io.open('engine.lua')); local s = f:read('*a'):gsub('\r', ''); f:close()
local a = assert(s:find('local function checkAndDispatchHospital()', 1, true))
local z = assert(s:find('\nlocal farmLabel', a, true))
local code = s:sub(a, z - 1) .. '\nreturn checkAndDispatchHospital'

local function run(opts)
    opts = opts or {}
    local resumed, routed, toggles = 0, 0, 0
    local logs = {}
    local env = setmetatable({
        bot = { status = 1, rotation = {}, level = 20, name = 'BOT_X', say = function() end,
                isInWorld = function() return true end },
        BotStatus = { online = 1 },
        getHospitalModule = function()
            return {
                hasAnyMalady = function() return true, opts.id or 3 end,
                checkNeedsHospital = function() local id = opts.id or 3; return (id == 1 or id == 2), id end,
                runCure = function() routed = routed + 1; return 'cured' end,
            }
        end,
        checkRecoveryStatus = function() return opts.clear == true end,
        recoveryStatus = { active = opts.active == true, known = opts.known == true, checking = false },
        hospitalPending = opts.pending == true,
        shouldResumeAfterCure = opts.shouldResume == true,
        farmRunIntent = opts.intent ~= false,
        intentionalStop = opts.manual == true,
        beginSpamRecovery = function() end,
        resumeFarming = function() resumed = resumed + 1; return true end,
        setRotationEnabled = function() toggles = toggles + 1 end,
        updateNativeMaladyForLevel = function() return true end,
        hospitalForLevel = function() return '4AID' end, FOUR_AID_MAX_FAILS = 5, fourAidFails = 0,
        updateWebhook = function() end, sendWebhookNotification = function() end,
        HOSPITAL_COOLDOWN = 180, lastHospitalAttempt = 0,
        os = { time = function() return 1000 end },
        print = function(m) logs[#logs + 1] = tostring(m) end,
    }, { __index = _G })
    local fn = assert(load(code, '@mild-transition', 't', env))()
    fn()
    return resumed, routed, toggles, env.hospitalPending, table.concat(logs, '\n')
end

-- 1. Jeda internal aktif (hospitalPending) lalu malady berubah jadi Chicken Feet.
local resumed, routed, _, pending, logs = run({ id = 3, pending = true, shouldResume = true })
assert(resumed == 1, 'Chicken Feet setelah jeda internal harus resume rotasi, resumed=' .. resumed)
assert(routed == 0, 'penyakit ringan tidak boleh memicu perjalanan rumah sakit')
assert(pending == false, 'hospitalPending harus dilepas untuk penyakit ringan')
assert(logs:find('BOT_X', 1, true), 'log pelepasan jeda harus memuat nama bot')

-- 2. Stop manual tidak boleh ditimpa.
resumed = run({ id = 3, pending = true, shouldResume = true, manual = true })
assert(resumed == 0, 'stop manual tidak boleh diaktifkan ulang oleh penyakit ringan')

-- 3. Tanpa intent farming, tidak resume.
resumed = run({ id = 3, pending = true, shouldResume = true, intent = false })
assert(resumed == 0, 'tanpa intent farming rotasi tidak boleh dinyalakan')

-- 4. Recovering aktif + Chicken Feet: tidak menahan, tidak dispatch.
resumed, routed, toggles = run({ id = 3, pending = false, active = true, known = true })
assert(routed == 0 and toggles == 0, 'Chicken Feet + Recovering tidak boleh menyentuh rotasi')

-- 5. Recovering terverifikasi hilang + Torn: harus masuk 4AID.
resumed, routed, toggles = run({ id = 1, pending = false, clear = true, known = true })
assert(routed == 1, 'Torn dengan Recovering terverifikasi hilang harus dispatch ke 4AID')

-- 6. Torn + Recovering aktif: farming dilanjutkan, bukan ke rumah sakit.
resumed, routed = run({ id = 1, pending = false, active = true, known = true, shouldResume = true })
assert(routed == 0, 'Torn + Recovering tidak boleh dispatch')
assert(resumed == 1, 'Torn + Recovering harus melanjutkan rotasi sesuai intent')

-- 7. Jeda internal + Chicken Feet + Recovering AKTIF: jeda harus dilepas.
resumed, routed, _, pending = run({ id = 3, pending = true, active = true, known = true, shouldResume = true })
assert(resumed == 1, 'Chicken Feet + Recovering aktif setelah jeda harus resume, resumed=' .. resumed)
assert(pending == false, 'hospitalPending harus dilepas walau Recovering aktif')
assert(routed == 0, 'penyakit ringan tidak boleh dispatch')

-- 8. Varian stop manual pada kondisi yang sama: tidak boleh menyalakan ulang.
resumed = run({ id = 3, pending = true, active = true, known = true, shouldResume = true, manual = true })
assert(resumed == 0, 'stop manual tetap dihormati saat Recovering aktif')

print('PASS transisi: Chicken Feet melepas jeda & resume (termasuk Recovering aktif, kecuali stop manual), Torn menunggu Recovering lalu ke 4AID')
