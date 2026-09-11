local Chatter = CreateFrame("Frame", "ChatterEventFrame")

Chatter.prefix = "CHATTER_ADDON "
Chatter.roster = {}
Chatter.pendingRoster = nil
Chatter.selectedGuid = nil
Chatter.pendingProfileGuid = nil
Chatter.pendingToneGuid = nil
Chatter.tonePollElapsed = 0
Chatter.tonePollRemaining = 0
Chatter.pendingBackstoryGuid = nil
Chatter.backstoryPollElapsed = 0
Chatter.backstoryPollRemaining = 0

local function trim(value)
    if not value then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sanitizeInput(value)
    value = trim(value or "")
    value = value:gsub("[%c]", " ")
    value = value:gsub("%s+", " ")
    return trim(value)
end

function Chatter:Encode(value)
    value = sanitizeInput(value)
    if value == "" then
        return "-"
    end

    return (value:gsub("([^%w%-_%.~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

function Chatter:Decode(value)
    if not value or value == "-" then
        return ""
    end

    return (value:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function Chatter:GetActivePanel()
    if self.frame and self.frame:IsShown() then
        return self.frame
    end
    if self.traitsPanel and self.traitsPanel:IsShown() then
        return self.traitsPanel
    end
    return self.frame
end

function Chatter:SetStatus(text, r, g, b)
    local panels = {}
    if self.frame then
        table.insert(panels, self.frame)
    end
    if self.traitsPanel then
        table.insert(panels, self.traitsPanel)
    end
    if self.storiesPanel then
        table.insert(panels, self.storiesPanel)
    end
    for _, p in ipairs(panels) do
        if p.status then
            p.status:SetText(text or "")
            p.status:SetTextColor(
                r or 1, g or 0.82, b or 0
            )
        end
    end
end

function Chatter:SendCommand(command)
    SendChatMessage(".llmc " .. command, "SAY")
end

function Chatter:StopTonePoll()
    self.pendingToneGuid = nil
    self.tonePollElapsed = 0
    self.tonePollRemaining = 0
end

function Chatter:StartTonePoll(guid)
    guid = tonumber(guid)
    if not guid then
        return
    end

    self.pendingToneGuid = guid
    self.tonePollElapsed = 0
    self.tonePollRemaining = 120

    local function applyPlaceholder(panel)
        if not panel then return end
        if panel.tone then
            panel.tone:SetTextColor(0.5, 0.5, 0.5)
            panel.tone:SetText("Generating tone...")
        end
    end
    applyPlaceholder(self.frame)
    applyPlaceholder(self.traitsPanel)
end

function Chatter:HandleTonePoll(elapsed)
    if not self.pendingToneGuid then
        return
    end

    self.tonePollElapsed = self.tonePollElapsed + elapsed
    self.tonePollRemaining = self.tonePollRemaining - elapsed

    if self.tonePollRemaining <= 0 then
        self:SetStatus(
            "Tone generation is still pending. Use Refresh.",
            1, 0.82, 0
        )
        self:StopTonePoll()
        return
    end

    if self.tonePollElapsed >= 1.5 then
        self.tonePollElapsed = 0
        self:SendCommand("get " .. self.pendingToneGuid)
    end
end

function Chatter:SetRegenStoryEnabled(enabled)
    local function apply(p)
        if not p or not p.regenStoryBtn then
            return
        end
        if enabled then
            p.regenStoryBtn:Enable()
        else
            p.regenStoryBtn:Disable()
        end
    end
    apply(self.frame)
    apply(self.traitsPanel)
    apply(self.storiesPanel)
end

function Chatter:SetSaveEnabled(enabled)
    local function apply(p)
        if not p or not p.saveBtn then return end
        if enabled then
            p.saveBtn:Enable()
        else
            p.saveBtn:Disable()
        end
    end
    apply(self.frame)
    apply(self.traitsPanel)
end

function Chatter:UpdateSaveButton()
    local loaded = self.loadedTraits
    if not loaded or self.pendingProfileGuid or self.forgetQueue then
        self:SetSaveEnabled(false)
        return
    end
    local p = self:GetActivePanel()
    if not p then
        self:SetSaveEnabled(false)
        return
    end
    local t1 = sanitizeInput(
        p.trait1 and p.trait1:GetText() or ""
    )
    local t2 = sanitizeInput(
        p.trait2 and p.trait2:GetText() or ""
    )
    local t3 = sanitizeInput(
        p.trait3 and p.trait3:GetText() or ""
    )
    local changed = (
        t1 ~= (loaded.trait1 or "")
        or t2 ~= (loaded.trait2 or "")
        or t3 ~= (loaded.trait3 or "")
    )
    self:SetSaveEnabled(changed)
end

function Chatter:StopBackstoryPoll()
    self.pendingBackstoryGuid = nil
    self.backstoryPollElapsed = 0
    self.backstoryPollRemaining = 0
    self:SetRegenStoryEnabled(true)
end

function Chatter:StartBackstoryPoll(guid)
    guid = tonumber(guid)
    if not guid then
        return
    end

    self.pendingBackstoryGuid = guid
    self.backstoryPollElapsed = 0
    self.backstoryPollRemaining = 120

    self:SetRegenStoryEnabled(false)

    -- Show placeholder in the backstory box
    local placeholder = "Creating background story..."
    if self.frame and self.frame.backstory then
        self.frame.backstory:SetText(placeholder)
        self.frame.backstory:SetTextColor(
            0.5, 0.5, 0.5
        )
    end
    if self.storiesPanel
        and self.storiesPanel.backstory then
        self.storiesPanel.backstory:SetText(
            placeholder
        )
        self.storiesPanel.backstory:SetTextColor(
            0.5, 0.5, 0.5
        )
    end
end

function Chatter:HandleBackstoryPoll(elapsed)
    if not self.pendingBackstoryGuid then
        return
    end

    self.backstoryPollElapsed =
        self.backstoryPollElapsed + elapsed
    self.backstoryPollRemaining =
        self.backstoryPollRemaining - elapsed

    if self.backstoryPollRemaining <= 0 then
        self:SetStatus(
            "Backstory generation still pending."
            .. " Use Refresh.",
            1, 0.82, 0
        )
        self:StopBackstoryPoll()
        return
    end

    if self.backstoryPollElapsed >= 2.0 then
        self.backstoryPollElapsed = 0
        self:SendCommand(
            "get " .. self.pendingBackstoryGuid
        )
    end
end

function Chatter:SaveWindowPosition()
    if not self.frame then
        return
    end

    local point, _, relPoint, x, y =
        self.frame:GetPoint(1)
    ChatterDB = ChatterDB or {}
    ChatterDB.point = point
    ChatterDB.relPoint = relPoint
    ChatterDB.x = x
    ChatterDB.y = y
end

function Chatter:RestoreWindowPosition()
    if not self.frame then
        return
    end

    self.frame:ClearAllPoints()
    if ChatterDB and ChatterDB.point then
        self.frame:SetPoint(
            ChatterDB.point,
            UIParent,
            ChatterDB.relPoint or ChatterDB.point,
            ChatterDB.x or 0,
            ChatterDB.y or 0
        )
    else
        self.frame:SetPoint("CENTER")
    end
end

function Chatter:ApplyProfileToPanel(p, profile)
    if not p then
        return
    end
    if p.trait1 then
        p.trait1:SetText(profile.trait1 or "")
    end
    if p.trait2 then
        p.trait2:SetText(profile.trait2 or "")
    end
    if p.trait3 then
        p.trait3:SetText(profile.trait3 or "")
    end
    if p.tone then
        local toneText = profile.tone or ""
        -- Only overwrite if not currently showing
        -- a live placeholder (poll in progress)
        local polling = (
            self.pendingToneGuid
            and self.pendingToneGuid == profile.guid
        )
        if not polling or toneText ~= "" then
            p.tone:SetText(toneText)
            p.tone:SetTextColor(0.7, 0.7, 0.7)
        end
    end
    if p.backstory then
        local bsText = profile.backstory or ""
        -- Only overwrite if not currently showing
        -- a live placeholder (poll in progress)
        local polling = (
            self.pendingBackstoryGuid
            and self.pendingBackstoryGuid == profile.guid
        )
        if not polling or bsText ~= "" then
            p.backstory:SetText(bsText)
            p.backstory:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

function Chatter:ApplyProfile(profile)
    if profile.guid ~= self.selectedGuid or self.forgetQueue then
        return
    end
    self.pendingProfileGuid = nil
    self:SetRegenStoryEnabled(not self.pendingBackstoryGuid)
    local awaitingTone = (
        self.pendingToneGuid == profile.guid
    )
    self.selectedGuid = profile.guid

    -- Store loaded traits for change detection
    self.loadedTraits = {
        trait1 = profile.trait1 or "",
        trait2 = profile.trait2 or "",
        trait3 = profile.trait3 or "",
    }

    self:ApplyProfileToPanel(self.frame, profile)
    self:ApplyProfileToPanel(self.traitsPanel, profile)
    self:ApplyProfileToPanel(self.storiesPanel, profile)

    -- Traits just loaded — no unsaved changes yet
    self:SetSaveEnabled(false)

    ChatterDB = ChatterDB or {}
    ChatterDB.selectedGuid = profile.guid

    self:UpdateRosterViews()
    if awaitingTone then
        if profile.tone and profile.tone ~= "" then
            self:StopTonePoll()
            self:SetStatus(
                "Generated tone for "
                    .. (profile.name or "bot"),
                0.3, 1, 0.3
            )
        else
            self:SetStatus(
                "Generating tone...", 1, 0.82, 0
            )
        end
    else
        self:SetStatus(
            "Loaded " .. (profile.name or "bot"),
            0.3, 1, 0.3
        )
    end
end

function Chatter:SelectBot(guid)
    if self.forgetQueue then return end
    guid = tonumber(guid)
    if not guid then
        return
    end

    if self.pendingToneGuid and self.pendingToneGuid ~= guid then
        self:StopTonePoll()
    end
    if self.pendingBackstoryGuid
        and self.pendingBackstoryGuid ~= guid then
        self:StopBackstoryPoll()
    end

    self.selectedGuid = guid
    self.pendingProfileGuid = guid
    self.loadedTraits = nil
    self:SetSaveEnabled(false)
    self:SetRegenStoryEnabled(false)
    local empty = {trait1 = "", trait2 = "", trait3 = "",
        tone = "", backstory = ""}
    self:ApplyProfileToPanel(self.frame, empty)
    self:ApplyProfileToPanel(self.traitsPanel, empty)
    self:ApplyProfileToPanel(self.storiesPanel, empty)
    self:UpdateRosterViews()
    self:SetStatus("Loading bot profile...", 1, 0.82, 0)
    self:SendCommand("get " .. guid)
end

function Chatter:RequestRoster()
    if self.forgetQueue or self.pendingRoster then return end
    self.pendingRoster = {}
    self.rosterElapsed = 0
    self:UpdateRosterViews()
    self:SetStatus("Requesting roster...", 1, 0.82, 0)
    self:SendCommand("roster")
end

function Chatter:SaveProfile()
    if self.pendingProfileGuid or self.forgetQueue then return end
    if not self.selectedGuid then
        self:SetStatus("Select a bot first.", 1, 0.2, 0.2)
        return
    end

    local p = self:GetActivePanel()
    if not p then
        self:SetStatus("No panel open.", 1, 0.2, 0.2)
        return
    end

    local trait1 = sanitizeInput(p.trait1:GetText())
    local trait2 = sanitizeInput(p.trait2:GetText())
    local trait3 = sanitizeInput(p.trait3:GetText())

    p.trait1:SetText(trait1)
    p.trait2:SetText(trait2)
    p.trait3:SetText(trait3)

    if trait1 == "" or trait2 == "" or trait3 == "" then
        self:SetStatus("All three traits are required.", 1, 0.2, 0.2)
        return
    end

    if string.len(trait1) > 64 or string.len(trait2) > 64
        or string.len(trait3) > 64 then
        self:SetStatus("Traits must stay under 64 characters.", 1, 0.2, 0.2)
        return
    end

    -- Store pending traits for use after confirm
    self.pendingTraits = {
        guid = self.selectedGuid,
        trait1 = trait1,
        trait2 = trait2,
        trait3 = trait3,
    }

    local loaded = self.loadedTraits or {}
    local changed = (
        trait1 ~= (loaded.trait1 or "")
        or trait2 ~= (loaded.trait2 or "")
        or trait3 ~= (loaded.trait3 or "")
    )

    if changed then
        StaticPopup_Show(
            "CHATTER_CONFIRM_SAVE_TRAITS"
        )
    else
        -- Nothing changed — no server round-trip
        self:SetStatus(
            "Traits unchanged.", 0.3, 1, 0.3
        )
    end
end

function Chatter:DoSaveProfile()
    local t = self.pendingTraits
    if not t or t.guid ~= self.selectedGuid
        or self.pendingProfileGuid or self.forgetQueue then
        return
    end

    local guid = self.selectedGuid
    self:StopTonePoll()
    self:StopBackstoryPoll()
    self:SendCommand(
        string.format(
            "set %d %s %s %s",
            guid,
            self:Encode(t.trait1),
            self:Encode(t.trait2),
            self:Encode(t.trait3)
        )
    )
    -- Start polls immediately so placeholders appear
    -- without waiting for the server round-trip
    self:StartTonePoll(guid)
    self:StartBackstoryPoll(guid)
    self:SetStatus(
        "Saving traits and regenerating tone"
            .. " and backstory...",
        1, 0.82, 0
    )
    self.pendingTraits = nil
end

function Chatter:GetSelectedName()
    if not self.selectedGuid then
        return nil
    end
    local guid = tonumber(self.selectedGuid)
    if not guid then return nil end
    for _, entry in ipairs(self.roster or {}) do
        if entry.guid == guid then
            return entry.name
        end
    end
    return nil
end

function Chatter:RegenBackstory()
    if self.pendingProfileGuid or self.forgetQueue then return end
    if not self.selectedGuid then
        self:SetStatus("Select a bot first.", 1, 0.2, 0.2)
        return
    end

    local guid = self.selectedGuid
    self:StopBackstoryPoll()
    self:SendCommand("regenbackstory " .. guid)
    self:StartBackstoryPoll(guid)
    self:SetStatus(
        "Regenerating backstory...", 1, 0.82, 0
    )
end

function Chatter:Toggle()
    self:BuildFrame()

    if self.frame:IsShown() then
        self.frame:Hide()
        return
    end

    self.frame:Show()
    self.frame:Raise()
    self:RequestRoster()
end

function Chatter:HandleRosterEntry(guidToken, nameToken)
    local guid = tonumber(guidToken)
    local name = self:Decode(nameToken)
    if not guid or name == "" then
        return
    end

    table.insert(self.pendingRoster, {
        guid = guid,
        name = name
    })
end

function Chatter:FinishRoster()
    self.roster = self.pendingRoster or {}
    self.pendingRoster = nil

    table.sort(self.roster, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    self:UpdateRosterViews()

    if #self.roster == 0 then
        self.selectedGuid = nil
        self.pendingProfileGuid = nil
        self.loadedTraits = nil
        ChatterDB.selectedGuid = nil
        self:StopTonePoll()
        self:StopBackstoryPoll()
        self:SetSaveEnabled(false)
        self:SetRegenStoryEnabled(false)
        self:UpdateRosterViews()
        local empty = {
            trait1 = "", trait2 = "", trait3 = "",
            tone = "", backstory = "",
        }
        self:ApplyProfileToPanel(self.frame, empty)
        self:ApplyProfileToPanel(self.traitsPanel, empty)
        self:ApplyProfileToPanel(self.storiesPanel, empty)
        self:SetStatus("No known bots yet.", 1, 0.82, 0)
        return
    end

    local preferredGuid = self.selectedGuid
    if not preferredGuid and ChatterDB then
        preferredGuid = ChatterDB.selectedGuid
    end

    local found = nil
    for _, bot in ipairs(self.roster) do
        if bot.guid == preferredGuid then
            found = bot.guid
            break
        end
    end

    if not found then
        found = self.roster[1].guid
    end

    self:SelectBot(found)
end

function Chatter:HandleProfilePayload(rest)
    -- Parse 6 fields: guid name t1 t2 t3 tone
    -- Backstory arrives as a separate BACKSTORY message
    local guid, name, trait1, trait2, trait3, tone =
        string.match(
            rest,
            "^(%d+)%s+(%S+)%s+(%S+)%s+(%S+)"
            .. "%s+(%S+)%s+(%S+)$"
        )
    if not guid then
        return
    end

    self:ApplyProfile({
        guid = tonumber(guid),
        name = self:Decode(name),
        trait1 = self:Decode(trait1),
        trait2 = self:Decode(trait2),
        trait3 = self:Decode(trait3),
        tone = self:Decode(tone),
    })
end

function Chatter:HandleBackstoryPayload(rest)
    local guid, encoded = string.match(
        rest, "^(%d+)%s+(.+)$"
    )
    if not guid then
        return
    end

    local numGuid = tonumber(guid)
    local text = self:Decode(encoded or "-")

    -- Only apply non-empty backstory to boxes;
    -- empty means still generating — preserve
    -- the "Creating background story..." placeholder
    if text and text ~= ""
        and self.selectedGuid == numGuid then
        if self.frame and self.frame.backstory then
            self.frame.backstory:SetText(text)
            self.frame.backstory:SetTextColor(
                0.7, 0.7, 0.7
            )
        end
        if self.storiesPanel
            and self.storiesPanel.backstory then
            self.storiesPanel.backstory:SetText(text)
            self.storiesPanel.backstory:SetTextColor(
                0.7, 0.7, 0.7
            )
        end
    end

    -- If we were polling for backstory, check
    -- if it arrived
    if self.pendingBackstoryGuid == numGuid then
        if text and text ~= "" then
            self:StopBackstoryPoll()
            -- Only show backstory status if tone
            -- poll is already done
            if not self.pendingToneGuid then
                self:SetStatus(
                    "Backstory generated.",
                    0.3, 1, 0.3
                )
            end
        end
    end
end

function Chatter:HandleSystemMessage(message)
    if not string.find(message, "^" .. self.prefix) then
        return
    end

    local payload = string.sub(message, string.len(self.prefix) + 1)
    local command, rest = string.match(payload, "^(%S+)%s*(.-)$")

    if command == "ROSTER_BEGIN" then
        self.pendingRoster = {}
        return
    end

    if command == "ROSTER" then
        local guid, name = string.match(rest, "^(%d+)%s+(%S+)$")
        if guid and name and self.pendingRoster then
            self:HandleRosterEntry(guid, name)
        end
        return
    end

    if command == "ROSTER_END" then
        self:FinishRoster()
        return
    end

    if command == "PROFILE" then
        self:HandleProfilePayload(rest)
        return
    end

    if command == "BACKSTORY" then
        self:HandleBackstoryPayload(rest)
        return
    end

    if command == "UPDATED" then
        local guid, name, flag = string.match(
            rest, "^(%d+)%s+(%S+)%s+(%S+)"
        )
        if guid and name and tonumber(guid) == self.selectedGuid
            and not self.forgetQueue then
            self.selectedGuid = tonumber(guid)
            local changed = (flag == "changed")
            if changed then
                -- Polls were started in DoSaveProfile;
                -- restart here to reset the 120s clock
                -- now that the server confirmed the save
                self:StartTonePoll(guid)
                self:StartBackstoryPoll(guid)
                self:SetStatus(
                    "Saved. Regenerating tone"
                        .. " and backstory...",
                    1, 0.82, 0
                )
            else
                self:StopTonePoll()
                self:StopBackstoryPoll()
                self:SetStatus(
                    "Traits saved for "
                        .. self:Decode(name) .. ".",
                    0.3, 1, 0.3
                )
                -- Reload profile to restore
                -- tone/backstory after optimistic polls
                self:SendCommand(
                    "get " .. tonumber(guid)
                )
            end
        end
        return
    end

    if command == "BACKSTORY_REGEN" then
        local guid, name = string.match(
            rest, "^(%d+)%s+(%S+)$"
        )
        if guid and name then
            self:SetStatus(
                "Regenerating backstory for "
                    .. self:Decode(name) .. "...",
                1, 0.82, 0
            )
        end
        return
    end

    if command == "FORGOTTEN" then
        self:HandleForgotten(tonumber(string.match(rest, "^(%d+)%s")))
        return
    end

    if command == "ERROR" then
        if self.forgetQueue then
            self:FinishForgetBatch("Stopped: " .. self:Decode(
                string.match(rest, "^%S+%s*(.-)$") or rest))
            return
        end
        self.pendingRoster = nil
        local _, encoded = string.match(
            rest, "^(%S+)%s*(.-)$"
        )
        self:SetStatus(
            self:Decode(encoded), 1, 0.2, 0.2
        )
    end
end

local function chatterSystemFilter(_, _, message, ...)
    if type(message) == "string"
        and string.find(message, "^" .. Chatter.prefix) then
        return true
    end
    return false
end

StaticPopupDialogs["CHATTER_CONFIRM_SAVE_TRAITS"] = {
    text = "These traits are different from the saved ones. Saving will regenerate this bot's tone and background story. Continue?",
    button1 = "Save",
    button2 = "Cancel",
    OnAccept = function()
        Chatter:DoSaveProfile()
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

SLASH_CHATTER1 = "/chatter"
SLASH_CHATTER2 = "/llmc"
SlashCmdList["CHATTER"] = function()
    Chatter:Toggle()
end

Chatter:SetScript("OnUpdate", function(self, elapsed)
    if self.pendingRoster then
        self.rosterElapsed = (self.rosterElapsed or 0) + elapsed
        if self.rosterElapsed >= 10 then
            self.pendingRoster = nil
            self:UpdateRosterViews()
            self:SetStatus("Roster request timed out. Use Refresh.", 1, 0.4, 0.3)
        end
    end
    self:HandleForgetQueue(elapsed)
    self:HandleTonePoll(elapsed)
    self:HandleBackstoryPoll(elapsed)
end)

Chatter:SetScript("OnEvent", function(self, event, message)
    if event == "PLAYER_LOGIN" then
        ChatterDB = ChatterDB or {}
        self:BuildOptionsPanel()
        self:BuildFrame()
        ChatFrame_AddMessageEventFilter(
            "CHAT_MSG_SYSTEM",
            chatterSystemFilter
        )
    elseif event == "PLAYER_LOGOUT" then
        self:SaveWindowPosition()
    elseif event == "CHAT_MSG_SYSTEM" then
        -- Filters run once per chat window; process each response only once.
        self:HandleSystemMessage(message)
    end
end)

Chatter:RegisterEvent("PLAYER_LOGIN")
Chatter:RegisterEvent("PLAYER_LOGOUT")
Chatter:RegisterEvent("CHAT_MSG_SYSTEM")
