#!/usr/bin/env python3
"""
Read Farttofloatdemo_v3.rbxl, print exact parent path of every script,
then fix gameclient and PlayerStats locations if wrong, save in place.
"""
import struct, zstandard, lz4.block

ZSTD = b'\x28\xb5\x2f\xfd'
FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'

# ---------------------------------------------------------------------------
def decomp(d, u):
    if len(d) >= 4 and d[:4] == ZSTD:
        return zstandard.ZstdDecompressor().decompress(d)
    return lz4.block.decompress(bytes(d), uncompressed_size=u) if u > 0 else bytes(d)

def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o + 4
def rstr(d, o):
    n, o = ru32(d, o); return d[o:o+n].decode('utf-8', 'replace'), o + n

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1, len(vals)): vals[i] += vals[i-1]
    return vals

def encode_refs(vals):
    if not vals: return b''
    count = len(vals)
    deltas = [vals[0]] + [vals[i]-vals[i-1] for i in range(1, count)]
    zz = [(-d*2-1) & 0xFFFFFFFF if d < 0 else (d*2) & 0xFFFFFFFF for d in deltas]
    result = bytearray(count * 4)
    for i, v in enumerate(zz):
        result[i]           = (v >> 24) & 0xFF
        result[count+i]     = (v >> 16) & 0xFF
        result[2*count+i]   = (v >>  8) & 0xFF
        result[3*count+i]   =  v        & 0xFF
    return bytes(result)

def write_unc(name, raw):
    nb = name.encode('latin-1')[:4].ljust(4, b'\x00')
    return nb + struct.pack('<III', 0, len(raw), 0) + raw

# ---------------------------------------------------------------------------
with open(FILE, 'rb') as f: data = bytearray(f.read())
header = bytes(data[:32])
print(f"File: {len(data):,} bytes\n")

chunks = []
offset = 32
while offset < len(data):
    nm    = data[offset:offset+4].decode('latin-1')
    comp  = struct.unpack_from('<I', data, offset+4)[0]
    uncomp= struct.unpack_from('<I', data, offset+8)[0]
    cs    = offset; offset += 16
    if comp == 0: raw = bytes(data[offset:offset+uncomp]); offset += uncomp
    else:         raw = decomp(bytes(data[offset:offset+comp]), uncomp); offset += comp
    orig = bytes(data[cs:offset])
    chunks.append({'name':nm, 'raw':raw, 'orig':orig, 'modified':False})
    if nm == 'END\x00': break

# ---------------------------------------------------------------------------
# Build inst_map: type_id -> (class_name, [refs])
inst_map = {}
for ch in chunks:
    if ch['name'] != 'INST': continue
    raw = ch['raw']; o = 0
    tid, o = ru32(raw, o); cname, o = rstr(raw, o); o += 1
    cnt, o = ru32(raw, o)
    refs = decode_refs(raw[o:o+cnt*4], cnt)
    inst_map[tid] = (cname, refs)

# ref_class: ref -> class_name
ref_class = {}
for tid, (cname, refs) in inst_map.items():
    for r in refs: ref_class[r] = cname

# Build PRNT map: child_ref -> parent_ref
prnt = {}
prnt_chunk_idx = None
for idx, ch in enumerate(chunks):
    if ch['name'] != 'PRNT': continue
    raw = ch['raw']; ver = raw[0]
    count = struct.unpack_from('<I', raw, 1)[0]
    cr = decode_refs(raw[5          : 5+count*4], count)
    pr = decode_refs(raw[5+count*4  : 5+count*8], count)
    prnt = dict(zip(cr, pr))
    prnt_chunk_idx = idx
    prnt_ver = ver; prnt_count = count
    prnt_children = cr; prnt_parents = pr
    break

