local Core, Constants = unpack(select(2, ...))
local Hyperlinks = Core:GetModule("Hyperlinks")

local HYPERLINK_CLICK = Constants.EVENTS.HYPERLINK_CLICK
local HYPERLINK_ENTER = Constants.EVENTS.HYPERLINK_ENTER
local HYPERLINK_LEAVE = Constants.EVENTS.HYPERLINK_LEAVE

-- luacheck: push ignore 113
local GameTooltip = GameTooltip
local UIParent = UIParent
local CreateFrame = CreateFrame
local IsShiftKeyDown = IsShiftKeyDown
-- luacheck: pop

-- Link types that can be previewed in a tooltip on hover.
local tooltipLinkTypes = {
	item = true,
	enchant = true,
	spell = true,
	quest = true,
	achievement = true,
	talent = true,
	currency = true,
	keystone = true,
	battlepet = false, -- needs the dedicated battle pet tooltip
}

-- Copy dialog shown when a detected URL link is clicked. Addons can't write
-- to the clipboard, so we present the URL in a focused, pre-selected edit box
-- for the user to Ctrl+C.
local copyDialog

local function ensureCopyDialog()
	if copyDialog then
		return copyDialog
	end

	local f = CreateFrame("Frame", "LimpidCopyURLDialog", UIParent, "BackdropTemplate")
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetSize(400, 112)
	f:SetPoint("CENTER")
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	title:SetPoint("TOP", 0, -18)
	title:SetText("Link (press Ctrl+C to copy):")

	local editBox = CreateFrame("EditBox", "LimpidCopyURLDialogEditBox", f, "InputBoxTemplate")
	editBox:SetSize(340, 20)
	editBox:SetPoint("TOP", title, "BOTTOM", 0, -14)
	editBox:SetAutoFocus(false)
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		f:Hide()
	end)
	editBox:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		f:Hide()
	end)
	editBox:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	f.editBox = editBox

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(100, 24)
	close:SetPoint("BOTTOM", 0, 16)
	close:SetText(_G.CLOSE or "Close")
	close:SetScript("OnClick", function()
		f:Hide()
	end)

	-- Let Escape close it via the standard mechanism.
	if _G.UISpecialFrames then
		table.insert(_G.UISpecialFrames, "LimpidCopyURLDialog")
	end

	f:Hide()
	copyDialog = f
	return f
end

local function showCopyDialog(url)
	local f = ensureCopyDialog()
	f.editBox:SetText(url or "")
	f.editBox:SetCursorPosition(0)
	f:Show()
	f:Raise()
	f.editBox:SetFocus()
	f.editBox:HighlightText()
end

function Hyperlinks:OnInitialize()
	self.state = {
		showingTooltip = nil,
	}
end

function Hyperlinks:OnEnable()
	Core:Subscribe(HYPERLINK_CLICK, function(payload)
		local link, text, button = unpack(payload)

		-- Detected URL links open a small copy dialog instead of SetItemRef.
		local linkType = link and string.match(link, "^(%a+):")
		if linkType == "url" then
			local url = string.match(link, "^url:(.+)$") or text
			if url and url ~= "" then
				showCopyDialog(url)
			end
			return
		end

		-- Shift-click on a player link sends a group invite when Limpid's
		-- "Shift-Click Invite" feature is enabled. The flag is read live from the
		-- shared saved variable, which a settings reset can briefly set to nil.
		if IsShiftKeyDown() and linkType == "player" then
			local ccdb = _G.Limpid_DB
			if ccdb and ccdb.filters and ccdb.filters.clickInvite then
				local inviteName = string.match(link, "^player:([^:]+)")
				if inviteName and inviteName ~= "" and _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
					_G.C_PartyInfo.InviteUnit(inviteName)
					return
				end
			end
		end

		-- Everything else goes to the game's own link handler, which already
		-- deals with modified clicks (shift-click to link in chat, ctrl-click
		-- for the dressing room) and with links other addons registered.
		--
		-- pcall it: custom link types SetItemRef doesn't understand would
		-- otherwise throw "Unknown link type" on click.
		--
		-- Pass the chat frame as 4th arg so channel/player menus know which
		-- frame they belong to.
		local chatFrame
		if Core.Components.selectedTab and Core.Components.selectedTab.chatFrame then
			chatFrame = Core.Components.selectedTab.chatFrame
		else
			chatFrame = _G.SELECTED_CHAT_FRAME or _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
		end
		pcall(_G.SetItemRef, link, text, button, chatFrame)
	end)

	Core:Subscribe(HYPERLINK_ENTER, function(payload)
		local link = unpack(payload)
		if type(link) ~= "string" then
			return
		end
		local t = string.match(link, "^(.-):")

		if t == "url" then
			self.state.showingTooltip = GameTooltip
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			GameTooltip:SetText("Click to copy link")
			GameTooltip:Show()
		elseif tooltipLinkTypes[t] then
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			-- pcall: an unknown or malformed link must not throw on hover.
			local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
			if ok then
				self.state.showingTooltip = GameTooltip
				GameTooltip:Show()
			else
				GameTooltip:Hide()
			end
		end
	end)

	Core:Subscribe(HYPERLINK_LEAVE, function(link)
		if self.state.showingTooltip then
			self.state.showingTooltip:Hide()
			self.state.showingTooltip = false
		end
	end)
end
