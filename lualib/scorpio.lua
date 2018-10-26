local scorpio = require "scorpio.core"
local socket = require "scorpio.socket"
local epoll = require "scorpio.epoll"


local epfd = assert(epoll.create())

local M = {}

local readers = {}


local function Connection(fd, addr)
	local self = {
		fd = fd,
		addr = addr
	}

	local handler = {}

	function self.emit(name, ...)
		return handler[name] and handler[name](...)
	end

	function self.on( name, func )
		handler[name] = func
	end

	function self.close()
		socket.close(self.fd)
	end

	function self.send(msg)
		return socket.send(self.fd, msg)
	end

	self.on('epoll', function ( )
		local msg, err = socket.recv(self.fd)
		
		if err then
			return handler.error and handler.error(err)
		else
			if msg == '' then
				return handler.close and handler.close()
			else
				return handler.message and handler.message(msg)		
			end
		end
	end)

	epoll.register(epfd, self.fd, epoll.EPOLLIN | epoll.EPOLLET)
	readers[fd] = self

	return self
end


local function Listener(host, port, fd)
	local self = {
		host = host,
		port = port,
		fd = fd,
	}

	local handler = {}

	function self.emit(name, ...)
		return handler[name] and handler[name](...)
	end

	function self.on(name, func)
		handler[name] = func
	end

	function self.close( )
		socket.close(self.fd)
	end

	self.on('epoll', function ()
		local fd, addr, err = socket.accept(self.fd)
		if err then
			return handler.error and handler.error(err)
		else
			local conn = Connection(fd, addr)
			return handler.connection and handler.connection(conn)
		end
	end)

	epoll.register(epfd, fd, epoll.EPOLLIN | epoll.EPOLLET)
	readers[fd] = self

	return self
end


function M.listen(host, port)
	local fd = assert(socket.listen(host, port))
	return Listener(host, port, fd)
end


function M.start( func )
	if func then func() end

	while true do
		local events = epoll.wait(epfd, -1, 512)
		for fd, event in pairs(events) do
			local reader = readers[fd]
			reader.emit('epoll', event)
		end
	end
end


return M