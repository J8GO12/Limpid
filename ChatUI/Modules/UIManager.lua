local Core, Constants, Utils = unpack(select(2, ...))
local UIManager = Core:GetModule("UIManager")

local L = LibStub("AceLocale-3.0"):GetLocale("Limpid")

local UnlockMover = Constants.ACTIONS.UnlockMover
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

local CreateChatTab = Core.Components.CreateChatTab
local CreateEditBox = Core.Components.CreateEditBox
local CreateMoverDialog = Core.Components.CreateMoverDialog
local CreateWindow = Core.Components.CreateWindow

-- luacheck: push ignore 113
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GetCVar = GetCVar
local SetCVar = SetCVar
local UIParent = UIParent
local hooksecurefunc = hooksecurefunc
-- luacheck: pop

----
-- Hiding the native chat (Forever port)
--
-- LimpidUI keeps Blizzard's chat frames alive as the data source (they decide
-- which messages each tab receives) but must not show them. The 3.3.5 version
-- forced their alpha to 0 with raw hooks and re-hid them on every Show; on the
-- modern client the frames are instead re-parented to a holder frame that is
-- never shown. Blizzard's code can Show/SetAlpha/fade them as much as it
-- likes: nothing under a hidden parent is drawn or receives the mouse, and no
-- Blizzard function is replaced. (This is the same technique the established
-- chat-replacement addons use on this client.)
local hiddenHolder = CreateFrame("Frame", "LimpidUIHiddenChatHolder", UIParent)
hiddenHolder:SetAllPoints(UIParent)
hiddenHolder:Hide()

local keptHidden = {} -- [frame] = true once the "stay hidden" hook is installed

-- Park a native frame under the hidden holder and keep it there: Blizzard's
-- dock code re-parents tab buttons whenever a window is docked/undocked.
local function HideNativeFrame(frame)
	if not frame or frame == hiddenHolder then
		return
	end

	local hookInstalled = keptHidden[frame] ~= nil
	keptHidden[frame] = true -- (also re-arms a frame that had been "released")

	-- The raw widget method, captured before the secure hook wraps it.
	local nativeSetParent = frame.SetParent
	if frame:GetParent() ~= hiddenHolder then
		nativeSetParent(frame, hiddenHolder)
	end

	if not hookInstalled then
		hooksecurefunc(frame, "SetParent", function(self, parent)
			-- "released" frames (e.g. the Combat Log while its tab is selected)
			-- are allowed out; everything else goes straight back.
			if keptHidden[self] == "released" then
				return
			end
			if parent ~= hiddenHolder then
				nativeSetParent(self, hiddenHolder)
			end
		end)
	end
end

----
-- UIManager Module
function UIManager:OnInitialize()
	self.state = {
		frames = {},
		tabs = {},
	}
	-- Registry of all LimpidUI windows. Each window is keyed by its id (e.g. "Main").
	-- Multi-window support: other parts of the addon can iterate self.windows.
	self.windows = {}
end

-- Iterate every existing Blizzard chat frame (permanent AND temporary).
local function ForEachChatFrame(callback)
	local names = _G.CHAT_FRAMES
	if type(names) ~= "table" then
		return
	end
	for _, name in ipairs(names) do
		local chatFrame = _G[name]
		if chatFrame then
			callback(chatFrame, name)
		end
	end
end

-- Is this chat frame something the player currently has open?
local function IsChatFrameActive(chatFrame)
	local id = chatFrame:GetID()

	-- General is always there.
	if id == 1 then
		return true
	end

	-- Combat Log: follows the "hide combat log" setting.
	if chatFrame == _G.ChatFrame2 then
		return not Core.db.profile.hideCombatLog
	end

	-- Temporary windows (whisper pop-outs) while they are in use.
	if chatFrame.isTemporary then
		return chatFrame.inUse and true or false
	end

	-- Regular windows: docked, or opened as a floating window.
	if chatFrame.isDocked then
		return true
	end
	if _G.FCF_GetChatWindowInfo then
		local ok, _, _, _, _, _, _, shown = pcall(_G.FCF_GetChatWindowInfo, id)
		if ok and shown then
			return true
		end
	end

	return false
