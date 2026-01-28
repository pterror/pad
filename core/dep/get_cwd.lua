local ffi = require("ffi")

local mod = {}

--[[posix max size is 4096; windows max size is 256/260/32767]]
local MAX_PATH_LENGTH = 4096

ffi.cdef [[
	char *getcwd(char *buf, size_t size);
]]

--[[@class getcwd_ffi]]
--[[@field getcwd fun(buf: ffi.cdata*, size: integer)]]

--[[@type getcwd_ffi]]
--[[@diagnostic disable-next-line: assign-type-mismatch]]
local getcwd_ns = ffi.C

local filename_buf = ffi.new("char[?]", MAX_PATH_LENGTH)

function mod.get_cwd()
	getcwd_ns.getcwd(filename_buf, MAX_PATH_LENGTH)
	--[[TODO: handle errors]]
	return ffi.string(filename_buf)
end

return mod
