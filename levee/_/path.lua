local ffi = require('ffi')
local C = ffi.C


local buffer = require("levee.buffer")


-- TODO: move
function dirname(s)
	if s:match(".-/.-") then
		return string.gsub(s, "(.*/)(.*)", "%1"):gsub("/$", "")
	end
	return ''
end

function basename(s)
	local name = string.gsub(s, "(.*/)(.*)", "%2")
	return name
end
----


return {
	proc = function()
		local buf = buffer(4096)
		local n, err = C.sp_path_proc(buf:tail())
		if n < 0 then return n, ffi.errno() end
		buf:bump(n)
		return buf:take_s()
	end,
}