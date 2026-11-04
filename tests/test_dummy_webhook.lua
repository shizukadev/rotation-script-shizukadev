-- Regresi dummy_webhook.lua: harus mencetak message_id dan menolak URL kosong.
local f = assert(io.open('dummy_webhook.lua'))
local text = f:read('*a'); f:close()

local log = {}
local sent = 0
local fakeWebhook = { new = function(url)
    local h = { url = url }
    function h:send() sent = sent + 1; self.message_id = "1234567890" end
    return h
end }
local env = {
    Webhook = fakeWebhook,
    print = function(s) log[#log + 1] = tostring(s) end,
}
setmetatable(env, { __index = _G })

-- URL masih placeholder: tidak boleh mengirim
assert(load(text, '@dummy_webhook.lua', 't', env))()
assert(sent == 0, "URL placeholder tidak boleh mengirim")
assert(table.concat(log, "\n"):find("Isi URL webhook", 1, true), "harus meminta URL diisi")

-- URL valid: kirim dan cetak id
local configured = text:gsub('local URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA"',
    'local URL = "https://discord.com/api/webhooks/1/abc"')
log = {}
assert(load(configured, '@dummy_webhook.lua', 't', env))()
assert(sent == 1, "URL valid harus mengirim sekali")
local out = table.concat(log, "\n")
assert(out:find("message_id = 1234567890", 1, true), "harus mencetak message_id")
assert(out:find('MESSAGE_ID = "1234567890"', 1, true), "harus memberi baris siap tempel")

print("PASS dummy_webhook: URL placeholder ditolak, URL valid mencetak message_id")
