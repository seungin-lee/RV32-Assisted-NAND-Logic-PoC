#!/usr/bin/env python3
#
# Purpose: Convert a little-endian RV32 firmware binary to Verilog $readmemh
# words for the NAND RV32 control-agent SRAM.
# Role: Build helper script.
# Related design docs:
# - design_spec/nand_picorv32.md
# - design_spec/nand_control_fw.md
# File version: v0.1
# Revision history:
# - v0.1: Import makehex helper into NAND repository.
#
# This is free and unencumbered software released into the public domain.
#
# Anyone is free to copy, modify, publish, use, compile, sell, or
# distribute this software, either in source code form or as a compiled
# binary, for any purpose, commercial or non-commercial, and by any
# means.

from sys import argv

binfile = argv[1]
nwords = int(argv[2])

with open(binfile, "rb") as f:
    bindata = f.read()

assert len(bindata) < 4*nwords
assert len(bindata) % 4 == 0

for i in range(nwords):
    if i < len(bindata) // 4:
        w = bindata[4*i : 4*i+4]
        print("%02x%02x%02x%02x" % (w[3], w[2], w[1], w[0]))
    else:
        print("0")
