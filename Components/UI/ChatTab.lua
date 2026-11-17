local Core, Constants, Utils = unpack(select(2, ...))

local LSM = Core.Libs.LSM

local UnlockMover = Constants.ACTIONS.UnlockMover

local Colors = Constants.COLORS

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

local L = LibStub("AceLocale-3.0"):GetLocale("Limpid")

local IsSecret = Utils.IsSecret
local Mixin = Utils.Mixin

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local InCombatLockdown = InCombatLockdown
-- luacheck: pop

----
-- ChatTab
--
-- Forever port: LimpidUI now draws its OWN tab buttons.
--
-- The 3.3.5 version adopted Blizzard's native ChatFrameNTab buttons: it mixed
-- methods into them, raw-hooked SetAlpha/SetWidth/SetText, replaced their
-- OnClick and re-initialised their dropdown menu. On the modern client those
-- tabs belong to the docking + Edit Mode code and their right-click menu is
-- built with the new Menu system, so every one of those tricks either no
-- longer exists or taints Blizzard's chat UI. The native tabs are simply
-- hidden (with their chat frames) and left alone; these buttons replace them
-- and call the same public FCF_* functions the native menu calls.

-- The Combat Log is ChatFrame2 (when Blizzard_CombatLog is loaded).
local function IsCombatLogFrame(chatFrame)
	return chatFrame == _G.ChatFrame2
end

-- Name shown on a tab: the chat window's saved name.
local function GetChatFrameName(chatFrame)
	local name
	if _G.FCF_GetChatWindowInfo then
		local ok, result = pcall(_G.FCF_GetChatWindowInfo, chatFrame:GetID())
		if ok then
			name = result
		end
	end
	if IsSecret(name) then
		-- Whisper windows can carry a secret name; it can still be displayed.
		return name
	end
	if type(name) ~= "string" or name == "" then
		name = chatFrame.name
	end
	if type(name) ~= "string" or name == "" then
		name = "Chat " .. tostring(chatFrame:GetID())
	end
	return name
end

local ChatTabMixin = {}

function ChatTabMixin:Init(slidingMessageFrame)
	self.slidingMessageFrame = slidingMessageFrame
	self.chatFrame = slidingMessageFrame.chatFrame

	self:SetHeight(Constants.DOCK_HEIGHT)

	if self.Text == nil then
		self.Text = self:CreateFontString(nil, "ARTWORK", "LimpidUIChatDockFont")
		self.Text:SetPoint("LEFT", Constants.TEXT_XPADDING, 0)
		self.Text:SetTextColor(Colors.apache.r, Colors.apache.g, Colors.apache.b)
	end

	-- Apply per-window font settings, then the name (which sizes the tab).
	self:UpdateFontFromProfile()
	self:UpdateName()

	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			self:ShowContextMenu()
			return
		end
		-- Switch to this tab's messages. The `true` flag marks this as a real
		-- user click so it also makes this window active.
		Core.Components.SelectChatTab(self, true)
	end)

	-- Listeners
	if self.subscriptions == nil then
		self.subscriptions = {
			Core:Subscribe(UPDATE_CONFIG, function(payload)
				local key = Core:ResolveConfigKey(
					payload,
					(
						self.slidingMessageFrame
						and self.slidingMessageFrame.window
						and self.slidingMessageFrame.window.id
					) or "Main"
				)

				if key == nil then
					return
				end

				-- Update font when dock font settings change for this window
				if key == "dockFont" or key == "dockFontSize" or key == "dockFontFlags" then
					self:UpdateFontFromProfile()
				end

				if
					key == "frameWidth"
					or key == "frameHeight"
					or key == "dockFont"
					or key == "dockFontSize"
					or key == "dockFontFlags"
					or key == "messageFontSize"
				then
					self:UpdateWidth()
					self:Reposition()
				end

				-- Update skin when tab style settings change for this window
				if
					key == "tabStyle"
					or key == "tabCornerStyle"
					or key == "tabActiveColor"
					or key == "tabInactiveColor"
					or key == "tabBackgroundOpacity"
					or key == "tabBorderThickness"
				then
					self:ApplySkin()
					self:UpdateSkinColors()
				end

				-- Update tab positions when spacing settings change
				if key == "tabSpacing" or key == "tabPadding" then
					self:Reposition()
				end
			end),
		}
	end

	-- Apply initial skin
	self:ApplySkin()
