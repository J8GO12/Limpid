local _, ns = ...

-- Loot popup
-- A floating, background-less list of what YOU just looted, drawn in the
-- Limpid style ("+ icon Item x3") and independent from the chat frames
-- and the quest tracker. A small green arrow marks an item with a higher item
-- level than what you wear in that slot (and that you can equip). Hovering a
-- line shows the item's regular tooltip.
--
-- Clicking on the list pins it: the lines stay until you click anywhere else.
-- The click itself is only observed (GLOBAL_MOUSE_DOWN), never captured, so
-- the list never blocks the game world.
--
-- Everything here is display-only: no Blizzard function is replaced and
-- secret chat payloads are skipped.

local Module = ns:NewModule("LootPopup", "AceEvent-3.0")
ns.LootPopup = Module

local L = LibStub("AceLocale-3.0"):GetLocale((...))

-- Lua API
local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local next = next
local pcall = pcall
local string_find = string.find
local string_format = string.format
local string_match = string.match
local table_insert = table.insert
local table_remove = table.remove
local tonumber = tonumber
local type = type

-- WoW API
local CreateFrame = CreateFrame
local GetTime = GetTime
local GetMoney = GetMoney
local UIParent = UIParent
-- GLOBALS: CreateFrame, GetTime, GetMoney, UIParent, C_Item, C_TooltipInfo, Item
-- GLOBALS: GetInventoryItemLink

local ASSETS = [[Interface\AddOns\Limpid\Assets\]]
local TEX_UP = ASSETS .. "loot_up"
local TEX_COINS = ASSETS .. "coins"

local COLOR_UP = { 0.30, 0.92, 0.38 }

local FADE_IN = 0.18
local FADE_OUT = 0.60
local SLIDE = 14

local defaults = {
	lootPopupDuration = 6, -- seconds a line stays fully visible
	lootPopupMax = 8, -- lines shown at once
	lootPopupScale = 1,
	lootPopupFontSize = 0, -- 0: same size as the chat text
	lootPopupMoney = true, -- show looted coins as one summed line
	lootPopupTotals = true, -- show how many you now carry
	lootPopupGrowUp = true, -- new lines push older ones upwards
}

local function setting(key)
	local db = ns.db
	local value = db and db[key]
	if value == nil then
		return defaults[key]
	end
	return value
end

---------------------------------------------------------------------------
-- Item helpers
---------------------------------------------------------------------------
local function GetItemInfo(link)
	if C_Item and C_Item.GetItemInfo then
		return C_Item.GetItemInfo(link)
	end
	if _G.GetItemInfo then
		return _G.GetItemInfo(link)
	end
end

local function GetItemInfoInstant(link)
	if C_Item and C_Item.GetItemInfoInstant then
		return C_Item.GetItemInfoInstant(link)
	end
	if _G.GetItemInfoInstant then
		return _G.GetItemInfoInstant(link)
	end
end

local function GetItemLevel(link)
	if not link then
		return nil
	end
	local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
	if fn then
		local ok, level = pcall(fn, link)
		if ok and type(level) == "number" then
			return level
		end
	end
	local _, _, _, level = GetItemInfo(link)
	return level
end

local function GetItemCount(itemID)
	local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
	if fn then
		local ok, count = pcall(fn, itemID)
		if ok and type(count) == "number" then
			return count
		end
	end
end

local function QualityColor(quality)
	local hex = ns.GetQualityColorCode and ns.GetQualityColorCode(quality)
	if type(hex) == "string" then
		local r, g, b = string_match(hex, "(%x%x)(%x%x)(%x%x)$")
		if r then
			return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
		end
	end
	local colors = _G.ITEM_QUALITY_COLORS
	local c = colors and colors[quality or 1]
	if c then
		return c.r, c.g, c.b
	end
	return 1, 1, 1
end

