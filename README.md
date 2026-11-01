# Lucifer Rotation (v2.86)

Koleksi skrip otomatisasi rotasi farm untuk Nuron's Lucifer Growtopia v2.86.

## Struktur Berkas

- **`loader.lua`**: Skrip ringan untuk dijalankan di Lucifer bot. Hanya berisi tabel konfigurasi (`CONFIG`) dan mengambil `engine.lua` secara realtime dari GitHub Raw.
- **`engine.lua`**: Logika utama rotasi (State Machine) yang di-host di GitHub. Pembaruan logika atau bug fix dilakukan di sini tanpa perlu mengubah skrip di setiap bot.
- **`rotation_final.lua`**: Skrip standalone lengkap (offline mode).
- **`docs_v2.86.md`**: Dokumentasi referensi lengkap API Lucifer v2.86 berbahasa Indonesia.

## Alur Kerja Rotasi

```text
Loader (CONFIG) → Engine → Daftarkan FARMS + STORAGE ke WorldManager → Setel interval/gem_limit/pack
→ Aktifkan rotasi bawaan Lucifer (panen, tanam, break, drop seed, beli pack, pindah world)
→ Script hanya memantau lewat webhook
```

Panen, tanam, break di Home, drop seed, beli pack, dan perpindahan world **dijalankan oleh fitur
rotasi bawaan Lucifer** (`bot.rotation`). Script ini tidak lagi melakukan harvest/plant manual —
tugasnya menyiapkan world/storage, interval, pickaxe, dan monitor webhook.

## Fitur Utama Baru
- **Live Webhook Monitor (`webhook_edit`)**: Mengirim dan mengedit satu pesan Discord secara realtime (`webhook:edit()`) menampilkan nama bot, status online/offline, world aktif, gems, slot inventory, ping, dan jumlah item pack di tas.
- **Auto Buy Pack & Storage Drop**: Diteruskan ke rotasi bawaan Lucifer — `PricePack` menjadi `gem_limit` + `setPack(PackName)`, dan hasil pack di-drop ke `STORAGE.doorpack` karena world storage didaftarkan sebagai `StorageType.pack`.

## Cara Penggunaan

1. Buka `loader.lua` di bot Lucifer.
2. Sesuaikan konfigurasi di tabel `CONFIG`:
   - `FARMS`: Daftar world target panen dan tanam.
   - `HOME`: World pemecahan blok.
   - `STORAGE`: World penyimpanan seed dan item pack.
   - `BLOCK_ID` & `SEED_ID`: ID blok dan seed tanaman.
   - `STORE_SEED_MIN`: ambang seed sebelum di-drop ke storage.
   - `WEBHOOK`: URL webhook Discord dan Message ID (opsional untuk live edit).
   - `AUTO_BUY_PACK`: Nama pack dan harga (menjadi `gem_limit` rotasi Lucifer).
3. Jalankan `loader.lua`. Bot akan mengunduh engine terbaru dan langsung mengeksekusi rotasi.

## Proteksi & Safety v2.86
- **Inbuilt Lucifer Rotation**: Panen, tanam, PNB di home, drop seed, beli pack, dan perpindahan world ditangani langsung oleh engine bawaan Lucifer (`bot.rotation`).
- **Custom Position Dinonaktifkan**: Memakai posisi tile default bawaan Lucifer (`rotation.custom_position = false`) agar bot tidak desync atau memukul di luar area yang ditentukan.
- **AutoWear & Storage**: Pengambilan dan pemakaian Pickaxe (ID 98) otomatis via `bot.auto_wear` dan `bot.wear_storage`.
- **AutoMalady**: Perlindungan otomatis terhadap Torn Punching Muscle (`auto_grumbleteeth`) dan `auto_chicken_feet`.
- **AutoTrash & AutoCollect**: Otomatis membuang sampah via `setTrashList()` dan memungut drop item sesuai konfigurasi range.
- **Auto-Reconnect Watchdog**: Menggunakan `bot.auto_reconnect` serta loop watchdog untuk mengaktifkan kembali rotasi jika mati pasca reconnect/DC.
