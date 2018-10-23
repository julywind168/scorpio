local scorpio = require "lualib.scorpio"
local timer = require "lualib.timer"
local socket = require "scorpio.socket"


local server = scorpio.server("127.0.0.1", 8888)

server:on("connection", function (sock)

	print("connect from " .. sock.addr .. " " .. sock.fd)

	sock:on("message", function ( str )
		print("recv:", sock.fd, str:sub(1, #str-1))
		if str == "bye\n" then
			scorpio.exit()
		else
			sock:send(str)
		end
	end)

	sock:on("close", function ( )
		print("sock has been closed")
	end)

end)


-- 设置主循环的间隔时间 
scorpio.hint("delay", 100)

--[[
-- will to do
scorpio.hint("me", "game1")
scorpio.hint("cluster", {
		{ name = 'hall1', 	ip = '127.7.0.1', port = 8000 },
		{ name = 'hall2', 	ip = '127.7.0.1', port = 8000 },
		{ name = 'game1',   ip = '127.7.0.1', port = 8001 },
		{ name = 'game2',   ip = '127.7.0.1', port = 8001 },
		{ name = 'mongo',  	ip = '127.7.0.1', port = 8002 },
	})
--]]

scorpio.start(function ( )
	print("scorpio start ...")
	
	timer.create(3000, function (count)
		print("timer1 timeout", count)
	end, -1)

	timer.create(1000, function ()
		print("timer2: i will been do only once")
	end)
end)

