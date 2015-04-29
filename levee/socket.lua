require("levee.cdef")

local ffi = require("ffi")
local FD = require("levee.fd")

ffi.cdef[[
struct LeveeSocket {
	struct LeveeFD base;
	union {
		socklen_t socklen[1];
		int intval[1];
	} tmp;
	bool listening;
};
]]

local C = ffi.C

local Socket = {}
Socket.__index = Socket


local sockaddr_in = ffi.typeof("struct sockaddr_in")
local sockaddr_storage ffi.typeof("struct sockaddr_storage")


function Socket:new(no, listening)
	local sock = self.allocate()
	sock.base.no = no
	sock.listening = listening
	sock.base:nonblock(true)
	return sock
end


function Socket:connect(port, host)
	local no = C.socket(C.PF_INET, C.SOCK_STREAM, 0)
	if no < 0 then return nil, ffi.errno() end

	local addr = sockaddr_in()
	addr.sin_family = C.AF_INET
	addr.sin_port = C.htons(port);
	C.inet_aton(host or "0.0.0.0", addr.sin_addr)

	local rc = C.connect(no, ffi.cast("struct sockaddr *", addr), ffi.sizeof(addr))
	if rc < 0 then return nil, ffi.errno() end

	return self:new(no, false), 0
end


function Socket:listen(port, host, backlog)
	local no = C.socket(C.PF_INET, C.SOCK_STREAM, 0)
	if no < 0 then return nil, ffi.errno() end

	local on = ffi.new("int32_t[1]", 1)
	local rc = C.setsockopt(no, C.SOL_SOCKET, C.SO_REUSEADDR, on, ffi.sizeof(on))
	if rc < 0 then return nil, ffi.errno() end

	local addr = sockaddr_in()
	addr.sin_family = C.AF_INET
	addr.sin_port = C.htons(port);
	C.inet_aton(host or "0.0.0.0", addr.sin_addr)
	rc = C.bind(no, ffi.cast("struct sockaddr *", addr), ffi.sizeof(addr))
	if rc < 0 then return nil, ffi.errno() end

	rc = C.listen(no, backlog or 256)
	if rc < 0 then return nil, ffi.errno() end

	return self:new(no, true), 0
end


local function addr_name(addr)
	if addr.ss_family == C.AF_INET then
		local cast = ffi.cast("struct sockaddr_in *", addr)
		local buf = ffi.new("char [16]")
		local str = C.inet_ntop(C.AF_INET, cast.sin_addr, buf, 16)
		if str then
			return string.format("%s:%d", ffi.string(buf), tonumber(C.ntohs(cast.sin_port)))
		end
	elseif addr.ss_family == C.AF_INET6 then
		local cast = ffi.cast("struct sockaddr_in6 *", addr)
		local buf = ffi.new("char [48]")
		local str = C.inet_ntop(C.AF_INET6, cast.sin6_addr, buf, 48)
		if str then
			return string.format("[%s]:%d", ffi.string(buf), tonumber(C.ntohs(cast.sin6_port)))
		end
	elseif addr.ss_family == C.AF_LOCAL then
		local cast = ffi.cast("struct sockaddr_un *", addr)
		return ffi.string(cast.sun_path)
	end
end

function Socket:__tostring()
	local addr = ffi.new("struct sockaddr_storage")
	local len = ffi.new("socklen_t[1]")
	local sock = nil
	local peer = nil

	len[0] = ffi.sizeof(addr)
	if C.getsockname(self.base.no, ffi.cast("struct sockaddr *", addr), len) then
		sock = addr_name(addr)
	end

	if self.listening then
		return string.format("levee.Socket: %d, %s", self.base.no, sock or "")
	else
		len[0] = ffi.sizeof(addr)
		if C.getpeername(self.base.no, ffi.cast("struct sockaddr *", addr), len) then
			peer = addr_name(addr)
		end
		return string.format("levee.Socket: %d, %s->%s", self.base.no, sock or "", peer or "")
	end

end


function Socket:__gc()
	self.base:__gc()
end


function Socket:accept()
	local addr = sockaddr_in()
	local no = C.accept(self.base.no, ffi.cast("struct sockaddr *", addr), self.tmp.socklen)
	if no < 0 then
		return nil, ffi.errno()
	end
	return Socket:new(no, false)
end


function Socket:available()
	if self.listening then
		-- TODO figure out accept count?
		return 0ULL
	else
		C.ioctl(self.base.no, C.FIONREAD, ffi.cast("int *", self.tmp.intval))
		return self.tmp.intval[0]
	end
end


function Socket:read(buf, len)
	return self.base:read(buf, len)
end


function Socket:write(buf, len)
	return self.base:write(buf, len)
end


Socket.allocate = ffi.metatype("struct LeveeSocket", Socket)

return Socket