#!/usr/bin/env python3
"""Find instances by name in RBXL - look for FartButton, FartGUI, etc."""
import struct, zstandard, lz4.block

INFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl'
ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'

def decompress_chunk(data_bytes, uncomp_len):
    if len(data_bytes) >= 4 and data_bytes[:4] == ZSTD_MAGIC:
        return zstandard.ZstdDecompressor().decompress(data_bytes)
    return lz4.block.decompress(bytes(data_bytes), uncompressed_size=uncomp_len)

def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o+4
def rstr(d, o):
    n, o = ru32(d, o)
    return d[o:o+n].decode('utf-8','replace'), o+n

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1, len(vals)): vals[i] += vals[i-1]
    return vals

with open(INFILE, 'rb') as f: data = bytearray(f.read())
num_types = struct.unpack_from('<I', data, 16)[0]
num_insts = struct.unpack_from('<I', data, 20)[0]

offset = 32
inst_map = {}  # type_id -> (class_name, instance_ids)
all_names = {} # referent -> name
prnt_map = {}  # child_ref -> parent_ref

while offset < len(data):
    name_bytes = data[offset:offset+4]
    name = name_bytes.decode('latin-1')
    comp = struct.unpack_from('<I', data, offset+4)[0]
    uncomp = struct.unpack_from('<I', data, offset+8)[0]
    offset += 16
    if comp == 0:
        raw = bytes(data[offset:offset+uncomp]); offset += uncomp
    else:
        raw = decompress_chunk(bytes(data[offset:offset+comp]), uncomp); offset += comp

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
        if dtype == 0x01 and pname == 'Name':  # string Name
            _, ids = inst_map.get(tid, ('?', []))
            for ref in ids:
                slen, o = ru32(raw, o)
                s = raw[o:o+slen].decode('utf-8','replace')
                all_names[ref] = s
                o += slen

    elif name == 'PRNT':
        # Parent chunk: count, [child_ref, parent_ref, ...]
        o = 1  # skip version byte
        count, o = ru32(raw, o)
        children = decode_refs(raw[o:o+count*4], count); o += count*4
        parents  = decode_refs(raw[o:o+count*4], count)
        for c, p in zip(children, parents):
            prnt_map[c] = p

    if name == 'END\x00': break

# Build reverse name map: name -> list of referents
name_to_refs = {}
for ref, n in all_names.items():
    name_to_refs.setdefault(n, []).append(ref)

# Find FartButton, FartGUI, StarterGui related
keywords = ['fart', 'gui', 'button', 'shop', 'stand', 'player', 'stats']
print("Instances matching keywords:")
for ref, n in all_names.items():
    if any(k in n.lower() for k in keywords):
        # Find class
        cls = '?'
        for tid, (cname, ids) in inst_map.items():
            if ref in ids: cls = cname; break
        # Find parent chain
        chain = [n]
        cur = ref
        for _ in range(6):
            par = prnt_map.get(cur)
            if par is None or par == -1: break
            chain.insert(0, all_names.get(par, f'<{par}>'))
            cur = par
        print(f"  {cls}: {'/'.join(chain)}")
