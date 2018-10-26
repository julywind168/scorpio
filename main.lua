local scorpio = require "lualib.scorpio"



local listener = scorpio.listen('127.0.0.1', 8888)

print("Listen on: 127.0.0.1:8888")

listener.on('connection', function (conn)
	print('new connection from', conn.addr)

	conn.on('message', function ( msg )
		print('recv:', msg:sub(1, #msg-1))
		conn.send(msg)
	end)

end)





scorpio.start()



