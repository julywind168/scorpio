CFLAGS = -g -O0 -Wall -Isrc -Ilualib-src -I/usr/local/include
LINK = -L/usr/local/lib -llua -lm -DLUA_USE_READLINE -ldl -lpthread


SCORPIO = \
	main.c \
	charbuffer.c \
	seri.c \

LUALIB = \
	lua_core.c \
	lua_serialize.c \
	lua_socket.c \
	lua_epoll.c \
	lua_timerfd.c \


.PHONY : scorpio	

scorpio :
	gcc $(CFLAGS) $(addprefix src/,$(SCORPIO)) $(addprefix lualib-src/,$(LUALIB)) -o scorpio $(LINK)







# lib:
# 	gcc -I /usr/local/include -o sco main.c -llua -lm -ldl