end

-- Re-run the dock layout for the window this tab lives in.
function ChatTabMixin:Reposition()
	local window = self.slidingMessageFrame and self.slidingMessageFrame.window
	if window and window.tabs then
		Core.Components.UpdateTabPositions(window.tabs)
	end
end

-- Refresh the label from the chat window's current name.
function ChatTabMixin:UpdateName()
	local name = GetChatFrameName(self.chatFrame)
	self.nameIsSecret = IsSecret(name)
	self.Text:SetText(name)
	self:UpdateWidth()
end

-- Size the tab to its label.
function ChatTabMixin:UpdateWidth()
	local width
	if not self.nameIsSecret then
		width = self.Text:GetStringWidth()
	end
	-- A secret name can't be measured from Lua: use a fixed width for it.
	if IsSecret(width) or type(width) ~= "number" then
		width = 70
	end
	local newWidth = width + Constants.TEXT_XPADDING * 2
	if newWidth < 40 then
		newWidth = 60 -- Minimum width
	end
	self:SetWidth(newWidth)
end

-- Right-click menu (built with the client's Menu system).
function ChatTabMixin:ShowContextMenu()
	if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then
		return
	end

	local chatFrame = self.chatFrame
	local UIManager = Core:GetModule("UIManager", true)
	local currentWindowId
	if UIManager then
		local _
		_, currentWindowId = UIManager:GetWindowForChatFrame(chatFrame:GetID())
	end
	local isCombatLog = IsCombatLogFrame(chatFrame)

	-- Blizzard's window functions use protected panel code; refuse politely
	-- in combat instead of triggering an "action blocked" error.
	local function outOfCombat()
		if InCombatLockdown() then
			Utils.notify(_G.ERR_NOT_IN_COMBAT or "You can't do that while in combat.")
			return false
		end
		return true
	end

	_G.MenuUtil.CreateContextMenu(self, function(_, root)
		root:SetTag("MENU_CLEANERCHAT_TAB")

		if chatFrame == DEFAULT_CHAT_FRAME then
			-- Unlock chat window (LimpidUI' own mover)
			root:CreateButton(_G.UNLOCK_WINDOW or "Unlock Window", function()
				Core:Dispatch(UnlockMover())
			end)

			-- Create new chat window
			local newButton = root:CreateButton(_G.NEW_CHAT_WINDOW or "Create New Window", function()
				if outOfCombat() and _G.FCF_NewChatWindow then
					_G.FCF_NewChatWindow()
				end
			end)
			if _G.FCF_CanOpenNewWindow and not _G.FCF_CanOpenNewWindow() then
				newButton:SetEnabled(false)
			end
		end

		-- Rename window (same popup the native tab menu opens)
		if not chatFrame.isTemporary then
			root:CreateButton(_G.RENAME_CHAT_WINDOW or "Rename Window", function()
				if _G.StaticPopup_Show then
					_G.StaticPopup_Show("NAME_CHAT", nil, nil, chatFrame:GetID())
				end
			end)
		end

		-- Close chat window (non-default, non-combat-log frames in the Main
		-- window only; for detached Limpid windows, "Delete window" closes).
		if
			chatFrame ~= DEFAULT_CHAT_FRAME
			and not isCombatLog
			and (not currentWindowId or currentWindowId == "Main")
		then
			root:CreateButton(_G.CLOSE_CHAT_WINDOW or "Close Window", function()
				if not outOfCombat() then
					return
				end
				if chatFrame.isTemporary and chatFrame.chatType ~= "WHISPER" and chatFrame.chatType ~= "BN_WHISPER" then
					if _G.FCF_Close then
						_G.FCF_Close(chatFrame)
					end
				elseif _G.FCF_PopInWindow then
					_G.FCF_PopInWindow(chatFrame)
				end
			end)
		end

		root:CreateTitle(_G.FILTERS or "Filters")

		-- Blizzard chat settings, opened on this tab's chat window.
		if not chatFrame.isTemporary then
			root:CreateButton(_G.CHAT_CONFIGURATION or "Settings", function()
				if not outOfCombat() or not _G.ChatConfigFrame then
					return
				end
				-- The settings window edits "the current chat frame". This
				-- global is only read by the chat settings / window-menu code.
				_G.CURRENT_CHAT_FRAME_ID = chatFrame:GetID()
				_G.ShowUIPanel(_G.ChatConfigFrame)
			end)
		end

		-- Limpid settings (opens the /limpid options panel)
		root:CreateButton(L["Limpid settings"], function()
			local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
			local cc = AceAddon and AceAddon:GetAddon("Limpid", true)
			local options = cc and cc:GetModule("Options", true)
			if options then
				options:OpenOptionsMenu("")
			end
		end)

		-- "New window" — spawn a brand-new Limpid window (a new chat frame
		-- rendered as its own LimpidUI window, copying the current window's
		-- settings). Available on any regular chat tab.
		if UIManager and not isCombatLog and not chatFrame.isTemporary then
			root:CreateButton(L["New detached window"], function()
				if outOfCombat() then
					UIManager:SpawnNewWindow(currentWindowId)
				end
			end)

			-- "Delete window" — only on non-default (added) windows.
			if currentWindowId and currentWindowId ~= "Main" then
				root:CreateButton(L["Delete window"], function()
					UIManager:DeleteWindow(currentWindowId)
				end)
			end
		end
	end)
end

-- Unsubscribe and hide (the button itself is kept for reuse by its chat frame).
function ChatTabMixin:Release()
	if self.subscriptions then
		for _, unsubscribe in ipairs(self.subscriptions) do
			if type(unsubscribe) == "function" then
				unsubscribe()
			end
		end
		self.subscriptions = nil
	end
	if self._flashFrame then
		self._flashFrame:SetScript("OnUpdate", nil)
	end
	self._isFlashing = false
	self:Hide()
end

---
-- Apply the visual skin style to the tab button.
-- Supports: minimal (text only), outline (border only)
-- With corner styles: square or rounded
function ChatTabMixin:ApplySkin()
	local profile = self.slidingMessageFrame
		and self.slidingMessageFrame.window
		and self.slidingMessageFrame.window.profile
	profile = profile or Core.db.profile

	local style = profile.tabStyle or "minimal"
	-- Backward compatibility: old styles map to outline
	if style == "modern" or style == "filled" then
		style = "outline"
	end

	local cornerStyle = profile.tabCornerStyle or "square"
	local isRounded = cornerStyle == "rounded"
	local isOutline = style == "outline"

	if isOutline then
		if isRounded then
			-- ROUNDED CORNERS: Use backdrop-based rendering
			-- Hide texture-based elements
			if self.skinBorderTop then
				self.skinBorderTop:Hide()
			end
			if self.skinBorderBottom then
				self.skinBorderBottom:Hide()
			end
			if self.skinBorderLeft then
				self.skinBorderLeft:Hide()
			end
			if self.skinBorderRight then
				self.skinBorderRight:Hide()
			end

			-- Create backdrop frame if needed
			if not self.skinBackdrop then
				self.skinBackdrop = CreateFrame("Frame", nil, self, "BackdropTemplate")
				self.skinBackdrop:SetFrameLevel(math.max(1, self:GetFrameLevel() - 1))
				self.skinBackdrop:SetAllPoints()
			end

			-- Set rounded backdrop (tooltip border has natural rounded corners)
			self.skinBackdrop:SetBackdrop({
				bgFile = nil, -- No fill, outline only
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = false,
				tileSize = 0,
				edgeSize = 14,
				insets = { left = 4, right = 4, top = 4, bottom = 4 },
			})
			self.skinBackdrop:Show()
		else
			-- SQUARE CORNERS: Use 4 edge textures for true outline
			-- Hide backdrop if exists
			if self.skinBackdrop then
				self.skinBackdrop:Hide()
			end

			local borderThickness = profile.tabBorderThickness or 1

			-- Create top edge
			if not self.skinBorderTop then
				self.skinBorderTop = self:CreateTexture(nil, "BACKGROUND", nil, -8)
				self.skinBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
				self.skinBorderTop:SetPoint("TOPLEFT", 0, 0)
				self.skinBorderTop:SetPoint("TOPRIGHT", 0, 0)
			end
			self.skinBorderTop:SetHeight(borderThickness)

			-- Create bottom edge
			if not self.skinBorderBottom then
				self.skinBorderBottom = self:CreateTexture(nil, "BACKGROUND", nil, -8)
				self.skinBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
				self.skinBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
				self.skinBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
			end
			self.skinBorderBottom:SetHeight(borderThickness)

			-- Create left edge
			if not self.skinBorderLeft then
				self.skinBorderLeft = self:CreateTexture(nil, "BACKGROUND", nil, -8)
				self.skinBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
				self.skinBorderLeft:SetPoint("TOPLEFT", 0, 0)
				self.skinBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
			end
			self.skinBorderLeft:SetWidth(borderThickness)

			-- Create right edge
			if not self.skinBorderRight then
				self.skinBorderRight = self:CreateTexture(nil, "BACKGROUND", nil, -8)
				self.skinBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
				self.skinBorderRight:SetPoint("TOPRIGHT", 0, 0)
				self.skinBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
			end
			self.skinBorderRight:SetWidth(borderThickness)

			self.skinBorderTop:Show()
			self.skinBorderBottom:Show()
			self.skinBorderLeft:Show()
			self.skinBorderRight:Show()
		end

		-- Hook hover events for visual feedback (only once)
		if not self._skinHoverHooked then
			self._skinHoverHooked = true
			self:HookScript("OnEnter", function()
				self:UpdateSkinColors(true)
			end)
			self:HookScript("OnLeave", function()
				self:UpdateSkinColors(false)
			end)
		end
	else
		-- Minimal style - hide all decoration elements
		if self.skinBorderTop then
			self.skinBorderTop:Hide()
		end
		if self.skinBorderBottom then
			self.skinBorderBottom:Hide()
		end
		if self.skinBorderLeft then
			self.skinBorderLeft:Hide()
		end
		if self.skinBorderRight then
			self.skinBorderRight:Hide()
		end
		if self.skinBackdrop then
			self.skinBackdrop:Hide()
		end
	end

	self:UpdateSkinColors()
end

---
-- Update skin colors based on selection state and hover.
-- @param isHovered boolean (optional) Whether the tab is being hovered
function ChatTabMixin:UpdateSkinColors(isHovered)
	local profile = self.slidingMessageFrame
		and self.slidingMessageFrame.window
		and self.slidingMessageFrame.window.profile
	profile = profile or Core.db.profile

	local style = profile.tabStyle or "minimal"
	-- Backward compatibility
	if style == "modern" or style == "filled" then
		style = "outline"
	end

	local cornerStyle = profile.tabCornerStyle or "square"
	local isRounded = cornerStyle == "rounded"
	local isOutline = style == "outline"

	if not isOutline then
		return
	end

	local isSelected = (Core.Components.selectedTab == self)

	-- Get colors from profile
	local activeColor = profile.tabActiveColor or { r = 223 / 255, g = 186 / 255, b = 105 / 255 }
	local inactiveColor = profile.tabInactiveColor or { r = 0.4, g = 0.4, b = 0.4 }
	local bgOpacity = profile.tabBackgroundOpacity or 0.7

	-- Determine the base color
	local baseColor = isSelected and activeColor or inactiveColor

	-- Apply hover brightening effect
	local hoverMult = isHovered and 1.3 or 1.0
	local r = math.min(1, baseColor.r * hoverMult)
	local g = math.min(1, baseColor.g * hoverMult)
	local b = math.min(1, baseColor.b * hoverMult)

	-- Opacity multiplier based on state
	local opacityMult = isSelected and 1.0 or (isHovered and 0.5 or 0.3)
	local finalOpacity = bgOpacity * opacityMult

	if isRounded then
		-- ROUNDED: Update backdrop colors
		if self.skinBackdrop then
			self.skinBackdrop:SetBackdropColor(0, 0, 0, 0) -- Transparent fill
			self.skinBackdrop:SetBackdropBorderColor(r, g, b, finalOpacity)
		end
	else
		-- SQUARE: Update 4 edge texture colors
		if self.skinBorderTop then
			self.skinBorderTop:SetVertexColor(r, g, b, finalOpacity)
		end
		if self.skinBorderBottom then
			self.skinBorderBottom:SetVertexColor(r, g, b, finalOpacity)
		end
		if self.skinBorderLeft then
			self.skinBorderLeft:SetVertexColor(r, g, b, finalOpacity)
		end
		if self.skinBorderRight then
			self.skinBorderRight:SetVertexColor(r, g, b, finalOpacity)
		end
	end

	-- Update text color based on style
	local tabText = self.Text
	if tabText then
		if isSelected then
			tabText:SetTextColor(1, 1, 1) -- White for selected
		else
			tabText:SetTextColor(activeColor.r, activeColor.g, activeColor.b) -- Gold for unselected
		end
	end
end

---
-- Apply font settings from the window's profile directly to the tab's FontString.
-- This allows each window to have independent tab font settings.
function ChatTabMixin:UpdateFontFromProfile()
	local profile = self.slidingMessageFrame
		and self.slidingMessageFrame.window
		and self.slidingMessageFrame.window.profile
	profile = profile or Core.db.profile

	local fontPath = LSM:Fetch(LSM.MediaType.FONT, profile.dockFont)
	local fontSize = profile.dockFontSize
	local fontFlags = profile.dockFontFlags

	if fontPath and fontSize and self.Text then
		self.Text:SetFont(fontPath, fontSize, fontFlags or "")
	end
end

---
-- Flash the tab to draw attention when a new message arrives.
-- Creates a pulsing highlight effect on the tab text and border.
-- Supports multiple flash styles: blink, pulse, glow, rapid.
-- Only works with outline tab style (modern/filled/outline).
-- If the dock/tabs are faded out, this will show just this tab during the flash.
function ChatTabMixin:FlashTab()
	-- Don't flash if this tab is already selected
	if Core.Components.selectedTab == self then
		return
	end

	-- Check if flashing is enabled (default to true if not set)
	local profile = Core.db.profile
	if self.slidingMessageFrame and self.slidingMessageFrame.window and self.slidingMessageFrame.window.profile then
		profile = self.slidingMessageFrame.window.profile
	end
	local flashEnabled = profile.flashTabOnMessage
	if flashEnabled == false then
		return
	end

	-- Only flash for outline style tabs (outline, modern, filled)
	local tabStyle = profile.tabStyle or "minimal"
	if tabStyle ~= "outline" and tabStyle ~= "modern" and tabStyle ~= "filled" then
		return
	end

	-- Don't start a new flash if one is already running
	if self._isFlashing then
		return
	end

	local tabText = self.Text
	if not tabText then
		return
	end

	self._isFlashing = true

	-- Create a frame for the flash animation if needed
	if not self._flashFrame then
		self._flashFrame = CreateFrame("Frame")
	end

	-- Get tab style info (normalize to outline)
	local cornerStyle = profile.tabCornerStyle or "square"
	local isRounded = cornerStyle == "rounded"

	-- Flash style configuration
	local flashStyle = profile.flashTabStyle or "blink"
	local activeColor = profile.tabActiveColor or { r = 223 / 255, g = 186 / 255, b = 105 / 255 }

	-- Colors for flash
	local highlightColor = { r = 1, g = 1, b = 1 } -- Bright white
	local dimColor = { r = 0.4, g = 0.4, b = 0.4 } -- Dim gray for better contrast

	-- Helper to set border colors for outline style tabs
	local function SetBorderColor(r, g, b, a)
		if isRounded and self.skinBackdrop then
			self.skinBackdrop:SetBackdropBorderColor(r, g, b, a)
		else
			for _, border in ipairs({
				self.skinBorderTop,
				self.skinBorderBottom,
				self.skinBorderLeft,
				self.skinBorderRight,
			}) do
				if border then
					border:SetVertexColor(r, g, b, a)
				end
			end
		end
	end

	-- Helper to set text color
	local function SetTextFlash(r, g, b)
		tabText:SetTextColor(r, g, b)
	end

	-- Helper to interpolate between two colors
	local function LerpColor(t, r1, g1, b1, r2, g2, b2)
		return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
	end

	-- Helper to ensure tab and dock are visible
	local function EnsureVisible()
		self:Show()
		self:SetAlpha(1)
		local dock = self.glassDock or self:GetParent()
		if dock then
			if dock.QuickShow then
				dock:QuickShow()
			elseif dock.Show then
				dock:Show()
				dock:SetAlpha(1)
			end
		end
	end

	-- Animation state
	local totalTime = 0

	-- Style-specific settings
	local config = {
		blink = { duration = 0.25, cycles = 3 }, -- Sharp on/off, 3 cycles
		pulse = { duration = 1.5, cycles = 2 }, -- Smooth sine wave, 2 cycles
		glow = { duration = 0.8, cycles = 3 }, -- Bright flash fading out, 3 cycles
		rapid = { duration = 0.1, cycles = 6 }, -- Fast urgent blinks, 6 cycles
	}
	local cfg = config[flashStyle] or config.blink
	local maxTime = cfg.duration * cfg.cycles

	self._flashFrame:SetScript("OnUpdate", function(frame, delta)
		totalTime = totalTime + delta

		-- Check if we should stop
		if totalTime >= maxTime or Core.Components.selectedTab == self then
			frame:SetScript("OnUpdate", nil)
			self._isFlashing = false
			self:UpdateSkinColors()

			-- After flash ends, restart the dock fade-out timer if tabsOnHover is enabled
			local dock = self.glassDock or self:GetParent()
			if dock and profile.tabsOnHover and dock.FadeOutTabs then
				dock:FadeOutTabs()
			end

			return
		end

		EnsureVisible()

		-- Calculate animation progress based on style
		local r, g, b

		if flashStyle == "blink" then
			-- Sharp on/off alternation
			local cyclePos = math.floor(totalTime / cfg.duration) % 2
			if cyclePos == 0 then
				-- Highlight: white
				SetTextFlash(highlightColor.r, highlightColor.g, highlightColor.b)
				SetBorderColor(1, 1, 1, 1)
			else
				-- Dim: gray (for contrast)
				SetTextFlash(dimColor.r, dimColor.g, dimColor.b)
				SetBorderColor(activeColor.r, activeColor.g, activeColor.b, 0.7)
			end
		elseif flashStyle == "pulse" then
			-- Smooth sine-wave fade between dim and bright
			local cycleProgress = (totalTime % cfg.duration) / cfg.duration
			local t = (math.sin(cycleProgress * math.pi * 2 - math.pi / 2) + 1) / 2 -- 0 to 1 sine wave
			r, g, b =
				LerpColor(t, dimColor.r, dimColor.g, dimColor.b, highlightColor.r, highlightColor.g, highlightColor.b)
			local a = 0.7 + t * 0.3 -- 0.7 to 1.0
			SetTextFlash(r, g, b)
			SetBorderColor(r, g, b, a)
		elseif flashStyle == "glow" then
			-- Starts bright white, gradually fades to dim, then snaps back
			local cycleProgress = (totalTime % cfg.duration) / cfg.duration
			local t = 1 - cycleProgress -- 1 to 0 (fade out)
			r, g, b =
				LerpColor(t, dimColor.r, dimColor.g, dimColor.b, highlightColor.r, highlightColor.g, highlightColor.b)
			local a = 0.5 + t * 0.5 -- 0.5 to 1.0
			SetTextFlash(r, g, b)
			SetBorderColor(r, g, b, a)
		elseif flashStyle == "rapid" then
			-- Fast urgent blinking
			local cyclePos = math.floor(totalTime / cfg.duration) % 2
			if cyclePos == 0 then
				SetTextFlash(highlightColor.r, highlightColor.g, highlightColor.b)
				SetBorderColor(1, 1, 1, 1)
			else
				SetTextFlash(dimColor.r, dimColor.g, dimColor.b)
				SetBorderColor(activeColor.r, activeColor.g, activeColor.b, 0.7)
			end
		end
	end)
end

-- One LimpidUI tab button per Blizzard chat frame, created on demand and reused.
local tabsByChatFrame = {}

Core.Components.GetChatTab = function(chatFrame)
	return tabsByChatFrame[chatFrame]
end

Core.Components.CreateChatTab = function(slidingMessageFrame)
	local chatFrame = slidingMessageFrame.chatFrame
	if not chatFrame then
		return nil
	end

	local dock = (slidingMessageFrame.window and slidingMessageFrame.window.dock) or _G["LimpidUIChatDock"]

	local tab = tabsByChatFrame[chatFrame]
	if tab then
		-- Already built: update its references (the chat frame may have been
		-- re-homed to a different window) and refresh its label.
		local rehomed = tab.slidingMessageFrame ~= slidingMessageFrame
		tab.slidingMessageFrame = slidingMessageFrame
		tab.chatFrame = chatFrame
		tab.glassDock = dock
		slidingMessageFrame.tab = tab
		if tab.subscriptions == nil then
			-- Released earlier (window closed, then reopened): re-initialise.
			tab:Init(slidingMessageFrame)
		elseif rehomed then
			tab:UpdateFontFromProfile()
			tab:ApplySkin()
		end
		tab:UpdateName()
		return tab
	end

	local frame = CreateFrame("Button", "LimpidUIChatTab" .. tostring(chatFrame:GetID()), dock)
	tab = Mixin(frame, ChatTabMixin)

	local success, err = pcall(tab.Init, tab, slidingMessageFrame)
	if not success then
		Utils.print("ChatTab init failed", err)
		frame:Hide()
		return nil
	end

	tab.glassDock = dock
	slidingMessageFrame.tab = tab
	tabsByChatFrame[chatFrame] = tab

	return tab
end

-- Helper function to update tab positions (called after all tabs are created).
-- `tabs` may be an array or a table keyed by chat-frame index.
Core.Components.UpdateTabPositions = function(tabs)
	if not tabs then
		return
	end

	-- Order by chat-frame id so the layout is stable.
	local ordered = {}
	for _, tab in pairs(tabs) do
		if tab then
			ordered[#ordered + 1] = tab
		end
	end
	table.sort(ordered, function(a, b)
		return a.chatFrame:GetID() < b.chatFrame:GetID()
	end)

	-- Position tabs in their owning window's dock (falls back to the main dock).
	local firstTab = ordered[1]
	local ownerWindow = firstTab and firstTab.slidingMessageFrame and firstTab.slidingMessageFrame.window
	local glassDock = (ownerWindow and ownerWindow.dock) or _G["LimpidUIChatDock"]
	if not glassDock then
		return
	end

	-- Get spacing settings from profile
	local profile = (ownerWindow and ownerWindow.profile) or Core.db.profile
	local tabPadding = profile.tabPadding or 5
	local tabSpacing = profile.tabSpacing or 5

	local xOffset = tabPadding -- Padding from left edge
	for _, tab in ipairs(ordered) do
		tab:SetParent(glassDock)
		-- Match the chat stack's "LOW" strata so tabs stay below Blizzard UI panels.
		tab:SetFrameStrata("LOW")
		tab:SetFrameLevel(11) -- Above the dock background
		tab:ClearAllPoints()
		tab:SetPoint("BOTTOMLEFT", glassDock, "BOTTOMLEFT", xOffset, 0)
		tab:SetAlpha(1)
		tab:Show()

		local tabWidth = tab:GetWidth()
		if type(tabWidth) ~= "number" or IsSecret(tabWidth) or tabWidth < 30 then
			tabWidth = 60 -- Default minimum width
		end
		xOffset = xOffset + tabWidth + tabSpacing -- Add spacing between tabs
	end
end

-- Track currently selected tab
Core.Components.selectedTab = nil

-- Select a chat tab and show its SlidingMessageFrame. `isUserClick` is true when
-- the user actually clicked the tab (vs. programmatic selection during setup);
-- only real clicks change which window is active for the edit box / ENTER.
Core.Components.SelectChatTab = function(selectedTab, isUserClick)
	local UIManager = Core:GetModule("UIManager")
	if not UIManager or not UIManager.state then
		return
	end

	-- Operate on the tab's OWNING window, so selecting a tab only changes that
	-- window's visible chat (multi-window). Falls back to the main render state.
	local window = selectedTab.slidingMessageFrame and selectedTab.slidingMessageFrame.window
	local frames = (window and window.frames) or UIManager.state.frames
	local tabs = (window and window.tabs) or UIManager.state.tabs

	-- Store selected tab (per-window, plus a global "last selected" for sync).
	if window then
		window.selectedTab = selectedTab
		-- A real click makes this window active: the edit box follows it, so ENTER
		-- opens under this window until another window is clicked.
		if isUserClick and UIManager.SetActiveWindow then
			UIManager:SetActiveWindow(window)
		end
	end
	Core.Components.selectedTab = selectedTab

	-- Get the chatFrame for the selected tab
	local selectedChatFrame = selectedTab.chatFrame

	-- NOTE (Forever port): Blizzard's own selection globals (SELECTED_CHAT_FRAME,
	-- SELECTED_DOCK_FRAME) are deliberately NOT written here anymore. The chat
	-- edit box reads them while sending, so an addon-written value would taint
	-- every command typed in chat (/cast, /target, ...).

	-- The Combat Log renders natively: show Blizzard's frame inside this
	-- window while its tab is selected, hide it again otherwise.
	if UIManager.ShowNativeCombatLog then
		UIManager:ShowNativeCombatLog(IsCombatLogFrame(selectedChatFrame) and window or nil)
	end

	-- Show/hide SlidingMessageFrames based on selection
	for _, smf in pairs(frames) do
		if smf and smf.chatFrame and smf.Show and smf.Hide then
			-- Skip showing LimpidUI overlay for Combat Log (it uses native rendering)
			if smf.state and smf.state.isCombatLog then
				smf:Hide()
			elseif smf.chatFrame == selectedChatFrame then
				smf:Show()
			else
				-- Hide every other frame's messages so only the selected tab is visible
				smf:Hide()
			end
		end
	end

	-- Update tab visual states and ensure all tabs stay visible
	for _, tab in pairs(tabs) do
		if tab then
			-- Keep all tabs visible
			tab:Show()

			-- Get the profile for skin style check
			local profile = tab.slidingMessageFrame
				and tab.slidingMessageFrame.window
				and tab.slidingMessageFrame.window.profile
			profile = profile or Core.db.profile
			local style = profile.tabStyle or "minimal"
			-- Backward compatibility
			if style == "modern" or style == "filled" then
				style = "outline"
			end

			-- Update skin colors for outline style tabs
			if style == "outline" and tab.UpdateSkinColors then
				tab:UpdateSkinColors()
			elseif tab.Text then
				-- Minimal style - just update text color directly
				if tab == selectedTab then
					tab.Text:SetTextColor(1, 1, 1) -- White for selected
				else
					tab.Text:SetTextColor(Colors.apache.r, Colors.apache.g, Colors.apache.b)
				end
			end
		end
	end

	-- Ensure the owning window's dock stays visible
	local visDock = (window and window.dock) or _G["LimpidUIChatDock"]
	if visDock then
		visDock:Show()
	end
end
