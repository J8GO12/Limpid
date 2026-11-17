local _, Constants = unpack(select(2, ...))

-- Constants
Constants.DOCK_HEIGHT = 20
Constants.TEXT_XPADDING = 15
-- Vertical gap (px) between the tab dock and the message area below it.
Constants.MESSAGE_DOCK_GAP = 5
-- Edit box vertical padding as a fraction of the font height (top and bottom).
Constants.EDITBOX_PADDING_RATIO = 0.66

-- Colors
local function createColor(r, g, b)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

Constants.COLORS = {
	black = createColor(0, 0, 0),
	codGray = createColor(17, 17, 17),
	apache = createColor(223, 186, 105),
}

-- Events
Constants.EVENTS = {
	EDIT_FOCUS_GAINED = "LimpidUI/EDIT_FOCUS_GAINED",
	EDIT_FOCUS_LOST = "LimpidUI/EDIT_FOCUS_LOST",
	HYPERLINK_CLICK = "LimpidUI/HYPERLINK_CLICK",
	HYPERLINK_ENTER = "LimpidUI/HYPERLINK_ENTER",
	HYPERLINK_LEAVE = "LimpidUI/HYPERLINK_LEAVE",
	LOCK_MOVER = "LimpidUI/LOCK_MOVER",
	MOUSE_ENTER = "LimpidUI/MOUSE_ENTER",
	MOUSE_LEAVE = "LimpidUI/MOUSE_LEAVE",
	SAVE_FRAME_POSITION = "LimpidUI/SAVE_FRAME_POSITION",
	UNLOCK_MOVER = "LimpidUI/UNLOCK_MOVER",
	UPDATE_CONFIG = "LimpidUI/UPDATE_CONFIG",
}

Constants.ACTIONS = {
	EditFocusGained = function()
		return Constants.EVENTS.EDIT_FOCUS_GAINED
	end,
	EditFocusLost = function()
		return Constants.EVENTS.EDIT_FOCUS_LOST
	end,
	HyperlinkClick = function(payload)
		return Constants.EVENTS.HYPERLINK_CLICK, payload
	end,
	HyperlinkEnter = function(payload)
		return Constants.EVENTS.HYPERLINK_ENTER, payload
	end,
	HyperlinkLeave = function(link)
		return Constants.EVENTS.HYPERLINK_LEAVE, link
	end,
	LockMover = function()
		return Constants.EVENTS.LOCK_MOVER
	end,
	MouseEnter = function()
		return Constants.EVENTS.MOUSE_ENTER
	end,
	MouseLeave = function()
		return Constants.EVENTS.MOUSE_LEAVE
	end,
	SaveFramePosition = function(payload)
		return Constants.EVENTS.SAVE_FRAME_POSITION, payload
	end,
	UnlockMover = function()
		return Constants.EVENTS.UNLOCK_MOVER
	end,
	UpdateConfig = function(key, windowId)
		return Constants.EVENTS.UPDATE_CONFIG, { key = key, windowId = windowId }
	end,
}
