#!/usr/bin/env python3
"""build_rom.py -- splice the netcode bank into Double Dribble.

  build_rom.py ORIG.nes BANK8.bin BANK8.lbl OUT.nes
  build_rom.py --org ORIG.nes OUT.nes     split + rejoin, untouched (verify-org)

UNROM 8 x 16K becomes UOROM 16 x 16K: banks 0-6 as they were, 7 a spare copy
of the old fixed bank (the game never selects it; kept so a stray select
still lands on real code), 8 the netcode, 9-14 empty, 15 the fixed bank with
tools/patches.py applied. The NES 2.0 header asks for 8K of PRG-RAM, which
the FujiNet cart serves at $6000.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from patches import PATCHES

BANK = 16384

def labels(path):
    out = {}
    for line in open(path):
        p = line.split()
        if len(p) == 3 and p[0] == 'al':
            out[p[2].lstrip('.')] = int(p[1], 16)
    return out

def expand(seq, syms):
    b = []
    for x in seq:
        if isinstance(x, str):
            v = syms[x]
            b += [v & 0xFF, v >> 8]
        else:
            b.append(x)
    return b

def split(path):
    d = open(path, 'rb').read()
    hdr, prg = d[:16], d[16:16 + d[4] * BANK]
    assert d[:4] == b'NES\x1a' and d[4] == 8 and (d[6] >> 4) == 2, "not the UNROM Double Dribble"
    return hdr, [bytearray(prg[i * BANK:(i + 1) * BANK]) for i in range(8)], d[16 + len(prg):]

def main():
    a = sys.argv[1:]
    if a[0] == '--org':
        hdr, banks, tail = split(a[1])
        open(a[2], 'wb').write(hdr + b''.join(banks) + tail)
        return
    orig, b8path, lblpath, out = a
    hdr, banks, tail = split(orig)
    syms = labels(lblpath)
    assert syms['NET_BOOT'] == 0x8003, "NET_BOOT must sit at $8003 (the boot stub jumps there)"
    b8 = bytearray(open(b8path, 'rb').read())
    assert len(b8) == BANK and b8[0] == 8
    fixed = bytearray(banks[7])
    for addr, old, new, why in PATCHES:
        new = expand(new, syms)
        o = addr - 0xC000
        have = list(fixed[o:o + len(old)])
        if have != old:
            sys.exit("patch ${:04X}: expected {} found {} ({})".format(
                addr, bytes(old).hex(), bytes(have).hex(), why))
        assert len(new) == len(old), "patch ${:04X} changes length".format(addr)
        fixed[o:o + len(new)] = bytes(new)
    out_banks = banks[:7] + [banks[7], b8]
    for n in range(9, 15):
        e = bytearray(b'\xff' * BANK)
        e[0] = n
        out_banks.append(e)
    out_banks.append(fixed)
    h = bytearray(hdr)
    h[4] = 16                   # 16 x 16K PRG
    h[7] = (h[7] & 0xF0) | 0x08 # NES 2.0
    h[9] = 0
    h[10] = 0x07                # 8K PRG-RAM (64 << 7), volatile
    open(out, 'wb').write(bytes(h) + b''.join(out_banks) + tail)

if __name__ == '__main__':
    main()
