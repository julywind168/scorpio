local scorpio = require "scorpio.core"
local socket = require "scorpio.socket"
local epoll = require "scorpio.epoll"
local timerfd = require "scorpio.timerfd"



local function create_manager()
	
	local epfd = assert(epoll.create())
	local readers = {}

	local self = {}

	function self.add(reader, read_func)

		epoll.register(epfd, reader.fd, epoll.EPOLLIN | epoll.EPOLLET)
		readers[reader.fd] = reader

		local handler = {
			read = read_func
		}

		function reader.emit(name, ...)
			return handler[name] and handler[name](...)
		end

		function reader.on( name, func )
			handler[name] = func
		end

		return reader
	end

	function self.remove(reader)
		print(epfd, reader.fd)
		print(epoll.unregister(epfd, reader.fd))
		readers[reader.fd] = nil
	end

	function self.poll( )
		local events = epoll.wait(epfd, -1, 512)
		for fd, event in pairs(events) do
			local reader = readers[fd]
			reader.emit('read', event)
		end
	end

	function self.destory()
		epoll.close(epfd)
	end

	return self
end


local M = {}

local alive = true
local manager = create_manager()


local function create_conntection(fd, addr)
	local self = {
		fd = fd,
		addr = addr
	}

	function self.close()
		manager.remove(self)
		socket.close(self.fd)
	end

	function self.send(msg)
		return socket.send(self.fd, msg)
	end

	manager.add(self, function ( )
		local msg, err = socket.recv(self.fd)
		
		if err then
			self.emit('error', err)
			self.close()
		else
			if msg == '' then
				self.emit('close')
				self.close()
			else
				self.emit('message', msg)
			end
		end
	end)

	return self
end


local function create_listener(host, port, fd)
	local self = {
		host = host,
		port = port,
		fd = fd,
	}

	function self.close( )
		manager.remove(self)
		socket.close(self.fd)
	end

	manager.add(self, function ()
		local fd, addr, err = socket.accept(self.fd)
		if err then
			self.emit('error', err)
			self.close()
		else
			local conn = create_conntection(fd, addr)
			self.emit('connection', conn)
		end
	end)

	return self
end


local function create_timer(delay, callback, iteration)

	local fd = timerfd.create()
	timerfd.settime(fd, delay)

	local self = {
		delay = delay,
		callback = callback,
		iteration = iteration or 1,
		count = 0,
		fd = fd,
	}

	function self.close()
		manager.remove(self)
		timerfd.close(self.fd)
	end

	manager.add(self, function ( )
		timerfd.read(self.fd)
		self.count = self.count + 1
		self.callback(self.count)
		if self.iteration > 0 and self.iteration == self.count then
			self.close()
		end
	end)

	return self
end


function M.listen(host, port)
	local fd = assert(socket.listen(host, port))
	return create_listener(host, port, fd)
end

function M.timer(...)
	return create_timer(...)
end

function M.exit( )
	alive = false
end

function M.start( func )
	if func then func() end

	while alive do
		manager.poll()
	end

	manager.destory()
	print('bye')
end


return setmetatable(M, {__index = scorpio})