unless RETURN
	require'moonstep.common.opname'

import deepcpy from require'moonstep.common.utils'
optbl = require'moonstep.optbl'

isk = (rk) ->
	(rk & 256) ~= 0

vm = (fnblock, src = {}, upreg = {}) ->
	{:constant, :instruction, :upvalue, :prototype} = fnblock

	{:reg} = src
	_ENV = deepcpy _ENV

	getrk = (rk) ->
		if isk rk
			constant[-rk].val
		else
			reg[rk]

	coroutine.create ->
		while src.pc <= #instruction
			ins = instruction[src.pc]
			{RA, RB, RC, op: opec} = ins

			switch opec
				when MOVE
					reg[RA] = reg[RB]
				when LOADK
					reg[RA] = constant[RB + 1].val
				when LOADKX
					assert instruction[src.pc + 1].op == EXTRAARG

					reg[RA] = constant[(513 + instruction[src.pc + 1][1]) % 256].val

					src.pc += 1
				when LOADBOOL
					reg[RA] = RB == 0

					if RC ~= 0
						src.pc += 1
				-- when LOADNIL
				when GETUPVAL
					reg[RA] = upreg[RB + 1]
				when GETTABUP
					reg[RA] = if upvalue[RB + 1].instack == 1
						_ENV[constant[-RC].val]
				when GETTABLE
					reg[RA] = reg[RB][getrk RC]
				when SETTABUP
					_ENV[-RB] = constant[-RC]
				when SETUPVAL
					upreg[RA] = reg[RB]
				when SETTABLE
					reg[RA][getrk RB] = getrk RC
				when NEWTABLE
					reg[RA] = {}
				when SELF
					reg[RA + 1] = reg[RB]
					reg[RA] = reg[RB][getrk RC]
				when ADD, SUB, MUL, DIV, BAND, BOR, BXOR, SHL, SHR, MOD, IDIV, POW
					reg[RA] = optbl[opec] (getrk RB), (getrk RC)
				when UNM
					reg[RA] = -reg[RB]
				when BNOT
					reg[RA] = ~ reg[RB]
				when NOT
					reg[RA] = not reg[RB]
				when LEN
					reg[RA] = #reg[RB]
				when CONCAT
					for r = RB, RC
						reg[RA] ..= reg[r]
				when JMP
					src.pc += RA
				when EQ, LT, LE
					src.pc += 1 if (optbl[opec] (getrk RB), (getrk RC)) ~= RA
				when TEST
					src.pc += 1 unless reg[RA]
				when TESTSET
					if reg[RB]
						reg[RA] = reg[RB]
					else
						src.pc += 1
				when CALL
					fn = reg[RA]
					calllimit = RB == 0 and #reg or (RA + RB - 1)
					retvals   = {fn unpack reg, (RA + 1), calllimit}
					retlimit  = RC == 0 and #retvals or (RC - 2)

					for r = RA, RA + retlimit
						reg[r] = retvals[r - RA + 1]
				when TAILCALL
					fn = reg[RA]

					return fn unpack reg, (RA + 1), (RA + RB - 1)
				when RETURN
					retlimit = switch RB
						when 0 then #reg
						when 1 then 0
						else        RB - 2

					return unpack reg, RA, (RA + retlimit)
				when FORLOOP
					reg[RA] += reg[RA + 2]

					if reg[RA] <= reg[RA + 1]
						src.pc += RB
						reg[RA + 3] = reg[RA]
				when FORPREP
					reg[RA] -= reg[RA + 2]
					src.pc += RB
				when TFORCALL
					-- fn = reg[RA]
					-- retvals = {fn unpack reg, (RA + 1), (RA + 2)}

					-- for r = RA + 3, RA + RC + 2
						-- reg[r] = retvals[r - RA - 2]

					-- if reg[RA] + 3
						-- reg[RA + 2] = reg[RA + 3]
					-- else
						-- src.pc += 1
					cb = RA + 3
					reg[cb + 2] = reg[RA + 2]
					reg[cb + 1] = reg[RA + 1]
					reg[cb] = reg[RA]
					fn = reg[cb]
					retvals = {fn unpack reg, cb, cb + RC}

					assert instruction[src.pc + 1] == TFORLOOP

					if reg[RA + 1]
						reg[RA] = reg[RA + 1]
				when SETLIST
					for i = 1, RB
						reg[RA][RC - 1 + i] = reg[RA + i]
				when CLOSURE
					reg[RA] = prototype[RB + 1]


			coroutine.yield!
			src.pc += 1

		reg

vm

