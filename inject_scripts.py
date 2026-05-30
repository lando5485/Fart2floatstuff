#!/usr/bin/env python3
"""Inject modified Lua scripts back into a Roblox binary .rbxl file"""
import struct, lz4.block, os

SCRIPT_CLASSES = {'Script', 'LocalScript', 'ModuleScript'}
INPUT  = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
OUTPUT = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
DUMP   = r'C:\Users\lando\Downloads\Fart2floatstuff\scripts_dump'

REPLACEMENTS = {
    (37, 0): os.path.join(DUMP, '37_0_LocalScript_gameclient.lua'),
    (60, 0): os.path.join(DUMP, '60_0_Script_PlayerStats.lua'),
}

def read_lstr(data, pos):
    l = struct.unpack_from('<I', data, pos)[0]
    return bytes(data[pos+4:pos+4+l]).decode('utf-8', errors='replace'), pos+4+l

def parse_file(path):
    raw = open(path, 'rb').read()
    assert raw[:8] == b'<roblox!', "Not a Roblox binary file"
    header = raw[:32]
    pos = 32
    chunks = []
    while pos < len(raw):
        if pos + 16 > len(raw): break
        ctype = raw[pos:pos+4]
        csz = struct.unpack_from('<i', raw, pos+4)[0]
        usz = struct.unpack_from('<i', raw, pos+8)[0]
        rsv = struct.unpack_from('<i', raw, pos+12)[0]
        pos += 16
        if csz == 0:
            data = bytearray(raw[pos:pos+usz]); pos += usz; compr = False
        else:
            data = bytearray(lz4.block.decompress(raw[pos:pos+csz], usz)); pos += csz; compr = True
        chunks.append({'type': ctype, 'data': data, 'compressed': compr, 'reserved': rsv})
        if ctype == b'END\x00': break
    return header, chunks

def get_classes(chunks):
    classes = {}
    for ch in chunks:
        if ch['type'] != b'INST': continue
        d = ch['data']; pos = 0
        ci = struct.unpack_from('<I', d, pos)[0]; pos += 4
        cl, pos = read_lstr(d, pos)
        is_svc = d[pos]; pos += 1
        ni = struct.unpack_from('<I', d, pos)[0]; pos += 4
        classes[ci] = (cl, ni)
    return classes

def get_names(chunks, classes):
    names = {}
    for ch in chunks:
        if ch['type'] != b'PROP': continue
        d = ch['data']; pos = 0
        ci = struct.unpack_from('<I', d, pos)[0]; pos += 4
        pn, pos = read_lstr(d, pos)
        tid = d[pos]; pos += 1
        if pn != 'Name' or tid != 0x01: continue
        ni = classes.get(ci, ('', 0))[1]
        ns = []
        for _ in range(ni):
            sl = struct.unpack_from('<I', d, pos)[0]; pos += 4
            ns.append(bytes(d[pos:pos+sl]).decode('utf-8', errors='replace')); pos += sl
        names[ci] = ns
    return names

def serialize(header, chunks):
    out = bytearray(header)
    for ch in chunks:
        ctype = ch['type']
        data = bytes(ch['data'])
        rsv = ch.get('reserved', 0)
        if ctype == b'END\x00' or not ch.get('compressed', True):
            out += ctype + struct.pack('<i', 0) + struct.pack('<i', len(data)) + struct.pack('<i', rsv) + data
        else:
            comp = lz4.block.compress(data, store_size=False)
            out += ctype + struct.pack('<i', len(comp)) + struct.pack('<i', len(data)) + struct.pack('<i', rsv) + comp
    return bytes(out)

header, chunks = parse_file(INPUT)
classes = get_classes(chunks)
names = get_names(chunks, classes)

modified = 0
for i, ch in enumerate(chunks):
    if ch['type'] != b'PROP': continue
    d = ch['data']; pos = 0
    ci = struct.unpack_from('<I', d, pos)[0]; pos += 4
    pn, pos = read_lstr(d, pos)
    tid = d[pos]; pos += 1
    cn = classes.get(ci, ('', 0))[0]
    if cn not in SCRIPT_CLASSES or pn != 'Source' or tid != 0x01:
        continue
    ni = classes[ci][1]
    cls_names = names.get(ci, [])
    for j in range(ni):
        key = (ci, j)
        if key not in REPLACEMENTS:
            # advance past this string
            sl = struct.unpack_from('<I', d, pos)[0]; pos += 4 + sl
            continue
        # Read position of this string in chunk data
        str_start = pos
        sl = struct.unpack_from('<I', d, pos)[0]; pos += 4 + sl
        str_end = pos
        # Load replacement
        new_text = open(REPLACEMENTS[key], 'r', encoding='utf-8').read()
        new_bytes = new_text.encode('utf-8')
        inst_name = cls_names[j] if j < len(cls_names) else f'#{j}'
        print(f"  Injecting [{ci}/{j}] {cn} '{inst_name}': {len(new_bytes)} bytes (was {str_end - str_start - 4})")
        new_chunk = bytes(d[:str_start]) + struct.pack('<I', len(new_bytes)) + new_bytes + bytes(d[str_end:])
        ch['data'] = bytearray(new_chunk)
        # Re-read updated data for subsequent iterations
        d = ch['data']
        # Recalculate pos after replacement
        pos = str_start + 4 + len(new_bytes)
        modified += 1

print(f"\nModified {modified} script(s)")
out = serialize(header, chunks)
with open(OUTPUT, 'wb') as f:
    f.write(out)
print(f"Saved {len(out)} bytes to {OUTPUT}")
print("Done!")
