import struct
with open(r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl','rb') as f:
    data = f.read(200)

print("First 200 bytes:")
for i in range(0, len(data), 16):
    chunk = data[i:i+16]
    hex_part = ' '.join(f'{b:02x}' for b in chunk)
    asc_part = ''.join(chr(b) if 32<=b<127 else '.' for b in chunk)
    print(f"{i:4d}: {hex_part:<48}  {asc_part}")

# Try to find first chunk - look for 4-char chunk name patterns
print("\nLooking for chunk starts (INST/PROP/PRNT/META/SSTR/END):")
full = open(r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl','rb').read()
for i in range(0, min(200, len(full)-16)):
    candidate = full[i:i+4]
    if candidate in (b'INST',b'PROP',b'PRNT',b'META',b'SSTR',b'END\x00'):
        comp = struct.unpack_from('<I', full, i+4)[0]
        uncomp = struct.unpack_from('<I', full, i+8)[0]
        print(f"  offset={i}: name={candidate} comp={comp} uncomp={uncomp}")
        break
