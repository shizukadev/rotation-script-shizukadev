-- Fasilitas event global untuk semua env: jawab /status dengan daftar mod lengkap.
Event = { variantlist = 1, game_message = 1 }
addEvent = function(_, fn) _G.__gmHandler = fn end
listenEvents = function()
  if not _G.__gmHandler then return end
  local n = _G.__gmName or "TESTBOT"
  _G.__gmHandler("msg|" .. n .. "'s Status:")
  _G.__gmHandler("msg|0 mods active")
end
-- Offline simulated host; no server connection. Loads engine.lua with a fake Lucifer bot.
local f = assert(io.open('engine.lua'))
local text = f:read('*a'); f:close()

local function boot(opts)
    opts = opts or {}
    local st = { out = {}, farms = {}, storages = {}, selection = 0, trashList = nil }
    local rotation = { enabled = false }
    local malady = { enabled = false }

    local world = {
        name = "HOME", x = 50, y = 50,
        getTile = function() return { fg = 0 } end,
        getObjects = function() return {} end,
        isValidTile = function() return true end,
    }

    local bot = {
        name = "TESTBOT", status = 1, x = 10, y = 10, gem_count = 5000, level = 50,
        say = function(self) _G.__gmName = self and self.name end,
        rotation = rotation, auto_malady = malady,
        auto_spam = { setText = function(self, index, message) self.text = message; self.textIndex = index end },
        auto_farm = { enabled = true }, auto_harvest = { enabled = true }, auto_plant = { enabled = true },
        getWorld = function() return world end,
        isInWorld = function() return true end,
        getPing = function() return 42 end,
        getInventory = function()
            return {
                findItem = function() return 0 end,
                getItem = function() return nil end,
                itemcount = 0, slotcount = 200, emptyslots = 200,
            }
        end,
    }

    local manager = {
        addFarm = function(_, nameAndDoor, itemId) table.insert(st.farms, { name = nameAndDoor, item = itemId }) end,
        removeFarm = function() end,
        addStorage = function(_, nameAndDoor, kind, seedId) table.insert(st.storages, { name = nameAndDoor, kind = kind, seed = seedId }) end,
        removeStorage = function() end,
        selectAll = function() st.selection = st.selection + 1 end,
    }

    local env = {
        getBot = function() return bot end,
        BotStatus = { online = 1 },
        StorageType = { seed = 1, pack = 2 },
        getWorldManager = function() return manager end,
        setTrashList = function(list) st.trashList = list end,
        sleep = function()
            if not st.flipped then
                st.flipped = true
                -- Simulasi DC: bot mati, rotasi mati
                bot.status = 0
                if opts.flipRotation then rotation.enabled = false end
            elseif not st.reconnected then
                -- Siklus kedua: bot kembali online
                st.reconnected = true
                bot.status = 1
            else
                -- Siklus ketiga: hentikan loop
                error("TERMINATE_TEST_LOOP")
            end
        end,
        print = function(s) st.out[#st.out + 1] = tostring(s) end,
        os = os,
    }
    setmetatable(env, { __index = _G })

    local CONFIG = {
        FARM_FROM_FILE = false,
        FARMS = { { world = "farm1", door = "DOOR1" }, "farm2" },
        STORAGE = { world = "MYSTORE", doorseed = "SEEDDOOR", doorpack = "PACKDOOR" },
        BLOCK_ID = 4584, SEED_ID = 4585,
        STORE_SEED_MIN = 100,
        ACTION_INTERVALS = { hit = 0.18, place = 0.16 },
        PNB = opts.pnb or { ENABLED = true, WORLD = "" },
        PICKAXE_WORLD = { world = "PICKSTORE", door = "" },
        AUTO_WEAR = true,
        AUTO_TRASH = { ENABLED = true, ITEMS = { 18, 32 } },
        AUTO_COLLECT = { ENABLED = true, RANGE = 3, ALL = false },
        AUTO_RECONNECT = { ENABLED = true, INTERVAL = 7 },
        MALADY = { GRUMBLETEETH = true, CHICKEN_FEET = true },
        AUTO_BUY_PACK = { ENABLED = true, PackName = "world_lock_10_pack", PricePack = 20000 },
        WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = false },
    }
    if opts.customConfig then opts.customConfig(CONFIG) end

    local okRun, errRun = pcall(function()
        assert(load(text, '@engine.lua', 't', env))(CONFIG)
    end)
    if not okRun and not tostring(errRun):find("TERMINATE_TEST_LOOP") then
        error(errRun)
    end

    st.rotation = rotation
    st.malady = malady
    st.bot = bot
    st.text = table.concat(st.out, "\n")
    return st
end

