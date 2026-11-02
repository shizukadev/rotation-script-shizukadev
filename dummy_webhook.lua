-- dummy_webhook.lua
-- Kirim satu pesan dummy, lalu cetak message id-nya.
-- Tempel hasilnya ke CONFIG.WEBHOOK.MESSAGE_ID di rotation_local.lua.
--
-- Cara pakai:
--   1. Isi URL di bawah dengan URL webhook Discord kamu.
--   2. Jalankan script ini di konsol Lucifer.
--   3. Salin angka "message_id" ke MESSAGE_ID.
--   4. Hapus pesan dummy di Discord kalau tidak dipakai.

local URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA"

if type(URL) ~= "string" or URL == "" or URL:find("MASUKKAN_URL", 1, true) then
    print("[Dummy] Isi URL webhook Discord dulu di baris URL.")
    return
end
if type(Webhook) ~= "table" or type(Webhook.new) ~= "function" then
    print("[Dummy] Webhook API tidak tersedia di build ini.")
    return
end

local ok, err = pcall(function()
    local hook = Webhook.new(URL)
    hook.username = "Lucifer Dummy"
    hook.content = "Pesan dummy untuk mengambil message id. Boleh dihapus."
    hook:send()
    local id = hook.message_id
    if id and tostring(id) ~= "" then
        print("[Dummy] message_id = " .. tostring(id))
        print("[Dummy] Tempel ke CONFIG.WEBHOOK.MESSAGE_ID = \"" .. tostring(id) .. "\"")
    else
        print("[Dummy] message_id kosong. Periksa URL webhook dan izin channel.")
    end
end)

if not ok then
    print("[Dummy] Gagal mengirim. Periksa URL webhook dan koneksi.")
end
