local levee = require("levee")


return {
	test_kv = function()
		local h = levee.Hub()
		local c = h.consul()

		-- clean up old runs
		c.kv:delete("foo/", {recurse=true})
		--

		local p = h:pipe()
		h:spawn(function()
			local index, data
			while true do
				index, data = c.kv:get("foo/", {index=index, recurse=true, keys=true})
				p:send(data)
			end
		end)

		assert.equal(p:recv(), nil)

		assert.equal(c.kv:put("foo/1", "1"), true)
		local index, data = c.kv:get("foo/1")
		assert.equal(data["Value"], "1")
		assert.same(p:recv(), {"foo/1"})

		assert.equal(c.kv:put("foo/2", "2"), true)
		assert.same(p:recv(), {"foo/1", "foo/2"})

		assert.equal(c.kv:put("foo/3", "3"), true)
		assert.same(p:recv(), {"foo/1", "foo/2", "foo/3"})

		assert.equal(c.kv:delete("foo/2"), true)
		assert.same(p:recv(), {"foo/1", "foo/3"})

		assert.equal(c.kv:delete("foo/", {recurse=true}), true)
		assert.same(p:recv(), nil)
	end,

	test_session = function()
		local h = levee.Hub()
		local c = h.consul()

		-- clean up old runs
		local index, sessions = c.session:list()
		for _, session in pairs(sessions) do
			c.session:destroy(session["ID"])
		end
		--

		local session_id = c.session:create({behavior="delete", ttl=10})

		local index, sessions = c.session:list()
		assert.equal(#sessions, 1)
		assert.equal(sessions[1]["ID"], session_id)

		local index, session = c.session:info("foo")
		assert.equal(session, nil)
		local index, session = c.session:info(session_id)
		assert.equal(session["ID"], session_id)

		assert.equal(c.session:renew("foo"), false)
		assert.equal(c.session:renew(session_id)["ID"], session_id)

		c.session:destroy(session_id)
		local index, sessions = c.session:list()
		assert.equal(#sessions, 0)
	end,

	test_service = function()
		local h = levee.Hub()
		local c = h.consul()

		-- clean up old runs
		c.agent.service:deregister("foo")
		--

		local p = h:pipe()
		h:spawn(function()
			local index, services
			while true do
				index, services = c.health:service("foo", {index=index})
				p:send(services)
			end
		end)
		assert.equal(#p:recv(), 0)

		assert.equal(c.agent.service:register("foo"), true)
		assert(c.agent:services()["foo"])
		assert.equal(#p:recv(), 1)

		assert.equal(c.agent.service:deregister("foo"), true)
		assert.equal(c.agent:services()["foo"], nil)
		local index, services = c.health:service("foo")
		assert.equal(#p:recv(), 0)
	end,
}
