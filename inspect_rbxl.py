#!/usr/bin/env python3
"""Inspect binary RBXL - list all Script/LocalScript instances."""
import struct, zstandard, lz4.block, sys

INFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl'

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'

def decompress_chunk(data_bytes, uncomp_len):
    if len(data_bytes) >= 4 and data_bytes[:4] == ZSTD_MAGIC:
        ctx = zstandard.ZstdDecompressor()
        return ctx.decompress(data_bytes)
    else:
        return lz4.block.decompress(bytes(data_bytes), uncompressed_size=uncomp_len)

def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o+4
def rstr(d, o):
    n, o = ru32(d, o)
    return d[o:o+n].decode('utf-8','replace'), o+n

def read_chunk(data, offset):
    name = data[offset:offset+4].decode('latin-1')
    comp = struct.unpack_from('<I', data, offset+4)[0]
    uncomp = struct.unpack_from('<I', data, offset+8)[0]
    offset += 16
    if comp == 0:
        raw = bytes(data[offset:offset+uncomp]); offset += uncomp
    else:
        compressed = bytes(data[offset:offset+comp])
        raw = decompress_chunk(compressed, uncomp)
        offset += comp
    return name, raw, offset

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1, len(vals)): vals[i] += vals[i-1]
    return vals

with open(INFILE, 'rb') as f: data = bytearray(f.read())

magic = data[0:8]
print(f"Magic: {magic}")
num_types = struct.unpack_from('<I', data, 16)[0]
num_insts = struct.unpack_from('<I', data, 20)[0]
print(f"Types: {num_types}, Instances: {num_insts}")

offset = 32
inst_map = {}   # type_id -> (class_name, instance_ids)
prop_names = {} # type_id -> {referent -> name}
prop_sources = {} # type_id -> {referent -> source}
chunk_list = []

while offset < len(data):
    try:
        name, raw, new_offset = read_chunk(data, offset)
    except Exception as e:
        print(f"Error at offset {offset}: {e}")
        break
    chunk_list.append((name, offset))
    offset = new_offset

    if name == 'INST':
        o = 0
        tid, o = ru32(raw, o)
        cname, o = rstr(raw, o)
        is_svc = raw[o]; o += 1
        count, o = ru32(raw, o)
        ids = decode_refs(raw[o:o+count*4], count)
        inst_map[tid] = (cname, ids)

    elif name == 'PROP':
        o = 0
        tid, o = ru32(raw, o)
        pname, o = rstr(raw, o)
        dtype = raw[o]; o += 1
        if dtype == 0x01:  # string
            cname, ids = inst_map.get(tid, ('?', []))
            if cname in ('Script','LocalScript','ModuleScript') and pname in ('Name','Source'):
                strs = []
                for _ in ids:
                    slen, o = ru32(raw, o)
                    s = raw[o:o+slen].decode('utf-8','replace')
                    strs.append(s); o += slen
                if pname == 'Name':
                    prop_names[tid] = dict(zip(ids, strs))
                elif pname == 'Source':
                    prop_sources[tid] = dict(zip(ids, strs))

    if name == 'END\x00': break

print(f"\nChunks found: {len(chunk_list)}")
print(f"Chunk names: {[n for n,_ in chunk_list]}")
print(f"\n=== Scripts Found ===")
for tid, (cname, ids) in inst_map.items():
    if cname in ('Script','LocalScript','ModuleScript'):
        names = prop_names.get(tid, {})
        sources = prop_sources.get(tid, {})
        for ref in ids:
            sname = names.get(ref, f'<ref:{ref}>')
            src = sources.get(ref, '')
            print(f"  [{tid}] {cname} name={sname!r} src_len={len(src)} first80={src[:80]!r}")
