#!/usr/bin/env python3
"""Inject updated Lua scripts into Farttofloatdemo_v3.rbxl (handles ZSTD + LZ4)."""
import struct, os

try:
    import zstandard
    HAS_ZSTD = True
except ImportError:
    HAS_ZSTD = False

try:
    import lz4.block
    HAS_LZ4 = True
except ImportError:
    HAS_LZ4 = False

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'
FILE  = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
DUMP  = r'C:\Users\lando\Downloads\Fart2floatstuff\scripts_dump'

REPLACEMENTS = {
    'gameclient':  os.path.join(DUMP, '37_0_LocalScript_gameclient.lua'),
    'PlayerStats': os.path.join(DUMP, '60_0_Script_PlayerStats.lua'),
}

def decomp(d, u):
    if len(d) >= 4 and d[:4] == ZSTD_MAGIC and HAS_ZSTD:
        return zstandard.ZstdDecompressor().decompress(d)
    if HAS_LZ4 and u > 0:
        return lz4.block.decompress(bytes(d), uncompressed_size=u)
    return bytes(d)

def write_unc(name_bytes, raw):
    return name_bytes + struct.pack('<III', 0, len(raw), 0) + raw

def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o + 4
def rstr(d, o):
    n, o = ru32(d, o)
    return d[o:o+n].decode('utf-8', 'replace'), o + n

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v & 1 else v >> 1)
    for i in range(1, len(vals)): vals[i] += vals[i-1]
    return vals

print(f"Reading {FILE} ...")
with open(FILE, 'rb') as f: data = bytearray(f.read())
print(f"  File size: {len(data):,} bytes")

header = bytes(data[:32])
chunks = []
offset = 32
while offset < len(data):
    nm_bytes = bytes(data[offset:offset+4])
    nm = nm_bytes.decode('latin-1')
    comp   = struct.unpack_from('<I', data, offset+4)[0]
    uncomp = struct.unpack_from('<I', data, offset+8)[0]
    cs = offset; offset += 16
    if comp == 0:
        raw = bytes(data[offset:offset+uncomp]); offset += uncomp
    else:
        raw = decomp(bytes(data[offset:offset+comp]), uncomp); offset += comp
    orig = bytes(data[cs:offset])
    chunks.append({'nm': nm, 'nm_bytes': nm_bytes, 'raw': raw, 'orig': orig, 'modified': False})
    if nm == 'END\x00': break

print(f"  Parsed {len(chunks)} chunks")

# Build inst_map: type_id -> (class_name, [refs])
inst_map = {}
for ch in chunks:
    if ch['nm'] != 'INST': continue
    raw = ch['raw']; o = 0
    tid, o = ru32(raw, o); cname, o = rstr(raw, o); o += 1
    count, o = ru32(raw, o)
    refs = decode_refs(raw[o:o+count*4], count)
    inst_map[tid] = (cname, refs)

# Build ref_name: ref -> instance name
ref_name = {}
for ch in chunks:
    if ch['nm'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid, o = ru32(raw, o); pn, o = rstr(raw, o); dt = raw[o]; o += 1
    if pn != 'Name' or dt != 0x01: continue
    _, refs = inst_map.get(tid, ('?', []))
    for ref in refs:
        slen, o = ru32(raw, o)
        ref_name[ref] = raw[o:o+slen].decode('utf-8', 'replace'); o += slen

# Map name -> ref
name_to_ref = {}
for ref, nm in ref_name.items():
    if nm in REPLACEMENTS:
        name_to_ref[nm] = ref

print(f"\nTarget scripts found:")
for nm, ref in name_to_ref.items():
    print(f"  {nm!r} -> ref={ref}")
for nm in REPLACEMENTS:
    if nm not in name_to_ref:
        print(f"  WARNING: {nm!r} NOT FOUND in file")

# Build source replacements: ref -> new_bytes
source_replacements = {}
for nm, ref in name_to_ref.items():
    path = REPLACEMENTS[nm]
    new_text = open(path, 'r', encoding='utf-8').read()
    source_replacements[ref] = new_text.encode('utf-8')
    print(f"  Loaded {nm!r}: {len(source_replacements[ref]):,} bytes")

SCRIPT_CLASSES = {'Script', 'LocalScript', 'ModuleScript'}
modified_count = 0

for ch in chunks:
    if ch['nm'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid, o = ru32(raw, o); pn, o = rstr(raw, o); dt = raw[o]; o += 1
    cname, refs = inst_map.get(tid, ('?', []))
    if pn != 'Source' or dt != 0x01 or cname not in SCRIPT_CLASSES: continue
    if not any(r in source_replacements for r in refs): continue

    print(f"\nModifying Source chunk: type_id={tid} ({cname}), {len(refs)} instances")
    sources = {}
    for ref in refs:
        slen, o = ru32(raw, o)
        sources[ref] = raw[o:o+slen]; o += slen

    for ref in refs:
        if ref in source_replacements:
            old_len = len(sources[ref])
            sources[ref] = source_replacements[ref]
            print(f"  ref={ref} ({ref_name.get(ref,'?')}): {old_len} -> {len(sources[ref])} bytes")

    # Rebuild chunk raw
    new_raw = bytearray()
    new_raw += struct.pack('<I', tid)
    pn_b = b'Source'
    new_raw += struct.pack('<I', len(pn_b)) + pn_b + bytes([0x01])
    for ref in refs:
        s = sources[ref]
        new_raw += struct.pack('<I', len(s)) + s

    ch['raw'] = bytes(new_raw)
    ch['modified'] = True
    modified_count += 1

print(f"\nModified {modified_count} PROP chunk(s)")

# Write output — uncompressed for modified chunks, original bytes otherwise
out = bytearray(header)
for ch in chunks:
    if ch['modified']:
        out += write_unc(ch['nm_bytes'], ch['raw'])
    else:
        out += ch['orig']

with open(FILE, 'wb') as f:
    f.write(out)

print(f"Saved: {len(out):,} bytes -> {FILE}")
print("\nV3 UPDATED")