end

-- Park every native chat frame, its tab button and its minimized stub.
function UIManager:HideNativeChat()
	ForEachChatFrame(function(chatFrame, name)
		-- The Combat Log is let out while its LimpidUI tab is selected.
		if keptHidden[chatFrame] ~= "released" then
			HideNativeFrame(chatFrame)
		end
		HideNativeFrame(_G[name .. "Tab"])
		HideNativeFrame(_G[name .. "Minimized"])
	end)

	-- The native tab strip, and the voice / text-to-speech buttons that sit
	-- beside the native chat frame.
	HideNativeFrame(_G.GeneralDockManager)
	HideNativeFrame(_G.ChatFrameToggleVoiceDeafenButton)
	HideNativeFrame(_G.ChatFrameToggleVoiceMuteButton)
	HideNativeFrame(_G.TextToSpeechButtonFrame)
end

function UIManager:OnEnable()
	-- Guarantee the shared font objects (LimpidUIMessageFont, etc.) exist before we
	-- build any window frames that inherit them. Module enable order isn't
	-- guaranteed when another addon's AceAddon wins the LibStub race, so create
	-- them defensively here instead of relying on Fonts:OnEnable running first.
	local Fonts = Core:GetModule("Fonts", true)
	if Fonts and Fonts.SetupFonts then
		Fonts:SetupFonts()
	end

	self.tickerFrame = CreateFrame("Frame", "LimpidUIUpdaterFrame", UIParent)

	-- Shared "unlock to move" dialog (one for the whole UI).
	self.moverDialog = CreateMoverDialog("LimpidUIMoverDialog", UIParent)

	-- Main window. Grouping its pieces (mover, container, dock, message-frame
	-- pool) behind a Window object is what allows multiple separate windows.
	-- The main window keeps the original frame names
	-- ("LimpidUIMoverFrame"/"LimpidUIFrame"/"LimpidUIChatDock") so saved positions are
	-- unchanged.
	self.mainWindow = CreateWindow({
		id = "Main",
		parent = UIParent,
		moverName = "LimpidUIMoverFrame",
		containerName = "LimpidUIFrame",
		dockName = "LimpidUIChatDock",
		primaryChatFrame = _G.ChatFrame1,
	})
	self.windows["Main"] = self.mainWindow

	-- Restore additional windows from saved profile (multi-window persistence)
	-- Clean up orphaned windows first (windows with no chat frames assigned)
	if Core.db.profile.windows then
		local orphanedWindows = {}
		for windowId, windowProfile in pairs(Core.db.profile.windows) do
			if windowId ~= "Main" and type(windowProfile) == "table" then
				-- Check if this window has any chat frames assigned
				local hasFrames = windowProfile.chatFrames and #windowProfile.chatFrames > 0
				if not hasFrames then
					table.insert(orphanedWindows, windowId)
				end
			end
		end
		-- Remove orphaned window profiles
		for _, windowId in ipairs(orphanedWindows) do
			Core.db.profile.windows[windowId] = nil
		end
	end

	-- Now restore valid windows
	if Core.db.profile.windows then
		local nextNum = 2
		for windowId, windowProfile in pairs(Core.db.profile.windows) do
			if windowId ~= "Main" and type(windowProfile) == "table" then
				-- Determine the numeric suffix for frame names
				local num = tonumber(windowId:match("%d+")) or nextNum
				nextNum = math.max(nextNum, num + 1)

				local window = CreateWindow({
					id = windowId,
					parent = UIParent,
					moverName = "LimpidUIMoverFrame" .. num,
					containerName = "LimpidUIFrame" .. num,
					dockName = "LimpidUIChatDock" .. num,
					-- Taken from the window's own saved frame list. The comment here
					-- used to say SetupTabs would fill this in, which it never did,
					-- so a restored window carried a nil primary frame all session.
					primaryChatFrame = windowProfile.chatFrames
						and windowProfile.chatFrames[1]
						and _G["ChatFrame" .. windowProfile.chatFrames[1]]
						or nil,
				})
				if window then
					self.windows[windowId] = window
					-- Apply saved position
					if windowProfile.positionAnchor then
						window.moverFrame:ClearAllPoints()
						window.moverFrame:SetPoint(
							windowProfile.positionAnchor.point or "BOTTOMLEFT",
							UIParent,
							windowProfile.positionAnchor.point or "BOTTOMLEFT",
							windowProfile.positionAnchor.xOfs or 50,
							windowProfile.positionAnchor.yOfs or 200
						)
					end
				end
			end
		end
	end

	-- Backwards-compatible aliases so the rest of UIManager and the components keep
	-- working unchanged.
	self.moverFrame = self.mainWindow.moverFrame
	self.container = self.mainWindow.container
	self.dock = self.mainWindow.dock
	self.slidingMessageFramePool = self.mainWindow.pool

	-- Back the shared render state with the main window's frame/tab tables.
	self.state.frames = self.mainWindow.frames
	self.state.tabs = self.mainWindow.tabs

	-- Build / refresh the LimpidUI frames and tabs from the current set of
	-- Blizzard chat frames. Idempotent: frames and tabs are reused.
	local function SetupTabs(reveal)
		-- Whatever Blizzard just created or re-docked goes back out of sight.
		self:HideNativeChat()

		-- Which chat-frame indexes exist right now (to drop stale entries).
		local seen = {}

		ForEachChatFrame(function(chatFrame)
			local i = chatFrame:GetID()
			seen[i] = true

			-- Which window owns this chat frame? (per-window profile.chatFrames,
			-- defaulting to the main window).
			local owner = self:GetOwnerWindowForIndex(i)
			local isActive = IsChatFrameActive(chatFrame)

			-- Reconcile ownership: if any OTHER window currently holds an SMF for
			-- this index (after a move / spawn / delete), release it so only the
			-- owner renders this chat frame and we never double-render.
			for _, w in pairs(self.windows) do
				if w ~= owner and w.frames[i] then
					local stale = w.frames[i]
					w.frames[i] = nil
					w.tabs[i] = nil
					if w.pool and w.pool.Release then
						w.pool:Release(stale)
					end
				end
			end

			if isActive then
				-- Create or get the sliding message frame in the owner window's pool.
				if not owner.frames[i] then
					local smf = owner.pool:Acquire()
					smf.window = owner
					smf:Init(chatFrame)
					owner.frames[i] = smf
				end

				local smf = owner.frames[i]
				smf.window = owner
				smf.profile = owner.profile

				local tab = CreateChatTab(smf)
				owner.tabs[i] = tab
				if tab then
					tab.glassDock = owner.dock
				end
			else
				-- Closed window: release its message frame and hide its tab so a
				-- closed window's tab is not re-shown later by SelectChatTab.
				local smf = owner.frames[i]
				if smf then
					owner.frames[i] = nil
					owner.pool:Release(smf)
				end
				local tab = Core.Components.GetChatTab and Core.Components.GetChatTab(chatFrame)
				if tab then
					tab:Release()
				end
				if owner.selectedTab == tab then
					owner.selectedTab = nil
				end
				if Core.Components.selectedTab == tab then
					Core.Components.selectedTab = nil
				end
				owner.tabs[i] = nil
			end
		end)

		-- Position each window's active tabs in that window's own dock.
		local UpdateTabPositions = Core.Components.UpdateTabPositions
		local SelectChatTab = Core.Components.SelectChatTab

		for _, window in pairs(self.windows) do
			-- Drop entries for chat frames that no longer exist.
			for index in pairs(window.tabs) do
				if not seen[index] then
					window.tabs[index] = nil
				end
			end

			if UpdateTabPositions then
				UpdateTabPositions(window.tabs)
			end

			-- Make sure exactly one tab's messages show per window. Every active
			-- chat frame gets its own SlidingMessageFrame anchored at the same
			-- spot, so without an explicit selection they would render together.
			local tabToSelect = window.selectedTab

			-- Validate the remembered selection still exists in this window.
			if tabToSelect then
				local stillThere = false
				for _, t in pairs(window.tabs) do
					if t == tabToSelect then
						stillThere = true
						break
					end
				end
				if not stillThere then
					tabToSelect = nil
				end
			end

			-- Otherwise fall back to the lowest-numbered tab in this window.
			local needsSelection = tabToSelect == nil
			if not tabToSelect then
				local lowest
				for index, t in pairs(window.tabs) do
					if t and (lowest == nil or index < lowest) then
						lowest = index
						tabToSelect = t
					end
				end
			end

			if tabToSelect and SelectChatTab and (reveal or needsSelection) then
				SelectChatTab(tabToSelect)
			end

			-- Only reveal the docks on an explicit setup; re-asserts must not pop
			-- the idle-faded tabs back up. On a real reveal we also re-arm the
			-- idle fade-out so the tabs disappear again when left alone.
			if reveal and window.dock then
				window.dock:Show()
				if window.dock.FadeOutTabs then
					window.dock:FadeOutTabs()
				end
			end
		end
	end
	-- Expose so the spawn / delete window helpers can re-run the layout.
	self._setupTabs = SetupTabs

	-- Run setup now, then re-assert it: Blizzard finishes restoring the chat
	-- windows (names, docking) a little after login.
	SetupTabs(true)
	C_Timer.After(0.5, function()
		SetupTabs(true)
	end)
	C_Timer.After(2, function()
		SetupTabs(true)
	end)
	-- Restore chat messages after 1 second
	C_Timer.After(1, function()
		self:RestoreChatMessages()
	end)

	-- Edit box
	self.editBox = CreateEditBox(self.container, self.mainWindow.profile)
	-- The single edit box follows the active (last-clicked) window. Start on main.
	self.editBox.window = self.mainWindow
	self.activeWindow = self.mainWindow

	-- Social toasts / alerts are anchored to the native chat frame; move them
	-- above the LimpidUI window instead.
	if _G.ChatAlertFrame then
		pcall(function()
			_G.ChatAlertFrame:ClearAllPoints()
			_G.ChatAlertFrame:SetPoint("BOTTOMLEFT", self.container, "TOPLEFT", 15, 10)
		end)
	end

	self:SetupTopBarButtonToggles()

	-- LimpidUI uses one edit box for every window, which is Blizzard's "classic"
	-- chat style (the "im" style gives each chat frame its own edit box).
	local chatStyleCVar = GetCVar("chatStyle")
	if chatStyleCVar and chatStyleCVar ~= "classic" then
		SetCVar("chatStyle", "classic")
		Utils.notify('Chat Style set to "Classic Style"')
	end

	self:InstallChatHooks()

	self:StartRenderLoop()
