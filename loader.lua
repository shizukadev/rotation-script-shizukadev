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
        -- door = "",  -- Fallback jika doorseed/doorpack tidak diisi
    },

    -- ID Item Target
    BLOCK_ID = 4584,       -- Contoh: Pepper Tree Block
    SEED_ID = 4585,        -- Contoh: Pepper Tree Seed

    -- Ambang seed di tas sebelum rotasi Lucifer men-drop ke storage
    STORE_SEED_MIN = 100,

    -- Panen akar pohon saat panen (opsional, default false)
    HARVEST_ROOTS = false,

    -- Interval Aksi Bot (Detik) -> diteruskan ke rotasi bawaan Lucifer
    ACTION_INTERVALS = {
        hit = 0.18,
        place = 0.16,
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

    -- AutoCollect: ambil objek drop di sekitar bot saat panen
    AUTO_COLLECT = {
        ENABLED = true,
        RANGE = 3,
        ALL = false,
    },

    -- AutoReconnect: tunggu & sambung ulang otomatis saat DC
    AUTO_RECONNECT = {
        ENABLED = true,
        INTERVAL = 5,
        BYPASS_LOGON = true, -- Gunakan bypass logon saat login/reconnect
        MAX_FAIL_ATTEMPTS = 15, -- Matikan bypass & reconnect jika gagal login > 15x
        MAX_FAIL_MINUTES = 5, -- Matikan bypass & reconnect jika gagal login > 5 menit
    },

    -- Pengawasan Offline & Notifikasi Discord
    OFFLINE_ALERT = {
        ENABLED = true,
        TIMEOUT_MINUTES = 5, -- 5-10 menit sebelum ping Discord
        DISCORD_USER_ID = "922775541097066576", -- User ID yang di-tag jika offline lama
    },

    -- AutoMalady: kebal Torn Punching Muscle (Grumbleteeth) / Chicken Feet
    MALADY = {
        GRUMBLETEETH = true,
        CHICKEN_FEET = true,
    },

    -- Webhook Live Monitor (webhook_edit)
    WEBHOOK = {
        ENABLED = true,
        URL = "MASUKKAN_URL_WEBHOOK_DISCORD_ANDA",
        MESSAGE_ID = "", -- Jika diisi, bot akan edit pesan ini terus-menerus (Live Dashboard)
    },

    -- Beli pack otomatis: rotasi Lucifer beli PackName saat gems mencapai PricePack,
    -- lalu drop hasilnya ke STORAGE (doorpack) lewat WorldManager.
    AUTO_BUY_PACK = {
        ENABLED = true,
        PackName = "world_lock_10_pack",
        PricePack = 20000,
        ItemIDOfPack = { 242 }, -- Hanya untuk tampilan jumlah pack di webhook
    },
}

-- ========================================================
-- 2. LOADER DARI GITHUB RAW (JANGAN DIUBAH)
-- ========================================================
local RAW_ENGINE_URL = "https://raw.githubusercontent.com/shizukadev/rotation-script-shizukadev/main/engine.lua"

print("[Loader] Mengunduh engine rotasi dari GitHub...")

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
