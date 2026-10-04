# Private PPU checksum regression

Run:

```
python run_ppu_private_crc_gate.py --compiler <pp> --config <moon-base.cfg> --output <new-directory>
```

Native x86-64 Win64/Linux, O2. Changing an anonymous nested array in the
producer's private section shifts DefId without changing its interface. The
consumer PPU is preserved between phases. The runner requires a new full CRC,
the original interface CRC, an actual consumer rebuild, and the correct runtime
result; it then reverses the change. This is a targeted invalidation check. It
does not claim that the old compiler necessarily produced a wrong runtime result
for this particular value.

This gate does not measure full product qualification or compilation cost.
