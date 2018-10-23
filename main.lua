local scorpio = require "lualib.scorpio"
local timer = require "lualib.timer"
local socket = require "scorpio.socket"


local server = scorpio.server("127.0.0.1", 8888)


server:on("connection", function (sock)

	print("connect from " .. sock.addr .. " " .. sock.fd)

	sock:on("message", function ( str )
		print("recv:", str:sub(1, #str-1))
		sock:send(str)
		if str == "bye\n" then
			scorpio.exit()
		end
	end)

	sock:on("close", function ( )
		print("sock has been closed")
	end)

end)


scorpio.start(function ( )
	print("Listen on 127.0.0.1:8888")
	
	timer.create(3000, function (count)
		print("timer1 timeout", count)
	end, -1)

	timer.create(1000, function ()
		print("timer2: i only say once")
	end)
end)