# Build name map: ref -> instance name (from Name PROP)
ref_name = {}
for ch in chunks:
    if ch['name'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid, o = ru32(raw, o); pn, o = rstr(raw, o); dt = raw[o]; o += 1
    if pn != 'Name' or dt != 0x01: continue
    _, refs = inst_map.get(tid, ('?', []))
    for ref in refs:
        slen, o = ru32(raw, o); ref_name[ref] = raw[o:o+slen].decode('utf-8','replace'); o += slen

def get_path(ref):
    """Walk parent chain and return list of (ref, name_or_class) from root to ref."""
    path = []
    r = ref
    visited = set()
    while r != -1 and r not in visited:
        visited.add(r)
        n = ref_name.get(r) or ('['+ref_class.get(r,'?')+']')
        path.append((r, n))
        r = prnt.get(r, -1)
    path.reverse()
    return path

def path_str(ref):
    return ' > '.join(n for _, n in get_path(ref))

# ---------------------------------------------------------------------------
# Print path of every script
script_classes = {'LocalScript', 'Script', 'ModuleScript'}
script_refs = {}
for ch in chunks:
    if ch['name'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid, o = ru32(raw, o); pn, o = rstr(raw, o); dt = raw[o]; o += 1
    if pn != 'Name' or dt != 0x01: continue
    cname, refs = inst_map.get(tid, ('?', []))
    if cname not in script_classes: continue
    for ref in refs:
        slen, o = ru32(raw, o); nm = raw[o:o+slen].decode('utf-8','replace'); o += slen
        script_refs[ref] = (cname, nm)

print("=" * 70)
print("SCRIPT LOCATIONS IN FILE:")
print("=" * 70)
for ref, (cls, nm) in sorted(script_refs.items(), key=lambda x: x[1][1]):
    p = path_str(ref)
    ok = ""
    if nm == 'gameclient':
        ok = "  [OK]" if 'StarterPlayerScripts' in p else "  [WRONG - needs StarterPlayerScripts]"
    elif nm == 'PlayerStats':
        ok = "  [OK]" if 'ServerScriptService' in p else "  [WRONG - needs ServerScriptService]"
    print(f"  [{cls}] {nm!r}{ok}")
    print(f"    ref={ref}")
    print(f"    path: {p}")
print()

# ---------------------------------------------------------------------------
# Find target container refs
def find_ref_by_name_and_class(name, cls):
    for ref, (c, n) in {r: (ref_class.get(r,'?'), ref_name.get(r,'')) for r in ref_name}.items():
        if n == name and c == cls:
            return ref
    return None

def find_ref_by_class(cls):
    for tid, (cname, refs) in inst_map.items():
        if cname == cls and refs: return refs[0]
    return None

sps_ref = find_ref_by_class('StarterPlayerScripts')
sss_ref = find_ref_by_class('ServerScriptService')

print(f"StarterPlayerScripts ref = {sps_ref}  path: {path_str(sps_ref) if sps_ref else 'NOT FOUND'}")
print(f"ServerScriptService  ref = {sss_ref}  path: {path_str(sss_ref) if sss_ref else 'NOT FOUND'}")
print()

# ---------------------------------------------------------------------------
# Fix PRNT if needed
fixes_needed = []
for ref, (cls, nm) in script_refs.items():
    if nm == 'gameclient':
        cur_parent = prnt.get(ref, -1)
        if cur_parent != sps_ref:
            fixes_needed.append((ref, nm, cur_parent, sps_ref, 'StarterPlayerScripts'))
    elif nm == 'PlayerStats':
        cur_parent = prnt.get(ref, -1)
        if cur_parent != sss_ref:
            fixes_needed.append((ref, nm, cur_parent, sss_ref, 'ServerScriptService'))

if not fixes_needed:
    print("All script locations are CORRECT. No PRNT changes needed.")
else:
    print("FIXING parent assignments:")
    for ref, nm, old, new, label in fixes_needed:
        idx_in_prnt = prnt_children.index(ref)
        prnt_parents[idx_in_prnt] = new
        old_path = path_str(old) if old != -1 else 'ROOT'
        print(f"  {nm!r}: parent {old}({old_path}) -> {new}({label})")

    # Rebuild PRNT chunk
    new_prnt_raw = bytes([prnt_ver]) + struct.pack('<I', prnt_count) + \
                   encode_refs(prnt_children) + encode_refs(prnt_parents)
    chunks[prnt_chunk_idx]['raw'] = new_prnt_raw
    chunks[prnt_chunk_idx]['modified'] = True

# ---------------------------------------------------------------------------
# Write output
out = bytearray(header)
for ch in chunks:
    if ch['modified']: out += write_unc(ch['name'], ch['raw'])
    else:              out += ch['orig']

with open(FILE, 'wb') as f: f.write(out)
print(f"\nSaved: {len(out):,} bytes -> {FILE}")

# ---------------------------------------------------------------------------
# Final report: re-read and print paths
print()
print("=" * 70)
print("FINAL VERIFIED PATHS (re-read from saved file):")
print("=" * 70)
with open(FILE, 'rb') as f: data2 = bytearray(f.read())
offset = 32; im2 = {}; prnt2 = {}; rn2 = {}; rc2 = {}
while offset < len(data2):
    nm = data2[offset:offset+4].decode('latin-1')
    comp = struct.unpack_from('<I',data2,offset+4)[0]; uncomp=struct.unpack_from('<I',data2,offset+8)[0]
    offset += 16
    if comp==0: raw=bytes(data2[offset:offset+uncomp]); offset+=uncomp
    else: raw=decomp(bytes(data2[offset:offset+comp]),uncomp); offset+=comp
    if nm=='INST':
        o=0; tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); im2[tid]=(cn,refs)
        for r in refs: rc2[r]=cn
    elif nm=='PROP':
        o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        if pn=='Name' and dt==0x01:
            _,refs=im2.get(tid,('?',[]))
            for ref in refs:
                sl,o=ru32(raw,o); rn2[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    elif nm=='PRNT':
        ver=raw[0]; cnt=struct.unpack_from('<I',raw,1)[0]
        cr2=decode_refs(raw[5:5+cnt*4],cnt); pr2=decode_refs(raw[5+cnt*4:5+cnt*8],cnt)
        prnt2=dict(zip(cr2,pr2))
    if nm=='END\x00': break

def get_path2(ref):
    path=[]; r=ref; visited=set()
    while r!=-1 and r not in visited:
        visited.add(r); n=rn2.get(r) or ('['+rc2.get(r,'?')+']'); path.append(n); r=prnt2.get(r,-1)
    path.reverse(); return ' > '.join(path)

for ref,(cls,nm) in sorted(script_refs.items(), key=lambda x: x[1][1]):
    print(f"  [{cls}] {nm!r}")
    print(f"    {get_path2(ref)}")
