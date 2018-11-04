local scorpio = require "scorpio.core"
local socket = require "scorpio.socket"
local epoll = require "scorpio.epoll"
local timerfd = require "scorpio.timerfd"


local M = {
	alive = true,
	tasks = {}
}

local epfd = assert(epoll.create())
local objects = {}	-- fd: obj
local tasks = {}	-- co: task

-- create object functions
local function create_timer(delay, callback, iteration)

	local fd = timerfd.create()
	timerfd.settime(fd, delay)

	local self = {
		name = 'timer',
		delay = delay,
		callback = callback,
		iteration = iteration or 1,
		count = 0,
		fd = fd,
	}

	function self.close()
		epoll.unregister(epfd, self.fd)
		timerfd.close(self.fd)
		objects[self.fd] = nil
	end

	objects[fd] = self
	epoll.register(epfd, fd, epoll.EPOLLIN | epoll.EPOLLET)

	return self
end

local function create_connection(fd, addr)
	local self = {
		name = 'connection',
		fd = fd,
		addr = addr
	}

	function self.recv()
		-- bind task on first call
		if self.task == nil then
			self.task = tasks[coroutine.running()]
		end

		return coroutine.yield('recv'..self.fd)
	end

	function self.close( )
		epoll.unregister(epfd, self.fd)
		socket.close(self.fd)
		objects[self.fd] = nil
	end

	function self.send(msg)
		return socket.send(self.fd, msg)
	end

	objects[fd] = self
	epoll.register(epfd, self.fd, epoll.EPOLLIN | epoll.EPOLLET)

	return self
end

local function create_listener(fd, host, port)
	local self = {
		name = 'listener',
		fd = fd,
		host = host,
		port = port,
	}

	function self.accept()
		-- check queue
		-- pass

		-- bind task on first call
		if self.task == nil then
			self.task = tasks[coroutine.running()]
		end

		return coroutine.yield('accept'..self.fd)
	end

	function self.close( )
		epoll.unregister(epfd, self.fd)
		socket.close(self.fd)
		objects[self.fd] = nil
	end

	objects[fd] = self
	epoll.register(epfd, fd, epoll.EPOLLIN | epoll.EPOLLET)

	return self
end


local function create_sleeper(time)

	local fd = timerfd.create()
	timerfd.settime(fd, time)

	local self = {
		name = 'sleeper',
		fd = fd,
		time = time,
		task = tasks[coroutine.running()]
	}

	function self.close()
		epoll.unregister(epfd, self.fd)
		timerfd.close(self.fd)
		objects[self.fd] = nil
	end

	objects[fd] = self
	epoll.register(epfd, fd, epoll.EPOLLIN | epoll.EPOLLET)

	return self
end

function M.sleep(time)
	create_sleeper(time)
	return coroutine.yield('wakeup')
end


function M.timer(...)
	return create_timer(...)
end


function M.listen(host, port)
	local fd, err = socket.listen(host, port)
	if err then return nil, err end

	return create_listener(fd, host, port)
end


function M.fork(func, run_now, ...)
	local co = coroutine.create(func)
	local task = {
			co = co,
			init = run_now and true or false,
			want = nil,
			queue = {}
		}

	local function do_task( task, ... )
		local ok, want = coroutine.resume(task.co, ...)
		assert(ok, want)

		if coroutine.status(task.co) == 'dead' then
			-- remove task
			for i,_task in ipairs(M.tasks) do
				if _task == task then
					table.remove(M.tasks, i)
					break
				end
			end
			tasks[task.co] = nil
		else
			task.want = want
			-- check queue
			while true do
				local event = task.queue[1]
				if not event then break end
				if event.name == task.want then
					table.remove(task.queue, 1)
					do_task(task, table.unpack(event.data))
				else
					break
				end
			end
		end
	end

	setmetatable(task, {__call = function (_, name, ...)
		if name == task.want then
			do_task(task, ...)
		else
			local data = {...}
			table.insert(task.queue, {
					name = name,
					data = data
				})
		end
	end})


	table.insert(M.tasks, task)
	tasks[co] = task

	if run_now then
		do_task(task, ...)
	end
end


function M.exit()
	M.alive = false
end


function M.start()

	local function init_task( )
		local index = 1
		while true do
			local task = M.tasks[index]
			
			if not task then
				break
			end

			if task.init == true then
				index = index + 1
			else
				local _, want = coroutine.resume(task.co)
				if coroutine.status(task.co) == 'dead' then
					table.remove(M.tasks, index)
					tasks[task.co] = nil
				else
					task.want = want
					task.init = true
					index = index + 1
				end 				
			end
		end
	end

	init_task()

	-- poll event
	while true do
		local events = epoll.wait(epfd, -1, 512)
		for fd, event in pairs(events) do

			local obj = objects[fd]
			if obj.name == 'listener' then
				local fd, addr, err = socket.accept(obj.fd)
				if err then
					obj.task('accept'.. obj.fd, nil, err)
				else
					obj.task('accept'.. obj.fd, create_connection(fd, addr))
				end
			elseif obj.name == 'connection' then
				local msg, err = socket.recv(obj.fd)
				obj.task('recv'..obj.fd, msg, err)
			elseif obj.name == 'timer' then
				timerfd.read(obj.fd)
				obj.count = obj.count + 1
				obj.callback(obj.count)
				if obj.iteration > 0 and obj.iteration == obj.count then
					obj.close()
				end
			elseif obj.name == 'sleeper' then
				timerfd.read(obj.fd)
				obj.close()
				obj.task('wakeup')
			end
		end

		-- if should exit?
		if M.alive == false then
			break
		end

		-- has new task need init?
		init_task()
	end

	print('bye')
end


return setmetatable(M, {__index = scorpio})