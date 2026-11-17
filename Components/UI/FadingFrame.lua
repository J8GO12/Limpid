local Core, _, Utils = unpack(select(2, ...))

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local C_Timer = C_Timer
-- luacheck: pop

local Mixin = Utils.Mixin

local Tween = Core.Libs.Tween

local FadingFrameMixin = {}

-- Configure an Alpha animation's endpoints.
local function SafeSetAlphaAnimation(anim, fromAlpha, toAlpha)
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	anim:SetSmoothing("OUT")
end

-- Native Frame methods (the mixin below overrides Show/Hide on our frames)
local FramePrototype = getmetatable(CreateFrame("Frame")).__index
local Frame_Show = FramePrototype.Show
local Frame_Hide = FramePrototype.Hide

function FadingFrameMixin:Init()
	if self.showAg == nil then
		self.showAg = self:CreateAnimationGroup()
		self.fadeIn = self.showAg:CreateAnimation("Alpha")
		SafeSetAlphaAnimation(self.fadeIn, 0, 1)
		self.fadeIn:SetDuration(0)

		self.showAg:SetScript("OnFinished", function()
			self:SetAlpha(1)
		end)
	end

	if self.hideAg == nil then
		self.hideAg = self:CreateAnimationGroup()
		self.fadeOut = self.hideAg:CreateAnimation("Alpha")
		SafeSetAlphaAnimation(self.fadeOut, 1, 0)
		self.fadeOut:SetDuration(0)

		self.hideAg:SetScript("OnFinished", function()
			self:SetAlpha(1) -- Reset alpha before hiding
			self:QuickHide()
		end)
	end
end

function FadingFrameMixin:QuickShow()
	self:StopAnimating()

	if self.fadeHandle and Tween then
		Tween:StopEasing(self.fadeHandle)
		self.fadeHandle = nil
	end

	if self.hideTimer ~= nil then
		self.hideTimer:Cancel()
		self.hideTimer = nil
	end

	self:SetAlpha(1)
	Frame_Show(self)
end

function FadingFrameMixin:QuickHide()
	if self.fadeHandle and Tween then
		Tween:StopEasing(self.fadeHandle)
		self.fadeHandle = nil
	end

	if self.hideTimer ~= nil then
		self.hideTimer:Cancel()
		self.hideTimer = nil
	end

	self:SetAlpha(1)
	Frame_Hide(self)
end

function FadingFrameMixin:Show()
	-- Cancel any pending hide / in-flight fade-out so a re-shown (e.g.
	-- moused-over) line snaps back to full opacity instead of continuing to fade.
	if self.hideTimer ~= nil then
		self.hideTimer:Cancel()
		self.hideTimer = nil
	end

	if self.fadeHandle and Tween then
		Tween:StopEasing(self.fadeHandle)
		self.fadeHandle = nil
	end

	self:StopAnimating()
	self:SetAlpha(1) -- Ensure fully visible
	if not self:IsVisible() then
		Frame_Show(self)
	end
	-- Fade-in itself is driven by the SlidingMessageFrame slide animation.
end

-- Fade in with animation (for hover/focus reveal)
function FadingFrameMixin:FadeIn(duration)
	-- Cancel any pending hide / in-flight fade
	if self.hideTimer ~= nil then
		self.hideTimer:Cancel()
		self.hideTimer = nil
	end

	if self.fadeHandle and Tween then
		Tween:StopEasing(self.fadeHandle)
		self.fadeHandle = nil
	end

	self:StopAnimating()

	duration = duration or (self.fadeInDuration or 0.3)
	local startAlpha = self:GetAlpha()

	if not self:IsVisible() then
		self:SetAlpha(0)
		startAlpha = 0
		Frame_Show(self)
	end

	if duration > 0 and startAlpha < 1 and Tween then
		self.fadeHandle = Tween:Ease(
			function(alpha)
				self:SetAlpha(alpha)
			end,
			startAlpha,
			1,
			duration,
			Tween.OutCubic,
			function()
				self.fadeHandle = nil
				self:SetAlpha(1)
			end
		)
	else
		self:SetAlpha(1)
	end
end

function FadingFrameMixin:Hide()
	if self.hideTimer ~= nil then
		self.hideTimer:Cancel()
		self.hideTimer = nil
	end

	if not self:IsVisible() then
		return
	end

	if self.fadeHandle and Tween then
		Tween:StopEasing(self.fadeHandle)
		self.fadeHandle = nil
	end

	-- Fade the alpha out over the configured duration, then hide for real,
	-- driven by Tween -- the same approach the chat dock uses.
	local duration = self.fadeOutDuration or 0
	if duration > 0 and Tween then
		self.fadeHandle = Tween:Ease(
			function(alpha)
				self:SetAlpha(alpha)
			end,
			self:GetAlpha(),
			0,
			duration,
			Tween.OutCubic,
			function()
				self.fadeHandle = nil
				Frame_Hide(self)
				self:SetAlpha(1)
			end
		)
	else
		self:SetAlpha(1)
		Frame_Hide(self)
	end
end

function FadingFrameMixin:HideDelay(delay)
	-- Ensure valid delay
	delay = delay or 10
	if delay < 1 then
		delay = 10 -- Default to 10 seconds
	end

	if self:IsVisible() then
		if self.hideTimer ~= nil then
			self.hideTimer:Cancel()
		end

		self.hideTimer = C_Timer.NewTimer(delay, function()
			self.hideTimer = nil
			self:Hide()
		end)
	end
end

function FadingFrameMixin:SetFadeInDuration(duration)
	self.fadeInDuration = duration
	self.fadeIn:SetDuration(duration)
end

function FadingFrameMixin:SetFadeOutDuration(duration)
	self.fadeOutDuration = duration
	self.fadeOut:SetDuration(duration)
end

local function CreateFadingFrame(frameType, name, parent)
	local frame = CreateFrame(frameType, name, parent)
	local object = Mixin(frame, FadingFrameMixin)
	object:Init()
	return object
end

Core.Components.CreateFadingFrame = CreateFadingFrame
Core.Components.FadingFrameMixin = FadingFrameMixin

local GradientBackgroundMixin = {}

function GradientBackgroundMixin:Init() end

function GradientBackgroundMixin:SetGradientBackground(_leftWidth, _rightWidth, color, opacity)
	-- Simplified background without gradient edges (solid colour).

	-- Left gradient edge (unused)
	if self.leftBg == nil then
		self.leftBg = self:CreateTexture(nil, "BACKGROUND")
		self.leftBg:SetPoint("TOPLEFT")
		self.leftBg:SetPoint("BOTTOMLEFT")
	end
	self.leftBg:SetWidth(0) -- Hide by setting width to 0
	self.leftBg:Hide()

	-- Right gradient edge (unused)
	if self.rightBg == nil then
		self.rightBg = self:CreateTexture(nil, "BACKGROUND")
		self.rightBg:SetPoint("TOPRIGHT")
		self.rightBg:SetPoint("BOTTOMRIGHT")
	end
	self.rightBg:SetWidth(0) -- Hide by setting width to 0
	self.rightBg:Hide()

	-- Full-width solid background
	if self.centerBg == nil then
		self.centerBg = self:CreateTexture(nil, "BACKGROUND")
		self.centerBg:SetAllPoints() -- Cover the entire frame
		self.centerBg:SetTexture("Interface\\Buttons\\WHITE8x8")
	end
	-- Solid color background
	self.centerBg:SetVertexColor(color.r, color.g, color.b, opacity)
	self.centerBg:Show()
end

Core.Components.GradientBackgroundMixin = GradientBackgroundMixin
