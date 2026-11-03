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
    local alert = config.OFFLINE_ALERT or {}
    local offlineSince, offlineSent, lastMalady, lastDashboard = nil, false, nil, nil
    local dashLogged = false
    local lastPhase = nil
    local messageId = cfg.MESSAGE_ID
    local function now() return api.os.time() end
    local function enabled()
        return cfg.ENABLED == true and type(cfg.URL) == "string" and cfg.URL ~= ""
            and not cfg.URL:find("MASUKKAN_URL", 1, true)
    end
    local function deliver(content, dashboard)
        if not enabled() then return false end
        local usedEdit = dashboard and messageId and messageId ~= ""
        local hookUser = (dashboard and (cfg.GLOBAL == true or cfg.ALL_BOTS == true))
            and "Lucifer Global Monitor"
            or ("Lucifer Monitor (" .. tostring(bot.name) .. ")")
        local ok = pcall(function()
            -- Fresh webhook prevents embed fields accumulating between edits.
            local hook = api.Webhook.new(cfg.URL)
            hook.username = hookUser
            hook.content = content
            if usedEdit then
                hook.message_id = tostring(messageId)
                hook:edit()
            else
                hook:send()
                if dashboard and hook.message_id and tostring(hook.message_id) ~= "" then
                    messageId = hook.message_id
                end
            end
        end)
        if ok then return true end

        -- Edit gagal (id basi, pesan dihapus, atau channel lain): dashboard
        -- jangan diam selamanya. Buang id lama lalu kirim pesan baru.
        if usedEdit then
            if api.print then api.print("[Webhook] Edit dashboard gagal; mengirim pesan baru.") end
            messageId = nil
            local okSend = pcall(function()
                local hook = api.Webhook.new(cfg.URL)
                hook.username = hookUser
                hook.content = content
                hook:send()
                if hook.message_id and tostring(hook.message_id) ~= "" then
                    messageId = hook.message_id
                end
            end)
            if okSend then return true end
        end
        if api.print then api.print("[Webhook] Request failed; delivery unverified.") end
        return false -- Invocation only; not a server delivery acknowledgement.
    end
    local function currentWorld(targetBot)
        local b = targetBot or bot
        local ok, world = pcall(function()
            if b:isInWorld() then return b:getWorld().name end
        end)
        return ok and world or "In Transit"
    end
    -- Status rotasi: OFF hanya kalau host benar-benar melaporkan enabled=false.
    -- Tidak terbaca = UNKNOWN, jangan disamakan dengan mati.
    local function rotationState(targetBot)
        local b = targetBot or bot
        local okR, rot = pcall(function() return b.rotation end)
        if not okR or not rot then return "UNKNOWN" end
        local okE, enabled = pcall(function() return rot.enabled end)
        if not okE or enabled == nil then return "UNKNOWN" end
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

    local function isLeader(myBot, allBots)
        local onlineStatus = (api.BotStatus and api.BotStatus.online) or 1
        for _, b in ipairs(allBots) do
            if b.status == onlineStatus then
                return b.name == myBot.name
            end
        end
        return allBots[1] and allBots[1].name == myBot.name
    end

    local function buildGlobalDashboard(allBots)
        local totalBots = #allBots
        local onlineStatus = (api.BotStatus and api.BotStatus.online) or 1
        local onlineCount = 0
        local totalGems = 0
        local lines = {}
        for i, b in ipairs(allBots) do
            local isOnline = b.status == onlineStatus
            if isOnline then onlineCount = onlineCount + 1 end
            local gems = tonumber(b.gem_count) or 0
            totalGems = totalGems + gems
            local wName = currentWorld(b)
            local rot = rotationState(b)
            local statusLabel = isOnline and "ONLINE" or "OFFLINE"
            local maladyBadge = ""
            local mid = tonumber(b.malady)
            if mid and mid > 0 then
                maladyBadge = " | ⚠️ " .. maladyLabel(mid)
            end
            lines[#lines + 1] = string.format("%d. **%s** [%s] | `%s` | Rot: `%s` | 💎 %d%s",
                i, tostring(b.name), statusLabel, tostring(wName), tostring(rot), gems, maladyBadge)
        end
        local offlineCount = totalBots - onlineCount
        local header = string.format("🌐 **[Lucifer Global Dashboard]**\n**Total:** %d Bot (%d Online, %d Offline) | **Total Gems:** %d\n\n",
            totalBots, onlineCount, offlineCount, totalGems)
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
        -- Unknown/invalid readings never establish recovery; preserve prior state.
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
        local isGlobal = cfg.GLOBAL == true or cfg.ALL_BOTS == true
        local getBotsFn = api.getBots or (type(getBots) == "function" and getBots)
        local allBots = nil
        if isGlobal and type(getBotsFn) == "function" then
            local okBots, resBots = pcall(getBotsFn)
            if okBots and type(resBots) == "table" and #resBots > 0 then
                allBots = resBots
            end
        end

        -- Perubahan fase rotasi langsung tercermin: paksa dashboard refresh,
        -- jangan tunggu interval. Tidak kirim pesan baru supaya tidak spam
        -- (farming_block <-> planting_seeds berganti tiap beberapa detik).
        local phaseNow = rotationState()
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
            -- Dalam mode global, hanya 1 bot (leader) yang mengedit dashboard
            -- agar tidak terjadi collision/rate-limit saat banyak bot berjalan bersamaan.
            if allBots and not isLeader(bot, allBots) then
                return
            end

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
                    api.print("[Webhook] dashboard terkirim (" .. modeDesc .. ", " .. (messageId and ("edit id " .. tostring(messageId)) or "pesan baru") .. ")")
                end
            end
        end
    end
    return obj
end
return M
