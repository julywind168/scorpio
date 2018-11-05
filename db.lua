local scorpio = require "lualib.scorpio"


local db = {
	['nick'] = 'windy'
}


scorpio.hint('name', 'db')

scorpio.hint('nodes', {
	{name = 'hall', ip = '127.0.0.1', port = 7000},
	{name = 'game', ip = '127.0.0.1', port = 8000},
	{name = 'db',   ip = '127.0.0.1', port = 9000},
})

scorpio.hint('response', {
	get = function (key)
		return db[key]
	end
})


scorpio.start(function ()
	print("node db start ...")
end)