#!/usr/bin/env python3
"""
Apply v3 changes - write modified chunks UNCOMPRESSED to avoid zstd param mismatch.
Modified PROP chunks: comp_len=0, uncomp_len=len(raw), data=raw bytes.
All other chunks: exact original bytes preserved.
"""
import sys, os, struct
sys.path.insert(0, r'C:\Users\lando\Downloads\Fart2floatstuff')

import zstandard, lz4.block
from sources_server import GAMESERVER_SOURCE, PLAYERSTATS_SOURCE
from sources_client import GAMECLIENT_SOURCE

INFILE  = r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl'
OUTFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'

# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------
def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o+4
def rstr(d, o):
    n, o = ru32(d, o)
    return d[o:o+n].decode('utf-8', 'replace'), o+n

def decompress(d, u):
    if len(d) >= 4 and d[:4] == ZSTD_MAGIC:
        return zstandard.ZstdDecompressor().decompress(d)
    if u > 0:
        return lz4.block.decompress(bytes(d), uncompressed_size=u)
    return bytes(d)

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1, len(vals)):
        vals[i] += vals[i-1]
    return vals

def write_chunk_uncompressed(name, raw_bytes):
    """Write a chunk with comp_len=0 (uncompressed). Always valid per RBXL spec."""
    name_b = name.encode('latin-1')[:4].ljust(4, b'\x00')
    return name_b + struct.pack('<III', 0, len(raw_bytes), 0) + raw_bytes

def encode_prop_source(type_id, inst_ids, old_strings, new_source_by_ref):
    """Rebuild a Source PROP chunk raw with modified sources."""
    result = bytearray()
    result += struct.pack('<I', type_id)
    prop_name = b'Source'
    result += struct.pack('<I', len(prop_name)) + prop_name
    result += bytes([0x01])  # string type
    for i, ref in enumerate(inst_ids):
        if ref in new_source_by_ref:
            s = new_source_by_ref[ref].encode('utf-8')
        else:
            s = old_strings[i]
        result += struct.pack('<I', len(s)) + s
    return bytes(result)

# ---------------------------------------------------------------------------
# Parse original file into chunks
# ---------------------------------------------------------------------------
print(f"Reading {INFILE} ...")
with open(INFILE, 'rb') as f:
    filedata = bytearray(f.read())

header = bytes(filedata[0:32])
print(f"Header: magic={filedata[0:8]}, num_types={struct.unpack_from('<I',filedata,16)[0]}, num_insts={struct.unpack_from('<I',filedata,20)[0]}")

# Each entry: (offset_in_file, chunk_name, comp_len, uncomp_len, raw_data)
chunks = []
offset = 32
while offset < len(filedata):
    name = filedata[offset:offset+4].decode('latin-1')
    comp  = struct.unpack_from('<I', filedata, offset+4)[0]
    uncomp= struct.unpack_from('<I', filedata, offset+8)[0]
    chunk_start = offset
    offset += 16
    if comp == 0:
        raw = bytes(filedata[offset:offset+uncomp]); offset += uncomp
    else:
        raw = decompress(bytes(filedata[offset:offset+comp]), uncomp); offset += comp
    orig_bytes = bytes(filedata[chunk_start:offset])
    chunks.append({'name':name,'comp':comp,'uncomp':uncomp,'raw':raw,'orig':orig_bytes,'modified':False})
    if name == 'END\x00': break

print(f"Parsed {len(chunks)} chunks")

# ---------------------------------------------------------------------------
# Build instance type map
# ---------------------------------------------------------------------------
inst_map = {}  # type_id -> (class_name, [refs])
for ch in chunks:
    if ch['name'] != 'INST': continue
    raw = ch['raw']; o = 0
    tid,  o = ru32(raw, o)
    cname,o = rstr(raw, o)
    o += 1  # is_service
    count, o = ru32(raw, o)
    refs = decode_refs(raw[o:o+count*4], count)
    inst_map[tid] = (cname, refs)

