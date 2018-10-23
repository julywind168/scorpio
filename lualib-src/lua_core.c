#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>

#include "seri.h"

#define VERSION "scorpio 0.0.1"




static int
l_pack(lua_State *L) {

	CharBuffer *buffer = seri_pack(L, 1, lua_gettop(L));

	lua_pushlstring(L, buffer->data, buffer->index);

	charbuffer_free(buffer);
	
	return 1;
}


static int
l_unpack(lua_State *L) {
	size_t sz;
	const char *buffer = lua_tolstring(L, 1, &sz);
	int n = seri_unpack(L, (void *)buffer, (int)sz);
	return n;
}


static int
l_sleep(lua_State *L) {
	int ti = luaL_checkinteger(L, 1);
	usleep(ti*1000);
	return 0;
}


static int
l_time(lua_State *L)
{   
    struct timeval start;
    gettimeofday( &start, NULL );
    lua_pushinteger(L, 1000*start.tv_sec + start.tv_usec/1000);
    return 1;  /* number of results */
}


static int
l_version(lua_State *L) {
	lua_pushstring(L, VERSION);
	return 1;
}


int
lua_lib_core(lua_State *L) {
	static const struct luaL_Reg l[] = {
		{"version", l_version},
		{"pack", l_pack},
		{"unpack", l_unpack},
		{"time", l_time},
		{"sleep", l_sleep},
	    {NULL, NULL}
	};

    luaL_newlib(L, l);
    return 1;
}