---------------------------------------------------------------------------
-- Upgrade arrow
---------------------------------------------------------------------------
local SLOTS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_SHIELD = { 17 },
}
do
	-- Ranged weapons: their own slot when the client still has one.
	local ranged = { _G.INVSLOT_RANGED or 16 }
	SLOTS.INVTYPE_RANGED = ranged
	SLOTS.INVTYPE_RANGEDRIGHT = ranged
	SLOTS.INVTYPE_THROWN = ranged
end

-- Red text in the item's tooltip means this character can't use it (wrong
-- class, armour type, level, skill...).
local function IsUnusable(link)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
		return false
	end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return false
	end
	local function red(color)
		if type(color) ~= "table" then
			return false
		end
		local r, g, b = color.r, color.g, color.b
		if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
			return false
		end
		return r > 0.9 and g < 0.2 and b < 0.2
	end
	for _, line in ipairs(data.lines) do
		if type(line) == "table" and (red(line.leftColor) or red(line.rightColor)) then
			return true
		end
	end
	return false
end

local function IsUpgrade(link, equipLoc, classID, subclassID)
	local slots = SLOTS[equipLoc or ""]
	if not slots or not GetInventoryItemLink then
		return false
	end
	local newLevel = GetItemLevel(link)
	if not newLevel then
		return false
	end

	-- Compare with the weakest piece among the slots it could go in.
	local lowest, lowestLink
	for _, slot in ipairs(slots) do
		local worn = GetInventoryItemLink("player", slot)
		if not worn then
			lowest, lowestLink = 0, nil
			break
		end
		local level = GetItemLevel(worn) or 0
		if not lowest or level < lowest then
			lowest, lowestLink = level, worn
		end
	end
	if not lowest or newLevel <= lowest then
		return false
	end

	-- Armour: never suggest a lighter type than the one worn there (cloth over
	-- mail), cloaks excepted since they are all cloth.
	if classID == 4 and lowestLink and equipLoc ~= "INVTYPE_CLOAK" and subclassID and subclassID >= 1 and subclassID <= 4 then
		local _, _, _, _, _, wornClass, wornSubclass = GetItemInfoInstant(lowestLink)
		if wornClass == 4 and wornSubclass and wornSubclass >= 1 and wornSubclass <= 4 and subclassID < wornSubclass then
			return false
		end
	end

	return not IsUnusable(link)
end

---------------------------------------------------------------------------
-- Money text
---------------------------------------------------------------------------
local function CoinTexture(kind, size)
	if kind == "gold" then
		return string_format("|T%s:%d:%d:0:0:64:64:0:32:0:32|t", TEX_COINS, size, size)
	elseif kind == "silver" then
		return string_format("|T%s:%d:%d:0:0:64:64:32:64:0:32|t", TEX_COINS, size, size)
	end
	return string_format("|T%s:%d:%d:0:0:64:64:0:32:32:64|t", TEX_COINS, size, size)
end

