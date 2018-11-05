local core = require "scorpio.core"
local scorpio = require "lualib.scorpio"


local function printf(...)
	print(string.format(...))
end


local function test_socket()
	scorpio.fork(function ()
		local listener = scorpio.listen('127.0.0.1', 8888)
		printf('Listen on: 127.0.0.1:8888')
		while true do
			local conn, err = listener.accept()
			assert(conn, err)

			printf("new connection from: %s", conn.addr)
			scorpio.fork(function ()
				while true do
					local msg, err = conn.recv()
					printf('conn[%d] recv: %s',conn.fd, msg:sub(1, #msg-1))
					conn.send(msg)
					if msg == 'bye\n' then
						scorpio.exit()
					end
				end
			end)
		end
	end)
end


local function test_timer( )
	scorpio.timer(50, function ( )
		printf('timer1: i only say once')
	end)

	-- 如果在timer 的 callback 中有 yield 的调用, 请fork一个 task并立即执行
	scorpio.timer(100, function (count)
		scorpio.fork(function ()
			printf('timer2 timeout %d, now:%d ms', count, scorpio.time())
			scorpio.sleep(1000)
			printf('timer2 timeout %d, now:%d ms', count, scorpio.time())
		end, true)
	end, 3)
end


local function test_rpc( )
	local db = scorpio.server.db
	local game = scorpio.server.game

	local nick = db.req.get('nick')		-- see db.lua
	printf('get my nick:%s, i will join game', nick)
	game.post.join(nick)				-- see game.lua
end


-----------------------------
-- this node is hall node
scorpio.hint('name', 'hall')

--[[
	如果ip 全部 (全部, 全部) 都是 localhost, 则会在该进程内 为每个节点启动一个物理线程(方便开发)
	否则认为是集群部署, 需要手动启动其他节点以完成组网

	下面是各节点的配置
]]
scorpio.hint('nodes', {
	{name = 'hall', ip = '127.0.0.1', port = 7000},
	{name = 'game', ip = '127.0.0.1', port = 8000},
	{name = 'db',   ip = '127.0.0.1', port = 9000},
})

-- 组网-> start_func -> tasks
scorpio.start(function ( )
	core.sleep(1000)
	print('node hall statr...')
	scorpio.fork(function ()
		test_rpc()
		test_socket()
		test_timer()
		-- 节点之间 rpc
	end, true)
end)