-- Kontrak transport webhook NATIVE (api.Webhook), bukan HttpClient.
-- Menggantikan cakupan lama yang menuntut PATCH mentah.
local M = assert(loadfile('webhook_monitor.lua'))()

local sends, edits, logs = 0, 0, {}
local t = 0
local body, lastEditId = {}, nil

local bot = {
    name = 'BOT_A', index = 1, status = 1, malady = 0, gem_count = 10,
    rotation = { enabled = true, status = 2 },
    isInWorld = function() return true end,
    getWorld = function() return { name = 'FARM_A' } end,
}
local api = {
    BotStatus = { online = 1, offline = 0 },
    RotationStatus = { farming_block = 2, planting_seeds = 3 },
    os = { time = function() return t end, getenv = function() return (os.getenv('TEMP') or '.') end },
    print = function(s) logs[#logs + 1] = tostring(s) end,
}
api.Webhook = {
    new = function(url)
        local h = { url = url, embed1 = { addField = function() end } }
        function h:send()
            sends = sends + 1
            body[#body + 1] = self.content
            self.message_id = '111111111111111111'
        end
        function h:edit()
            edits = edits + 1
            lastEditId = self.message_id
            body[#body + 1] = self.content
            return true
        end
        return h
    end,
}

local cfg = { WEBHOOK = {
    ENABLED = true, URL = 'https://example.invalid/h', GLOBAL = true,
    MESSAGE_ID = '111111111111111111', MIN_EDIT_SECONDS = 5, UPDATE_INTERVAL_SECONDS = 5,
} }

local m = M.new(bot, cfg, api)
t = 10 -- lewati grace registrasi snapshot
m.tick()
assert(edits == 1 and sends == 0, 'dashboard pertama harus EDIT pesan yang ada, bukan POST baru')
assert(lastEditId == '111111111111111111', 'edit harus memakai MESSAGE_ID konfigurasi')

t = 11
bot.rotation.status = 3
m.tick()
assert(edits == 1, 'minimum edit interval harus menahan pengiriman terlalu cepat')

t = 15
m.tick()
assert(edits == 2, 'perubahan fase harus dikirim setelah interval')
assert(body[#body]:find('ON planting_seeds', 1, true), 'fase terbaru harus terkirim')

local before = edits
t = 20
m.tick()
assert(edits == before, 'isi identik tidak boleh dikirim ulang')

-- Edit gagal (return false) tidak boleh membuat pesan baru dan harus dicoba lagi.
local realNew = api.Webhook.new
local failing = true
api.Webhook.new = function(url)
    local h = realNew(url)
    local realEdit = h.edit
    function h:edit()
        if failing then return false end
        return realEdit(self)
    end
    return h
end
bot.rotation.status = 2
t = 30
m.tick()
assert(sends == 0, 'edit gagal tidak boleh memicu POST pesan baru')
local editsAfterFail = edits
t = 60
failing = false
m.tick()
assert(edits == editsAfterFail + 1, 'edit harus dicoba lagi setelah backoff')

assert(not table.concat(logs):find('https://example.invalid', 1, true), 'URL webhook tidak boleh bocor ke log')

print('PASS webhook native: edit pesan tetap, interval minimum, dedupe, edit gagal tanpa POST baru, retry, tanpa bocor URL')
