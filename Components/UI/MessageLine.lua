local Core, Constants, Utils = unpack(select(2, ...))

local Colors = Constants.COLORS

local HyperlinkClick = Constants.ACTIONS.HyperlinkClick
local HyperlinkEnter = Constants.ACTIONS.HyperlinkEnter
local HyperlinkLeave = Constants.ACTIONS.HyperlinkLeave

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
-- luacheck: pop

local CreateObjectPool = Utils.CreateObjectPool
local IsSecret = Utils.IsSecret
local Mixin = Utils.Mixin

-- Forever port notes
-- ------------------
-- The 3.3.5 version had to (a) overlay an invisible Button on every |H...|h
-- link, because plain Frames didn't fire hyperlink scripts there, and (b) split
-- embedded |T...|t icons out into separate Textures, because embedded icons
-- ignored the line's alpha. Neither limitation exists on the modern client:
--   * a plain Frame with SetHyperlinksEnabled(true) receives
--     OnHyperlinkClick/Enter/Leave for the FontStrings it owns, with exact hit
--     areas computed by the engine;
--   * embedded textures fade with the FontString.
-- Both workarounds needed to PARSE the text in Lua, which is impossible for
-- secret chat text (boss encounters), so removing them is also what makes the
-- line safe: the text is only ever handed to SetText.

local MessageLineMixin = {}

local LSM = Core.Libs.LSM

function MessageLineMixin:Init()
	self:SetWidth(self.profile.frameWidth)
	local animate = self.profile.messageAnimations ~= false
	self:SetFadeInDuration(animate and self.profile.chatFadeInDuration or 0)
	self:SetFadeOutDuration(animate and self.profile.chatFadeOutDuration or 0)

	local rightBgWidth = math.min(250, self.profile.frameWidth - 50)
	self:SetGradientBackground(
		50,
		rightBgWidth,
		self.profile.chatBackgroundColor or Colors.codGray,
		self.profile.chatBackgroundOpacity
	)

	if self.text == nil then
		self.text = self:CreateFontString(nil, "ARTWORK", "LimpidUIMessageFont")
	end
	-- Apply font settings from window's profile directly (not global FontObject)
	self:UpdateFontFromProfile()
	local leftPadding = self.profile.messageLeftPadding or Constants.TEXT_XPADDING
	self.text:SetPoint("LEFT", leftPadding, 0)
	self.text:SetWidth(self.profile.frameWidth - leftPadding - Constants.TEXT_XPADDING)
	self.text:SetIndentedWordWrap(self.profile.indentWordWrap and true or false)
	-- Allow a single very long run of non-space characters (e.g. spammed
	-- "AAAA...") to break across lines at the frame width.
	self.text:SetNonSpaceWrap(true)

	-- Hyperlink handling (native).
	if not self.hyperlinksReady then
		self.hyperlinksReady = true
		self:SetHyperlinksEnabled(true)
		self:EnableMouse(true)

		self:SetScript("OnHyperlinkClick", function(_, link, text, button)
			-- Links inside secret chat text can't be inspected; ignore them.
			if IsSecret(link) or IsSecret(text) then
				return
			end
			Core:Dispatch(HyperlinkClick({ link, text, button }))
		end)

		self:SetScript("OnHyperlinkEnter", function(_, link, text)
			if IsSecret(link) or IsSecret(text) then
				return
			end
			if self.profile.mouseOverTooltips then
				self.hoveredLink = link
				Core:Dispatch(HyperlinkEnter({ link, text }))
			end
		end)

		self:SetScript("OnHyperlinkLeave", function()
			local link = self.hoveredLink
			self.hoveredLink = nil
			Core:Dispatch(HyperlinkLeave(link))
		end)

		-- The line is mouse-enabled for its links, so forward plain clicks to
		-- the window-focus logic the message frame underneath would have run.
		self:SetScript("OnMouseDown", function(_, button)
			if button == "LeftButton" and self.smf and self.smf.window then
				local UIManager = Core:GetModule("UIManager", true)
				if UIManager and UIManager.SetActiveWindow then
					UIManager:SetActiveWindow(self.smf.window)
				end
			end
		end)
	end

	if self.subscriptions == nil then
		self.subscriptions = {
			Core:Subscribe(UPDATE_CONFIG, function(payload)
				local key =
					Core:ResolveConfigKey(payload, (self.smf and self.smf.window and self.smf.window.id) or "Main")

				if key == nil then
					return
				end

				if key == "chatFadeInDuration" or key == "messageAnimations" then
					local shouldAnimate = self.profile.messageAnimations ~= false
					self:SetFadeInDuration(shouldAnimate and self.profile.chatFadeInDuration or 0)
				end

				if key == "chatFadeOutDuration" or key == "messageAnimations" then
					local shouldAnimate = self.profile.messageAnimations ~= false
					self:SetFadeOutDuration(shouldAnimate and self.profile.chatFadeOutDuration or 0)
				end

				if key == "messageLeftPadding" then
					self:UpdateFrame()
				end

				-- Update font when font settings change for this window
				if
					key == "messageFont"
					or key == "messageFontSize"
					or key == "messageFontFlags"
					or key == "messageLeading"
				then
					self:UpdateFontFromProfile()
				end
			end),
		}
	end
