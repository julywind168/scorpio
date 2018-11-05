local scorpio = require "lualib.scorpio"


local function printf(...)
	print(string.format(...))
end


scorpio.hint('name', 'game')

scorpio.hint('nodes', {
	{name = 'hall', ip = '127.0.0.1', port = 7000},
	{name = 'game', ip = '127.0.0.1', port = 8000},
	{name = 'db',   ip = '127.0.0.1', port = 9000},
})

scorpio.hint('accept', {
	join = function (nick)
		printf('new player[%s] join', nick)
	end
})


scorpio.start(function ()
	print("node game start ...")
end)