end

-- Show Blizzard's own Combat Log frame inside `window` while its LimpidUI tab is
-- selected (the Combat Log draws itself; LimpidUI only provides the tab), and
-- park it again when `window` is nil.
function UIManager:ShowNativeCombatLog(window)
	local combatLogFrame = _G.ChatFrame2
	if not combatLogFrame then
		return
	end

	if window and window.container then
		if not keptHidden[combatLogFrame] then
			HideNativeFrame(combatLogFrame) -- installs the hook first
		end
		keptHidden[combatLogFrame] = "released"
		combatLogFrame:SetParent(window.container)
		combatLogFrame:ClearAllPoints()
		-- Below the LimpidUI dock (extra offset for the Combat Log's filter bar).
		combatLogFrame:SetPoint("TOPLEFT", window.container, "TOPLEFT", 0, -Constants.DOCK_HEIGHT - 30)
		combatLogFrame:SetPoint("BOTTOMRIGHT", window.container, "BOTTOMRIGHT", 0, 0)
		combatLogFrame:SetAlpha(1)
		combatLogFrame:Show()
		self.combatLogWindow = window
	elseif keptHidden[combatLogFrame] == "released" then
		keptHidden[combatLogFrame] = true
		combatLogFrame:SetParent(hiddenHolder)
		self.combatLogWindow = nil
	end
end

-- Apply and enforce the user's "hide Social / Chat Menu button" settings, and
-- keep them in sync when those settings change.
--
-- On this client the Chat Menu button lives inside the native chat frame (so
-- it is hidden with it) and the Social button is the Quick Join button.
function UIManager:SetupTopBarButtonToggles()
	local function applySocialButton()
		local button = _G.QuickJoinToastButton
		if not button then
			return
		end
		if Core.db.profile.hideSocialButton then
			HideNativeFrame(button)
		elseif keptHidden[button] then
			keptHidden[button] = "released"
			button:SetParent(UIParent)
			button:ClearAllPoints()
			button:SetPoint("TOPRIGHT", self.container, "TOPLEFT", -4, 0)
			button:Show()
		end
	end

	local function applyChatMenuButton()
		local button = _G.ChatFrameMenuButton
		if not button then
			return
		end
		if Core.db.profile.hideChatMenuButton then
			if keptHidden[button] then
				keptHidden[button] = true
				button:SetParent(hiddenHolder)
			end
			-- Otherwise it is still inside the (hidden) native chat frame.
		else
			if not keptHidden[button] then
				HideNativeFrame(button) -- installs the hook first
			end
			keptHidden[button] = "released"
			button:SetParent(self.container)
			button:ClearAllPoints()
			button:SetPoint("BOTTOMRIGHT", self.container, "BOTTOMLEFT", -4, 0)
			button:Show()
		end
	end

	if not self._topBarButtonsHooked then
		self._topBarButtonsHooked = true
		Core:Subscribe(UPDATE_CONFIG, function(payload)
			local key = Core:ResolveConfigKey(payload)
			if key == "hideSocialButton" then
				applySocialButton()
			elseif key == "hideChatMenuButton" then
				applyChatMenuButton()
			end
		end)
	end

	applySocialButton()
	applyChatMenuButton()

	-- Register PLAYER_LOGOUT and PLAYER_LEAVING_WORLD to save chat history
	-- PLAYER_LEAVING_WORLD fires on /reload, PLAYER_LOGOUT on actual logout
	if not self._logoutRegistered then
		self._logoutRegistered = true
		local logoutFrame = CreateFrame("Frame")
		logoutFrame:RegisterEvent("PLAYER_LOGOUT")
		logoutFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
		local uiManager = self -- Capture self for closure
		local hasSaved = false -- Prevent double-save
		logoutFrame:SetScript("OnEvent", function()
			if hasSaved then
				return
			end
			hasSaved = true
			uiManager:SaveChatMessages()
		end)
	end
end

-- Save chat messages to global storage for restore after reload.
--
-- Forever port: the history comes from what LimpidUI itself displayed (already
-- filtered and formatted, with its colour) instead of being read back from the
-- native frames, and lines received as secret values are never kept -- they
-- must not reach the saved variables.
function UIManager:SaveChatMessages()
	if not Core.db.profile.restoreChatMessages then
		-- Clear any stored history if feature is disabled
		Core.db.global.chatHistory = {}
		Core.db.global.chatHistoryTime = 0
		return
	end

	Core.db.global.chatHistory = {}
	Core.db.global.chatHistoryTime = time()

	for _, window in pairs(self.windows) do
		for chatFrameIndex, smf in pairs(window.frames) do
			local raw = smf.state and smf.state.rawMessages
			-- Skip combat log (index 2) and temporary whisper windows.
			if chatFrameIndex ~= 2 and raw and #raw > 0 and not (smf.chatFrame and smf.chatFrame.isTemporary) then
				local saved = {}
				-- Only save the last 50 messages
				local first = (#raw > 50) and (#raw - 50 + 1) or 1
				for n = first, #raw do
					local entry = raw[n]
					if type(entry.text) == "string" and not Utils.IsSecret(entry.text) then
						-- Strip textures and atlases that can't be serialized well
						local msg = entry.text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
						local hex = string.format(
							"|cff%02x%02x%02x",
							math.floor((entry.r or 1) * 255 + 0.5),
							math.floor((entry.g or 1) * 255 + 0.5),
							math.floor((entry.b or 1) * 255 + 0.5)
						)
						-- Wrap message with its colour and handle |r resets
						saved[#saved + 1] = hex .. msg:gsub("|r", "|r" .. hex) .. "|r"
					end
				end
				Core.db.global.chatHistory["ChatFrame" .. chatFrameIndex] = saved
			end
		end
	end
end

-- Restore chat messages from global storage after reload
function UIManager:RestoreChatMessages()
	if self._messagesRestored then
		return
	end

	if not Core.db.profile.restoreChatMessages then
		return
	end

	-- Only restore if the last save was within 10 seconds (reload detection)
	local savedTime = Core.db.global.chatHistoryTime or 0
	if time() - savedTime > 10 then
		return
	end

	local chatHistory = Core.db.global.chatHistory
	if not chatHistory then
		return
	end

	-- Mark as restored to prevent multiple calls
	self._messagesRestored = true

	-- Restore messages directly to our SlidingMessageFrames
	for _, window in pairs(self.windows) do
		if window.frames then
			for chatFrameIndex, smf in pairs(window.frames) do
				-- Skip combat log (index 2)
				if chatFrameIndex ~= 2 then
					local historyKey = "ChatFrame" .. chatFrameIndex
					local messages = chatHistory[historyKey]

					if type(messages) == "table" and #messages > 0 and smf.chatFrame then
						-- Add each saved message directly to our SMF
						-- Text is already wrapped with colors from save
						for _, line in ipairs(messages) do
							if type(line) == "string" then
								smf:AddMessage(smf.chatFrame, line)
							end
						end
					end
				end
			end
		end
	end
end

-- Follow Blizzard's chat-window changes with secure post-hooks: none of
-- Blizzard's functions is replaced. Each hook just schedules a re-layout.
function UIManager:InstallChatHooks()
	if self.chatHooksInstalled then
		return
	end
	self.chatHooksInstalled = true

	-- Defer + debounce: several of these fire in a burst (and from inside
	-- Blizzard's dock code), so re-run the tab setup once, on the next frame.
	local scheduled = false
	local revealNext = false
	local function Reassert(reveal)
		revealNext = revealNext or reveal
		if scheduled then
			return
		end
		scheduled = true
		C_Timer.After(0, function()
			scheduled = false
			local reveal = revealNext
			revealNext = false
			if self._setupTabs then
				self._setupTabs(reveal)
			end
		end)
	end

	local function hook(name, reveal, immediate)
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function()
				if immediate then
					-- Newly created frames must not flash on screen for a frame.
					self:HideNativeChat()
				end
				Reassert(reveal)
			end)
		end
	end

	-- Dock re-layout (also fires constantly; never force the dock visible).
	hook("FCF_DockUpdate", false)
	-- Windows opened / closed / renamed: refresh and show the tabs.
	hook("FCF_OpenNewWindow", true, true)
	hook("FCF_OpenTemporaryWindow", true, true)
	hook("FCF_Close", true)
	hook("FCF_SetWindowName", false)
	hook("FCF_ResetChatWindows", true, true)

	-- Chat window settings pushed by the server at login / on layout changes.
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("UPDATE_CHAT_WINDOWS")
	watcher:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
	watcher:SetScript("OnEvent", function()
		Reassert(false)
	end)
end

-- Drive the per-window render loop: tick each window's container (mouse-over
-- tracking) and its sliding message frames, plus any temporary whisper frames.
function UIManager:StartRenderLoop()
	self.timeElapsed = 0
	self.tickerFrame:SetScript("OnUpdate", function(_, elapsed)
		self.timeElapsed = self.timeElapsed + elapsed

		while self.timeElapsed > 0.01 do
			self.timeElapsed = self.timeElapsed - 0.01

			-- Tick every window: its container (mouse-over tracking) and all of its
			-- sliding message frames. The main window is part of self.windows, so this
			-- covers it too.
			for _, window in pairs(self.windows) do
				if window.container and window.container.OnFrame then
					window.container:OnFrame()
				end
				for _, smf in pairs(window.frames) do
					if smf and smf.OnFrame then
						smf:OnFrame()
					end
				end
			end

		end
	end)
end

-- Make `window` the active window: the single edit box follows it, so pressing
-- ENTER opens the edit box under that window and focus reveals only its
-- messages. Called when the user clicks a window's tab.
function UIManager:SetActiveWindow(window)
	if not window then
		return
	end
	self.activeWindow = window
	if self.editBox and self.editBox.AttachToWindow then
		self.editBox:AttachToWindow(window.container, window.profile, window)
	end
	-- NOTE (Forever port): Blizzard's selection globals are no longer written
	-- here; an addon-written SELECTED_CHAT_FRAME taints commands typed in chat.
end

-- Returns the window that owns a given chat-frame index, based on each
-- secondary window's saved profile.chatFrames list. Defaults to the main window.
function UIManager:GetOwnerWindowForIndex(chatFrameIndex)
	if self.windows then
		for windowId, window in pairs(self.windows) do
			if windowId ~= "Main" and window.profile and window.profile.chatFrames then
				for _, idx in ipairs(window.profile.chatFrames) do
					if idx == chatFrameIndex then
						return window
					end
				end
			end
		end
	end
	return self.mainWindow
end

-- Spawn a brand-new Limpid window hosting a freshly created chat frame.
-- Settings are copied from the source window (the tab that was right-clicked).
-- Returns the new window object, or nil if creation failed.
function UIManager:SpawnNewWindow(sourceWindowId)
	sourceWindowId = sourceWindowId or "Main"

	-- Ask Blizzard which chat frame the next new window will use (the same
	-- function FCF_OpenNewWindow calls), so the frame we assign to the new
	-- LimpidUI window is the one that actually gets opened.
	local newIndex = _G.FCF_GetNextOpenChatWindowIndex and _G.FCF_GetNextOpenChatWindowIndex()
	if not newIndex then
		Utils.notify("No free chat windows available")
		return nil
	end

	-- Generate a unique window id + numeric suffix for frame names.
	local nextNum = 2
	while self.windows["Window" .. nextNum] do
		nextNum = nextNum + 1
	end
	local windowId = "Window" .. nextNum

	-- Copy settings from the source window onto the new one.
	local profile = Core:CreateWindowProfile(windowId, sourceWindowId)
	if not profile then
		return nil
	end
	profile.chatFrames = { newIndex }

	-- Center the new window on screen so it's immediately visible.
	profile.positionAnchor = {
		point = "CENTER",
		xOfs = 0,
		yOfs = 0,
	}

	-- Create the LimpidUI window (mover, container, dock, pool).
	local newWindow = CreateWindow({
		id = windowId,
		parent = UIParent,
		moverName = "LimpidUIMoverFrame" .. nextNum,
		containerName = "LimpidUIFrame" .. nextNum,
		dockName = "LimpidUIChatDock" .. nextNum,
		primaryChatFrame = _G["ChatFrame" .. newIndex],
	})
	if not newWindow then
		Core:DeleteWindowProfile(windowId)
		return nil
	end
	self.windows[windowId] = newWindow

	-- Position the new window's mover.
	newWindow.moverFrame:ClearAllPoints()
	newWindow.moverFrame:SetPoint(
		profile.positionAnchor.point,
		UIParent,
		profile.positionAnchor.point,
		profile.positionAnchor.xOfs,
		profile.positionAnchor.yOfs
	)

	-- Actually spawn the Blizzard chat frame (opens ChatFrame<newIndex>).
	if _G.FCF_OpenNewWindow then
		local ok, _, openedIndex = pcall(_G.FCF_OpenNewWindow)
		if ok and type(openedIndex) == "number" and openedIndex ~= newIndex then
			-- Blizzard picked a different frame than announced: follow it.
			newIndex = openedIndex
			profile.chatFrames = { newIndex }
			newWindow.primaryChatFrame = _G["ChatFrame" .. newIndex]
		end
	end

	-- Route the new chat frame into this window and lay everything out. SetupTabs
	-- reads profile.chatFrames, so the freshly opened frame renders in the new
	-- window's dock rather than the main one.
	if self._setupTabs then
		self._setupTabs(true)
	end

	newWindow.moverFrame:Show()
	newWindow.container:Show()
	newWindow.dock:Show()

	-- Make the window the user just created the active one, so pressing Enter
	-- opens the edit box under IT instead of under the window they came from.
	if self.SetActiveWindow then
		self:SetActiveWindow(newWindow)
	end

	-- Automatically unlock frames so the user can see the new window and
	-- reposition/resize it immediately. This dispatches UNLOCK_MOVER which
	-- enables mouse on all mover frames (including the new one) and shows the
	-- lock/unlock dialog.
	Core:Dispatch(UnlockMover())

	-- A brand-new chat window starts with NO numbered channels: the client
	-- gives it say/yell/guild/party/whispers and nothing else. That is the
	-- game's own behaviour for any new window, but it looks like a bug from
	-- here, so say it plainly instead of leaving the user with a window that
	-- never shows General or Trade.
	if Utils and Utils.notify then
		Utils.notify(L["New window: use its tab menu > Settings to add chat channels."])
	end

	return newWindow
end

-- Delete a (non-default) Limpid window. Its chat frames revert to the main
-- window so nothing is lost.
function UIManager:DeleteWindow(windowId)
	if not windowId or windowId == "Main" then
		return
	end

	local window = self.windows[windowId]
	if not window then
		return
	end

	-- Release this window's SMFs so SetupTabs can re-home its chat frames into the
	-- main window's pool/dock.
	local released = {}
	for idx, smf in pairs(window.frames) do
		released[#released + 1] = { idx = idx, smf = smf }
	end
	for _, entry in ipairs(released) do
		window.frames[entry.idx] = nil
		window.tabs[entry.idx] = nil
		if window.pool and window.pool.Release then
			window.pool:Release(entry.smf)
		end
	end
	window.selectedTab = nil

	-- Hide the window's LimpidUI frames and clean up subscriptions. The SMFs were
	-- unsubscribed by the pool resetter (Release -> smf:Destroy()) above; the dock
	-- and container are one-per-window, so destroy them directly.
	if window.dock then
		if window.dock.Destroy then
			window.dock:Destroy()
		end
		window.dock:Hide()
	end
	if window.container then
		if window.container.Destroy then
			window.container:Destroy()
		end
		window.container:Hide()
	end
	if window.moverFrame then
		-- Destroy unsubscribes from LOCK_MOVER/UNLOCK_MOVER so the mover won't
		-- reappear when the user does /limpid lock after deleting this window.
		if window.moverFrame.Destroy then
			window.moverFrame:Destroy()
		else
			window.moverFrame:Hide()
		end
	end

	-- If this was the active (edit-focus) window, hand focus back to main.
	if self.activeWindow == window then
		self:SetActiveWindow(self.mainWindow)
	end

	-- Drop the window from the registry and remove its saved settings. Clearing
	-- its profile (and thus its chatFrames ownership) means the freed chat frames
	-- have no owner, so the main window reclaims them on the next layout.
	self.windows[windowId] = nil
	Core:DeleteWindowProfile(windowId)

	-- If the options panel was editing this window, fall back to Main.
	local Config = Core:GetModule("Config", true)
	if Config and Config.selectedWindowId == windowId then
		Config.selectedWindowId = "Main"
	end

	-- Re-lay out: the freed chat frames now have no owner → main reclaims them.
	if self._setupTabs then
		self._setupTabs(true)
	end
end

-- Get the window that owns a specific chat frame index (and its id).
function UIManager:GetWindowForChatFrame(chatFrameIndex)
	local owner = self:GetOwnerWindowForIndex(chatFrameIndex)
	for windowId, window in pairs(self.windows) do
		if window == owner then
			return window, windowId
		end
	end
	-- Default: main window owns it
	return self.mainWindow, "Main"
end