end

---
-- Apply font settings from the window's profile directly to the FontString.
-- This allows each window to have independent font settings.
function MessageLineMixin:UpdateFontFromProfile()
	local fontPath = LSM:Fetch(LSM.MediaType.FONT, self.profile.messageFont)
	local fontSize = self.profile.messageFontSize
	local fontFlags = self.profile.messageFontFlags
	local leading = self.profile.messageLeading

	if fontPath and fontSize then
		self.text:SetFont(fontPath, fontSize, fontFlags or "")
		self.text:SetSpacing(leading or 0)
	end
end

---
-- Set the message text. `text` may be a secret value: it is only passed to
-- SetText, never inspected.
function MessageLineMixin:SetMessageText(text)
	if text == nil then
		text = ""
	end
	self.text:SetText(text)
end

-- Height of one line of text for the current font (never secret: it only
-- depends on the font, not on the text).
local function GetFontHeight(fontString)
	local height = fontString:GetLineHeight()
	if type(height) == "number" and not IsSecret(height) and height > 0 then
		return height
	end
	local _, fontHeight = fontString:GetFont()
	if type(fontHeight) == "number" and fontHeight > 0 then
		return fontHeight
	end
	return 14
end

---
-- Update height based on text height
function MessageLineMixin:UpdateFrame()
	-- Set the widths first so wrapped text reports its real (multi-line) height.
	local leftPadding = self.profile.messageLeftPadding or Constants.TEXT_XPADDING
	self:SetWidth(self.profile.frameWidth)
	self.text:ClearAllPoints()
	self.text:SetPoint("LEFT", leftPadding, 0)
	self.text:SetWidth(self.profile.frameWidth - leftPadding - Constants.TEXT_XPADDING)
	self.text:SetIndentedWordWrap(self.profile.indentWordWrap and true or false)

	local lineHeight = GetFontHeight(self.text)

	-- The measured height is a plain number even when the text itself is
	-- secret (only the text content is protected, not its layout). If the
	-- client ever does return a secret here, fall back to a single line
	-- instead of doing arithmetic on it (which would throw).
	local stringHeight = self.text:GetStringHeight()
	if IsSecret(stringHeight) or type(stringHeight) ~= "number" then
		stringHeight = lineHeight
	end
	if stringHeight < lineHeight then
		stringHeight = lineHeight
	end

	-- Fall back to the default if this (per-window) profile predates the setting,
	-- so a missing value can never crash the render path.
	local linePadding = self.profile.messageLinePadding or Core.defaults.profile.messageLinePadding
	local Ypadding = lineHeight * linePadding
	self:SetHeight(stringHeight + Ypadding * 2)

	local rightBgWidth = math.min(250, self.profile.frameWidth - 50)
	self:SetGradientBackground(
		50,
		rightBgWidth,
		self.profile.chatBackgroundColor or Colors.codGray,
		self.profile.chatBackgroundOpacity
	)
end

---
-- Update texture color based on setting
function MessageLineMixin:UpdateTextures()
	local rightBgWidth = math.min(250, self.profile.frameWidth - 50)
	self:SetGradientBackground(
		50,
		rightBgWidth,
		self.profile.chatBackgroundColor or Colors.codGray,
		self.profile.chatBackgroundOpacity
	)
end

local function CreateMessageLine(parent, profile)
	local FadingFrameMixin = Core.Components.FadingFrameMixin
	local GradientBackgroundMixin = Core.Components.GradientBackgroundMixin

	local frame = CreateFrame("Frame", nil, parent)
	local object = Mixin(frame, FadingFrameMixin, GradientBackgroundMixin, MessageLineMixin)

	object.profile = profile or Core.db.profile
	FadingFrameMixin.Init(object)
	GradientBackgroundMixin.Init(object)
	MessageLineMixin.Init(object)

	return object
end

local function CreateMessageLinePool(parent, profile)
	return CreateObjectPool(function()
		return CreateMessageLine(parent, profile)
	end, function(_, message)
		-- Reset all animations and timers
		message:QuickHide()
		-- Drop the old text; ClearText also removes the "secret text" aspect a
		-- line gets after displaying a secret message, so a reused line behaves
		-- like a fresh one.
		if not (message.text.ClearText and pcall(message.text.ClearText, message.text)) then
			message.text:SetText("")
		end
	end)
end

Core.Components.CreateMessageLine = CreateMessageLine
Core.Components.CreateMessageLinePool = CreateMessageLinePool