# Build name map for scripts
script_names = {}  # ref -> name
for ch in chunks:
    if ch['name'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid,  o = ru32(raw, o)
    pname,o = rstr(raw, o)
    dtype = raw[o]; o += 1
    if dtype != 0x01 or pname != 'Name': continue
    cname, refs = inst_map.get(tid, ('?', []))
    if cname not in ('Script','LocalScript'): continue
    for ref in refs:
        slen, o = ru32(raw, o)
        script_names[ref] = raw[o:o+slen].decode('utf-8','replace')
        o += slen

print("Scripts found:")
for ref, name in sorted(script_names.items(), key=lambda x: x[1]):
    cname = next((c for tid,(c,refs) in inst_map.items() if ref in refs), '?')
    print(f"  ref={ref} [{cname}] {name}")

# Resolve target refs
name_to_ref = {v:k for k,v in script_names.items()}
ref_gameserver  = name_to_ref.get('gameserver')
ref_gameclient  = name_to_ref.get('gameclient')
ref_playerstats = name_to_ref.get('PlayerStats')
print(f"\nTargets: gameserver={ref_gameserver}, gameclient={ref_gameclient}, PlayerStats={ref_playerstats}")

new_sources = {}
if ref_gameserver:  new_sources[ref_gameserver]  = GAMESERVER_SOURCE
if ref_gameclient:  new_sources[ref_gameclient]  = GAMECLIENT_SOURCE
if ref_playerstats: new_sources[ref_playerstats] = PLAYERSTATS_SOURCE

# ---------------------------------------------------------------------------
# Modify Source PROP chunks in-place
# ---------------------------------------------------------------------------
modified = 0
for ch in chunks:
    if ch['name'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid,  o = ru32(raw, o)
    pname,o = rstr(raw, o)
    dtype = raw[o]
    if pname != 'Source' or dtype != 0x01: continue
    cname, refs = inst_map.get(tid, ('?',[]))
    if cname not in ('Script','LocalScript'): continue
    if not any(r in new_sources for r in refs): continue

    # Read existing strings
    o2 = o + 1
    old_strs = []
    for _ in refs:
        slen, o2 = ru32(raw, o2)
        old_strs.append(raw[o2:o2+slen]); o2 += slen

    # Build new raw
    new_raw = encode_prop_source(tid, refs, old_strs, new_sources)
    ch['raw']      = new_raw
    ch['modified'] = True
    ch['comp']     = -1  # will be written uncompressed
    modified += 1

    for ref in refs:
        if ref in new_sources:
            print(f"  Modified Source for '{script_names.get(ref,'?')}' ref={ref}: {len(new_sources[ref])} chars")

print(f"\nModified {modified} PROP Source chunk(s)")

# ---------------------------------------------------------------------------
# Write output — modified chunks uncompressed, rest verbatim
# ---------------------------------------------------------------------------
print(f"Writing {OUTFILE} ...")
out = bytearray(header)
for ch in chunks:
    if ch['modified']:
        out += write_chunk_uncompressed(ch['name'], ch['raw'])
    else:
        out += ch['orig']

with open(OUTFILE, 'wb') as f:
    f.write(out)

size_in  = os.path.getsize(INFILE)
size_out = os.path.getsize(OUTFILE)
print(f"Input:  {size_in:,} bytes")
print(f"Output: {size_out:,} bytes")

# ---------------------------------------------------------------------------
# Quick verify: re-read and confirm changed sources
# ---------------------------------------------------------------------------
print("\nVerifying...")
with open(OUTFILE,'rb') as f: vdata = bytearray(f.read())
voffset = 32; vinst={}; vnames={}; vsrcs={}
while voffset < len(vdata):
    nm = vdata[voffset:voffset+4].decode('latin-1')
    vc = struct.unpack_from('<I',vdata,voffset+4)[0]
    vu = struct.unpack_from('<I',vdata,voffset+8)[0]
    voffset += 16
    if vc==0: vraw=bytes(vdata[voffset:voffset+vu]); voffset+=vu
    else: vraw=decompress(bytes(vdata[voffset:voffset+vc]),vu); voffset+=vc
    if nm=='INST':
        o=0; t,o=ru32(vraw,o); cn,o=rstr(vraw,o); o+=1; cnt,o=ru32(vraw,o)
        vinst[t]=(cn,decode_refs(vraw[o:o+cnt*4],cnt))
    elif nm=='PROP':
        o=0; t,o=ru32(vraw,o); pn,o=rstr(vraw,o); dt=vraw[o]; o+=1
        if dt==0x01:
            cn,refs=vinst.get(t,('?',[]))
            if cn in ('Script','LocalScript') and pn in ('Name','Source'):
                strs=[]
                for _ in refs:
                    sl,o=ru32(vraw,o); strs.append(vraw[o:o+sl].decode('utf-8','replace')); o+=sl
                d=dict(zip(refs,strs))
                if pn=='Name': vnames[t]=d
                elif pn=='Source': vsrcs[t]=d
    if nm=='END\x00': break

print("\nScript sources in output file:")
for t,(cn,refs) in vinst.items():
    if cn not in ('Script','LocalScript'): continue
    for ref in refs:
        name = vnames.get(t,{}).get(ref,'?')
        src  = vsrcs.get(t,{}).get(ref,'<none>')
        first = src.split('\n')[0][:60]
        print(f"  [{cn}] {name}: {len(src)} chars | {first!r}")

print("\nV3 COMPLETE")