-- 1. Registrasi world & storage ke WorldManager
local r = boot({ flipRotation = true })
assert(#r.farms == 2, "harus daftar 2 farm, dapat " .. #r.farms)
assert(r.farms[1].name == "FARM1:DOOR1:4584" and r.farms[1].item == 4584, "farm 1 salah: " .. tostring(r.farms[1].name))
assert(r.farms[2].name == "FARM2" and r.farms[2].item == 4584, "farm 2 salah: " .. tostring(r.farms[2].name))
assert(#r.storages == 2, "harus daftar 2 storage, dapat " .. #r.storages)
assert(r.storages[1].name == "MYSTORE:SEEDDOOR" and r.storages[1].kind == 1 and r.storages[1].seed == 4585, "storage seed salah")
assert(r.storages[2].name == "MYSTORE:PACKDOOR" and r.storages[2].kind == 2 and r.storages[2].seed == 0, "storage pack salah")
-- Format nama ke WorldManager harus WORLD:DOOR:ITEMID (UI: Name:DoorID:ItemID).
-- Dulu id hanya jadi argumen kedua yang diabaikan host -> kolom Item "Unknown".
assert(r.farms[1].name:match(":%d+$") ~= nil, "nama farm harus diakhiri :ITEMID, dapat: " .. tostring(r.farms[1].name))
assert(r.farms[1].name == "FARM1:DOOR1:" .. tostring(r.farms[1].item), "id di nama harus sama dengan item")
print("PASS registrasi farm & storage")

-- 2. Fitur bawaan Lucifer yang menggantikan kode manual
assert(r.bot.auto_wear == true and r.bot.wear_id == 98, "AutoWear pickaxe tidak disetel")
assert(r.bot.wear_storage == "PICKSTORE", "wear_storage harus = PICKAXE_WORLD.world")
assert(r.bot.auto_trash == true, "AutoTrash harus aktif")
assert(r.trashList and r.trashList[1] == 18 and r.trashList[2] == 32, "setTrashList tidak dipanggil dengan benar")
assert(r.bot.auto_collect == nil and r.bot.collect_range == nil and r.bot.collect_all == nil,
    "AutoCollect harus DIBIARKAN: rotasi bawaan Lucifer yang mengurus collect saat harvest")
assert(r.bot.auto_reconnect == true and r.bot.reconnect_interval == 7, "AutoReconnect tidak disetel")
assert(r.malady.auto_grumbleteeth == false and r.malady.auto_chicken_feet == false, "AutoMalady native harus dimatikan")
assert(r.malady.enabled == true, "AutoMalady harus aktif untuk refresh status; kedua aksi penyakit tetap false")
assert(r.bot.auto_spam.enabled == false and r.bot.auto_spam.interval == nil and r.bot.auto_spam.text == nil, "AutoSpam hanya toggle; fixture world/penyakit tidak Healthy terverifikasi")
print("PASS AutoWear/AutoTrash/AutoCollect/AutoReconnect/AutoMalady")

-- 3. Setelan rotasi: PNB native, custom tile mati, automation lain mati
assert(r.rotation.pnb_in_home == true, "PNB harus lewat rotation.pnb_in_home")
assert(r.rotation.custom_position == nil,
    "custom_position TIDAK boleh ditulis: mengisinya membuat toggle Custom Break Position ON")
assert(r.rotation.harvest_interval == 0.18 and r.rotation.plant_interval == 0.16, "interval salah")
assert(r.rotation.seed_drop_amount == 100, "seed_drop_amount salah")
assert(r.rotation.id == nil and r.rotation.world_limit == nil,
    "id/world_limit bukan properti rotation di API asli; jangan ditulis")
assert(r.bot.gem_limit == 20000, "gem_limit harus = PricePack")
assert(r.bot.auto_farm.enabled == false and r.bot.auto_harvest.enabled == false and r.bot.auto_plant.enabled == false,
    "AutoFarm/AutoHarvest/AutoPlant harus dimatikan")
print("PASS setelan rotasi + PNB native")

-- 3b. Log status rotasi berkala: satu baris, isinya terbaca.
assert(r.text:find("%[Rot%] enabled="), "engine harus mencatat status rotasi berkala")
assert(not r.text:find("%[Rot%] enabled=.*\n.*%[Rot%] enabled="), "log [Rot] tidak boleh spam dalam satu menit")

-- 4. PNB world kustom & pnb_world kosong
r = boot({ pnb = { ENABLED = true, WORLD = "MYPNB" } })
assert(r.rotation.pnb_in_home == true and r.rotation.pnb_world == "MYPNB", "pnb_world kustom tidak dipakai")
r = boot({ pnb = { ENABLED = false } })
assert(r.rotation.pnb_in_home == false and r.rotation.pnb_world == "", "pnb_in_home harus false dan pnb_world nil jika disabled")
print("PASS pnb_world kustom + bisa dimatikan")

-- 5. Watchdog rotasi saat DC
-- Diverifikasi secara komprehensif pada uji #10 langsung terhadap engine.lua
print("PASS watchdog rotasi")

-- 6. Tidak ada implementasi manual yang tersisa (smartDrop, pnbUnderDoor/Gem, pnbBatch, dll sudah diganti total)
for _, name in ipairs({ "pnbBatch", "goToWorkSpot", "warpSimple", "checkAndEquipPickaxe",
                        "doHarvest", "doPlant", "doAutoTrash", "collectFloatingObjects",
                        "smartDrop", "smart_drop", "pnbUnderDoor", "pnbDoorColumns",
                        "pnbUnderGem", "findBreakSpot", "isTileHarvestable", "plantSeedAt" }) do
    assert(not text:find(name, 1, true), "engine masih memuat " .. name)
end
print("PASS tanpa implementasi manual (engine.lua)")

-- 7. rotation_final.lua juga bebas dari implementasi manual lama
local f_final = assert(io.open('rotation_final.lua'))
local text_final = f_final:read('*a'); f_final:close()
for _, name in ipairs({ "pnbBatch", "goToWorkSpot", "warpSimple", "checkAndEquipPickaxe",
                        "doHarvest", "doPlant", "doAutoTrash", "collectFloatingObjects",
                        "smartDrop", "smart_drop", "pnbUnderDoor", "pnbDoorColumns",
                        "pnbUnderGem", "findBreakSpot", "isTileHarvestable", "plantSeedAt" }) do
    assert(not text_final:find(name, 1, true), "rotation_final masih memuat " .. name)
end
assert(not text_final:find('custom_position", 0', 1, true) and not text_final:find("rotation.custom_position = 0", 1, true),
    "custom_position tidak boleh ditulis di rotation_final (membuat toggle ON)")
print("PASS tanpa implementasi manual (rotation_final.lua)")

-- 8. Pemuatan farm dari file (format WORLD:DOOR:ID)
local f_test = assert(io.open('test_farms_sample.txt', 'w'))
f_test:write("WORLD_A:DOOR_A:4584\nWORLD_B:DOOR_B:3004\nWORLD_C\n")
f_test:close()

local r_file = boot({
    flipRotation = true,
    customConfig = function(cfg)
        cfg.FARM_FROM_FILE = true
        cfg.FARM_FILE = "test_farms_sample.txt"
    end
})
os.remove('test_farms_sample.txt')
assert(#r_file.farms == 3, "harus memuat 3 farm dari file, dapat " .. #r_file.farms)
assert(r_file.farms[1].name == "WORLD_A:DOOR_A:4584" and r_file.farms[1].item == 4584, "farm 1 dari file salah")
assert(r_file.farms[2].name == "WORLD_B:DOOR_B:3004" and r_file.farms[2].item == 3004, "farm 2 dari file salah")
assert(r_file.farms[3].name == "WORLD_C" and r_file.farms[3].item == 4584, "farm 3 dari file salah (harus fallback ke BLOCK_ID)")
print("PASS pemuatan farm dari file rotation.txt")

-- 9. Pemuatan farm dengan FARM_FILE = "" (auto-detect Downloads)
local username = (os.getenv and (os.getenv("USERNAME") or os.getenv("USER"))) or "Administrator"
local autoPath = string.format("C:\\Users\\%s\\Downloads\\rotation.txt", username)
local f_auto = io.open(autoPath, "w")
if f_auto then
    f_auto:write("AUTOFARM:AUTODOOR:4584\n")
    f_auto:close()
    local r_auto = boot({
        customConfig = function(cfg)
            cfg.FARM_FROM_FILE = true
            cfg.FARM_FILE = ""
        end
    })
    os.remove(autoPath)
    assert(#r_auto.farms >= 1, "harus auto-detect rotation.txt dari Downloads")
    assert(r_auto.farms[1].name == "AUTOFARM:AUTODOOR:4584", "nama auto-detect salah: " .. tostring(r_auto.farms[1].name))
    print("PASS auto-detect Downloads/rotation.txt")
end

-- 10. Uji ketahanan Disconnect & Reconnect (waitOnline produksi)
-- Uji disconnect di tengah proses eksekusi engine.lua
local testSteps = 0
local liveBot = {
    name = "TEST_RECON_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}

local reconLogs = {}
local activationHistory = {}

local liveEnv = {
    getBot = function() return liveBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        testSteps = testSteps + 1
        if testSteps == 1 then
            -- Simulasi bot mendadak DC (rotasi mati)
            liveBot.status = 0
            liveBot.rotation.enabled = false
        elseif testSteps == 2 then
            -- Simulasi waitOnline: bot kembali online (reconnect)
            liveBot.status = 1
        elseif testSteps == 3 then
            -- Watchdog berputar saat online
        elseif testSteps >= 4 then
            -- Hentikan loop
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s)
        table.insert(reconLogs, tostring(s))
        if tostring(s):find("Bot pulih dari disconnect") then
            -- Catat status bot saat rotasi diaktifkan kembali
            table.insert(activationHistory, liveBot.status)
        end
    end,
    os = os,
}
setmetatable(liveEnv, { __index = _G })

local cfgRecon = {
    FARM_FROM_FILE = false,
    FARMS = { "WORLD1" },
    BLOCK_ID = 4584,
    SEED_ID = 4585,
    WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = false },
}
pcall(function() assert(load(text, '@engine.lua', 't', liveEnv))(cfgRecon) end)
assert(testSteps >= 3, "loop engine harus bertahan melalui siklus disconnect-reconnect")
assert(#activationHistory >= 1, "watchdog harus mengaktifkan kembali rotasi pasca reconnect")
for _, botStatusAtActivation in ipairs(activationHistory) do
    assert(botStatusAtActivation == 1, "CRITICAL: Rotasi HANYA boleh diaktifkan kembali saat bot berstatus ONLINE!")
end
print("PASS uji ketahanan reconnect/disconnect (terkonfirmasi aktivasi saat ONLINE)")

-- 11. Uji hormati stop manual pengguna
local stopSteps = 0
local manualBot = {
    name = "TEST_STOP_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local stopLogs = {}
local stopEnv = {
    getBot = function() return manualBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        stopSteps = stopSteps + 1
        if stopSteps == 1 then
            -- Bot tetap online, tapi rotasi dimatikan secara sengaja oleh user
            manualBot.rotation.enabled = false
        elseif stopSteps >= 3 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(stopLogs, tostring(s)) end,
    os = os,
}
setmetatable(stopEnv, { __index = _G })
pcall(function() assert(load(text, '@engine.lua', 't', stopEnv))(cfgRecon) end)
local stopLogsStr = table.concat(stopLogs, "\n")
assert(stopLogsStr:find("Rotasi dimatikan secara manual oleh user"), "engine harus mendeteksi dan menghormati stop manual user")
assert(manualBot.rotation.enabled == false, "rotasi TIDAK BOLEH dinyalakan kembali jika user melakukan stop manual")
print("PASS uji hormati stop manual user")

-- 12. Uji ketahanan disconnect saat navigasi 4AID (auto_malady_4aid.lua)
-- Kasus A: Disconnect di tengah findPath
local dcNavSteps = 0
local dcNavBot
dcNavBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    currentWorld = "",
    isInWorld = function(_, w)
        if w then return dcNavBot.currentWorld == w end
        return dcNavBot.currentWorld ~= ""
    end,
    warp = function(_, w) dcNavBot.currentWorld = w end,
    findPath = function(_, x, y)
        dcNavSteps = dcNavSteps + 1
        if dcNavSteps == 1 then
            -- Simulasi DC saat mencoba walkTo(22, 16)
            dcNavBot.status = 0
            return false
        end
        dcNavBot.x, dcNavBot.y = x, y
        return true
    end,
    hit = function() end,
    sendPacket = function() end,
    enter = function() end,
}
local navLogs = {}
local envDcNav = {
    getBot = function() return dcNavBot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1, game_message = 1 },
    addEvent = function(_, fn) _G.__gmHandler = fn end,
    removeEvent = function() end,
    sleep = function() end,
    print = function(s) table.insert(navLogs, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envDcNav, { __index = _G })
local f_malady = assert(io.open('auto_malady_4aid.lua'))
local maladyText = f_malady:read('*a'); f_malady:close()
local maladyMod = assert(load(maladyText, '@auto_malady_4aid.lua', 't', envDcNav))("auto_malady_4aid")
local navRes = maladyMod.runCure(dcNavBot)
assert(navRes == false, "runCure harus return false dan abort jika terjadi DC saat navigasi")
local navLogsStr = table.concat(navLogs, "\n")
assert(navLogsStr:find("Gagal findPath"), "harus mencatat kegagalan path saat DC")
print("PASS uji ketahanan disconnect di tengah navigasi 4AID (Kasus A)")

-- Kasus B: Disconnect tepat SETELAH posisi (50, 15) tercapai sebelum aksi pintu
local dcAtDoorActions = {}
local dcAtDoorBot
dcAtDoorBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    currentWorld = "",
    isInWorld = function(_, w)
        if w then return dcAtDoorBot.currentWorld == w end
        return dcAtDoorBot.currentWorld ~= ""
    end,
    warp = function(_, w) dcAtDoorBot.currentWorld = w end,
    findPath = function(_, x, y)
        dcAtDoorBot.x, dcAtDoorBot.y = x, y
        if x == 50 and y == 15 then
            -- Tepat saat bot sampai di koordinat pintu (50, 15), koneksi putus
            dcAtDoorBot.status = 0
            while #dcAtDoorActions > 0 do table.remove(dcAtDoorActions) end
        end
        return true
    end,
    hit = function()
        table.insert(dcAtDoorActions, "hit")
    end,
    sendPacket = function()
        table.insert(dcAtDoorActions, "sendPacket")
    end,
    enter = function()
        table.insert(dcAtDoorActions, "enter")
    end,
}
local doorLogs = {}
local doorActionsCount = 0
local envDcDoor = {
    getBot = function() return dcAtDoorBot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1, game_message = 1 },
    addEvent = function(_, fn) _G.__gmHandler = fn end,
    removeEvent = function() end,
    sleep = function() end,
    print = function(s) table.insert(doorLogs, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envDcDoor, { __index = _G })
dcAtDoorActions = {}
f_malady = assert(io.open('auto_malady_4aid.lua'))
maladyText = f_malady:read('*a'); f_malady:close()
doorMod = assert(load(maladyText, '@auto_malady_4aid.lua', 't', envDcDoor))("auto_malady_4aid")
doorRes = doorMod.runCure(dcAtDoorBot)
assert(doorRes == false, "runCure harus gagal jika bot offline sesaat setelah sampai di pintu")
assert(#dcAtDoorActions == 0, "TIDAK BOLEH mengirim hit/enter/packet offline setelah sampai di pintu (actions: " .. #dcAtDoorActions .. ")")
local doorLogsStr = table.concat(doorLogs, "\n")
assert(doorLogsStr:find("Gagal findPath ke adventure door") or doorLogsStr:find("Bot offline sebelum interaksi adventure door"), "harus mendeteksi bot offline pada step 3 door")
print("PASS uji ketahanan disconnect saat sampai di pintu (Kasus B)")

-- Kasus C: World berganti menjadi WRONGWORLD di tengah jalan (misal warp paksa/terlempar)
local wrongWorldActions = {}
local wrongWorldBot
wrongWorldBot = {
    x = 0, y = 0,
    status = 1,
    malady = 1,
    currentWorld = "4AID",
    isInWorld = function(_, w)
        if w then return wrongWorldBot.currentWorld == w end
        return wrongWorldBot.currentWorld ~= ""
    end,
    warp = function(_, w) wrongWorldBot.currentWorld = w end,
    findPath = function(_, x, y)
        wrongWorldBot.x, wrongWorldBot.y = x, y
        if x == 61 and y == 12 then
            -- Tepat sebelum ke key, bot terlempar ke world lain!
            wrongWorldBot.currentWorld = "WRONGWORLD"
            wrongWorldActions = {} -- reset aksi sebelum world berubah
        end
        return true
    end,
    hit = function() table.insert(wrongWorldActions, "hit") end,
    sendPacket = function() table.insert(wrongWorldActions, "sendPacket") end,
    enter = function() table.insert(wrongWorldActions, "enter") end,
}
local wrongWorldLogs = {}
local envWrongWorld = {
    getBot = function() return wrongWorldBot end,
    BotStatus = { online = 1 },
    Event = { variantlist = 1, game_message = 1 },
    addEvent = function(_, fn) _G.__gmHandler = fn end,
    removeEvent = function() end,
    sleep = function() end,
    print = function(s) table.insert(wrongWorldLogs, tostring(s)) end,
    pcall = pcall,
    tostring = tostring,
    type = type,
    string = string,
    tonumber = tonumber,
}
setmetatable(envWrongWorld, { __index = _G })
f_malady = assert(io.open('auto_malady_4aid.lua'))
maladyText = f_malady:read('*a'); f_malady:close()
local wrongMod = assert(load(maladyText, '@auto_malady_4aid.lua', 't', envWrongWorld))("auto_malady_4aid")
local wrongRes = wrongMod.runCure(wrongWorldBot)
assert(wrongRes == false, "runCure harus return false jika world berganti menjadi WRONGWORLD")
assert(#wrongWorldActions == 0, "TIDAK BOLEH mengirim hit/enter/packet jika world berubah saat rute (actions: " .. #wrongWorldActions .. ")")
local wrongLogsStr = table.concat(wrongWorldLogs, "\n")
assert(wrongLogsStr:find("salah world") or wrongLogsStr:find("Salah world"), "harus mencatat error salah world jika terlempar dari 4AID: " .. wrongLogsStr)
print("PASS uji penolakan aksi saat world berubah di tengah rute (Kasus C)")

-- 13. Uji disconnect selama dispatcher berjalan (tidak boleh menyalakan rotasi jika masih offline)
local dcDuringDispSteps = 0
local dcDispBot = {
    name = "TEST_DISP_DC_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    status = 1,
    malady = 1,
    level = 50,
    rotation = { enabled = true },
    auto_malady = { enabled = true, auto_grumbleteeth = false, auto_chicken_feet = false },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
    warp = function() end,
    findPath = function()
        -- Simulasi DC di tengah pengobatan
        dcDispBot.status = 0
        return false
    end,
    hit = function() end,
    sendPacket = function() end,
    enter = function() end,
}
local dispLogs = {}
local envDispDc = {
    getBot = function() return dcDispBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    Event = { variantlist = 1, game_message = 1 },
    addEvent = function(_, fn) _G.__gmHandler = fn end,
    removeEvent = function() end,
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        dcDuringDispSteps = dcDuringDispSteps + 1
        if dcDuringDispSteps == 1 then
            -- Awal watchdog
        elseif dcDuringDispSteps >= 2 then
            -- Akhiri loop
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(dispLogs, tostring(s)) end,
    os = os,
    require = function() return maladyMod end,
}
setmetatable(envDispDc, { __index = _G })
pcall(function() assert(load(text, '@engine.lua', 't', envDispDc))(cfgRecon) end)
assert(dcDispBot.rotation.enabled == false, "rotasi TIDAK BOLEH dinyalakan jika pengobatan gagal/masih sakit atau bot offline!")
print("PASS guard disconnect selama dispatcher berjalan")

-- 16. Uji pengobatan gagal saat online -> rotasi tetap terjeda dan TIDAK salah dideteksi sebagai stop manual
local failOnlineDispBot = {
    name = "TEST_FAIL_ONLINE_DISP_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    malady = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
    warp = function() end,
    findPath = function()
        -- Gagal path saat online (misal terhalang)
        return false
    end,
    hit = function() end,
    sendPacket = function() end,
    enter = function() end,
}
local failOnlineSteps = 0
local failOnlineLogs = {}
local envFailOnline = {
    getBot = function() return failOnlineDispBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    Event = { variantlist = 1, game_message = 1 },
    addEvent = function(_, fn) _G.__gmHandler = fn end,
    removeEvent = function() end,
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        failOnlineSteps = failOnlineSteps + 1
        if failOnlineSteps >= 3 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(failOnlineLogs, tostring(s)) end,
    os = os,
    require = function() return maladyMod end,
}
setmetatable(envFailOnline, { __index = _G })
pcall(function() assert(load(text, '@engine.lua', 't', envFailOnline))(cfgRecon) end)
local failOnlineLogsStr = table.concat(failOnlineLogs, "\n")
assert(not failOnlineLogsStr:find("Rotasi dimatikan secara manual oleh user"), "pause pengobatan TIDAK BOLEH dianggap stop manual!")
assert(failOnlineDispBot.rotation.enabled == false, "rotasi harus tetap ditahan mati selama bot masih sakit")
print("PASS pause pengobatan saat online tidak dianggap stop manual & rotasi tetap terjeda")

-- 17. Uji integrasi pengobatan: gagal -> cooldown -> retry -> cured -> rotasi dipulihkan
local retryBot = {
    name = "TEST_RETRY_CURE_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    malady = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local retryModRuns = 0
local mockHospitalMod = {
    checkNeedsHospital = function(b) return b.malady == 1, 1 end,
    hasAnyMalady = function(b) return b.malady > 0, b.malady end,
    runCure = function(b)
        retryModRuns = retryModRuns + 1
        if retryModRuns == 1 then
            -- Percobaan 1 gagal
            return false
        else
            -- Percobaan 2 (retry) sukses sembuh!
            b.malady = 0
            return "cured"
        end
    end,
}
local retrySteps = 0
local fakeTime = 1000
local retryLogs = {}
local envRetry = {
    getBot = function() return retryBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        retrySteps = retrySteps + 1
        if retrySteps == 2 then
            -- Pasca percobaan 1 gagal: maju 200 detik melewati cooldown (180 detik). flag
            fakeTime = fakeTime + 200
        elseif retrySteps >= 5 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(retryLogs, tostring(s)) end,
    io = io,
    pcall = pcall,
    type = type,
    tostring = tostring,
    os = {
        time = function() return fakeTime end,
        getenv = os.getenv,
    },
    require = function(modname)
        if modname == "auto_malady_4aid" then return mockHospitalMod end
        return nil
    end,
    Webhook = { new = function() return { embed1 = { addField = function() end } } end },
}
setmetatable(envRetry, { __index = _G })
local okRetry, errRetry = pcall(function() assert(load(text, '@engine.lua', 't', envRetry))(cfgRecon) end)
if not okRetry and not tostring(errRetry):find("TERMINATE_TEST_LOOP") then
    error(errRetry)
end
assert(retryModRuns >= 2, "dispatcher harus melakukan retry setelah cooldown berlalu")
assert(retryBot.malady == 0, "bot harus sembuh setelah retry")
assert(retryBot.rotation.enabled == true, "rotasi HARUS dipulihkan setelah retry berhasil 'cured'!")
print("PASS integrasi pengobatan gagal -> cooldown -> retry -> cured -> rotasi dipulihkan")

-- 18. Uji pending -> penyakit bermutasi ke non-target (ID 5: Broken Heart) -> reconnect -> rotasi tetap ditahan mati
local nonTargetDispBot = {
    name = "TEST_NON_TARGET_DISP_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    malady = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local nonTargetMod = {
    checkNeedsHospital = function(b) return b.malady == 1, 1 end,
    hasAnyMalady = function(b)
        -- Penyakit bermutasi ke non-target (ID 5: Broken Heart) saat pending
        return (b.malady > 0), b.malady
    end,
    runCure = function(b)
        -- Pengobatan gagal, penyakit berubah ke ID 5 (Broken Heart)
        b.malady = 5
        return false
    end,
}
local nonTargetSteps = 0
local envNonTarget = {
    getBot = function() return nonTargetDispBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        nonTargetSteps = nonTargetSteps + 1
        if nonTargetSteps == 1 then
            -- Bot sempat DC setelah mutasi
            nonTargetDispBot.status = 0
            nonTargetDispBot.rotation.enabled = false
        elseif nonTargetSteps == 2 then
            -- Reconnect saat masih sakit (ID 5)
            nonTargetDispBot.status = 1
        elseif nonTargetSteps >= 4 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function() end,
    os = os,
    require = function() return nonTargetMod end,
}
setmetatable(envNonTarget, { __index = _G })
local okNonTarget, errNonTarget = pcall(function() assert(load(text, '@engine.lua', 't', envNonTarget))(cfgRecon) end)
if not okNonTarget and not tostring(errNonTarget):find("TERMINATE_TEST_LOOP") then
    error(errNonTarget)
end
assert(nonTargetDispBot.rotation.enabled == false, "rotasi TIDAK BOLEH dinyalakan jika reconnect saat malady masih belum sembuh (ID 5: Broken Heart)!")
print("PASS pending malady non-target -> reconnect -> rotasi tetap ditahan mati")

-- Engine utuh: pending -> unknown -> disconnect/reconnect -> tetap pause -> valid 0 -> resume.
do
    local b = nonTargetDispBot
    b.status, b.malady = 1, 1
    b.rotation.enabled = true
    local steps, runs, unknownReads, reconnectChecks = 0, 0, 0, 0
    envNonTarget.require = function()
        return {
            checkNeedsHospital = function(bot) return bot.malady == 1, bot.malady end,
            hasAnyMalady = function(bot)
                if bot.malady == "invalid" then
                    unknownReads = unknownReads + 1
                    assert(bot.rotation.enabled == false, "unknown tidak boleh melepas pause")
                    return "unknown"
                end
                return bot.malady ~= 0, bot.malady
            end,
            runCure = function(bot)
                runs = runs + 1
                assert(bot.rotation.enabled == false, "dispatch harus dijeda")
                bot.malady = "invalid"
                return false
            end,
        }
    end
    envNonTarget.sleep = function()
        steps = steps + 1
        assert(steps < 9, "supervisor test tidak selesai")
        if steps == 2 then
            assert(runs == 1 and b.rotation.enabled == false, "episode harus pending sebelum DC")
            b.status = 0
        elseif steps == 3 then
            b.status = 1
        elseif steps == 5 then
            assert(unknownReads > 0, "watchdog wajib membaca unknown setelah reconnect")
            assert(b.status == 1 and b.rotation.enabled == false, "reconnect unknown harus tetap pause")
            reconnectChecks = reconnectChecks + 1
            b.malady = 0
        elseif steps == 6 then
            assert(b.rotation.enabled == true, "valid 0 harus memulihkan resume intent")
            error("TERMINATE_UNKNOWN_TEST")
        end
    end
    local ok, err = pcall(function()
        assert(load(text, '@engine.lua', 't', envNonTarget))(cfgRecon)
    end)
    assert(not ok and tostring(err):find("TERMINATE_UNKNOWN_TEST", 1, true), tostring(err))
    assert(runs == 1 and reconnectChecks == 1, "jalur unknown/reconnect harus benar-benar dieksekusi")
    print("PASS engine utuh pending -> unknown -> reconnect tetap pause -> valid 0 resume")
end

-- 19. Uji Webhook Offline Alert: bot offline > 5 menit men-tag user id 922775541097066576
local offlineAlertBot = {
    name = "TEST_ALERT_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 0, -- offline
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local offlineAlertLogs = {}
local offlineAlertHooks = {}
local offlineClock = 1000
local alertSteps = 0
local alertMonObj = nil
local envOfflineAlert = {
    getBot = function() return offlineAlertBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        alertSteps = alertSteps + 1
        offlineClock = offlineClock + 70
        if alertSteps >= 8 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(offlineAlertLogs, tostring(s)) end,
    os = {
        time = function() return offlineClock end,
        getenv = os.getenv,
    },
    require = function(mod)
        if mod == "webhook_monitor" then
            local f = assert(io.open('webhook_monitor.lua'))
            local code = f:read('*a'); f:close()
            local envMon = {
                BotStatus = { online = 1 },
                os = { time = function() return offlineClock end },
                print = function() end,
                Webhook = {
                    new = function()
                        return {
                            embed1 = { addField = function() end },
                            send = function(self)
                                if self.content and self.content ~= "" then
                                    table.insert(offlineAlertHooks, self.content)
                                end
                            end,
                            edit = function(self)
                                if self.content and self.content ~= "" then
                                    table.insert(offlineAlertHooks, self.content)
                                end
                            end,
                        }
                    end
                },
                pcall = pcall,
                tonumber = tonumber,
                tostring = tostring,
                type = type,
                string = string,
                math = math,
            }
            setmetatable(envMon, { __index = _G })
            local M = assert(load(code, '@webhook_monitor.lua', 't', envMon))()
            return {
                new = function(b, c)
                    alertMonObj = M.new(b, c, envMon)
                    return alertMonObj
                end
            }
        end
        return nil
    end,
}
setmetatable(envOfflineAlert, { __index = _G })
local cfgAlert = {
    FARM_FROM_FILE = false,
    FARMS = { "WORLD1" },
    BLOCK_ID = 4584,
    SEED_ID = 4585,
    WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = true, URL = "https://discord.com/api/webhooks/mock" },
    OFFLINE_ALERT = { ENABLED = true, TIMEOUT_MINUTES = 5, DISCORD_USER_ID = "922775541097066576" },
}
local okAlert, errAlert = pcall(function() assert(load(text, '@engine.lua', 't', envOfflineAlert))(cfgAlert) end)
if not okAlert and not tostring(errAlert):find("TERMINATE_TEST_LOOP") then
    error(errAlert)
end
local alertFound = false
for _, msg in ipairs(offlineAlertHooks) do
    if msg:find("<@922775541097066576>") and msg:find("offline selama") then
        alertFound = true
        break
    end
end
assert(alertFound, "harus mengirim notifikasi Discord mentag user ID 922775541097066576 saat offline > 5 menit")
print("PASS offline alert men-tag user Discord terverifikasi")

-- 20. Uji Lockout Gagal Login: transisi kegagalan nyata > 15x atau > 5 menit mematikan bypass_logon dan auto_reconnect
local lockoutBot = {
    name = "TEST_LOCKOUT_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 0,
    auto_reconnect = true,
    bypass_logon = true,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local lockoutSteps = 0
local lockoutHooks = {}
local envLockout = {
    getBot = function() return lockoutBot end,
    BotStatus = {
        online = 1,
        offline = 0,
        getting_server_data = 4,
        logon_fail = 2,
        error_connecting = 3,
    },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        lockoutSteps = lockoutSteps + 1
        -- Simulasi transisi kegagalan login nyata bergantian (logon_fail -> error_connecting)
        if lockoutSteps % 2 == 1 then
            lockoutBot.status = 4 -- getting_server_data: attempt start
        else
            lockoutBot.status = 2 -- logon_fail: attempt result fixe
        end
        if lockoutSteps >= 60 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function() end,
    os = {
        time = function() return 1000 + (lockoutSteps * 2) end,
        getenv = os.getenv,
    },
    Webhook = {
        new = function()
            return {
                embed1 = { addField = function() end },
                send = function(self)
                    if self.content and self.content ~= "" then
                        table.insert(lockoutHooks, self.content)
                    end
                end,
                edit = function() end,
            }
        end
    },
    require = function(mod)
        if mod == "webhook_monitor" then
            return {
                new = function()
                    return {
                        tick = function() end,
                        notify = function(msg)
                            table.insert(lockoutHooks, tostring(msg))
                        end
                    }
                end
            }
        end
        return nil
    end,
}
setmetatable(envLockout, { __index = _G })
local cfgLockout = {
    FARM_FROM_FILE = false,
    FARMS = { "WORLD1" },
    BLOCK_ID = 4584,
    SEED_ID = 4585,
    AUTO_RECONNECT = { ENABLED = true, BYPASS_LOGON = true, MAX_FAIL_ATTEMPTS = 15, MAX_FAIL_MINUTES = 5 },
    WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = true, URL = "https://discord.com/api/webhooks/mock" },
}
local okLockout, errLockout = pcall(function() assert(load(text, '@engine.lua', 't', envLockout))(cfgLockout) end)
if not okLockout and not tostring(errLockout):find("TERMINATE_TEST_LOOP") then
    error(errLockout)
end
assert(lockoutBot.auto_reconnect == false, "auto_reconnect harus dimatikan setelah gagal login > 15x")
assert(lockoutBot.bypass_logon == false, "bypass_logon harus dimatikan setelah gagal login > 15x")
assert(lockoutBot.rotation.enabled == false, "rotasi harus dimatikan saat lockout")
local lockoutAlertFound = false
for _, msg in ipairs(lockoutHooks) do
    if msg:find("Login Fail Lockout") and msg:find("DINONAKTIFKAN") then
        lockoutAlertFound = true
        break
    end
end
assert(lockoutAlertFound, "harus mengirim alert webhook saat lockout login terjadi")
print("PASS lockout gagal login > 15x / > 5 menit mematikan bypass & reconnect permanen")

-- 20b. Uji lockout tetap mengunci rotasi pada watchdog meskipun status online
local lockWatchBot = {
    name = "TEST_LOCK_WATCH_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 0, -- mula-mula offline
    auto_reconnect = true,
    bypass_logon = true,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local lockWatchSteps = 0
local envLockWatch = {
    getBot = function() return lockWatchBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, selectAll = function() end } end,
    sleep = function()
        lockWatchSteps = lockWatchSteps + 1
        if lockWatchSteps <= 60 then
            -- Picu kegagalan transisi login hingga lockout
            lockWatchBot.status = (lockWatchSteps % 2 == 1) and 4 or 2
        elseif lockWatchSteps == 61 then
            -- Bot tiba-tiba online setelah lockout terpicu (namun owner TIDAK mereset auto_reconnect)
            lockWatchBot.status = 1
            lockWatchBot.auto_reconnect = false -- pastikan tetap false
        elseif lockWatchSteps >= 65 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function() end,
    os = { time = function() return 1000 + (lockWatchSteps * 2) end, getenv = os.getenv },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envLockWatch, { __index = _G })
local okWatch, errWatch = pcall(function() assert(load(text, '@engine.lua', 't', envLockWatch))(cfgLockout) end)
assert(not okWatch and tostring(errWatch):find("TERMINATE_TEST_LOOP", 1, true), tostring(errWatch))
assert(lockWatchSteps >= 65, "test harus melewati reconnect")

assert(lockWatchBot.rotation.enabled == false, "rotasi TIDAK BOLEH aktif kembali saat lockout meskipun status online!")
assert(lockWatchBot.auto_reconnect == false and lockWatchBot.bypass_logon == false, "fitur harus tetap terkunci!")
print("PASS lockout tetap mengunci rotasi meskipun status online")

-- 20c. Uji batas durasi offline/gagal login (offline tanpa transisi status melebihi MAX_FAIL_MINUTES)
local durLockoutBot = {
    name = "TEST_DUR_LOCKOUT_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 0, -- offline diam tanpa transisi
    auto_reconnect = true,
    bypass_logon = true,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local durLockoutSteps = 0
local durLockoutClock = 1000
local envDurLockout = {
    getBot = function() return durLockoutBot end,
    BotStatus = { online = 1, offline = 0 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, selectAll = function() end } end,
    sleep = function()
        durLockoutSteps = durLockoutSteps + 1
        if durLockoutSteps == 1 then
            -- Langsung maju 350 detik (> 5 menit / 300s batas durasi)
            durLockoutClock = durLockoutClock + 350
        elseif durLockoutSteps >= 3 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function() end,
    os = {
        time = function() return durLockoutClock end,
        getenv = os.getenv,
    },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envDurLockout, { __index = _G })
local cfgDurLockout = {
    FARM_FROM_FILE = false,
    FARMS = { "WORLD1" },
    BLOCK_ID = 4584,
    SEED_ID = 4585,
    AUTO_RECONNECT = { ENABLED = true, BYPASS_LOGON = true, MAX_FAIL_ATTEMPTS = 50, MAX_FAIL_MINUTES = 5 },
}
pcall(function() assert(load(text, '@engine.lua', 't', envDurLockout))(cfgDurLockout) end)
assert(durLockoutBot.auto_reconnect == false, "auto_reconnect harus dimatikan saat durasi gagal login > 5 menit")
assert(durLockoutBot.bypass_logon == false, "bypass_logon harus dimatikan saat durasi gagal login > 5 menit")
print("PASS lockout batas durasi gagal login (> 5 menit) terverifikasi")

-- 20d. Uji pemulihan manual owner pada runtime: lockout terpicu, owner ubah flag saat runtime, engine langsung pulih
local runtimeLockBot = {
    name = "TEST_RUNTIME_LOCK_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 0,
    auto_reconnect = true,
    bypass_logon = true,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local runtimeSteps = 0
local envRuntimeLock = {
    getBot = function() return runtimeLockBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, selectAll = function() end } end,
    sleep = function()
        runtimeSteps = runtimeSteps + 1
        if runtimeSteps <= 32 then
            -- Picu kegagalan transisi login hingga lockout aktif
            runtimeLockBot.status = (runtimeSteps % 2 == 1) and 4 or 2
        elseif runtimeSteps == 33 then
            -- Verifikasi bahwa bot sudah lockout
            assert(runtimeLockBot.auto_reconnect == false and runtimeLockBot.bypass_logon == false, "harus sudah terkunci!")
            -- Owner melakukan intervensi manual pada runtime dengan menyalakan auto_reconnect!
            runtimeLockBot.auto_reconnect = true
        elseif runtimeSteps == 34 then
            -- Bot kembali online setelah reset
            runtimeLockBot.status = 1
        elseif runtimeSteps >= 36 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function() end,
    os = { time = function() return 1000 + (runtimeSteps * 2) end, getenv = os.getenv },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envRuntimeLock, { __index = _G })
pcall(function() assert(load(text, '@engine.lua', 't', envRuntimeLock))(cfgLockout) end)
assert(runtimeLockBot.rotation.enabled == true, "rotasi HARUS pulih setelah owner mereset auto_reconnect secara manual pada runtime!")
print("PASS pemulihan manual runtime oleh owner terverifikasi tanpa restart script")

-- 14. Uji disconnect saat memasuki waitOnline() lalu pulih selama penantian (TIDAK BOLEH dianggap stop manual) ternary?
local inWaitSteps = 0
local inWaitBot = {
    name = "TEST_IN_WAIT_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local inWaitLogs = {}
local inWaitEnv = {
    getBot = function() return inWaitBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        inWaitSteps = inWaitSteps + 1
        if inWaitSteps == 1 then
            -- Siklus watchdog 1: bot online normal
        elseif inWaitSteps == 2 then
            -- Bot disconnect dan rotasi mati tepat saat evaluasi
            inWaitBot.status = 0
            inWaitBot.rotation.enabled = false
        elseif inWaitSteps == 3 then
            -- Bot masih offline di dalam loop waitOnline()
            inWaitBot.status = 0
        elseif inWaitSteps == 4 then
            -- Bot berhasil reconnect di dalam loop waitOnline()!
            inWaitBot.status = 1
        elseif inWaitSteps >= 6 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(inWaitLogs, tostring(s)) end,
    os = os,
}
setmetatable(inWaitEnv, { __index = _G })
pcall(function() assert(load(text, '@engine.lua', 't', inWaitEnv))(cfgRecon) end)
local inWaitLogsStr = table.concat(inWaitLogs, "\n")
assert(not inWaitLogsStr:find("Rotasi dimatikan secara manual"), "reconnect selama waitOnline TIDAK BOLEH dianggap stop manual: " .. inWaitLogsStr)
assert(inWaitLogsStr:find("Bot pulih dari disconnect"), "rotasi HARUS dipulihkan setelah reconnect selama waitOnline")
assert(inWaitBot.rotation.enabled == true, "rotasi harus aktif kembali")
print("PASS disconnect di dalam waitOnline() pulih tanpa dianggap stop manual")

-- 15. Uji offline berkepanjangan melampaui timeout lalu reconnect (loop supervisor tidak mati)
local longDcSteps = 0
local longDcBot = {
    name = "TEST_LONG_DC_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local longDcLogs = {}
local longDcEnv = {
    getBot = function() return longDcBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        longDcSteps = longDcSteps + 1
        if longDcSteps == 1 then
            -- Bot offline berkepanjangan
            longDcBot.status = 0
            longDcBot.rotation.enabled = false
        elseif longDcSteps >= 2 and longDcSteps <= 15 then
            -- Melewati batas timeout waitOnline(10)
            longDcBot.status = 0
        elseif longDcSteps == 16 then
            -- Akhirnya bot reconnect setelah sekian lama!
            longDcBot.status = 1
        elseif longDcSteps >= 18 then
            error("TERMINATE_TEST_LOOP")
        end
    end,
    print = function(s) table.insert(longDcLogs, tostring(s)) end,
    os = os,
}
setmetatable(longDcEnv, { __index = _G })
pcall(function() assert(load(text, '@engine.lua', 't', longDcEnv))(cfgRecon) end)
local longDcLogsStr = table.concat(longDcLogs, "\n")
assert(longDcLogsStr:find("Bot pulih dari disconnect"), "supervisor harus tetap hidup dan memulihkan rotasi pasca-offline berkepanjangan: " .. longDcLogsStr)
assert(longDcBot.rotation.enabled == true, "rotasi harus aktif kembali setelah long offline")
print("PASS supervisor bertahan dari offline berkepanjangan melampaui timeout")

-- 21. Uji integrasi dashboard: tidak menampilkan daftar farm, hanya world saat ini
local dashHooks = {}
local dashBot = {
    name = "TEST_DASH_BOT",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    rotation = { enabled = true },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true },
    auto_harvest = { enabled = true },
    auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function(self) return { name = "CURRENT_FARM_ONLY" } end,
    isInWorld = function(self, w)
        if w then return w == "CURRENT_FARM_ONLY" end
        return true
    end,
    getPing = function() return 20 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local dashSteps = 0
local envDash = {
    getBot = function() return dashBot end,
    BotStatus = { online = 1 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            addFarm = function() end,
            removeFarm = function() end,
            addStorage = function() end,
            removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        dashSteps = dashSteps + 1
        if dashSteps >= 2 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function() end,
    os = {
        time = function() return 1000 + (dashSteps * 15) end,
        getenv = os.getenv,
    },
    require = function(mod)
        if mod == "webhook_monitor" then
            local f = assert(io.open('webhook_monitor.lua'))
            local code = f:read('*a'); f:close()
            local envMon = {
                BotStatus = { online = 1 },
                os = { time = function() return 1000 + (dashSteps * 15) end },
                pcall = pcall,
                tonumber = tonumber,
                tostring = tostring,
                type = type,
                string = string,
                math = math,
                Webhook = {
                    new = function()
                        return {
                            embed1 = { addField = function() end },
                            send = function(self)
                                if self.content and self.content ~= "" then
                                    table.insert(dashHooks, self.content)
                                end
                            end,
                            edit = function(self)
                                if self.content and self.content ~= "" then
                                    table.insert(dashHooks, self.content)
                                end
                            end,
                        }
                    end
                },
            }
            local M = assert(load(code, '@webhook_monitor.lua', 't', envMon))()
            return {
                new = function(b, c)
                    return M.new(b, c, envMon)
                end
            }
        end
        return nil
    end,
}
setmetatable(envDash, { __index = _G })
local cfgDash = {
    FARM_FROM_FILE = false,
    FARMS = { "SECRET_FARMLIST_1", "SECRET_FARMLIST_2" },
    BLOCK_ID = 4584,
    SEED_ID = 4585,
    WEBHOOK = { EVENT_NOTIFICATIONS = true, MIN_EDIT_SECONDS = 5, ENABLED = true, URL = "https://discord.com/api/webhooks/mock" },
}
local okDash, errDash = pcall(function() assert(load(text, '@engine.lua', 't', envDash))(cfgDash) end)
if not okDash and not tostring(errDash):find("TERMINATE_TEST_LOOP") then
    error(errDash)
end
assert(#dashHooks > 0, "dashboard webhook harus terkirim")
local foundWorldName = false
for _, content in ipairs(dashHooks) do
    assert(not content:find("SECRET_FARMLIST"), "daftar farm tidak boleh bocor/tampil di dashboard!")
    if content:find("CURRENT_FARM_ONLY") then
        foundWorldName = true
    end
end
assert(foundWorldName, "dashboard harus memuat nama world saat ini: CURRENT_FARM_ONLY")
print("PASS integrasi dashboard: hanya tampilkan world saat ini tanpa list farm")

-- 21. Timer recovery AutoSpam harus bertahan setelah script di-restart.
-- Tanpa file state, spam langsung menyala lagi pasca-cured padahal owner minta jeda 1 jam.
local tmpDir = os.getenv("TEMP") or "."
local statePath = tmpDir .. "/lucifer_spam_recovery.txt"
local futureUntil = (os.time() or 0) + 900
do
    local f = assert(io.open(statePath, "w"))
    f:write(tostring(futureUntil))
    f:close()
end

local spamBot = {
    name = "TEST_SPAM_RESTART",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    malady = 0,
    auto_spam = { enabled = true },
    auto_reconnect = true,
    rotation = { enabled = false },
    auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local spamSteps = 0
local envSpam = {
    getBot = function() return spamBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        spamSteps = spamSteps + 1
        if spamSteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function() end,
    os = {
        time = function() return os.time() end,
        getenv = function(k)
            if k == "TEMP" or k == "TMP" then return tmpDir end
            return os.getenv(k)
        end,
        date = os.date,
    },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envSpam, { __index = _G })
local okSpam, errSpam = pcall(function() assert(load(text, '@engine.lua', 't', envSpam))({ FARM_FROM_FILE = false, FARMS = {}, AUTO_SPAM = { ENABLED = true, RECOVERY_SECONDS = 3600 } }) end)
if not okSpam and not tostring(errSpam):find("TERMINATE_TEST_LOOP") then error(errSpam) end
assert(spamBot.auto_spam.enabled == false,
    "AutoSpam harus tetap OFF setelah restart selama timer recovery belum habis, dapat: " .. tostring(spamBot.auto_spam.enabled))
os.remove(statePath)
print("PASS timer recovery AutoSpam bertahan setelah restart")

-- 22. Build host yang menolak sebagian field rotasi tidak boleh mematikan rotasi.
-- Dulu satu field asing melempar error -> applyRotationSettings gagal -> rotasi OFF.
local ROTATION_KNOWN = {
    enabled = true, auto_rest = true, harvest_roots = true, dynamic_delay = true,
    visit_random_worlds = true, custom_position = true, harvest_interval = true,
    plant_interval = true, break_interval = true, pnb_in_home = true,
    pnb_world = true, seed_drop_amount = true,
}
local strictFields = { enabled = true }
local strictRotation = setmetatable({}, {
    __index = function(_, k) return strictFields[k] end,
    __newindex = function(_, k, v)
        if not ROTATION_KNOWN[k] then
            error("field rotasi tidak didukung host: " .. tostring(k))
        end
        strictFields[k] = v
    end,
})
local strictBot = {
    name = "TEST_STRICT_ROTATION",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    malady = 0,
    auto_spam = { enabled = false },
    auto_reconnect = true,
    rotation = strictRotation,
    auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local strictSteps = 0
local strictLog = {}
local envStrict = {
    getBot = function() return strictBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        strictSteps = strictSteps + 1
        if strictSteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) strictLog[#strictLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envStrict, { __index = _G })
local okStrict, errStrict = pcall(function()
    assert(load(text, '@engine.lua', 't', envStrict))({
        FARM_FROM_FILE = false,
        FARMS = { "STRICT_FARM" },
        BLOCK_ID = 4584,
        SEED_ID = 4585,
        PNB = { ENABLED = true, WORLD = "PNBWORLD" },
        STORE_SEED_MIN = 100,
    })
end)
if not okStrict and not tostring(errStrict):find("TERMINATE_TEST_LOOP") then error(errStrict) end
assert(strictBot.rotation.enabled == true,
    "rotasi HARUS menyala walau host menolak sebagian field; log: " .. table.concat(strictLog, " | "))
print("PASS host menolak sebagian field rotasi -> rotasi tetap menyala")

-- 23. Host yang melempar error saat rotation.enabled = true (mis. farm belum
-- ter-assign) dulu membunuh script tepat setelah setup: toggle tidak pernah
-- menyala dan supervisor penyakit mati. Sekarang harus dilaporkan & tetap hidup.
local strictFields2 = { enabled = false }
local denyRotation = setmetatable({}, {
    __index = function(_, k) return strictFields2[k] end,
    __newindex = function(_, k, v)
        if k == "enabled" and v == true then
            error("rotation tidak bisa dinyalakan: belum ada farm ter-assign")
        end
        if not ROTATION_KNOWN[k] then
            error("field rotasi tidak didukung host: " .. tostring(k))
        end
        strictFields2[k] = v
    end,
})
local denyBot = {
    name = "TEST_DENY_ROTATION",
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    status = 1,
    malady = 0,
    auto_spam = { enabled = false },
    auto_reconnect = true,
    rotation = denyRotation,
    auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local denySteps, denyLog, denyIntervals = 0, {}, {}
local envDeny = {
    getBot = function() return denyBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    Action = { move = "move", hit = "hit", place = "place", harvest = "harvest", plant = "plant", warp = "warp", drop = "drop", trash = "trash" },
    getWorldManager = function()
        return {
            addFarm = function() end, removeFarm = function() end,
            addStorage = function() end, removeStorage = function() end,
            selectAll = function() end, apply = function() end,
        }
    end,
    sleep = function()
        denySteps = denySteps + 1
        if denySteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) denyLog[#denyLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envDeny, { __index = _G })
-- setInterval lewat method bot; tambahkan ke tabel bot
denyBot.setInterval = function(_, action, seconds) denyIntervals[action] = seconds end
local okDeny, errDeny = pcall(function()
    assert(load(text, '@engine.lua', 't', envDeny))({
        FARM_FROM_FILE = false, FARMS = { "DENY_FARM" },
        BLOCK_ID = 4584, SEED_ID = 4585,
        ACTION_INTERVALS = {
            moveDelay = 110, hitDelay = 160, placeDelay = 115,
            harvestDelay = 150, plantDelay = 140,
            warpDelay = 7000, dropDelay = 4000, trashDelay = 4000,
            dynamicDelay = false,
        },
    })
end)
assert(not okDeny and tostring(errDeny):find("TERMINATE_TEST_LOOP", 1, true),
    "engine harus bertahan hidup setelah host menolak rotation.enabled=true, err: " .. tostring(errDeny))
local sawEnableError = false
for _, line in ipairs(denyLog) do
    if line:find("Gagal menyalakan rotasi", 1, true) then sawEnableError = true end
    assert(not line:find("Rotasi bawaan Lucifer AKTIF", 1, true), "tidak boleh mengklaim AKTIF saat host menolak")
    assert(not line:find("field rotasi tidak dikenal", 1, true),
        "field yang memang tidak ada di host tidak boleh jadi peringatan: " .. line)
end
assert(sawEnableError, "kegagalan menyalakan rotasi harus dilaporkan, log: " .. table.concat(denyLog, " | "))
assert(denyIntervals.harvest == 0.15, "ms->detik: harvestDelay 150 harus jadi 0.15, dapat: " .. tostring(denyIntervals.harvest))
assert(denyIntervals.move == 0.11, "moveDelay 110 harus jadi 0.11, dapat: " .. tostring(denyIntervals.move))
assert(denyIntervals.warp == 7, "warpDelay 7000 harus jadi 7, dapat: " .. tostring(denyIntervals.warp))
assert(denyIntervals.trash == 4, "trashDelay 4000 harus jadi 4, dapat: " .. tostring(denyIntervals.trash))
assert(denyIntervals.hit == 0.16 and denyIntervals.place == 0.115, "hit/place harus ikut ms config")
assert(denyBot.dynamic_delay == false, "dynamicDelay=false harus diteruskan ke bot.dynamic_delay (v2.86), dapat: " .. tostring(denyBot.dynamic_delay))
print("PASS host menolak rotation.enabled=true -> dilaporkan, supervisor tetap hidup, interval via setInterval")

-- 24. Script dijalankan sebelum bot login: host mengabaikan enabled=true saat
-- offline. Dulu bacaan enabled==false berikutnya dianggap "stop manual" dan
-- rotasi tidak pernah menyala lagi.
local hostReady = false
local lateFields = { enabled = false }
local lateRotation = setmetatable({}, {
    __index = function(_, k) return lateFields[k] end,
    __newindex = function(_, k, v)
        if k == "enabled" then
            if v == true and not hostReady then return end -- host belum siap: diabaikan
            lateFields.enabled = v
            return
        end
        lateFields[k] = v
    end,
})
local lateBot = {
    name = "TEST_LATE_LOGIN", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = lateRotation, auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local lateSteps, lateLog = 0, {}
local envLate = {
    getBot = function() return lateBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        lateSteps = lateSteps + 1
        if lateSteps == 3 then hostReady = true end -- host baru siap menerima toggle
        if lateSteps >= 6 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) lateLog[#lateLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envLate, { __index = _G })
local okLate, errLate = pcall(function()
    assert(load(text, '@engine.lua', 't', envLate))({ FARM_FROM_FILE = false, FARMS = { "LATE_FARM" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okLate and tostring(errLate):find("TERMINATE_TEST_LOOP", 1, true), tostring(errLate))
assert(lateBot.rotation.enabled == true, "watchdog harus menyalakan rotasi setelah login selesai")
local sawManualStop = false
for _, line in ipairs(lateLog) do
    if line:find("dimatikan secara manual", 1, true) then sawManualStop = true end
end
assert(not sawManualStop, "rotasi yang belum pernah menyala TIDAK boleh dianggap stop manual")
print("PASS script dijalankan sebelum login -> rotasi dinyalakan watchdog, bukan dianggap stop manual")

-- 25. Rotasi belum pernah menyala saat bot sakit; setelah sembuh harus tetap farming.
local cureSteps, cureLog = 0, {}
local cureBot = {
    name = "TEST_CURE_NEVER_ON", status = 1, malady = 1,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = { enabled = false }, auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local cureMod = {
    hasAnyMalady = function(b) return (b.malady > 0), b.malady end,
    checkNeedsHospital = function(b) return b.malady == 1, b.malady end,
    runCure = function(b) b.malady = 0; return "cured" end,
}
local envCure = {
    getBot = function() return cureBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        cureSteps = cureSteps + 1
        if cureSteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) cureLog[#cureLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function(name)
        if name == "auto_malady_4aid" then return cureMod end
        return { new = function() return { tick = function() end, notify = function() end } end }
    end,
}
setmetatable(envCure, { __index = _G })
local okCure, errCure = pcall(function()
    assert(load(text, '@engine.lua', 't', envCure))({ FARM_FROM_FILE = false, FARMS = { "CURE_FARM" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okCure and tostring(errCure):find("TERMINATE_TEST_LOOP", 1, true), tostring(errCure))
assert(cureBot.rotation.enabled == true,
    "setelah sembuh rotasi HARUS dinyalakan walau sebelumnya belum pernah menyala; log: " .. table.concat(cureLog, " | "))
print("PASS sembuh -> rotasi dinyalakan walau sebelumnya belum pernah aktif")

-- 26. Start pertama: rotation.enabled hanya boleh ditulis SEKALI (true).
-- Dulu dimatikan dulu lalu dinyalakan di tick yang sama; build yang mengabaikan
-- toggle kedua membuat rotasi tidak pernah aktif saat script dijalankan.
local toggleWrites = {}
local onceFields = { enabled = false }
local onceRotation = setmetatable({}, {
    __index = function(_, k) return onceFields[k] end,
    __newindex = function(_, k, v)
        if k == "enabled" then toggleWrites[#toggleWrites + 1] = v end
        onceFields[k] = v
    end,
})
local onceBot = {
    name = "TEST_SINGLE_TOGGLE", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = onceRotation, auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local onceSteps = 0
local envOnce = {
    getBot = function() return onceBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        onceSteps = onceSteps + 1
        if onceSteps >= 2 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function() end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envOnce, { __index = _G })
local okOnce, errOnce = pcall(function()
    assert(load(text, '@engine.lua', 't', envOnce))({ FARM_FROM_FILE = false, FARMS = { "ONCE_FARM" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okOnce and tostring(errOnce):find("TERMINATE_TEST_LOOP", 1, true), tostring(errOnce))
assert(#toggleWrites == 1, "rotation.enabled harus ditulis tepat sekali saat start, dapat: " .. tostring(#toggleWrites))
assert(toggleWrites[1] == true, "satu-satunya tulisan harus true")
assert(onceBot.rotation.enabled == true, "rotasi harus aktif sejak start")
print("PASS start pertama: rotation.enabled ditulis sekali (true), tanpa toggle ganda")

-- 27. Diagnostik harus mencetak isi nyata bot.rotation (bukan tebakan).
-- Build host di lapangan punya runInbuiltRotation/getInbuiltRotationStatus,
-- jadi daftar field harus terbaca dari objeknya sendiri.
local diagLog = {}
local diagRotation = setmetatable({ status = 0, pnb_in_home = true, custom_position = 0 }, {
    __index = function(_, k) if k == "enabled" then return false end end,
    __newindex = function(t, k, v)
        if k == "enabled" then error("rotation.enabled read-only di build ini") end
        rawset(t, k, v)
    end,
})
local diagBot = {
    name = "TEST_DIAG", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = diagRotation,
    auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local diagSteps = 0
local envDiag = {
    getBot = function() return diagBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        diagSteps = diagSteps + 1
        if diagSteps >= 2 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) diagLog[#diagLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envDiag, { __index = _G })
local okDiag, errDiag = pcall(function()
    assert(load(text, '@engine.lua', 't', envDiag))({ FARM_FROM_FILE = false, FARMS = { "DIAG_FARM" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okDiag and tostring(errDiag):find("TERMINATE_TEST_LOOP", 1, true), tostring(errDiag))
local joined = table.concat(diagLog, "\n")
assert(joined:find("type(bot.rotation)", 1, true), "diagnostik harus mencetak tipe bot.rotation")
assert(joined:find("pnb_in_home", 1, true), "diagnostik harus mencetak daftar field rotation")
assert(joined:find("runInbuiltRotation", 1, true), "diagnostik harus mencetak keberadaan global inbuilt rotation")
print("PASS diagnostik rotasi mencetak tipe, daftar field, dan global inbuilt")

-- 28. Build yang MELEMPAR error saat `rotation.enabled` DIBACA.
-- Dulu bacaan mentah setelah setup membunuh script tanpa pesan: log berhenti di
-- "Selesai: pengaturan rotasi" dan rotasi tidak pernah dinyalakan.
local readErrWrites = {}
local readErrLog = {}
local readErrBot = {
    name = "TEST_READ_ERROR", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = setmetatable({}, {
        __index = function(_, k)
            if k == "enabled" then error("rotation.enabled tidak bisa dibaca di build ini") end
            return nil
        end,
        __newindex = function(_, k, v) readErrWrites[k] = v end,
    }),
    auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return false end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local readErrSteps = 0
local envReadErr = {
    getBot = function() return readErrBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 4, logon_fail = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function() return { addFarm = function() end, removeFarm = function() end, addStorage = function() end, removeStorage = function() end, selectAll = function() end } end,
    sleep = function()
        readErrSteps = readErrSteps + 1
        if readErrSteps >= 4 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) readErrLog[#readErrLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envReadErr, { __index = _G })
local okReadErr, errReadErr = pcall(function()
    assert(load(text, '@engine.lua', 't', envReadErr))({ FARM_FROM_FILE = false, FARMS = { "READERR_FARM" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okReadErr and tostring(errReadErr):find("TERMINATE_TEST_LOOP", 1, true),
    "script tidak boleh mati hanya karena gagal MEMBACA rotation.enabled; err: " .. tostring(errReadErr))
assert(readErrWrites.enabled == true, "rotasi harus tetap dicoba dinyalakan walau status tidak bisa dibaca")
assert(readErrSteps >= 4, "watchdog harus tetap berjalan")
print("PASS gagal baca rotation.enabled tidak membunuh script; toggle tetap dicoba")

-- 30. Dokumentasi Alfin: fase rotasi dibaca lewat simbol RotationStatus, dan
-- pemilihan farm diverifikasi lewat manager.worlds[i].selected.
local selLog = {}
local selBot = {
    name = "TEST_SELECTION", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = { enabled = true, status = 2 },
    auto_malady = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
local selSteps = 0
local envSel = {
    getBot = function() return selBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 28, logon_fail = 20 },
    RotationStatus = { scanning_world = 0, harvesting_trees = 1, farming_block = 2, planting_seeds = 3 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            worlds = { { name = "F1", selected = false }, { name = "F2", selected = false } },
            addFarm = function() end, removeFarm = function() end,
            addStorage = function() end, removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        selSteps = selSteps + 1
        if selSteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s) selLog[#selLog + 1] = tostring(s) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envSel, { __index = _G })
local okSel, errSel = pcall(function()
    assert(load(text, '@engine.lua', 't', envSel))({ FARM_FROM_FILE = false, FARMS = { "F1", "F2" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okSel and tostring(errSel):find("TERMINATE_TEST_LOOP", 1, true), tostring(errSel))
local selText = table.concat(selLog, "\n")
assert(selText:find("farm terpilih setelah selectAll", 1, true),
    "harus memperingatkan setelah selectAll, bukan sebelum; log: " .. selText)
assert(selText:find("farming_block", 1, true),
    "fase rotasi harus disebut dengan simbol RotationStatus, bukan angka; log: " .. selText)
print("PASS fase rotasi pakai RotationStatus dan peringatan farm tak terpilih muncul")

do
-- 31. Setter AutoWear GAGAL sementara auto_farm/auto_harvest/auto_plant awalnya ON.
-- Modul pesaing WAJIB mati dulu; rotasi boleh nyala karena kegagalan itu opsional.
local softLog = {}
local softBot = {
    name = "TEST_SOFT_SETUP", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false },
    auto_reconnect = true,
    rotation = { enabled = false, status = 2 },
    auto_malady = { enabled = true },
    auto_farm = { enabled = true }, auto_harvest = { enabled = true }, auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
-- AutoWear setter melempar error: mensimulasikan API wear yang tidak cocok.
setmetatable(softBot, { __newindex = function(t, k, v)
    if k == "auto_wear" or k == "wear_id" or k == "wear_storage" then
        error("AutoWear setter tidak didukung build ini")
    end
    rawset(t, k, v)
end })
local softSteps = 0
local envSoft = {
    getBot = function() return softBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 28, logon_fail = 20 },
    RotationStatus = { scanning_world = 0, farming_block = 2 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return {
            worlds = { { name = "F1", selected = true } },
            addFarm = function() end, removeFarm = function() end,
            addStorage = function() end, removeStorage = function() end,
            selectAll = function() end,
        }
    end,
    sleep = function()
        softSteps = softSteps + 1
        if softSteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s2) softLog[#softLog + 1] = tostring(s2) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envSoft, { __index = _G })
local okSoft, errSoft = pcall(function()
    assert(load(text, '@engine.lua', 't', envSoft))({ FARM_FROM_FILE = false, FARMS = { "F1" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okSoft and tostring(errSoft):find("TERMINATE_TEST_LOOP", 1, true), tostring(errSoft))
assert(softBot.auto_farm.enabled == false and softBot.auto_harvest.enabled == false and softBot.auto_plant.enabled == false,
    "modul pesaing WAJIB mati walau AutoWear gagal")
assert(softBot.rotation.enabled == true,
    "rotasi harus tetap dinyalakan saat kegagalan hanya opsional; log: " .. table.concat(softLog, " | "))
print("PASS AutoWear gagal -> modul pesaing tetap dimatikan, rotasi tetap dinyalakan")
end

do
-- 32. Modul pesaing yang TIDAK bisa dimatikan harus menahan rotasi.
local blockLog = {}
local blockBot = {
    name = "TEST_BLOCKED_COMPETING", status = 1, malady = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
    auto_spam = { enabled = false }, auto_reconnect = true,
    rotation = { enabled = false, status = 0 },
    auto_malady = { enabled = true },
    auto_harvest = { enabled = true }, auto_plant = { enabled = true },
    x = 10, y = 10, gem_count = 5000,
    getWorld = function() return { name = "HOME" } end,
    isInWorld = function() return true end,
    getPing = function() return 0 end,
    getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
}
-- auto_farm tidak bisa dibaca: pemadaman gagal.
setmetatable(blockBot, { __index = function(_, k)
    if k == "auto_farm" then error("auto_farm tidak bisa diakses") end
end })
local blockSteps = 0
local envBlock = {
    getBot = function() return blockBot end,
    BotStatus = { online = 1, offline = 0, getting_server_data = 28, logon_fail = 20 },
    RotationStatus = { scanning_world = 0 },
    StorageType = { seed = 1, pack = 2 },
    getWorldManager = function()
        return { worlds = { { name = "F1", selected = true } },
                 addFarm = function() end, removeFarm = function() end,
                 addStorage = function() end, removeStorage = function() end,
                 selectAll = function() end }
    end,
    sleep = function()
        blockSteps = blockSteps + 1
        if blockSteps >= 3 then error("TERMINATE_TEST_LOOP") end
    end,
    print = function(s2) blockLog[#blockLog + 1] = tostring(s2) end,
    os = { time = function() return os.time() end, getenv = os.getenv, date = os.date },
    require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
}
setmetatable(envBlock, { __index = _G })
local okBlock, errBlock = pcall(function()
    assert(load(text, '@engine.lua', 't', envBlock))({ FARM_FROM_FILE = false, FARMS = { "F1" }, BLOCK_ID = 4584, SEED_ID = 4585 })
end)
assert(not okBlock and tostring(errBlock):find("TERMINATE_TEST_LOOP", 1, true), tostring(errBlock))
assert(blockBot.rotation.enabled == false, "rotasi TIDAK BOLEH nyala saat modul pesaing masih aktif")
local blockText = table.concat(blockLog, "\n")
assert(blockText:find("modul pesaing", 1, true), "harus menyebut tahap yang gagal")
assert(blockText:find("Rotasi TIDAK dinyalakan", 1, true), "harus menyatakan rotasi ditahan")
print("PASS modul pesaing tak bisa dimatikan -> rotasi ditahan")
end

-- 33. Pack boleh punya world sendiri (STORAGE.packworld), terpisah dari seed.
(function()
    local rp = boot({ customConfig = function(c) c.STORAGE.packworld = "PACKSTORE" end })
    local packEntry = nil
    for _, s2 in ipairs(rp.storages) do
        if s2.kind == 2 then packEntry = s2 end
    end
    assert(packEntry and packEntry.name == "PACKSTORE:PACKDOOR",
        "pack storage harus memakai STORAGE.packworld, dapat: " .. tostring(packEntry and packEntry.name))
    local seedEntry = nil
    for _, s2 in ipairs(rp.storages) do
        if s2.kind == 1 then seedEntry = s2 end
    end
    assert(seedEntry and seedEntry.name == "MYSTORE:SEEDDOOR", "seed storage tetap di STORAGE.world")
    print("PASS pack world kustom terpisah dari seed storage")
end)();

-- 34. Setelah sembuh di 4AID, rotasi harus dinyalakan lagi walau percobaan
-- pertama gagal. Dulu rotationConfirmedOn tetap true, watchdog membaca
-- "mati padahal pernah nyala" sebagai stop manual dan mengunci mati.
;(function()
    local log = {}
    local webhookNotes = {}
    local rejects, attempts = 2, 0
    local fields = { enabled = true, status = 2 }
    local rot = setmetatable({}, {
        __index = function(_, k) return fields[k] end,
        __newindex = function(_, k, v)
            if k == "enabled" and v == true then
                attempts = attempts + 1
                if attempts <= rejects then return end -- host menolak dulu
            end
            fields[k] = v
        end,
    })
    local b = {
        name = "TEST_CURE_RESUME", status = 1, malady = 1,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
        auto_spam = { enabled = false }, auto_reconnect = true,
        rotation = rot, auto_malady = { enabled = true },
        auto_farm = { enabled = false }, auto_harvest = { enabled = false }, auto_plant = { enabled = false },
        x = 10, y = 10, gem_count = 5000,
        getWorld = function() return { name = "4AID" } end,
        isInWorld = function() return true end,
        getPing = function() return 0 end,
        getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
    }
    local mod = {
        hasAnyMalady = function(x) return (x.malady > 0), x.malady end,
        checkNeedsHospital = function(x) return x.malady == 1, x.malady end,
        runCure = function(x) x.malady = 0; return "cured" end,
    }
    local steps = 0
    local manualStopTriggeredAt = nil
    local env = {
        getBot = function() return b end,
        BotStatus = { online = 1, offline = 0, getting_server_data = 28, logon_fail = 20 },
        RotationStatus = { farming_block = 2, planting_seeds = 3 },
        StorageType = { seed = 1, pack = 2 },
        getWorldManager = function()
            return { worlds = { { name = "F1", selected = true } },
                     addFarm = function() end, removeFarm = function() end,
                     addStorage = function() end, removeStorage = function() end,
                     selectAll = function() end }
        end,
        sleep = function()
            steps = steps + 1
            -- Setelah rotasi pulih dan berjalan (attempts >= 3), simulasikan owner mematikan rotasi manual
            if steps == 8 and fields.enabled == true then
                fields.enabled = false
                manualStopTriggeredAt = steps
            end
            if steps >= 15 then error("TERMINATE_TEST_LOOP") end
        end,
        print = function(x) log[#log + 1] = tostring(x) end,
        os = { time = function() return os.time() + steps end, getenv = os.getenv, date = os.date },
        require = function(name)
            if name == "auto_malady_4aid" then return mod end
            return { new = function() return {
                tick = function() end,
                notify = function(msg) webhookNotes[#webhookNotes + 1] = tostring(msg) end,
            } end }
        end,
    }
    setmetatable(env, { __index = _G })
    local ok, err = pcall(function()
        assert(load(text, "@engine.lua", "t", env))({ FARM_FROM_FILE = false, FARMS = { "F1" }, BLOCK_ID = 4584, SEED_ID = 4585 })
    end)
    assert(not ok and tostring(err):find("TERMINATE_TEST_LOOP", 1, true), tostring(err))
    local txt = table.concat(log, "\n")
    -- Sebelum step 8 (saat rotasi dicoba pulih): tidak boleh ada tuduhan stop manual
    assert(attempts >= 3, "watchdog harus mencoba mengaktifkan rotasi lagi setelah percobaan pertama ditolak")
    assert(txt:find("Rotasi terkonfirmasi AKTIF setelah bot online", 1, true),
        "rotasi harus terkonfirmasi aktif kembali oleh watchdog")
    -- Notifikasi cured saat enable gagal TIDAK boleh dikirim
    for _, msg in ipairs(webhookNotes) do
        if msg:find("berhasil disembuhkan di 4AID", 1, true) then
            error("notifikasi sembuh + rotasi dilanjutkan TIDAK boleh dikirim jika enable ditolak")
        end
    end
    -- Setelah owner benar-benar mematikan manual di step 8, watchdog harus menghormatinya
    assert(manualStopTriggeredAt ~= nil, "simulasi stop manual harus dieksekusi")
    assert(txt:find("Rotasi dimatikan secara manual oleh user", 1, true),
        "stop manual setelah rotasi aktif harus tetap dihormati watchdog")
    assert(fields.enabled == false, "rotasi harus tetap OFF setelah owner stop manual")
    print("PASS resume pengobatan gagal -> watchdog pulihkan -> stop manual tetap dihormati")
end)();

-- 35. Lockout customizable: jika CONFIG.AUTO_RECONNECT.LOCKOUT_ENABLED = false,
-- gagal login berulang kali dan durasi lama TIDAK mematikan reconnect / bypass.
;(function()
    local log = {}
    local steps = 0
    local b = {
        name = "TEST_NO_LOCKOUT", status = 0,
    say = function(self) _G.__gmName = self and self.name end,
    level = 50,
        auto_reconnect = true, bypass_logon = true,
        rotation = { enabled = true }, auto_malady = { enabled = true },
        auto_farm = { enabled = false }, auto_harvest = { enabled = false }, auto_plant = { enabled = false },
        x = 10, y = 10, gem_count = 5000,
        getWorld = function() return { name = "HOME" } end,
        isInWorld = function() return false end,
        getPing = function() return 0 end,
        getInventory = function() return { itemcount = 0, slotcount = 200, emptyslots = 200, findItem = function() return 0 end } end,
    }
    local env = {
        getBot = function() return b end,
        BotStatus = { online = 1, offline = 0, getting_server_data = 28, logon_fail = 20 },
        RotationStatus = { scanning_world = 0 },
        StorageType = { seed = 1, pack = 2 },
        getWorldManager = function()
            return { worlds = { { name = "F1", selected = true } },
                     addFarm = function() end, removeFarm = function() end,
                     addStorage = function() end, removeStorage = function() end,
                     selectAll = function() end }
        end,
        sleep = function()
            steps = steps + 1
            -- Simulasi 40 kegagalan login bergantian
            b.status = (steps % 2 == 1) and 28 or 20
            if steps >= 50 then error("TERMINATE_TEST_LOOP") end
        end,
        print = function(x) log[#log + 1] = tostring(x) end,
        os = { time = function() return 1000 + (steps * 20) end, getenv = os.getenv, date = os.date },
        require = function() return { new = function() return { tick = function() end, notify = function() end } end } end,
    }
    setmetatable(env, { __index = _G })
    local ok, err = pcall(function()
        assert(load(text, "@engine.lua", "t", env))({
            FARM_FROM_FILE = false, FARMS = { "F1" }, BLOCK_ID = 4584, SEED_ID = 4585,
            AUTO_RECONNECT = { ENABLED = true, LOCKOUT_ENABLED = false, MAX_FAIL_ATTEMPTS = 5, MAX_FAIL_MINUTES = 1 },
        })
    end)
    assert(not ok and tostring(err):find("TERMINATE_TEST_LOOP", 1, true), tostring(err))
    assert(b.auto_reconnect == true, "auto_reconnect HARUS tetap aktif jika LOCKOUT_ENABLED = false")
    assert(b.bypass_logon == true, "bypass_logon HARUS tetap aktif jika LOCKOUT_ENABLED = false")
    local txt = table.concat(log, "\n")
    assert(not txt:find("Login Fail Lockout", 1, true), "lockout alert tidak boleh muncul jika dinonaktifkan")
    print("PASS lockout customizable (LOCKOUT_ENABLED = false) terverifikasi")
end)();

print("All offline simulated checks passed; no server verification.")
