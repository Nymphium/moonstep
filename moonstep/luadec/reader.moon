import concat from table
import char from string

import zsplit, map, prerr, undecimal from require'moonstep.common.utils'
import hexdecode, hextobin, adjustdigit, bintoint, hextoint, hextochar, bintohex from undecimal

string = string
string.zsplit = zsplit

insgen = (ins) ->
	abc = (a, b, c) ->
		unpack map (=> with r = bintoint @ do if r > 255 then return 255 - r), {a, b, c}
	abx = (a, b, _b) ->
		unpack map bintoint, {a, b .. _b}
	asbx = (a, b, _b) ->
		mpjs = map bintoint, {a, b .. _b}
		mpjs[2] -= 2^17 - 1
		unpack mpjs
	ax = (a, _, _) -> bintoint a

	oplist = require'moonstep.common.oplist' abc, abx, asbx, ax
	setmetatable oplist,
		__index: (v) =>
			if e = rawget @, v then e
			else error "invalid opcode: #{math.tointeger v}"

	b, c, a, i = (hextobin ins)\match "(#{"."\rep 9})(#{"."\rep 9})(#{"."\rep 8})(#{"."\rep 6})"
	{op, fn} = oplist[(bintoint i) + 1]

	{:op, fn(a, b, c)}

-- XXX: supported little endian 64bit float only
ieee2f = (input) ->
	mantissa = (input\byte 7) % 16
	for i = 6, 1, -1 do mantissa = mantissa * 256 + input\byte i
	exponent = ((input\byte 8) % 128) * 16 + ((input\byte 7) // 16)
	exponent == 0 and
	0 or ((mantissa * 2 ^ -52 + 1) * ((input\byte 8) > 127 and -1 or 1)) * (2 ^ (exponent - 1023))

-- Reader class
-- add common operations to string and file object
-- {{{
class Reader
	new: (@val) =>
		@val = if (type(@val) == "userdata") and io.type(@val) == "file"
			current = @val\seek!
			with @val\read"*a"
				@val\seek "set", current
		elseif type(@val) == "string"
			@val
		else
			error "Reader constructor receives only the type of string or file (got `#{type @val}`)"

		@priv = {val: @val}
		@cur = 1

	__len: => #@priv.val - @cur

	__shr: (n) => @\read n

	read: (n) =>
		if n == "*a" then n = #@
		@cur += n
		local ret

		ret, @val = @val\match("^(#{(".")\rep n})(.*)$")
		ret

	seek: (s, ofs) =>
		setofs = ->
			if type(ofs) != "number"
				error "seek #2 require number, got #{type ofs}"
			else
				@cur += ofs
				@val = @priv.val\match ".*$", @cur

		switch s
			when "seek"
				@cur = 0
				@val = @priv.val
			else
				unless ofs then @cur
				else setofs!

-- }}}

-- bytecode structure
----{{{
-- headerblock {{{
---- [signature(4)] [version(1)] [format(1)] [conversion error check(6)]
---- [sizeof int(1)] [sizeof size_t(1)] [sizeof instruction(1)] [sizeof lua_integer(1)] [sizeof lua_number(1)]
---- [endianness(8)] [float format check(10)]
-- }}}
-- number of upvalues (1)
-- function block {{{
---- [name(n)] [line defined(sizeof int)] [line lastdefined(sizeof int)] [numparams(1)] [is_vararg(1)]
---- [maxstacksize(1)] [number of instructions(1)] [instructions(num of ins)] [number of constants(1)] [constants(num of cons)] [upvalue(num of upvalue)] [protos(?)] [debuginfo(?)]
-- }}}
----}}}

-- decodeer
----{{{
hblockdecode = (input) ->
	{
		hsig: input >> 4
		version: (hexdecode! (input >> 1)\byte!)\gsub("(%d)(%d)", "%1.%2")
		format: (input >> 1)\byte!
		luac_data: input >> 6
		size: {
			int: (input >> 1)\byte!
			size_t: (input >> 1)\byte!
			instruction: (input >> 1)\byte!
			lua_integer: (input >> 1)\byte!
			lua_number: (input >> 1)\byte!
		}

		-- luac_int, 0x5678
		endian: (input >> 8) == ((char(0x00))\rep(6) .. char(0x56, 0x78)) and 0 or 1

		-- luac_num, checking IEEE754 float format
		luac_num: input >> 9
		has_debug: input >> 1 -- `0a` or `00`, the formar is that `has_debug`
	}

headassert = (header) ->
	assert header.hsig == char(0x1b, 0x4c, 0x75, 0x61), "HEADER SIGNATURE ERROR" -- header signature
	assert header.luac_data == char(0x19, 0x93, 0x0d, 0x0a, 0x1a, 0x0a), "CONVERSION ERROR"
	header

providetools = (input, header) -> with header or hblockdecode input
	mayberotate = if .endian < 1 then (=> @) else (xs) -> [xs[i] for i = #xs, 1, -1]
	undumpchar = -> hexdecode! (input >> 1)\byte!
	undump_n = (n) -> hexdecode(n) unpack mayberotate {(input >> n)\byte 1, n}
	undumpint = -> undump_n tonumber .size.int -- number of 

	return {
		:mayberotate
		:undump_n
		:undumpchar
		:undumpint
	}

chunknamedecode = (input, header) ->
	header or= hblockdecode input
	import mayberotate, undump_n, undumpchar, undumpint from providetools input, header
	with ret = ""
		if header.has_debug\byte! > 0
			undumpchar!
			c = undumpchar!

			while hextoint(c) > 0
				ret ..= char hextoint c
				c = undumpchar!
			input\seek "cur", #ret == 0 and -2 or -1

fnblockdecode = (input, header) ->
	header or= hblockdecode input
	import mayberotate, undump_n, undumpchar, undumpint from providetools input, header

	local instnum

	return {
		line: {
			defined: undumpint!
			lastdefined: undumpint!
		}

		params: undumpchar!
		vararg: undumpchar!
		regnum: undumpchar! -- number of register to use

		-- instructions: [num (4)] [instructions..]
		-- instruction: [inst(4)]
		instruction: do
			-- with num: hextoint undumpint!
			num = hextoint undumpint!
			instnum = num
			[insgen undumpint! for _ = 1, num]

		-- constants: [num (4)] [constants..]
		-- constant: [type(1)] [...]
		constant: for _ = 1, hextoint undumpint!
			with type: (input >> 1)\byte!
				.val = switch .type
					when  0x1
						-- bool
						undumpchar!
					when  0x3
						-- number
						ieee2f input >> 8
					when 0x13
						-- signed integer
						n = undump_n 8
						if n\match"^[^0-7]"
							0x10000000000000000 + hextoint n
						else hextoint n
					when  0x4, 0x14
						-- string
						if s = (=> concat mayberotate map hextochar, (undump_n @)\zsplit 2 if @ > 0) with len = hextoint undumpchar!
								if len == 0xff -- #str > 255
									len = hextoint undump_n 8
								return len - 1 -- remove '\0' in internal expression
							s
						else
							""
					else nil

		upvalue: for _ = 1, hextoint undumpint!
			u = mayberotate {(hextoint undumpchar!), (hextoint undumpchar!)}
			{reg: u[1], instack: u[2]} -- {reg, instack}, instack is whether it is in stack

		prototype: for i = 1, hextoint undumpint!
			undumpchar!
			fnblockdecode input, header

		debug: with ret = {}
			.has_debug = header.has_debug\byte! > 0
			.linenum = hextoint undumpint!

			if .has_debug then .opline = [hextoint undumpint! for _ = 1, instnum]

			.varnum = hextoint undumpint!

			if .has_debug then .varinfo = for _ = 1, .varnum
				{
					concat mayberotate map hextochar, (undump_n (hextoint undumpchar!) - 1)\zsplit 2
					hextoint undumpint! -- lifespan begin
					hextoint undumpint! -- lifespan end
				}

			.upvnum = hextoint undumpint!

			if .has_debug then .upvname = for _ = 1, .upvnum
				concat mayberotate map hextochar, (undump_n (hextoint undumpchar!) - 1)\zsplit 2
	}

-- instant decoder
decode = (f_or_s) ->
	input = Reader f_or_s

	h = headassert hblockdecode input
	cn = chunknamedecode input, h
	fn = fnblockdecode input, h

	h, cn, fn
----}}}

{:Reader, :hblockdecode, :headassert, :chunknamedecode, :fnblockdecode, :decode}

