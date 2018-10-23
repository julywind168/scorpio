local scorpio = require "scorpio.core"
local socket = require "scorpio.socket"

local tasks = {}

local M = {
	alive = true,
	delay = 200,
}

function M.hint( name, value )
	if not M[name] then
		error(string.format("scorpio don't has this property:%s", tostring(name)))
	else
		M[name] = value
	end
end


function M.fork(func)
	local co = coroutine.wrap(func)
	table.insert(tasks, co)
end


function M.exit()
	M.alive = false
end


local function client_socket( fd, addr )

	local self = {
		fd = fd,
		addr = addr,
		handler = {},

		connected = true,
	}

	function self:on(name, func)
		self.handler[name] = func
	end

	function self:send( str )
		if connected == false then
			print("failed to send this sock has closed")
		else
			socket.send(self.fd, str)
		end
	end

	setmetatable(self, {__call = function (_, name, ...)
		local f = self.handler[name]
		if f then
			f(...)
		end
	end})


	M.fork(function ( )
			
		socket.setnonblocking(fd)

		while true do
			if M.alive == false then
				coroutine.yield(1)
			end

			local str, err = socket.recv(fd)

			if str == "" then
				self.connected = false
				self("close")
				coroutine.yield(1)
			else
				if err then
					if err == "timeout" then
						coroutine.yield()
					else
						socket.close(fd)
						self("error", err)
						coroutine.yield(1)
					end
				else
					self("message", str)
				end
			end
		end
	end)

	return self
end


function M.server( host, port)

	local self = {
		host = host,
		port = port,
		handler = {},

		fd = nil,
	}

	function self:on(name, func)
		self.handler[name] = func
	end

	setmetatable(self, {__call = function (_, name, ...)
		local f = self.handler[name]
		if f then
			f(...)
		end
	end})


	M.fork(function ()
		local fd = assert(socket.listen(host, port))
		socket.setnonblocking(fd)

		self.fd = fd
		while true do

			if M.alive == false then
				coroutine.yield(1)
			end

			local id, addr, err = socket.accept(fd)

			if not err then
				self("connection", client_socket(id, addr))
			else
				if err == "timeout" then
					coroutine.yield()
				else
					socket.close(fd)
					self("error", err)
					coroutine.yield(1)
				end
			end
		end
	end)

	return self
end


function M.start(start_func)
	if start_func then
		start_func()
	end

	while true do
		scorpio.sleep(M.delay)

		local i = 1
		while true do

			if tasks[i] == nil then
				if tasks[1] == nil then
					goto _end
				end
				break
			end

			-- if co yield value means it's done
			local done = tasks[i]()
			if done then
				table.remove(tasks, i)
			else
				i = i + 1
			end			
		end
	end
::_end::
	print('bye')
end

return M