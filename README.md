moonstep
===
step-executable Lua VM

## usage
`moonstep <luac file>`

## command
###`bp <pc>`
set a breakpoint to `<pc>`
###`r`
run the code. if the breakpoint is set, stop at `<pc>`
###`n`
execute the next instruction
### `d`
dump the current registers and PC
###`q`
quit interactive shell

## demo
```
$ cat << LUA | luac -l -l -
print "hello, world"
LUA

main <stdin:0,0> (4 instructions at 0xf58760)
0+ params, 2 slots, 1 upvalue, 0 locals, 2 constants, 0 functions
        1       [1]     GETTABUP        0 0 -1  ; _ENV "print"
        2       [1]     LOADK           1 -2    ; "hello, world"
        3       [1]     CALL            0 2 1
        4       [1]     RETURN          0 1
constants (2) for 0xf58760:
        1       "print"
        2       "hello, world"
locals (0) for 0xf58760:
upvalues (1) for 0xf58760:
        0       _ENV    1       0
$ moonstep luac.out
[1]> d
{
  pc = 1,
  reg = {}
}
[1]> n
[1]> n
[2]> n
hello, world
[3]> d
{
  pc = 3,
  reg = { "hello, world",
    [0] = <function 1>
  }
}
[3]> n
[(dead)]> q
```

## LICENSE
MIT
