local scorpio = require "lualib.scorpio"
local timer = require "lualib.timer"
local socket = scorpio.socket

local function printf( ... )
	print(string.format(...))
end


scorpio.fork(function ( )
	local fd = socket.listen("127.0.0.1", 8888)
	printf("Listen on: %s", "127.0.0.1:8888")
	while true do
		local id, addr = socket.accept(fd)

		printf("new connection from: %s", addr)

		scorpio.fork(function ( )
			while true do
				local msg = socket.recv(id)
				if msg == '' then
					print('socket close')
				else
					printf('client[id:%d] say:%s', id, msg:sub(1, #msg-1))
					socket.send(id, msg)
					if msg == 'bye\n' then
						scorpio.exit()
					end
				end
			end
		end)
	end
end)


scorpio.start()