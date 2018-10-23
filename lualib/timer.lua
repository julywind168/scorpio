local core = require "scorpio.core"
local scorpio = require "lualib.scorpio"


local function id_producer()
	local pool = {}
	local id = 0

	local self = {}

	function self:id( )
		local _id = next(pool)
		if _id then
			pool[_id] = nil
			return _id
		else
			id = id + 1
			return tostring(id)
		end
	end

	function self:recover( id )
		pool[id] = true
	end

	return self
end


local M = {}

local timers = {}
local id_prod = id_producer()


function M.create(delay, callback, iteration)
	
	local id = id_prod:id()
	local count = 0
	local time = 0
	iteration = iteration or 1

	local update = function ( dt )
		time = time + dt
		if time >= delay then
			time = time - delay
			count = count + 1
			callback(count)
			if iteration > 0 and count == iteration then
				M.cancel(id)
			end
		end
	end

	timers[id] = update

	return id
end


function M.cancel(id)
	timers[id] = nil
	id_prod:recover(id)
end

function M.cancel_all()
	for id,_ in pairs(timers) do
		M.cancel(id)
	end
end


do
	local last, now, dt

	scorpio.fork(function ( )
		while true do

			if scorpio.alive == false then
				coroutine.yield(1)
			end

			if last == nil then
				last = core.time()
				coroutine.yield()
			end

			now = core.time()
			dt = now - last
			last = now

			for _,update in pairs(timers) do
				update(dt)
			end
			coroutine.yield()
		end
	end)
end

return M