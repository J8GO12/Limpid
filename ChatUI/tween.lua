local Core = unpack(select(2, ...))

-- Tween
-- A tiny value animator: Tween:Ease(apply, from, to, duration, curve, done)
-- calls apply(value) every frame while the value travels from `from` to `to`
-- along `curve` (a function mapping progress 0..1 to 0..1), then calls
-- apply(to) once and done() if given. Returns a handle for Tween:StopEasing.
-- All running animations share one frame, which only ticks while needed.

local Tween = {}

local CreateFrame = CreateFrame
local GetTime = GetTime
local next = next

-- Curves: progress in [0, 1] -> eased progress in [0, 1].
function Tween.Linear(progress)
	return progress
end

-- Fast start, gentle stop.
function Tween.OutCubic(progress)
	local rest = 1 - progress
	return 1 - rest * rest * rest
end

-- Gentle start and stop.
function Tween.InOutQuad(progress)
	if progress < 0.5 then
		return 2 * progress * progress
	end
	local rest = 1 - progress
	return 1 - 2 * rest * rest
end

local running = {} -- [handle] = animation
local lastHandle = 0
local driver = CreateFrame("Frame")

local function Tick()
	local now = GetTime()
	-- Finished animations are collected first so a `done` callback may start
	-- or stop animations without disturbing the walk.
	local finished
	for handle, animation in next, running do
		local elapsed = now - animation.started
		if elapsed >= animation.duration then
			finished = finished or {}
			finished[#finished + 1] = handle
		else
			animation.apply(animation.from + animation.span * animation.curve(elapsed / animation.duration))
		end
	end
	if finished then
		for index = 1, #finished do
			local handle = finished[index]
			local animation = running[handle]
			if animation then
				running[handle] = nil
				animation.apply(animation.to)
				if animation.done then
					animation.done()
				end
			end
		end
	end
	if next(running) == nil then
		driver:SetScript("OnUpdate", nil)
	end
end

function Tween:Ease(apply, from, to, duration, curve, done)
	lastHandle = lastHandle + 1
	running[lastHandle] = {
		apply = apply,
		from = from,
		to = to,
		span = to - from,
		duration = duration or 0,
		curve = curve or Tween.InOutQuad,
		done = done,
		started = GetTime(),
	}
	driver:SetScript("OnUpdate", Tick)
	return lastHandle
end

function Tween:StopEasing(handle)
	if handle and running[handle] then
		running[handle] = nil
		return true
	end
	return false
end

Core.Libs.Tween = Tween