-- Compact: at most the two highest coin types.
local function MoneyText(amount, size)
	amount = math_floor(amount or 0)
	local gold = math_floor(amount / 10000)
	local silver = math_floor((amount % 10000) / 100)
	local copper = amount % 100
	local parts = {}
	if gold > 0 then
		parts[#parts + 1] = gold .. CoinTexture("gold", size)
	end
	if silver > 0 and #parts < 2 then
		parts[#parts + 1] = silver .. CoinTexture("silver", size)
	end
	if (copper > 0 or #parts == 0) and #parts < 2 and gold == 0 then
		parts[#parts + 1] = copper .. CoinTexture("copper", size)
	end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local anchor -- the movable holder
local pinned = false -- clicked: lines stay until a click elsewhere
local demo = false -- demo mode: lines stay until the demo is turned off
local rows = {} -- visible rows, newest first
local pool = {} -- recycled rows

local function FontSettings()
	local path, size, flags
	local glass = ns[1]
	local profile = glass and glass.db and glass.db.profile
	if profile then
		local lsm = glass.Libs and glass.Libs.LSM
		if lsm and profile.messageFont then
			local ok, fetched = pcall(lsm.Fetch, lsm, "font", profile.messageFont)
			if ok and type(fetched) == "string" then
				path = fetched
			end
		end
		size = profile.messageFontSize
		flags = profile.messageFontFlags
	end
	path = path or _G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
	size = (type(size) == "number" and size > 0) and size or 12
	local override = setting("lootPopupFontSize")
	if type(override) == "number" and override > 0 then
		size = override
	end
	flags = type(flags) == "string" and flags or ""
	return path, size, flags
end

local function ApplyFont(fontString, path, size, flags)
	if not fontString:SetFont(path, size, flags) then
		fontString:SetFont(_G.STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, flags)
	end
	fontString:SetShadowColor(0, 0, 0, 1)
	fontString:SetShadowOffset(1, -1)
end

local function SavePosition()
	if not anchor or not ns.db then
		return
	end
	local scale = anchor:GetScale() or 1
	local left, bottom = anchor:GetLeft(), anchor:GetBottom()
	if left and bottom then
		ns.db.lootPopupPos = { x = math_floor(left * scale + 0.5), y = math_floor(bottom * scale + 0.5) }
	end
end

local function ApplyPosition()
	local scale = setting("lootPopupScale")
	anchor:SetScale(scale)
	anchor:ClearAllPoints()
	local pos = ns.db and ns.db.lootPopupPos
	if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
		anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos.x / scale, pos.y / scale)
	else
		anchor:SetPoint("CENTER", UIParent, "CENTER", 260, -40)
	end
end

local OnUpdate

local WIDTH = 260
local GOLD = { 223 / 255, 186 / 255, 105 / 255 }
local SIZES = { 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24 }
local SCALES = { 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.2, 1.3, 1.5, 1.75, 2 }

-- The holder spans the whole list area (all lines), so the mover outlines
-- exactly where loot will appear.
local function UpdateAnchorSize()
	local _, size = FontSettings()
	anchor:SetSize(WIDTH, math_max(1, setting("lootPopupMax")) * (size + 7))
end

local function ShowMenu(owner)
	if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then
		return
	end
	_G.MenuUtil.CreateContextMenu(owner, function(_, root)
		root:SetTag("MENU_CLEANERCHAT_LOOTPOPUP")
		root:CreateTitle(L["Loot Popup"])

		local sizeMenu = root:CreateButton(L["Text size"])
		sizeMenu:CreateRadio(L["Same as chat"], function()
			return (setting("lootPopupFontSize") or 0) == 0
		end, function()
			ns.db.lootPopupFontSize = 0
			Module:Refresh()
		end)
		for _, value in ipairs(SIZES) do
			sizeMenu:CreateRadio(tostring(value), function()
				return setting("lootPopupFontSize") == value
			end, function()
				ns.db.lootPopupFontSize = value
				Module:Refresh()
			end)
		end

		local scaleMenu = root:CreateButton(L["Scale"])
		for _, value in ipairs(SCALES) do
			scaleMenu:CreateRadio(string_format("%d%%", value * 100 + 0.5), function()
				return math.abs((setting("lootPopupScale") or 1) - value) < 0.01
			end, function()
				-- Keep the box where it is on screen while its scale changes.
				SavePosition()
				ns.db.lootPopupScale = value
				Module:Refresh()
			end)
		end

		root:CreateButton(L["Lock"], function()
			if anchor and anchor.unlocked then
				Module:ToggleLock()
			end
		end)
	end)
end

local function EnsureAnchor()
	if anchor then
		return anchor
	end
	anchor = CreateFrame("Frame", "LimpidLootPopup", UIParent)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetClampedToScreen(true)
	anchor:SetMovable(true)
	anchor:EnableMouse(false)
	anchor:RegisterForDrag("LeftButton")
	anchor:SetScript("OnDragStart", function(self)
		if self.unlocked then
			self:StartMoving()
		end
	end)
	anchor:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
		ApplyPosition()
	end)
	anchor:SetScript("OnMouseUp", function(self, button)
		if self.unlocked and button == "RightButton" then
			ShowMenu(self)
		end
	end)

	-- Mover visuals (same look as the chat frame mover), only shown while
	-- unlocked. The title card sits ABOVE the box so it never covers a line.
	local visuals = {}
	local function add(region)
		region:Hide()
		visuals[#visuals + 1] = region
		return region
	end
	local bg = add(anchor:CreateTexture(nil, "BACKGROUND"))
	bg:SetAllPoints()
	bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.10)

	local function edge()
		local t = add(anchor:CreateTexture(nil, "BORDER"))
		t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.85)
		return t
	end
	local top, bottom, left, right = edge(), edge(), edge(), edge()
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(2)
	bottom:SetPoint("BOTTOMLEFT")
	bottom:SetPoint("BOTTOMRIGHT")
	bottom:SetHeight(2)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(2)
	right:SetPoint("TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT")
	right:SetWidth(2)

	local plate = add(anchor:CreateTexture(nil, "ARTWORK"))
	plate:SetColorTexture(0, 0, 0, 0.6)
	plate:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
	plate:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
	plate:SetHeight(44)

	local title = add(anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
	title:SetPoint("TOPLEFT", plate, "TOPLEFT", 10, -8)
	title:SetText(L["Move loot popup"])
	title:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)

	local hint = add(anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
	hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	hint:SetText(L["Drag to move · Right-click for options"])
	hint:SetTextColor(0.8, 0.8, 0.8, 1)

	anchor.visuals = visuals
	anchor.SetMoverShown = function(self, shown)
		for _, region in ipairs(self.visuals) do
			region:SetShown(shown)
		end
	end

	UpdateAnchorSize()
	ApplyPosition()
	return anchor
end

local function CreateRow()
	local row = CreateFrame("Frame", nil, anchor)
	row:EnableMouse(false)

	row.sign = row:CreateFontString(nil, "ARTWORK")
	row.sign:SetPoint("LEFT", row, "LEFT", 0, 0)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	row.name = row:CreateFontString(nil, "ARTWORK")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)

	row.badge = row:CreateTexture(nil, "ARTWORK")

	-- Hover area over the sign, icon and name: shows the item tooltip (other
	-- addons add their lines to it). It reacts to mouse
	-- motion only, so clicks still go through to the game world.
	local hit = CreateFrame("Frame", nil, row)
	hit:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	hit:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
	hit:SetPoint("RIGHT", row.name, "RIGHT", 2, 0)
	hit:EnableMouse(true)
	if hit.SetMouseClickEnabled then
		hit:SetMouseClickEnabled(false)
	end
	hit:SetScript("OnEnter", function(self)
		local link = row.link
		local tooltip = _G.GameTooltip
		if not link or not tooltip then
			return
		end
		row.hovered = true
		tooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = pcall(tooltip.SetHyperlink, tooltip, link)
		if ok then
			tooltip:Show()
		else
			tooltip:Hide()
		end
	end)
	hit:SetScript("OnLeave", function(self)
		row.hovered = nil
		local tooltip = _G.GameTooltip
		if tooltip and tooltip:IsOwned(self) then
			tooltip:Hide()
		end
	end)
	row.hit = hit

	return row
end

local function Layout()
	local growUp = setting("lootPopupGrowUp")
	local offset = 0
	for _, row in ipairs(rows) do
		row:ClearAllPoints()
		if growUp then
			row:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 4 + (row.slide or 0), offset)
		else
			row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 4 + (row.slide or 0), -offset)
		end
		offset = offset + row:GetHeight()
	end
