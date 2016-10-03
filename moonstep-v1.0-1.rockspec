package = "moonstep"
version = "v1.0-1"
source = {
	url = "git://github.com/nymphium/moonstep",
	tag = "v1.0"
}
description = {
	homepage = "http://github.com/nymphium/moonstep",
	license = "MIT"
}
dependencies = {
	"inspect",
	"moonscript >= 0.5"
}

build = {
	type = "builtin",
	modules = {},
	install = {
		bin = {
			moonstep = "bin/moonstep"
		},
		lua = {
			["moonstep.common.oplist"] = "moonstep/common/oplist.lua",
			["moonstep.common.opname"] = "moonstep/common/opname.lua",
			["moonstep.common.utils"] = "moonstep/common/utils.moon",
			["moonstep.luadec.reader"] = "moonstep/luadec/reader.moon",
			["moonstep.vm"] = "moonstep/vm.moon",
			["moonstep.optbl"] = "moonstep/optbl.moon"
		}
	}
}
