-- Native Lucifer webhook monitor. No network activity until tick()/notify().
local MALADY_NAMES = {
    [0] = "Healthy",
    [1] = "Torn Punching Muscle",
    [2] = "Gem Cuts",
    [3] = "Chicken Feet",
    [4] = "Grumbleteeth",
    [5] = "Broken Heart",
    [6] = "Chaos Infection",
    [7] = "Moldy Guts",
    [8] = "Brainworms",
    [9] = "Lupus",
    [10] = "Ecto-Bones",
    [11] = "Fatty Liver",
}

local function maladyLabel(id)
    return MALADY_NAMES[tonumber(id)] or ("ID " .. tostring(id))
end

local M = {}
function M.new(bot, config, api)
    api = api or _G
    local cfg = config.WEBHOOK or {}
    local range = config.MULTI_BOT
    local alert = config.OFFLINE_ALERT or {}
    local offlineSince, offlineSent, lastMalady, lastDashboard = nil, false, nil, nil
    local dashLogged = false
    local lastPhase = nil
    local messageId = cfg.MESSAGE_ID
    local lastRequest, lastBody = nil, nil
    local retryAfter = 0

    local function now() return api.os.time() end
    local function enabled()
        return cfg.ENABLED == true and type(cfg.URL) == "string" and cfg.URL ~= ""
            and not cfg.URL:find("MASUKKAN_URL", 1, true)
    end

    local createAttempted = false

    local function deliver(content, dashboard)
        if not enabled() then return false end
        if range and tonumber(bot.index) ~= range.startbot then return false end
        if not dashboard and cfg.EVENT_NOTIFICATIONS ~= true then return true end

        local t = now()
        if t < retryAfter then return false end

        if dashboard then
            if content == lastBody then return true end
            local minEdit = math.max(5, tonumber(cfg.MIN_EDIT_SECONDS) or 5)
            if minEdit and minEdit > 0 and lastRequest and (t - lastRequest) < minEdit then return false end
            lastRequest = t
        end

        local id = messageId and tostring(messageId) or ""
        local isGlobal = cfg.GLOBAL == true

        if dashboard and isGlobal and id == "" then
            if not createAttempted and api.print then
                createAttempted = true
                api.print("[Webhook] Mode global WAJIB mengisi CONFIG.WEBHOOK.MESSAGE_ID agar pesan tidak duplikat.")
            end
            return false
        end

        local usedEdit = dashboard and id ~= ""
        if dashboard and not usedEdit then
            if isGlobal then return false end
            -- Single-bot tanpa ID: hanya SATU percobaan pembuatan pesan.
            -- Hasil ambigu (tanpa ID) tidak boleh memicu pengiriman berulang.
            if createAttempted then return false end
            createAttempted = true
        end

        local hookUser = (dashboard and (cfg.GLOBAL == true or cfg.ALL_BOTS == true))
            and "Lucifer Global Monitor"
            or ("Lucifer Monitor (" .. tostring(bot.name) .. ")")

        local deliverSuccess = false
        local hook = nil
        local ok = pcall(function()
            hook = api.Webhook.new(cfg.URL)
            hook.username = hookUser
            hook.content = tostring(content)
            if usedEdit then
                hook.message_id = id
                local okEdit, resEdit = pcall(function() return hook:edit() end)
                if okEdit and resEdit ~= false then
                    deliverSuccess = (resEdit == true) and "confirmed" or "unconfirmed"
                else
                    deliverSuccess = false
                    error("Webhook:edit failed")
                end
            else
                local resSend = hook:send()
                if resSend == false then
                    deliverSuccess = false
                    error("Webhook:send failed")
                end
                local newId = hook.message_id
                if newId and tostring(newId) ~= "" then
                    if dashboard then messageId = tostring(newId) end
                    deliverSuccess = "confirmed"
                elseif dashboard then
                    -- Terkirim tanpa ID: pemanggilan jalan, penerimaan tidak terbukti.
                    deliverSuccess = "unconfirmed"
                else
                    deliverSuccess = "confirmed"
                end
            end
        end)

        if ok and deliverSuccess then
            -- Hanya cache lastBody saat terkonfirmasi; hasil unconfirmed dicoba lagi.
            if dashboard and deliverSuccess == "confirmed" then
                lastBody = content
            end
            return deliverSuccess
        else
            if dashboard then retryAfter = now() + 15 end
            if api.print then api.print("[Webhook] Request failed; delivery unverified.") end
            return false
        end
    end

    -- World saat ini: HANYA membaca bot lokal (self).
    -- Hindari akses native lintas bot; akar crash host belum terkonfirmasi.
    local function currentWorld()
        local ok, world = pcall(function()
            if bot:isInWorld() then return bot:getWorld().name end
        end)
        return (ok and world and world ~= "") and world or "In Transit"
    end

    -- Status rotasi: HANYA membaca bot lokal (self).
    local function rotationState()
        local okR, rot = pcall(function() return bot.rotation end)
        if not okR or not rot then return "UNKNOWN" end
        local okE, enabled = pcall(function() return rot.enabled end)
        if not okE or type(enabled) ~= "boolean" then return "UNKNOWN" end
        if enabled ~= true then return "OFF" end
        local okS, status = pcall(function() return rot.status end)
        if not okS or status == nil then return "ON UNKNOWN" end
        if type(api.RotationStatus) == "table" then
            for name, value in pairs(api.RotationStatus) do
                if value == status then return "ON " .. tostring(name) end
            end
        end
        return "ON " .. tostring(status)
    end

    -- Komunikasi status antar-bot berbasis file I/O lokal (%TEMP%).
    -- Snapshot tervalidasi; file hilang/parsial/kedaluwarsa ditampilkan UNKNOWN.
    local snapshotIO = api.io or io
    local startedAt = now()
    local autoNames = {}
    local function slotPath(index)
        local tmp = api.os.getenv and (api.os.getenv("TEMP") or api.os.getenv("TMP")) or "."
        return tmp .. "/lucifer_monitor_slot_" .. tostring(index) .. ".txt"
    end
    local function discoverParticipants()
        local names, seen = {}, {}
        for i = (range and range.startbot or 0), (range and range.endbot or 511) do
            local ok, f = pcall(snapshotIO.open, slotPath(i), "r")
            if ok and f then
                local line = f:read("*l"); f:close()
                local name, stamp, target = tostring(line or ""):match("^([%w_%-]+)|(%d+)|(%d+)$")
                stamp = tonumber(stamp)
                if name and target == tostring(messageId) and stamp <= now() and now() - stamp < 20 and not seen[name] then
                    seen[name] = true; names[#names + 1] = name
                end
            end
        end
        table.sort(names)
        return names
    end
    local function saveLocalStatus(rotState)
        local tmp = api.os.getenv and (api.os.getenv("TEMP") or api.os.getenv("TMP")) or "."
        local safeName = tostring(bot.name):gsub("[^%w_%-]", "")
        if safeName == "" then return end
        local f = snapshotIO.open(tmp .. "/lucifer_bot_" .. safeName .. ".txt", "w")
        if f then
            local w = currentWorld()
            local online = (bot.status == api.BotStatus.online) and "ONLINE" or "OFFLINE"
            local gems = tostring(bot.gem_count or 0)
            local mid = "unknown"
            if bot.status == api.BotStatus.online then
                local ok, value = pcall(function() return tonumber(bot.malady) end)
                if ok and value then mid = tostring(value) end
            end
            f:write(string.format("%s|%s|%s|%s|%s|%s|%d\n",
                safeName, online, tostring(w), tostring(rotState), gems, mid, now()))
            f:close()
            local index = tonumber(bot.index)
            if index and index % 1 == 0 and index >= 0 and index <= 511 and tostring(messageId or ""):match("^%d+$") then
                local slot = snapshotIO.open(slotPath(index), "w")
                if slot then slot:write(safeName .. "|" .. tostring(now()) .. "|" .. tostring(messageId)); slot:close() end
            end
        end
    end

    local function readRemoteBotStatus(name)
        local safeName = tostring(name):gsub("[^%w_%-]", "")
        if safeName == "" then return nil end
        local tmp = api.os.getenv and (api.os.getenv("TEMP") or api.os.getenv("TMP")) or "."
        local okOpen, f = pcall(snapshotIO.open, tmp .. "/lucifer_bot_" .. safeName .. ".txt", "r")
        if not okOpen then return nil end
        if not f then return nil end
        local line = f:read("*l")
        f:close()
        if not line then return nil end
        local bname, online, wName, rot, gems, mid, timestamp = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(%d+)$")
        if bname == safeName and tonumber(timestamp) <= now() and (now() - tonumber(timestamp)) < 60 then
            return {
                name = bname,
                online = (online == "ONLINE"),
                world = wName,
                rot = rot,
                gems = tonumber(gems) or 0,
                malady = tonumber(mid) or 0,
            }
        end
        return nil
    end

    local function isLeader(myBot, allBots)
        if range then return tonumber(myBot.index) == range.startbot end
        -- Jika pengirim eksplisit diatur di config (LEADER_BOT), hanya bot itu yang mengirim
        if cfg.LEADER_BOT and tostring(cfg.LEADER_BOT) ~= "" then
            return myBot.name == cfg.LEADER_BOT
        end
        -- Tanpa LEADER_BOT eksplisit, setiap bot mengelola statusnya sendiri
        -- (tidak ada klaim failover palsu tanpa shared memory/file lock terverifikasi)
        return autoNames[1] == tostring(myBot.name)
    end

    local function buildGlobalDashboard(allBots)
        local totalBots = #allBots
        local onlineStatus = (api.BotStatus and api.BotStatus.online) or 1
        local onlineCount, unknownCount = 0, 0
        local totalGems = 0
        local lines = {}
        for i, b in ipairs(allBots) do
            local bName = tostring(b.name)
            local isOnline, wName, rot, gems, mid
            if bName == tostring(bot.name) then
                isOnline = (bot.status == onlineStatus)
                wName = currentWorld()
                rot = rotationState()
                gems = tonumber(bot.gem_count) or 0
                mid = nil
                if isOnline then mid = tonumber(bot.malady) end
            else
                local st = readRemoteBotStatus(bName)
                if st then
                    isOnline = st.online
                    wName = st.world
                    rot = st.rot
                    gems = st.gems
                    mid = st.malady
                elseif type(allBotsList) == "table" or type(api.getBots) == "function" then
                    -- Fallback jika dalam lingkungan test/mock yang menyediakan objek bot di allBots
                    local targetB = nil
                    if type(api.getBots) == "function" then
                        local okB, bots = pcall(api.getBots)
                        if okB and type(bots) == "table" then
                            for _, tb in ipairs(bots) do
                                if tostring(tb.name) == bName then targetB = tb; break end
                            end
                        end
                    end
                    if targetB then
                        isOnline = (targetB.status == onlineStatus)
                        local okW, gw = pcall(function() return targetB:getWorld() end)
                        wName = (okW and gw and gw.name) or "In Transit"
                        local okR, gr = pcall(function() return targetB.rotation end)
                        if okR and gr and gr.enabled then
                            local phaseName = tostring(gr.status or "")
                            if type(api.RotationStatus) == "table" then
                                for k, v in pairs(api.RotationStatus) do
                                    if v == gr.status then phaseName = tostring(k); break end
                                end
                            end
                            rot = "ON " .. phaseName
                        else
                            rot = "OFF"
                        end
                        gems = tonumber(targetB.gem_count) or 0
                        mid = isOnline and tonumber(targetB.malady) or nil
                    else
                        isOnline = false
                        wName = "In Transit"
                        rot = "UNKNOWN"
                        gems = 0
                        mid = 0
                    end
                else
                    isOnline = false
                    wName = "In Transit"
                    rot = "UNKNOWN"
                    gems = 0
                    mid = 0
                end
            end
            if isOnline then onlineCount = onlineCount + 1 end
            totalGems = totalGems + gems
            local statusLabel = isOnline and "ONLINE" or "OFFLINE"
            if bName ~= tostring(bot.name) and not readRemoteBotStatus(bName) and (not api.getBots) then statusLabel = "UNKNOWN"; unknownCount = unknownCount + 1 end
            local maladyBadge = ""
            if isOnline and mid and mid > 0 then
                maladyBadge = " | ⚠️ " .. maladyLabel(mid)
            end
            lines[#lines + 1] = string.format("%d. **%s** [%s] | `%s` | Rot: `%s` | 💎 %d%s",
                i, bName, statusLabel, tostring(wName), tostring(rot), gems, maladyBadge)
        end
        local offlineCount = totalBots - onlineCount - unknownCount
        local header
        if unknownCount > 0 then
            header = string.format("🌐 **[Lucifer Global Dashboard]**\n**Total:** %d Bot (%d Online, %d Offline, %d Unknown) | **Total Gems teramati:** %d\n\n",
                totalBots, onlineCount, offlineCount, unknownCount, totalGems)
        else
            header = string.format("🌐 **[Lucifer Global Dashboard]**\n**Total:** %d Bot (%d Online, %d Offline) | **Total Gems:** %d\n\n",
                totalBots, onlineCount, offlineCount, totalGems)
        end
        local body = header .. table.concat(lines, "\n")
        if #body > 1950 then
            body = body:sub(1, 1900) .. "\n... (dipotong karena batas pesan Discord)"
        end
        return body
    end

    local lastDiseaseCheck = nil
    local obj = {}
    function obj.notify(message) return deliver(tostring(message), false) end
    function obj.tick(action)
        local t = now()
        local online = bot.status == api.BotStatus.online
        if online then
            offlineSince, offlineSent = nil, false
        else
            offlineSince = offlineSince or t
            local minutes = tonumber(alert.TIMEOUT_MINUTES) or 5
            if minutes <= 0 then minutes = 5 end
            if alert.ENABLED ~= false and not offlineSent and t - offlineSince >= minutes * 60 then
                local user = tostring(alert.DISCORD_USER_ID or "922775541097066576")
                if not user:match("^%d+$") then user = "922775541097066576" end
                offlineSent = deliver(string.format("<@%s> Bot **%s** offline selama %d detik. World saat ini: %s.", user, tostring(bot.name), t-offlineSince, currentWorld()), false)
            end
        end

        if not online then lastDiseaseCheck = nil end
        if online and (not lastDiseaseCheck or t - lastDiseaseCheck >= 5) then
            lastDiseaseCheck = t
            local id = tonumber(bot.malady)
            if id and id >= 0 and id % 1 == 0 then
                if id > 0 and id ~= lastMalady then
                    if deliver(string.format("Bot **%s** terkena penyakit **%s** (ID %d). World saat ini: %s.", tostring(bot.name), maladyLabel(id), id, currentWorld()), false) then lastMalady = id end
                elseif id == 0 then
                    local durationOk, duration = true, 0
                    if type(bot.getMaladyDuration) == "function" then durationOk, duration = pcall(function() return bot:getMaladyDuration() end) end
                    if durationOk and type(duration) == "number" and duration == 0 then
                        if lastMalady and lastMalady > 0 then
                            if deliver(string.format("Bot **%s**: status penyakit sudah hilang (ID 0). World saat ini: %s.", tostring(bot.name), currentWorld()), false) then lastMalady = 0 end
                        else lastMalady = 0 end
                    end
                end
            end
        end

        local interval = tonumber(cfg.UPDATE_INTERVAL_SECONDS) or 15
        local isGlobal = cfg.GLOBAL == true
        -- Publish SELF before leader gate. Never enumerate native bot objects.
        local phaseNow = rotationState()
        if isGlobal then pcall(saveLocalStatus, phaseNow) end
        local allBots = nil
        if isGlobal then
            local ok, names = pcall(discoverParticipants)
            autoNames = ok and names or {}
            if #autoNames == 0 and type(api.getBots) == "function" then
                local okB, bots = pcall(api.getBots)
                if okB and type(bots) == "table" then
                    for _, b in ipairs(bots) do
                        if b.name then autoNames[#autoNames + 1] = tostring(b.name) end
                    end
                end
            end
            if now() - startedAt < 10 and #autoNames == 0 then return end
            if #autoNames == 0 then return end
        end
        if isGlobal then
            if not isLeader(bot) then return end
            allBots = {}
            local seen = {}
            for _, name in ipairs(autoNames) do
                name = tostring(name)
                if name:match("^[%w_%-]+$") and not seen[name] then
                    seen[name] = true
                    allBots[#allBots + 1] = {name = name}
                end
            end
        end

        if allBots then
            local phases = {}
            for _, b in ipairs(allBots) do
                local bName = tostring(b.name)
                if bName == tostring(bot.name) then
                    phases[#phases + 1] = bName .. ":" .. phaseNow .. ":" .. tostring(bot.status)
                else
                    local st = readRemoteBotStatus(bName)
                    if st then
                        phases[#phases + 1] = bName .. ":" .. tostring(st.rot) .. ":" .. (st.online and "1" or "0")
                    end
                end
            end
            phaseNow = table.concat(phases, "|")
        end
        if phaseNow ~= lastPhase then
            if lastPhase ~= nil then
                lastDashboard = nil
                if cfg.PHASE_NOTIFY == true then
                    deliver(string.format("Bot **%s**: fase rotasi **%s** → **%s** (%s).",
                        tostring(bot.name), tostring(lastPhase), tostring(phaseNow), currentWorld()), false)
                end
            end
            lastPhase = phaseNow
        end

        if not lastDashboard or t-lastDashboard >= math.max(3, interval) then
            local body
            if allBots then
                body = buildGlobalDashboard(allBots)
            else
                local rotText = phaseNow
                body = string.format("**Bot:** %s\n**Status:** %s\n**World saat ini:** %s\n**Rotasi:** %s\n**Aktivitas:** %s\n**Gems:** %s", tostring(bot.name), online and "ONLINE" or "OFFLINE", currentWorld(), rotText, tostring(action or "-"), tostring(bot.gem_count or 0))
            end

            local dashOk = deliver(body, true)
            if dashOk then
                lastDashboard = t
                if not dashLogged and api.print then
                    dashLogged = true
                    local modeDesc = allBots and string.format("global %d bot", #allBots) or "single bot"
                    local target = messageId and ("edit id " .. tostring(messageId)) or "pesan baru"
                    if dashOk == "confirmed" then
                        api.print("[Webhook] dashboard terkirim (" .. modeDesc .. ", " .. target .. ")")
                    else
                        api.print("[Webhook] dashboard terkirim tanpa konfirmasi (" .. modeDesc .. ", " .. target .. ")")
                    end
                end
            end
        end
    end
    return obj
end
return M