end

local function ReleaseRow(index)
	local row = table_remove(rows, index)
	if row then
		if row.hovered then
			row.hovered = nil
			local tooltip = _G.GameTooltip
			if tooltip and row.hit and tooltip:IsOwned(row.hit) then
				tooltip:Hide()
			end
		end
		row:Hide()
		row.key = nil
		row.itemID = nil
		row.link = nil
		pool[#pool + 1] = row
	end
end

-- Paint a row from its data fields.
local function Render(row)
	local path, size, flags = FontSettings()
	local iconSize = size + 3
	local badgeSize = size + 1
	ApplyFont(row.sign, path, size, flags)
	ApplyFont(row.name, path, size, flags)

	row:SetHeight(size + 7)
	row.sign:SetText("+")
	row.sign:SetTextColor(0.94, 0.94, 0.94)

	local previous = row.sign
	if row.texture then
		row.icon:SetTexture(row.texture)
		row.icon:SetSize(iconSize, iconSize)
		row.icon:ClearAllPoints()
		row.icon:SetPoint("LEFT", previous, "RIGHT", 4, 0)
		row.icon:Show()
		previous = row.icon
	else
		row.icon:Hide()
	end

	local text = row.text or ""
	if row.count and row.count > 1 then
		text = text .. " |cfff0f0f0x" .. row.count .. "|r"
	end
	if row.total and row.total > (row.count or 1) and setting("lootPopupTotals") then
		text = text .. string_format(" |cff8c8c8c(%d)|r", row.total)
	end
	row.name:ClearAllPoints()
	row.name:SetPoint("LEFT", previous, "RIGHT", 4, 0)
	row.name:SetText(text)
	row.name:SetTextColor(row.r or 1, row.g or 1, row.b or 1)
	previous = row.name

	if row.upgrade then
		row.badge:SetTexture(TEX_UP)
		row.badge:SetVertexColor(COLOR_UP[1], COLOR_UP[2], COLOR_UP[3])
		row.badge:SetSize(badgeSize, badgeSize)
		row.badge:ClearAllPoints()
		row.badge:SetPoint("LEFT", previous, "RIGHT", 6, 0)
		row.badge:Show()
	else
		row.badge:Hide()
	end

	-- Wide enough for the pin click and the hover area to cover the text.
	row:SetWidth(math_max(WIDTH, 30 + (row.name:GetStringWidth() or 0) + size * 3))
end

local function Touch(row, fresh)
	local now = GetTime()
	if fresh then
		row.born = now
		row.slide = -SLIDE
		row:SetAlpha(0)
	end
	row.expires = now + setting("lootPopupDuration")
	anchor:SetScript("OnUpdate", OnUpdate)
end

local function FindRow(key)
	for _, row in ipairs(rows) do
		if row.key == key then
			return row
		end
	end
end

local function NewRow(key)
	EnsureAnchor()
	local row = table_remove(pool) or CreateRow()
	row.key = key
	row.itemID, row.texture, row.text, row.count, row.total = nil, nil, nil, nil, nil
	row.link, row.hovered, row.demoUpgrade = nil, nil, nil
	row.upgrade = nil
	row.r, row.g, row.b = 1, 1, 1
	table_insert(rows, 1, row)
	local limit = math_max(1, setting("lootPopupMax"))
	while #rows > limit do
		ReleaseRow(#rows)
	end
	row:Show()
	Touch(row, true)
	return row
end

OnUpdate = function()
	local now = GetTime()
	local moved = false
	for index = #rows, 1, -1 do
		local row = rows[index]
		local age = now - (row.born or now)
		local alpha = 1
		if age < FADE_IN then
			local progress = age / FADE_IN
			alpha = progress
			row.slide = -SLIDE * (1 - progress)
			moved = true
		elseif row.slide ~= 0 then
			row.slide = 0
			moved = true
		end
		if anchor.unlocked or row.hovered or pinned then
			row.expires = math_max(row.expires or now, now + 1)
		end
		local left = (row.expires or now) - now
		if left <= -FADE_OUT then
			ReleaseRow(index)
			moved = true
		else
			if left < 0 then
				alpha = math_min(alpha, 1 + left / FADE_OUT)
			end
			row:SetAlpha(alpha)
		end
	end
	if moved then
		Layout()
	end
	if #rows == 0 then
		pinned = false
		anchor:SetScript("OnUpdate", nil)
	end
end

-- A click on a visible line pins the list, a click anywhere else releases it
-- and lets the lines fade out. Observed only: the click still reaches the game.
local function OverList()
	for _, row in ipairs(rows) do
		if row:IsMouseOver() then
			return true
		end
	end
	return false
end

function Module:OnGlobalMouseDown()
	if not anchor or anchor.unlocked or demo or #rows == 0 then
		return
	end
	if OverList() then
		pinned = true
	elseif pinned then
		pinned = false
		local now = GetTime()
		for _, row in ipairs(rows) do
			row.expires = now + 0.3
		end
	end
end

---------------------------------------------------------------------------
-- Feeding the popup
---------------------------------------------------------------------------
local function FillItem(row, link)
	local name, _, quality, _, _, _, _, _, equipLoc, texture, _, classID, subclassID = GetItemInfo(link)
	if not name then
		return false
	end
	row.text = name
	row.texture = texture
	row.r, row.g, row.b = QualityColor(quality)
	row.upgrade = row.demoUpgrade or IsUpgrade(link, equipLoc, classID, subclassID)
	return true
end

function Module:AddItem(link, count)
	if type(link) ~= "string" or ns.IsSecret(link) then
		return
	end
	local itemID = tonumber(string_match(link, "|Hitem:(%d+)") or string_match(link, "^item:(%d+)"))
	if not itemID then
		return
	end
	count = tonumber(count) or 1

	local key = "item:" .. itemID
	local row = FindRow(key)
	if row then
		row.count = (row.count or 1) + count
		Touch(row, false)
	else
		row = NewRow(key)
		row.itemID = itemID
		row.count = count
		row.link = link
		-- Placeholder until the item data is available.
		row.text = string_match(link, "|h%[(.-)%]|h") or ("item:" .. itemID)
		local _, _, _, _, icon = GetItemInfoInstant(itemID)
		row.texture = icon
	end

	if not FillItem(row, link) and _G.Item and _G.Item.CreateFromItemID then
		local item = _G.Item:CreateFromItemID(itemID)
		item:ContinueOnItemLoad(function()
			if row.key == key then
				FillItem(row, link)
				Render(row)
				Layout()
			end
		end)
	end
	Render(row)
	Layout()

	-- The bags are updated a moment after the chat line.
	ns.Timer.After(0.4, function()
		if row.key == key then
			row.total = GetItemCount(itemID)
			Render(row)
		end
	end)
end

function Module:AddMoney(amount)
	if not amount or amount <= 0 or not setting("lootPopupMoney") then
		return
	end
	local row = FindRow("money")
	if row then
		row.amount = (row.amount or 0) + amount
		Touch(row, false)
	else
		row = NewRow("money")
		row.amount = amount
	end
	local _, size = FontSettings()
	row.text = MoneyText(row.amount, size + 2)
	row.r, row.g, row.b = 0.94, 0.94, 0.94
	Render(row)
	Layout()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local patterns

local function BuildPatterns()
	patterns = {}
	-- Every "...x%d" variant before its single-item twin.
	for _, global in ipairs({
		"LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
		"LOOT_ITEM_BONUS_ROLL_SELF",
		"LOOT_ITEM_CREATED_SELF_MULTIPLE",
		"LOOT_ITEM_CREATED_SELF",
		"LOOT_ITEM_SELF_MULTIPLE",
		"LOOT_ITEM_SELF",
		"LOOT_ITEM_PUSHED_SELF_MULTIPLE",
		"LOOT_ITEM_PUSHED_SELF",
	}) do
		local pattern = ns.MakePattern(_G[global])
		if pattern then
			patterns[#patterns + 1] = "^" .. pattern
		end
	end
end

function Module:OnLoot(_, msg)
	if ns.IsSecret(msg) or type(msg) ~= "string" then
		return
	end
	if not string_find(msg, "|Hitem:", 1, true) then
		return
	end
	if not patterns then
		BuildPatterns()
	end
	for _, pattern in ipairs(patterns) do
		local a, b = string_match(msg, pattern)
		if a then
			local link, count
			if string_find(a, "|H", 1, true) then
				link, count = a, tonumber(b)
			elseif type(b) == "string" and string_find(b, "|H", 1, true) then
				link, count = b, tonumber(a)
			end
			if link then
				self:AddItem(link, count or 1)
			end
			return
		end
	end
end

-- Looted coins: the chat event says "this was loot", the money event says how
-- much. They arrive in either order, a moment apart.
local lastMoney, pendingGain, gainTime, lootTime

local function FlushMoney()
	if pendingGain and pendingGain > 0 and gainTime and lootTime and math.abs(gainTime - lootTime) < 1.5 then
		Module:AddMoney(pendingGain)
		pendingGain, gainTime, lootTime = nil, nil, nil
	end
end

function Module:OnMoneyMessage()
	lootTime = GetTime()
	FlushMoney()
end

function Module:OnMoneyChanged()
	local money = GetMoney and GetMoney()
	if type(money) ~= "number" or ns.IsSecret(money) then
		return
	end
	local now = GetTime()
	if lastMoney and money > lastMoney then
		if gainTime and now - gainTime > 1.5 then
			pendingGain = nil
		end
		pendingGain = (pendingGain or 0) + (money - lastMoney)
		gainTime = now
		FlushMoney()
	end
	lastMoney = money
end

---------------------------------------------------------------------------
-- Mover and test
---------------------------------------------------------------------------
function Module:ToggleLock()
	if not self:IsEnabled() then
		print("|cffDFBA69Limpid|r: Loot Popup - OFF (/limpid)")
		return
	end
	EnsureAnchor()
	anchor.unlocked = not anchor.unlocked
	anchor:EnableMouse(anchor.unlocked)
	anchor:SetMoverShown(anchor.unlocked)
	if anchor.unlocked then
		self:Test()
	end
end

-- Show a few sample lines made from what's in the bags.
function Module:Test()
	if not self:IsEnabled() then
		return
	end
	local links = ns.SampleItemLinks and ns.SampleItemLinks(5) or {}
	for index, link in ipairs(links) do
		if not FindRow("item:" .. (string_match(link, "|Hitem:(%d+)") or "")) then
			self:AddItem(link, (index % 3 == 2) and 3 or 1)
		end
	end
	self:AddMoney(1234)
end

-- Demo mode (/lpd): fill the list, mark one line as an upgrade and keep
-- everything on screen until the demo is turned off.
function Module:Demo(on)
	if not self:IsEnabled() then
		return
	end
	EnsureAnchor()
	if on then
		demo = true
		self:Test()
		for index = #rows, 1, -1 do
			local row = rows[index]
			if row.itemID then
				row.demoUpgrade = true
				row.upgrade = true
				Render(row)
				break
			end
		end
		pinned = true
	else
		demo = false
		pinned = false
		for index = #rows, 1, -1 do
			ReleaseRow(index)
		end
	end
end

function Module:Refresh()
	if not anchor then
		return
	end
	UpdateAnchorSize()
	ApplyPosition()
	for _, row in ipairs(rows) do
		if row.key == "money" then
			local _, size = FontSettings()
			row.text = MoneyText(row.amount, size + 2)
		end
		Render(row)
	end
	Layout()
end

function Module:OnEnable()
	lastMoney = GetMoney and GetMoney()
	if ns.IsSecret(lastMoney) or type(lastMoney) ~= "number" then
		lastMoney = nil
	end
	self:RegisterEvent("CHAT_MSG_LOOT", "OnLoot")
	self:RegisterEvent("CHAT_MSG_MONEY", "OnMoneyMessage")
	self:RegisterEvent("PLAYER_MONEY", "OnMoneyChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnMoneyChanged")
	self:RegisterEvent("GLOBAL_MOUSE_DOWN", "OnGlobalMouseDown")
end

function Module:OnDisable()
	self:UnregisterAllEvents()
	pinned = false
	demo = false
	for index = #rows, 1, -1 do
		ReleaseRow(index)
	end
	if anchor then
		anchor.unlocked = false
		anchor:EnableMouse(false)
		anchor:SetMoverShown(false)
		anchor:SetScript("OnUpdate", nil)
	end
end
