local levee = require("levee")

return {
	test_string = function()
		local want = "foo"
		local buf = levee.msgpack.encode(want)
		local ok, got = levee.msgpack.decoder():stream_consume(buf)
		assert(ok)
		assert.same(want, got)
		assert.equal(#buf, 0)
	end,

	test_nested = function()
		local want = {
			foo = "bar",
			arr = {3, -4, "foo", true, false, 3.7},
		}

		local buf = levee.msgpack.encode(want)

		local ok, got = levee.msgpack.decoder():stream_consume(buf)
		assert(ok)
		assert.same(want, got)
		assert.equal(#buf, 0)
	end,
}
