-- loader.lua
-- Script ringkas untuk dieksekusi di bot Lucifer
-- Mengambil engine utama secara realtime dari GitHub Raw
-- https://github.com/shizukadev/rotation-script-shizukadev

-- ========================================================
-- 1. KONFIGURASI ROTASI & FITUR (Sesuaikan di sini)
-- ========================================================
local CONFIG = {
    -- Sumber daftar farm:
    -- Jika FARM_FROM_FILE = true, script otomatis membaca file rotation.txt di folder Downloads user
    -- (format per baris: WORLD:DOOR:ID atau WORLD:DOOR atau WORLD)
    FARM_FROM_FILE = true,
    FARM_FILE = "", -- Kosongkan agar auto-detect folder Downloads user, atau isi path lengkap rotation.txt

    -- Daftar world farm fallback (dipakai jika file tidak ditemukan / FARM_FROM_FILE = false)
    FARMS = {
        { world = "FARM1", door = "" },
        { world = "FARM2", door = "" },
    },

    -- World storage: doorseed = pintu drop seed, doorpack = pintu drop hasil pack
    STORAGE = {
        world = "MYSTORE",
        doorseed = "DOORSEED",
        doorpack = "DOORPACK",
        -- packworld = "MYPACKSTORE",  -- opsional: world khusus hasil pack
        -- door = "",  -- Fallback jika doorseed/doorpack tidak diisi
    },

    -- ID Item Target
    BLOCK_ID = 4584,       -- Contoh: Pepper Tree Block
    SEED_ID = 4585,        -- Contoh: Pepper Tree Seed

    -- Ambang seed di tas sebelum rotasi Lucifer men-drop ke storage
    STORE_SEED_MIN = 100,

    -- Panen akar pohon saat panen (opsional, default false)
    HARVEST_ROOTS = false,

    -- Interval Aksi Bot dalam MILIDETIK (disesuaikan untuk RDP Ping 50-100 ms)
    ACTION_INTERVALS = {
        moveDelay    = 115, -- 115ms: pergerakan lincah tanpa desync di ping 50-100
        hitDelay     = 160, -- 160ms: break / hit blok sesuai permintaan
        placeDelay   = 110, -- 110ms: place blok sesuai permintaan
        harvestDelay = 160, -- 160ms: panen pohon (hit) selaras dengan break
        plantDelay   = 110, -- 110ms: tanam pohon (place) selaras dengan place
        warpDelay    = 7000, -- 7s: cooldown warp world aman dari subserver lockout
        dropDelay    = 3500, -- 3.5s: jeda dialog & drop barang di storage
        trashDelay   = 3500, -- 3.5s: jeda dialog & trash barang
        dynamicDelay = true, -- true: Lucifer dynamic delay kompensasi jitter ping 50-100 ms
    },

    -- PNB (place & break blok) dijalankan fitur bawaan Lucifer: rotation.pnb_in_home
    -- Isi WORLD hanya kalau PNB dilakukan di world lain, bukan home.
    PNB = {
        ENABLED = true,
        WORLD = "",   -- kosong = pakai home world
    },

    -- Pickaxe diambil & dipakai otomatis oleh AutoWear Lucifer (ID 98).
    -- Isi world kalau pickaxe disimpan di world storage.
    PICKAXE_WORLD = { world = "WORLDPICK", door = "" },

    -- AutoWear: pakai pickaxe otomatis walau PICKAXE_WORLD kosong
    AUTO_WEAR = true,

    -- AutoTrash: daftar ID item yang DIBUANG (jangan masukkan pickaxe/blok/seed/hasil pack)
    AUTO_TRASH = {
        ENABLED = true,
        ITEMS = {},   -- contoh: { 18, 32 }
    },

    -- AutoCollect TIDAK diatur script ini. Rotasi bawaan Lucifer sudah
    -- mengumpulkan item saat harvest; menimpa auto_collect/collect_range/
    -- collect_all membuat hasil panen tidak terambil. Atur di UI Lucifer.

    -- AutoReconnect: tunggu & sambung ulang otomatis saat DC
    AUTO_RECONNECT = {
        ENABLED = true,
        INTERVAL = 5,
        BYPASS_LOGON = true, -- Gunakan bypass logon saat login/reconnect
        LOCKOUT_ENABLED = true, -- true = proteksi aktif (matikan reconnect jika gagal > 15x / > 5 menit); false = disable lockout (retry terus)
        MAX_FAIL_ATTEMPTS = 15, -- Matikan bypass & reconnect jika gagal login > 15x
        MAX_FAIL_MINUTES = 5, -- Matikan bypass & reconnect jika gagal login > 5 menit
    },

    -- Pengawasan Offline & Notifikasi Discord
    OFFLINE_ALERT = {
        ENABLED = true,
        TIMEOUT_MINUTES = 5, -- 5-10 menit sebelum ping Discord
        DISCORD_USER_ID = "922775541097066576", -- User ID yang di-tag jika offline lama
    },

    -- AutoMalady native: Grumbleteeth (ID 4) / Chicken Feet (ID 3).
    -- Torn Punching Muscle (ID 1) / Gem Cuts (ID 2) ditangani rute custom 4AID.
    AUTO_SPAM = { ENABLED = true, RECOVERY_SECONDS = 3600 },
    MALADY = {
        GRUMBLETEETH = false,
        CHICKEN_FEET = false,
    },

    -- Webhook Live Monitor (webhook_edit)
    WEBHOOK = {
        ENABLED = true,
        URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA", -- ganti dengan URL webhook Discord Anda (jangan di-commit ke publik)
        MESSAGE_ID = "1567025865047539856", -- Jika diisi, bot akan edit pesan ini terus-menerus (Live Dashboard)
        UPDATE_INTERVAL_SECONDS = 15, -- jeda refresh dashboard
        EVENT_NOTIFICATIONS = true, -- live dashboard only; true mengaktifkan pesan alert terpisah
        MIN_EDIT_SECONDS = 5, -- gabungkan perubahan cepat ke edit berikutnya
        PHASE_NOTIFY = false, -- true = kirim pesan tiap fase rotasi berubah (bisa ramai)
        GLOBAL = true, -- true = satu dashboard global terpadu untuk semua bot jika beberapa/semua bot dijalankan bersamaan
        LEADER_BOT = "", -- nama bot pengirim dashboard global (kosongkan jika single bot)
    },

    -- Beli pack otomatis: rotasi Lucifer beli PackName saat gems mencapai PricePack,
    -- lalu drop hasilnya ke STORAGE (doorpack) lewat WorldManager.
    AUTO_BUY_PACK = {
        ENABLED = true,
        PackName = "vending_machine",
        PricePack = 8000,
        ItemIDOfPack = { 2978 },
    },
}

-- ========================================================
-- 2. LOADER DARI GITHUB RAW (JANGAN DIUBAH)
-- ========================================================
local RAW_ENGINE_URL = "https://raw.githubusercontent.com/shizukadev/rotation-script-shizukadev/main/engine.lua"

print("[Loader] Mengunduh engine rotasi dari: " .. RAW_ENGINE_URL)

local client = HttpClient.new()
client.url = RAW_ENGINE_URL
client:setMethod(Method.get)
client.timeout = 15
client.headers = { ["User-Agent"] = "Lucifer" }

local res = client:request()
if res.error == 0 and res.status == 200 then
    print("[Loader] Engine berhasil diunduh. Memulai kompilasi...")
    _G.CONFIG = CONFIG
    local chunk, err = (loadstring or load)(res.body)
    if chunk then
        chunk(CONFIG)
    else
        print("[Error] Gagal kompilasi engine: " .. tostring(err))
    end
else
    print(string.format("[Error] Gagal mengunduh engine. Status HTTP: %s | Error: %s", tostring(res.status), tostring(res:getError())))
end
