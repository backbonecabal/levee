local json = require("levee.json")


--
-- utilities

local function b64dec(data)
	local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	local data = string.gsub(data, '[^'..b..'=]', '')
	return (
		data:gsub('.', function(x)
			if (x == '=') then return '' end
			local r,f='',(b:find(x)-1)
			for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
			return r;
		end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
			if (#x ~= 8) then return '' end
			local c=0
			for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
			return string.char(c)
		end))
end


--
-- Consul API

local Consul_mt = {}
Consul_mt.__index = Consul_mt


function Consul_mt:election(prefix, session_id, n)
	n = n or 1
	local ok = self.kv:put(prefix..session_id, session_id, {acquire=session_id})
	assert(ok)

	local is_elected = false

	local p = self.hub:pipe()
	self.hub:spawn(function()
		local index, data
		while true do
			index, data = self.kv:get(prefix, {index=index, recurse=true})

			local order = {}
			local map = {}

			local seen = false

			for _, v in ipairs(data) do
				if v.Value == session_id then
					seen = true
				end
				table.insert(order, v.CreateIndex)
				map[v.CreateIndex] = v.Value
			end

			if not seen then
				-- our entry has dropped out of consul
				p:close()
				return
			end

			table.sort(order)
			local elected = false
			for i = 1, n do
				if map[order[i]] == session_id then
					elected = true
					break
				end
			end

			-- it shouldn't be possible to drop from election, once elected
			assert(not (is_elected and not elected))

			if elected and not is_elected then
				is_elected = true
				p:send(true)
			end
		end
	end)
	return p
end


function Consul_mt:request(method, path, options, callback)
	local conn = self.hub.http:connect(self.port)
	if not conn then return end
	local res = conn:request(
		method, "/v1/"..path, options.params, options.headers, options.data):recv()
	res = {callback(res)}
	conn:close()
	return unpack(res)
end


--
-- KV namespace

local KV_mt = {}
KV_mt.__index = KV_mt


function KV_mt:get(key, options)
	-- options:
	-- 	index
	-- 	wait
	-- 	recurse
	-- 	keys
	-- 	separator
	-- 	TODO:
	-- 	token
	-- 	consistency

	options = options or {}
	local params = {}

	params.index = options.index
	params.wait = options.wait
	params.recurse = options.recurse and "1"
	params.keys = options.keys and "1"
	params.separator = options.separator

	return self.agent:request("GET", "kv/"..key, {params=params},
		function(res)
			if res.code ~= 200 then
				res:discard()
				return res.headers["X-Consul-Index"], options.recurse and {} or nil
			end

			local data = res:json()

			if not options.keys then
				for _, item in ipairs(data) do
					if item.Value then item.Value = b64dec(item.Value) end
				end
				if not options.recurse then
					data = data[1]
				end
			end
			return res.headers["X-Consul-Index"], data
	end)
end


function KV_mt:put(key, value, options)
	-- options:
	-- 	acquire
	-- 	release
	-- 	cas
	-- 	TODO:
	-- 	flags
	-- 	token

	options = options or {}
	local params = {}

	params.acquire = options.acquire
	params.release = options.release
	params.cas = options.cas

	return self.agent:request("PUT", "kv/"..key, {params=params, data=value},
		function(res)
			return res:tostring() == "true"
		end)
end


function KV_mt:delete(key, options)
	-- options:
	-- 	recurse
	-- 	TODO:
	-- 	cas
	-- 	token

	options = options or {}
	local params = {}
	params.recurse = options.recurse and "1"

	return self.agent:request("DELETE", "kv/"..key, {params=params},
		function(res)
			res:discard()
			return res.code == 200
		end)
end


local Session_mt = {}
Session_mt.__index = Session_mt


-- convenience to establish an ephemeral session and keep alive
function Session_mt:init()
	local session_id = self:create({behavior="delete", ttl=10})

	-- keep session alive
	self.agent.hub:spawn(function()
		while true do
			self.agent.hub:sleep(5000)
			self:renew(session_id)
		end
	end)

	return session_id
end


function Session_mt:create(options)
	-- options:
	-- 	name
	-- 	node
	-- 	lock_delay
	-- 	behavior
	-- 	ttl

	options = options or {}
	local data = {}

	data.name = options.name
	data.node = options.node

	-- TODO: checks

	if options.lock_delay then
		data.lockdelay = tostring(options.lock_delay).."s"
	end

	data.behavior = options.behavior

	if options.ttl then
		assert(options.ttl >= 10 and options.ttl <= 3600)
		data.ttl = tostring(options.ttl).."s"
	end

	return self.agent:request("PUT", "session/create", {data=json.encode(data)},
		function(res)
			assert(res.code == 200)
			return res:json()["ID"]
		end)
end


function Session_mt:list()
	return self.agent:request("GET", "session/list", {},
		function(res)
			assert(res.code == 200)
			return res.headers["X-Consul-Index"], res:json()
		end)
end


function Session_mt:destroy(session_id)
	return self.agent:request("PUT", "session/destroy/"..session_id, {},
		function(res)
			res:discard()
			return res.code == 200
		end)
end


function Session_mt:info(session_id)
	return self.agent:request("GET", "session/info/"..session_id, {},
		function(res)
			assert(res.code == 200)
			local session = res:json()
			if session then session = session[1] end
			return res.headers["X-Consul-Index"], session
		end)
end


function Session_mt:renew(session_id)
	return self.agent:request("PUT", "session/renew/"..session_id, {},
		function(res)
			if res.code == 404 then
				res:discard()
				return false
			end
			assert(res.code == 200)
			return res:json()[1]
		end)
end


local Agent_mt = {}
Agent_mt.__index = Agent_mt


function Agent_mt:self()
	return self.agent:request("GET", "agent/self", {},
		function(res)
			assert(res.code == 200)
			return res:json()
		end)
end


function Agent_mt:services()
	return self.agent:request("GET", "agent/services", {},
		function(res)
			assert(res.code == 200)
			return res:json()
		end)
end


local AgentService_mt = {}
AgentService_mt.__index = AgentService_mt


function AgentService_mt:register(name, options)
	-- options:
	-- 	service_id
	-- 	address
	-- 	port
	-- 	tags
	-- 	check
	-- 		ttl or
	-- 		script, interval or
	-- 		http, interval, timeout

	options = options or {}
	local data = {name = name}

	data.id = options.service_id
	data.address = options.address
	data.port = options.port
	data.tags = options.tags
	data.check = options.check

	return self.agent:request(
		"PUT", "agent/service/register", {data=json.encode(data)},
		function(res)
			return res.code == 200, res:tostring()
		end)
end


function AgentService_mt:deregister(service_id)
	return self.agent:request("GET", "agent/service/deregister/"..service_id, {},
		function(res)
			res:discard()
			return res.code == 200
		end)
end


local Health_mt = {}
Health_mt.__index = Health_mt


function Health_mt:service(name, options)
	-- options
	-- 	index
	-- 	passing
	-- 	tags

	options = options or {}
	local params = {}

	params.index = options.index
	params.passing = options.passing and "1"
	params.tag = options.tag

	return self.agent:request("GET", "health/service/"..name, {params=params},
		function(res)
			assert(res.code == 200)
			return res.headers["X-Consul-Index"], res:json()
		end)
end


--
-- Module interface

local M_mt = {}
M_mt.__index = M_mt


function M_mt:__call(hub, port)
	local M = setmetatable({hub = self.hub, port = port or 8500}, Consul_mt)
	M.kv = setmetatable({agent = M}, KV_mt)
	M.session = setmetatable({agent = M}, Session_mt)
	M.agent = setmetatable({agent = M}, Agent_mt)
	M.agent.service = setmetatable({agent = M}, AgentService_mt)
	M.health = setmetatable({agent = M}, Health_mt)
	return M
end


return function(hub)
	return setmetatable({hub=hub}, M_mt)
end