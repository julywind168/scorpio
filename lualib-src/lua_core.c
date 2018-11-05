#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>
#include <pthread.h>

#include "main.h"
#include "seri.h"


#define VERSION "scorpio 0.0.1"


static void *
thread_main(void *_arg) {
	lua_State *L = (lua_State *)_arg;

	open_libs(L);

	int error = lua_pcall(L, 0, 0, 0);
	if (error) {
		fprintf(stderr, "%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}

	lua_close(L);
	printf("thread exit\n");
	return NULL;
}


static int
l_thread(lua_State *L) {
	const char *file = luaL_checkstring(L, 1);
	pthread_t thread;

	lua_State *L1 = luaL_newstate();

	if (luaL_loadfile(L1, file) != 0 ) {
		luaL_error(L, "failed to loadfile, %s", lua_tostring(L1, -1));	
	}

	if (pthread_create(&thread, NULL, thread_main, L1) != 0)
		luaL_error(L, "unable to create thread");

	pthread_detach(thread);
	return 0;
}


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

static int
l_main(lua_State *L) {
	lua_getfield(L, LUA_REGISTRYINDEX, "main");
	return 1;
}


int
lua_lib_core(lua_State *L) {
	static const struct luaL_Reg l[] = {
		{"version", l_version},
		{"main", l_main},
		{"pack", l_pack},
		{"unpack", l_unpack},
		{"time", l_time},
		{"sleep", l_sleep},
		{"thread", l_thread},
	    {NULL, NULL}
	};

    luaL_newlib(L, l);
    return 1;
}
