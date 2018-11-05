# Build & Test
```
	1. only for linux 
	2. 从源码安装lua5.3	
	3. git clone https://github.com/HYbutterfly/scorpio.git
	4. cd scorpio
	5. make
	6. ./scorpio main.lua
	7. 在另一个命令窗口 用 nc 127.0.0.1 8888 连接服务器 并输入一些内容 (发送 bye 服务器将关闭)
```


# 框架
```
	1. scorpio 是一个单线程服务端框架

	2. scorpio 将会支持分布式

	3. scorpio 节点之间通信(RPC) 使用 socket(tcp? upd?) 
```