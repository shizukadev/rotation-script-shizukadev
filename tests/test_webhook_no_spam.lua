-- Kontrak anti-spam transport webhook NATIVE: hasil send ambigu/gagal tidak
-- boleh memicu pembuatan pesan berulang. Menggantikan cakupan lama.
local M = assert(loadfile('webhook_monitor.lua'))()

local sends, edits, t = 0, 0, 0
local bot = {
    name = 'B', status = 1, malady = 0, gem_count = 1,
    rotation = { enabled = true, status = 2 },
    isInWorld = function() return true end,
    getWorld = function() return { name = 'CURRENT' } end,
}
local api = {
    BotStatus = { online = 1, offline = 0 },
    RotationStatus = { farming_block = 2, planting_seeds = 3 },
    os = { time = function() return t end, getenv = function() return (os.getenv('TEMP') or '.') end },
    print = function() end,
}

local mode = 'fail'   -- 'fail' = send() return false, 'ambiguous' = tanpa message_id
api.Webhook = {
    new = function(url)
        local h = { url = url, embed1 = { addField = function() end } }
        function h:send()
            sends = sends + 1
            if mode == 'fail' then return false end
            -- mode ambiguous: sukses tanpa message_id (penerimaan tidak terbukti)
        end
        function h:edit()
            edits = edits + 1
            return true
        end
        return h
    end,
}

local cfg = { WEBHOOK = { ENABLED = true, URL = 'https://example.invalid/h', MIN_EDIT_SECONDS = 0, MESSAGE_ID = '' } }

local m = M.new(bot, cfg, api)
m.tick()
assert(sends == 1, 'percobaan pembuatan pertama harus jalan')
for i = 1, 3 do
    t = t + 60
    bot.gem_count = bot.gem_count + 1
    m.tick()
end
assert(sends == 1, 'send() gagal tidak boleh memicu pembuatan pesan berulang, sends=' .. sends)

mode = 'ambiguous'
local m2 = M.new(bot, cfg, api)
m2.tick()
assert(sends == 2, 'percobaan pembuatan berikutnya harus jalan sekali')
for i = 1, 3 do
    t = t + 60
    bot.gem_count = bot.gem_count + 1
    m2.tick()
end
assert(sends == 2, 'hasil send tanpa message_id tidak boleh membuat pesan baru berulang, sends=' .. sends)

print('PASS webhook native: send gagal/ambigu tidak membuat pesan baru berulang')
