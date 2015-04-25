require('ev.cdef')

local ffi = require('ffi')
local errno = require('ev.errno')

ffi.cdef[[
static const int EV_POLL_IN_MAX = 64;
static const int EV_POLL_OUT_MAX = 64;
struct EVPoller {
	int fd;
	int ev_in_pos;
	uintptr_t id;
	struct kevent ev_in[EV_POLL_IN_MAX];
	struct kevent ev_out[EV_POLL_OUT_MAX];
};
]]

local C = ffi.C

local mt = {}
mt.__index = mt

function mt:__gc()
	C.close(self.fd)
end

function mt:register(fd)
	if self.ev_in_pos == C.EV_POLL_IN_MAX then
		-- flush pending events if the list is full
		local rc = C.kevent(self.fd, self.ev_in, C.EV_POLL_IN_MAX, nil, 0, nil)
		if rc < 0 then errno.error("kevent") end
		self.ev_in_pos = 0
	end
	local ev = self.ev_in[self.ev_in_pos]
	ev.ident = fd
	ev.filter = C.EVFILT_READ
	ev.flags = bit.bor(C.EV_ADD, C.EV_CLEAR)
	ev.fflags = 0
	ev.data = 0
	ev.udata = self.id

	self.id = self.id + 1

	C.kevent(self.fd, self.ev_in, 1, self.ev_out, 0, nil)
	return tonumber(ev.udata)
end


function mt:poll()
	--local n = C.kevent(self.fd, self.ev_in, self.ev_in_pos, self.ev_out, C.EV_POLL_OUT_MAX, nil)
	local n = C.kevent(self.fd, self.ev_in, self.ev_in_pos, self.ev_out, 1, nil)
	if n < 0 then errno.error("kevent") end
	self.ev_in_pos = 0

	print("poll got:", n)
	return tonumber(self.ev_out[0].udata)
end


local Poller = ffi.metatype("struct EVPoller", mt)

return function()
	local fd = C.kqueue()
	if fd < 0 then errno.error("kqueue") end
	return Poller(fd)
end
