local scorpio = require "scorpio.core"
local socket = require "scorpio.socket"
local epoll = require "scorpio.epoll"
local timerfd = require "scorpio.timerfd"

local SERVER_CALL = 1
local SERVER_SEND = 2
local SERVER_RETURN = 3

local M = {
	alive = true,
	tasks = {},
	server = {},
}

local epfd = assert(epoll.create())
local objects = {}	-- fd: obj
local tasks = {}	-- co: task
local nodes = {}

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


local function create_caller(fd, msg_id)
	local self = {
		name = 'caller',
		task = tasks[coroutine.running()]
	}

	local server = objects[fd]


	return self
end


local function create_server(node)
	local self = {
		name = 'server',
		fd = node.fd,
		ip = node.ip,
		port = node.port,
		caller = {},	-- msg_id: task
	}

	function self.close()
		epoll.unregister(epfd, self.fd)
		socket.close(self.fd)
		objects[self.fd] = nil
	end

	local function message(type, msg_id, name, ...)
		if type == SERVER_CALL then
			local f = assert(M.response[name], tostring(name))
			socket.send(self.fd, scorpio.pack(SERVER_RETURN, msg_id, f(...)))
		elseif type == SERVER_SEND then
			local f = M.accept[name]
			f(...)
		elseif type == SERVER_RETURN then
			local task = self.caller[tostring(msg_id)]
			task('return', name, ...)
		end
	end

	function self.handler_message(msg)
		message(scorpio.unpack(msg))
	end

	objects[self.fd] = self
	epoll.register(epfd, self.fd, epoll.EPOLLIN | epoll.EPOLLET)

	return self
end

local msg_id = 0
local function create_proxy(node)

	local function call_mt(_, name)
		return function (...)
			local server = objects[node.fd]
			msg_id = msg_id + 1
			server.caller[tostring(msg_id)] = tasks[coroutine.running()]

			socket.send(node.fd, scorpio.pack(SERVER_CALL, msg_id, name, ...))
			return coroutine.yield('return')
		end
	end

	local function send_mt(_, name)
		return function (...)
			msg_id = msg_id + 1
			socket.send(node.fd, scorpio.pack(SERVER_SEND, msg_id, name, ...))
		end
	end

	local self = {
		name = node.name,
		req = setmetatable({}, {__index = call_mt}),
		post = setmetatable({}, {__index = send_mt}),
	}

	return self
end


function M.hint(name, value)
	local property = {
		alive = 'boolean',
		name = 'string',
		nodes = 'table',
		accept = 'table',
		response = 'table',
	}
	assert(property[name] == type(value), 'no this property or invlaid value type')
	M[name] = value
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

local msg_id = 0


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


function M.start(func)

	--[[
		如果所有节点的ip 都是 127.0.0.1 则启用本地多线程模式 (方便开发)
	]]

	--[[
		思路: 每个节点单线相连

		启动时，尝试连接其他节点	
			全部成功:
				启动服务器
			有失败:
				开启监听
					有人连接->握手->连接成功->(全部成功)?->启动服务器

	]]
	local function init_nodes()
		local function find(name)
			for _,conf in ipairs(M.nodes) do					
				if conf.name == name then
					return conf
				end
			end
			error("can't find node " .. tostring(name) .. " conf")
		end

		local version = scorpio.version()
		local node_num = #M.nodes
		local conn_ok = 0

		for _,node in ipairs(M.nodes) do
			if node.name ~= M.name then
				local fd, err = socket.connect(node.ip, node.port)
				if fd then
					socket.send(fd, version .. ' ' .. M.name)
					local msg, err = socket.recv(fd)
					if msg == 'ok' then
						conn_ok = conn_ok + 1
						node.fd = fd
						-- print(string.format('scorpio[%s]: connect to node[%s]', M.name, node.name))
					end
				end
			end
		end

		if conn_ok ~= node_num - 1 then
			local me = find(M.name)	
			local lis_fd = assert(socket.listen(me.ip, me.port))
			while true do
				local fd, addr, err = socket.accept(lis_fd)
				local msg, err = socket.recv(fd)
				if msg:sub(1, #version) == version then
					local name = msg:sub(#version+2, #msg)
					local node = find(name)
					if node then
						node.fd = fd
						conn_ok = conn_ok + 1
						socket.send(fd, 'ok')
						-- print(string.format('scorpio[%s]: connect to node[%s]', M.name, node.name))
						if conn_ok == node_num - 1 then
							socket.close(lis_fd)
							break
						end
					end
				end
			end
		end

		for _,node in ipairs(M.nodes) do
			if node.name ~= M.name then
				create_server(node)
				local proxy = create_proxy(node)
				M.server[proxy.name] = proxy
			end
		end
	end

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

	local function local_mode_and_is_main()
		for _,node in ipairs(M.nodes) do
			if node.ip ~= '127.0.0.1' then
				return false
			end
		end

		return scorpio.main()
	end

	if M.nodes then
		assert(M.name)
		
		for _,node in ipairs(M.nodes) do
			nodes[node.name] = node
		end

		if local_mode_and_is_main() then
			for _,node in ipairs(M.nodes) do
				if node.name ~= M.name then
					scorpio.thread(node.main or node.name..'.lua')
					scorpio.sleep(100)
				end
			end
		end
		init_nodes()
	end

	if func then
		func()
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
			elseif obj.name == 'server' then
				local msg, err = socket.recv(obj.fd)
				if msg then
					obj.handler_message(msg)
				else
					error(err)
				end
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