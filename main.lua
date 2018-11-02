local scorpio = require "lualib.scorpio"



local listener = scorpio.listen('127.0.0.1', 8888)

print("Listen on: 127.0.0.1:8888")

listener.on('connection', function (conn)
	print('new connection from', conn.addr)

	conn.on('message', function ( msg )
		print('recv:', msg:sub(1, #msg-1))
		conn.send(msg)

		if msg == 'bye\n' then
			scorpio.exit()
		end
	end)

end)


local t1 = scorpio.timer(1000, function ( count )
	print('timeout', count, os.time())
end, 5)



scorpio.start()



