local scorpio = require "lualib.scorpio2"


local function printf(...)
	print(string.format(...))
end


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


scorpio.timer(1, function ( )
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




scorpio.start()