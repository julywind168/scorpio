local scorpio = require "scorpio.core"
local socket = require "scorpio.socket"

local tasks = {}
local waiting = {}

local M = {
	delay = 100,
	alive = true,
	socket = setmetatable({}, {__index = socket})
}

function M.hint( name, value )
	local property = {
		delay = 1,
	}
	assert(property[name] and type(property[name]) == type(value),
		'invalid property name or value type')
	
	M[name] = value
end

function M.exit()
	M.alive = false
end

function M.fork(f, ...)
	local co = coroutine.wrap(f)
	local args = {...}
	local task = function ( )
		return co, co(table.unpack(args))
	end
	table.insert(tasks, task)
end

function M.socket.listen(...)
	return socket.setnonblocking(assert(socket.listen(...)))
end

function M.socket.accept(listen_fd)
	local fd, addr, err = socket.accept(listen_fd)
	if err == 'timeout' then
		return coroutine.yield('accept', listen_fd)
	else
		return fd and socket.setnonblocking(fd), addr, err
	end
end

function M.socket.recv(fd)
	local msg, err = socket.recv(fd)
	if err == 'timeout' then
		return coroutine.yield('recv', fd)
	else
		return msg, err
	end
end





function M.start()

	local wait = {}

	function wait:accept(fd)
		table.insert(waiting, function (exit)
			if exit then
				return function ( )
					socket.close(fd)
				end
			end

			local fd, addr, err = socket.accept(fd)
			if fd or err ~= 'timeout' then
				table.insert(tasks, function ( )
					return self, self(fd and socket.setnonblocking(fd), addr, err)
				end)
				return true
			end
		end)
	end

	function wait:recv(fd)
		table.insert(waiting, function (exit)

			if exit then
				return function ( )
					socket.close(fd)
				end
			end

			local msg, err = socket.recv(fd)
			if msg or err ~= 'timeout' then
				table.insert(tasks, function ()
					return self, self(msg, err)
				end)
				return true
			end
		end)
	end


	local function after(co, name, ...)
		if name then
			assert(wait[name])(co, ...)
		else
			print("task done")
		end
	end

	while true do
		scorpio.sleep(M.delay)
		
		if #tasks == 0 and #waiting == 0 then
			break
		end

		while true do
			if #tasks == 0 then break end
			local task = table.remove(tasks, 1)
			after(task())
		end

		if M.alive == false then
			for _,exit in ipairs(waiting) do
				exit(true)()
			end
			break
		end

		local i = 1
		while true do
			if waiting[i] == nil then break end
			local over = waiting[i]()
			if over == true then
				table.remove(waiting, i)
			else
				i = i + 1
			end
		end
	end

	print('bye')
end


return M