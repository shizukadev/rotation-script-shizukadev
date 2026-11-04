local M = assert(loadfile('webhook_monitor.lua'))()
local t, messages = 0, {}
local b = {name='TEST',status=0,malady=0,gem_count=50}
function b:isInWorld() return true end
function b:getWorld() return {name='CURRENT'} end
local api = {BotStatus={online=1},os={time=function() return t end},Webhook={new=function()
    local h={}
    function h:send() messages[#messages+1]=self.content;self.message_id='123' end
    function h:edit() messages[#messages+1]=self.content end
    return h
end}}
local c={WEBHOOK={EVENT_NOTIFICATIONS=true,ENABLED=true,URL='https://example.invalid/test'},OFFLINE_ALERT={TIMEOUT_MINUTES=5,DISCORD_USER_ID='922775541097066576'}}
local m=M.new(b,c,api)
local function count(pattern)
 local n=0;for _,s in ipairs(messages) do if s:find(pattern,1,true) then n=n+1 end end;return n
end
m.tick('Starting');t=299;m.tick();assert(count('<@')==0)
t=300;m.tick();assert(count('<@922775541097066576>')==1)
t=600;m.tick();assert(count('<@')==1)
b.status=1;b.malady=1;m.tick();m.tick();assert(count('terkena penyakit')==1);assert(count('Torn Punching Muscle')==1)
b.malady='invalid';t=t+5;m.tick();assert(count('sudah hilang')==0)
-- ID nil atau invalid dengan durasi 0 tetap unknown / tidak boleh dianggap sembuh
b.malady='invalid';b.getMaladyDuration=function() return 0 end;t=t+5;m.tick();assert(count('sudah hilang')==0)
b.malady=nil;b.getMaladyDuration=function() return 0 end;t=t+5;m.tick();assert(count('sudah hilang')==0)
b.malady=0;t=t+5;m.tick();t=t+5;m.tick();assert(count('sudah hilang')==1)
-- Uji label penyakit konfirmasi: ID 3 (Chicken Feet), ID 4 (Grumbleteeth), ID 5 (Broken Heart)
b.malady=5;t=t+5;m.tick();t=t+5;m.tick();assert(count('Broken Heart')==1)
b.malady=3;t=t+5;m.tick();t=t+5;m.tick();assert(count('Chicken Feet')==1)
b.malady=4;t=t+5;m.tick();t=t+5;m.tick();assert(count('Grumbleteeth')==1)
b.status=0;t=700;m.tick();t=1000;m.tick();assert(count('<@')==2)
for _,s in ipairs(messages) do assert(not s:find('Target Farm',1,true));assert(not s:find('FARMSECRET',1,true)) end

-- Rotasi: fase dari enum RotationStatus, dan OFF saat enabled=false
api.RotationStatus = { scanning_world = 0, farming_block = 2, planting_seeds = 3 }
b.rotation = { enabled = true, status = 2 }
b.status = 1; t = t + 60; m.tick('Rotasi')
assert(count('**Rotasi:** ON farming_block') >= 1, 'dashboard harus menampilkan fase rotasi')
b.rotation.status = 3; t = t + 60; m.tick('Rotasi')
assert(count('**Rotasi:** ON planting_seeds') >= 1, 'fase harus ikut berubah')
b.rotation.enabled = false; t = t + 60; m.tick('Rotasi')
assert(count('**Rotasi:** OFF') >= 1, 'rotasi mati harus tertulis OFF')
-- userdata yang tidak bisa dibaca = UNKNOWN, bukan OFF
b.rotation = setmetatable({}, { __index = function() error('unreadable') end })
t = t + 60; m.tick('Rotasi')
assert(count('**Rotasi:** UNKNOWN') >= 1, 'rotasi tak terbaca harus UNKNOWN, bukan OFF')
-- enabled terbaca true tapi status tak terbaca
b.rotation = setmetatable({}, {
    __index = function(_, k) if k == 'enabled' then return true end error('unreadable') end,
})
t = t + 60; m.tick('Rotasi')
assert(count('**Rotasi:** ON UNKNOWN') >= 1, 'enabled true + status tak terbaca harus ON UNKNOWN')

print('PASS webhook offline threshold, dedupe, reconnect reset, disease/recovery, unknown guard, current world only')
print('PASS webhook status rotasi: fase RotationStatus, OFF, dan UNKNOWN terpisah')

-- Edit dashboard yang gagal tidak boleh membuat pesan diam selamanya.
do
    local log2, mode = {}, 'send'
    local hooks = { new = function(url)
        local h = { url = url, content = '' }
        function h:send() mode = 'send'; self.message_id = 'NEWID' end
        function h:edit() mode = 'edit'; if h.message_id == 'STALE' then error('unknown message') end end
        return h
    end }
    local b2 = { name = 'B', status = 1, malady = 0, gem_count = 1, rotation = { enabled = true, status = 2 } }
    function b2:isInWorld() return true end
    function b2:getWorld() return { name = 'W' } end
    local t2 = 0
    local api2 = { BotStatus = { online = 1 }, RotationStatus = { farming_block = 2 },
                   os = { time = function() return t2 end }, Webhook = hooks,
                   print = function(s) log2[#log2 + 1] = tostring(s) end }
    local c2 = { WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = true, URL = 'https://example.invalid/h', MESSAGE_ID = 'STALE' },
                 OFFLINE_ALERT = { TIMEOUT_MINUTES = 5 } }
    local m2 = M.new(b2, c2, api2)
    m2.tick('A')                                  -- edit STALE -> gagal -> kirim baru
    t2 = t2 + 60; m2.tick('B')                    -- sekarang edit NEWID
    assert(mode == 'edit', 'failed edit must remain edit')
    local txt = table.concat(log2, '\n')
    assert(txt:find('Request failed', 1, true), 'kegagalan edit harus dilaporkan')
    assert(not txt:find('dashboard terkirim', 1, true), 'failed edit cannot claim delivered')
end

print('PASS webhook: failed edit preserves target and never creates another message')

-- Fase rotasi berubah -> dashboard langsung di-edit, tanpa menunggu interval.
do
    local edits, sends = 0, 0
    local hooks = { new = function()
        local h = {}
        function h:send() sends = sends + 1; self.message_id = 'M1' end
        function h:edit() edits = edits + 1 end
        return h
    end }
    local b3 = { name = 'B', status = 1, malady = 0, gem_count = 1, rotation = { enabled = true, status = 2 } }
    function b3:isInWorld() return true end
    function b3:getWorld() return { name = 'W' } end
    local t3 = 0
    local api3 = { BotStatus = { online = 1 },
                   RotationStatus = { farming_block = 2, planting_seeds = 3, dropping_seeds = 4 },
                   os = { time = function() return t3 end }, Webhook = hooks, print = function() end }
    local m3 = M.new(b3, { WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = true, URL = 'https://x.invalid/h', UPDATE_INTERVAL_SECONDS = 900 } }, api3)
    m3.tick('A')                       -- kirim pertama (send)
    assert(sends == 1 and edits == 0, 'tick pertama harus send')
    t3 = t3 + 5; b3.rotation.status = 3
    m3.tick('A')                       -- fase berubah: harus edit walau interval 900s
    assert(edits == 1, 'perubahan fase harus langsung meng-edit dashboard, edits=' .. edits)
    t3 = t3 + 1; m3.tick('A')          -- fase sama: tidak ada kiriman
    assert(edits == 1 and sends == 1, 'fase sama tidak boleh memicu kiriman')
end

print('PASS webhook: perubahan fase rotasi langsung memperbarui dashboard')

-- Mode Dashboard Global: semua bot ditampilkan dalam 1 dashboard, hanya 1 bot leader yang mengedit
do
    local dashMessages = {}
    local notifyMessages = {}
    local hooks4 = { new = function(url)
        local h = { url = url }
        function h:send()
            if self.content:find('Lucifer Global Dashboard', 1, true) then
                dashMessages[#dashMessages + 1] = { content = self.content, user = self.username }
                self.message_id = 'G1'
            else
                notifyMessages[#notifyMessages + 1] = { content = self.content, user = self.username }
            end
        end
        function h:edit()
            dashMessages[#dashMessages + 1] = { content = self.content, user = self.username }
        end
        return h
    end }
    local botA = { name = 'BOT_ALFA', status = 1, malady = 0, gem_count = 1000, rotation = { enabled = true, status = 2 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_A' } end }
    local botB = { name = 'BOT_BETA', status = 1, malady = 1, gem_count = 2500, rotation = { enabled = true, status = 3 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_B' } end }
    local botC = { name = 'BOT_GAMMA', status = 0, malady = 0, gem_count = 500, rotation = { enabled = false, status = 0 },
                   isInWorld = function() return false end, getWorld = function() return { name = '' } end }
    local allBotsList = { botA, botB, botC }
    local t4 = 100
    local api4 = {
        BotStatus = { online = 1, offline = 0 },
        RotationStatus = { scanning_world = 0, farming_block = 2, planting_seeds = 3 },
        os = { time = function() return t4 end },
        Webhook = hooks4,
        getBots = function() return allBotsList end,
        print = function() end,
    }
-- Mode Dashboard Global: semua bot ditampilkan dalam 1 dashboard via snapshot file, pengirim adalah leader (startbot / LEADER_BOT)
do
    local dashMessages = {}
    local notifyMessages = {}
    local disk = {}
    local fio = { open = function(path, mode)
        if mode == 'w' then return { write = function(_, s) disk[path] = s end, close = function() end } end
        if not disk[path] then return nil end
        return { read = function() return disk[path]:gsub('\n$', '') end, close = function() end }
    end }
    local hooks4 = { new = function(url)
        local h = { url = url }
        function h:send()
            if self.content:find('Lucifer Global Dashboard', 1, true) then
                dashMessages[#dashMessages + 1] = { content = self.content, user = self.username }
                self.message_id = 'G1'
            else
                notifyMessages[#notifyMessages + 1] = { content = self.content, user = self.username }
            end
        end
        function h:edit()
            dashMessages[#dashMessages + 1] = { content = self.content, user = self.username }
            return true
        end
        return h
    end }
    local botA = { name = 'BOT_ALFA', index = 1, status = 1, malady = 0, gem_count = 1000, rotation = { enabled = true, status = 2 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_A' } end }
    local botB = { name = 'BOT_BETA', index = 2, status = 1, malady = 1, gem_count = 2500, rotation = { enabled = true, status = 3 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_B' } end }
    local botC = { name = 'BOT_GAMMA', index = 3, status = 0, malady = 0, gem_count = 500, rotation = { enabled = false, status = 0 },
                   isInWorld = function() return false end, getWorld = function() return { name = '' } end }
    local t4 = 100
    local function makeApi(b)
        return {
            BotStatus = { online = 1, offline = 0 },
            RotationStatus = { scanning_world = 0, farming_block = 2, planting_seeds = 3 },
            os = { time = function() return t4 end, getenv = function() return 'TESTDIR' end },
            io = fio,
            Webhook = hooks4,
            print = function() end,
        }
    end
    local cfgGlobalA = {
        MULTI_BOT = { startbot = 1, endbot = 3 },
        WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 0, ENABLED = true, URL = 'https://x.invalid/h', MESSAGE_ID = '123456789', GLOBAL = true, UPDATE_INTERVAL_SECONDS = 5 },
        OFFLINE_ALERT = { TIMEOUT_MINUTES = 5 },
    }
    local cfgGlobalB = {
        MULTI_BOT = { startbot = 1, endbot = 3 },
        WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 0, ENABLED = true, URL = 'https://x.invalid/h', MESSAGE_ID = '123456789', GLOBAL = true, UPDATE_INTERVAL_SECONDS = 5 },
        OFFLINE_ALERT = { TIMEOUT_MINUTES = 5 },
    }
    local monA = M.new(botA, cfgGlobalA, makeApi(botA))
    local monB = M.new(botB, cfgGlobalB, makeApi(botB))

    -- Majukan waktu agar melewati registration grace (10s)
    t4 = t4 + 15
    monB.tick('Work')
    monA.tick('Work')
    assert(#dashMessages == 1, 'leader startbot=1 harus mengirim dashboard global')
    assert(dashMessages[1].user == 'Lucifer Global Monitor', 'username harus Lucifer Global Monitor')
    local bodyGlobal = dashMessages[1].content
    assert(bodyGlobal:find('Lucifer Global Dashboard', 1, true), 'header global dashboard')
    assert(bodyGlobal:find('BOT_ALFA', 1, true), 'detail bot A')
    assert(bodyGlobal:find('BOT_BETA', 1, true), 'detail bot B')

    -- Bot Beta (bukan leader) memanggil tick -> TIDAK boleh mengedit dashboard
    local countBefore = #dashMessages
    monB.tick('Work')
    assert(#dashMessages == countBefore, 'non-leader bot tidak boleh mengedit dashboard global')
end

print('PASS webhook: dashboard global multi-bot dengan pengirim leader eksplisit')

-- Edit silent failure (mengembalikan false atau nil tanpa error) tidak boleh dicache sebagai sukses
do
    local editCalls = 0
    local editResult = nil
    local silentFailHook = { new = function(url)
        local h = { url = url }
        function h:send() self.message_id = 'MID1' end
        function h:edit() editCalls = editCalls + 1; return editResult end -- controllable
        return h
    end }
    local botX = { name = 'BOT_SILENT', status = 1, malady = 0, gem_count = 10, rotation = { enabled = true, status = 2 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_X' } end }
    local tX = 10
    local apiX = {
        BotStatus = { online = 1, offline = 0 },
        RotationStatus = { farming_block = 2 },
        os = { time = function() return tX end },
        Webhook = silentFailHook,
        print = function() end,
    }
    local mX = M.new(botX, { WEBHOOK = { ENABLED = true, URL = 'https://x.invalid', MESSAGE_ID = 'MID1', MIN_EDIT_SECONDS = 5 } }, apiX)
    mX.tick('Work')
    assert(editCalls >= 1, 'percobaan edit pertama')
    local firstCount = editCalls
    -- Tick kedua setelah jeda retry (15s): karena edit pertama gagal diam-diam (return nil), HARUS dicoba lagi
    tX = tX + 20
    mX.tick('Work')
    assert(editCalls > firstCount, 'kegagalan edit diam-diam (return nil/false) TIDAK boleh dicache sebagai sukses; harus dicoba ulang')
    -- Saat edit akhirnya terkonfirmasi sukses (return true), lastBody dicache dan tidak mengedit ulang isi yang identik
    silentFailHook.editResult = true
    editResult = true
    tX = tX + 20
    mX.tick('Work')
    local confirmedCount = editCalls
    tX = tX + 20
    mX.tick('Work') -- isi identik, terkonfirmasi sukses -> skip edit
    assert(editCalls == confirmedCount, 'edit terkonfirmasi sukses dicache dan tidak mengirim ulang isi identik')
end

-- Bot peserta saja yang berhak menjadi leader dashboard global jika ditunjuk via LEADER_BOT
do
    local dashSent = 0
    local hooksY = { new = function(url)
        local h = { url = url }
        function h:send() dashSent = dashSent + 1; self.message_id = 'G_MID' end
        function h:edit() dashSent = dashSent + 1; return true end
        return h
    end }
    local botA = { name = 'BOT_AFK', status = 1, malady = 0, gem_count = 0, rotation = { enabled = false, status = 0 },
                   isInWorld = function() return false end, getWorld = function() return { name = '' } end }
    local botB = { name = 'BOT_WORKER', status = 1, malady = 0, gem_count = 500, rotation = { enabled = true, status = 2 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_B' } end }
    local allBots = { botA, botB }
    local tY = 10
    local apiY = {
        BotStatus = { online = 1, offline = 0 },
        RotationStatus = { farming_block = 2 },
        os = { time = function() return tY end },
        Webhook = hooksY,
        getBots = function() return allBots end,
        print = function() end,
    }
    -- Hanya Bot B yang ditunjuk sebagai LEADER_BOT eksplisit
    local mB = M.new(botB, { WEBHOOK = { ENABLED = true, URL = 'https://x.invalid', GLOBAL = true, LEADER_BOT = 'BOT_WORKER', MESSAGE_ID = 'G_MID' } }, apiY)
    mB.tick('Work')
    assert(dashSent == 1, 'Bot B sebagai LEADER_BOT eksplisit HARUS mengirim dashboard')
end

print('PASS webhook: retry kegagalan edit eksplisit & pemilihan leader berbasis LEADER_BOT')

-- Regresi anti-spam: send() mengembalikan false/nil TANPA message_id, isi berubah
-- -> tidak boleh membuat pesan baru berulang (percobaan pembuatan dibatasi satu kali).
do
    local sends = 0
    local sendResult = nil -- simulasi send() balik nil tanpa memberikan message_id
    local hooksZ = { new = function(url)
        local h = { url = url }
        function h:send() sends = sends + 1; return sendResult end -- tidak menulis h.message_id
        function h:edit() error('tidak boleh meng-edit tanpa message id') end
        return h
    end }
    local botZ = { name = 'BOT_SPAM', status = 1, malady = 0, gem_count = 1, rotation = { enabled = true, status = 2 },
                   isInWorld = function() return true end, getWorld = function() return { name = 'FARM_Z' } end }
    local tZ = 100
    local apiZ = {
        BotStatus = { online = 1, offline = 0 },
        RotationStatus = { farming_block = 2 },
        os = { time = function() return tZ end },
        Webhook = hooksZ,
        print = function() end,
    }
    -- MESSAGE_ID kosong, mode single-bot (bukan global)
    local mZ = M.new(botZ, { WEBHOOK = { ENABLED = true, URL = 'https://x.invalid', MESSAGE_ID = '', MIN_EDIT_SECONDS = 0 } }, apiZ)
    mZ.tick('Work')
    assert(sends == 1, 'percobaan pembuatan pertama, sends=' .. sends)
    -- Isi berubah (gems naik) dan waktu maju -> tidak boleh membuat pesan baru lagi
    botZ.gem_count = 999
    tZ = tZ + 60
    mZ.tick('Work')
    botZ.gem_count = 1234
    tZ = tZ + 60
    mZ.tick('Work')
    assert(sends == 1, 'hasil ambigu (send nil tanpa message_id) TIDAK boleh memicu pesan berulang, sends=' .. sends)

    -- send() yang jelas gagal (false) juga tidak boleh memicu pengiriman berulang
    local sendsFail = 0
    local hooksF = { new = function(url)
        local h = { url = url }
        function h:send() sendsFail = sendsFail + 1; return false end
        function h:edit() error('tidak boleh edit tanpa id') end
        return h
    end }
    local apiF = {
        BotStatus = { online = 1, offline = 0 },
        RotationStatus = { farming_block = 2 },
        os = { time = function() return tZ end },
        Webhook = hooksF,
        print = function() end,
    }
    local mF = M.new(botZ, { WEBHOOK = { ENABLED = true, URL = 'https://x.invalid', MESSAGE_ID = '', MIN_EDIT_SECONDS = 0 } }, apiF)
    mF.tick('Work')
    botZ.gem_count = 5555
    tZ = tZ + 60
    mF.tick('Work')
    assert(sendsFail == 1, 'send() gagal tidak boleh memicu pembuatan pesan berulang, sends=' .. sendsFail)
end

end

print('PASS webhook: hasil send ambigu/gagal tidak membuat pesan baru berulang')
