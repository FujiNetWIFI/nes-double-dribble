# rom/

Put your own dump of Double Dribble (USA) here as `double_dribble.nes`. It is
not in this repository and must never be committed (`.gitignore` excludes
every `.nes` file).

Expected image:

| | |
|---|---|
| Header | NES 2.0, mapper 2 (UNROM), 128K PRG, 8K CHR-RAM, vertical mirroring |
| File SHA-1 | `d0f467306af230bfb1332cc39a5d3459b27d2201` |
| PRG CRC32 | `437E7B69` |

`tools/build_rom.py` checks the bytes at every patch site and refuses any
other image.
