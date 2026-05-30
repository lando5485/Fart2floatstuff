#!/usr/bin/env python3
"""Extract all Lua scripts from a Roblox binary .rbxl file"""
import struct, lz4.block, os, sys

SCRIPT_CLASSES = {'Script', 'LocalScript', 'ModuleScript'}
INPUT = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
OUT_DIR = r'C:\Users\lando\Downloads\Fart2floatstuff\scripts_dump'

def read_lstr(data, pos):
    l = struct.unpack_from('<I', data, pos)[0]
    return data[pos+4:pos+4+l].decode('utf-8', errors='replace'), pos+4+l

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
        cn, pos = read_lstr(d, pos)
        is_svc = d[pos]; pos += 1
        ni = struct.unpack_from('<I', d, pos)[0]; pos += 4
        classes[ci] = (cn, ni)
    return classes

def get_prop_strings(chunk, classes):
    d = chunk['data']; pos = 0
    ci = struct.unpack_from('<I', d, pos)[0]; pos += 4
    pn, pos = read_lstr(d, pos)
    tid = d[pos]; pos += 1
    ni = classes.get(ci, ('', 0))[1]
    vals = []
    if tid == 0x01:
        for _ in range(ni):
            sl = struct.unpack_from('<I', d, pos)[0]; pos += 4
            vals.append(bytes(d[pos:pos+sl])); pos += sl
    return ci, pn, tid, vals

header, chunks = parse_file(INPUT)
classes = get_classes(chunks)

print("=== CLASS LIST ===")
for idx, (cn, ni) in sorted(classes.items()):
    print(f"  [{idx}] {cn} x{ni}")

# Gather names and sources per class
names = {}   # class_index -> [name, ...]
sources = {} # class_index -> [(chunk_i, src_i, text), ...]

for i, ch in enumerate(chunks):
    if ch['type'] != b'PROP': continue
    try:
        ci, pn, tid, vals = get_prop_strings(ch, classes)
    except Exception as e:
        continue
    if tid != 0x01: continue
    cn = classes.get(ci, ('', 0))[0]
    if pn == 'Name':
        names[ci] = [v.decode('utf-8', errors='replace') for v in vals]
    if cn in SCRIPT_CLASSES and pn == 'Source':
        sources[ci] = [(i, j, vals[j].decode('utf-8', errors='replace')) for j in range(len(vals))]

os.makedirs(OUT_DIR, exist_ok=True)

print("\n=== SCRIPTS ===")
for ci, srcs in sorted(sources.items()):
    cn = classes[ci][0]
    cls_names = names.get(ci, [])
    for chunk_i, src_i, text in srcs:
        name = cls_names[src_i] if src_i < len(cls_names) else f"#{src_i}"
        safe = name.replace('/', '_').replace('\\', '_').replace(':', '_')
        fname = f"{OUT_DIR}\\{ci}_{src_i}_{cn}_{safe}.lua"
        open(fname, 'w', encoding='utf-8').write(text)
        print(f"  [{ci}/{src_i}] {cn} '{name}' -> {fname} ({len(text)} chars)")
        if text.strip():
            preview = text[:200].replace('\n', ' | ')
            print(f"    Preview: {preview}")

print(f"\nDone. Scripts saved to {OUT_DIR}")
