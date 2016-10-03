import concat from table
import char from string

import zsplit, map, insgen, prerr, undecimal from require'common.utils'
import hexdecode, hextobin, adjustdigit, bintoint, hextoint, hextochar, bintohex from undecimal

string = string
string.zsplit = zsplit

-- f2ieee = require'luadec.f2ieee'

-- refer: https://github.com/leegao/LuaInLua/blob/master/bytecode/writer.lua#L28
-- TODO: now only supported signed 64bit float
f2ieee = (flt) ->
	if flt == 0 then return 0
	m, e = math.frexp flt

	hi = math.floor 0x200000 * m
	lo = math.floor (0x200000 * m - hi) * 0x100000000
	hi = hi & 0xfffff

	hie = (0x7ff & (e + 1022)) << 20
	sign = (flt < 0 and 1 or 0) << 31
	hi = (sign | (hi | hie))

	math.tointeger ("0x%x%x"\format hi, lo)

-- Writer class
-- interface to write to file
-- {{{
class Writer
	new: (file) =>
		file = if type(file) == "userdata"
			file
		elseif type(file) == "string"
			file = assert io.open(file, "w+b"), "Writer.new #1: failed to open file #{file}"
		else error "Writer constructor receives only the type of string or file"

		@priv = {:file}

	__shl: (v) => with @ do assert @priv.file\write v
	close: =>
		@priv.file\flush!
		with @priv.file\close!
			@priv = nil
			@ = nil
	show: =>
		pos = @priv.file\seek "cur"
		@priv.file\seek "set"
		with @priv.file\read "*a"
			@priv.file\seek "set", pos
-- }}}

-- write (re) encoded data to file
-- {{{
regx = (i) -> hextobin "%x"\format i
writeint = (wt, int, rotate, dig = 8) ->
	map (=> wt << hextochar @), rotate (adjustdigit ("%x"\format int), dig)\zsplit 2

write_fnblock = (wt, fnblock, op_list, mayberotate, has_debug) ->
	with fnblock
		map (=> writeint wt, (hextoint @), mayberotate), {.line.defined, .line.lastdefined}
		map (=> wt << hextochar @), {
				.params
				.vararg
				.regnum
			}

	with ins = fnblock.instruction
		writeint wt, #ins, mayberotate

		for i = 1, #ins
			{RA, RB, RC} = ins[i]
			a = adjustdigit (regx RA), 8

			rbc = do
				if RC
					concat map (=> adjustdigit (regx if @ < 0 then 2^8 - 1 - @ else @), 9), {RB, RC}
				else
					adjustdigit (regx if op_list[ins[i].op][2] == "asbx" then RB +2^17-1 else RB), 18

			bins = rbc ..a..(adjustdigit (regx (op_list[ins[i].op].idx - 1)), 6)

			assert #bins == 32
			map (=> wt << hextochar @), mayberotate (concat map (=> bintohex @), bins\zsplit 4)\zsplit 2

	with cst = fnblock.constant
		writeint wt, #cst, mayberotate

		for i = 1, #cst
			wt << char cst[i].type

			switch cst[i].type
				when 0x1
					wt << char cst[i].val
				when 0x3
					writeint wt, math.tointeger("0x#{(adjustdigit (hexdecode! f2ieee cst[i].val)\reverse!, 16)\reverse!}"), mayberotate, 16
				when 0x13
					writeint wt, cst[i].val, mayberotate, 16
				when 0x4, 0x14
					if #cst[i].val > 0xff
						wt << char 0xff
						writeint wt, #cst[i].val + 1, mayberotate, 16
					else
						writeint wt, #cst[i].val + 1, mayberotate, 2

					wt << cst[i].val

	with upv = fnblock.upvalue
		writeint wt, #upv, mayberotate

		for i = 1, #upv
			map (=> wt << char @), mayberotate {upv[i].reg, upv[i].instack}

	with proto = fnblock.prototype
		writeint wt, #proto, mayberotate

		for i = 1, #proto
			wt << char 0
			write_fnblock wt, proto[i], op_list, mayberotate, has_debug

	with fnblock.debug
		writeint wt, (has_debug and .linenum or 0), mayberotate

		if has_debug then for i = 1, #(.opline or "")
			writeint wt, .opline[i], mayberotate

		writeint wt, (has_debug and .varnum or 0), mayberotate

		if has_debug then for i = 1, #(.varinfo or "")
			writeint wt, #.varinfo[i][1]+1, mayberotate, 2
			wt << .varinfo[i][1]
			map (=> writeint wt, @, mayberotate), {.varinfo[i][2], .varinfo[i][3]}

		writeint wt, (has_debug and .upvnum or 0), mayberotate

		if has_debug then for i = 1, #(.upvname or "")
			writeint wt, #.upvname[i]+1, mayberotate, 2
			wt << .upvname[i]

write = (wt, header, chunkname, fnblock) ->
	op_list = require'common.oplist' "abc", "abx", "asbx", "ab"
	mayberotate = if header.endian < 1 then (=> @) else (xs) -> [xs[i] for i = #xs, 1, -1]

	with header
		map (=> wt << @), {
				.hsig
				(hextochar math.tointeger .version * 10)
				(char .format)
				.luac_data
			}

		with .size
			map (=> wt << (char @)), {
					.int
					.size_t
					.instruction
					.lua_integer
					.lua_number
				}

		map (=> wt << @), {
				(concat mayberotate (((char 0x00)\rep 6) .. char 0x56, 0x78)\zsplit!)
				.luac_num
				.has_debug
			}

	has_debug = header.has_debug\byte! > 0

	if has_debug
		wt << char 0x40 -- i don't know why '0x40' but it works
		wt << chunkname

	write_fnblock wt, fnblock, op_list, mayberotate, has_debug
-- }}}

{:Writer, :write}

