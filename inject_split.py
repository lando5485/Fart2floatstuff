#!/usr/bin/env python3
"""Add ShopClient/WorldClient/EventClient LocalScripts to .rbxl and rename gameclient->CoreClient."""
import struct, os, random, uuid

try:
    import zstandard; HAS_ZSTD=True
except ImportError: HAS_ZSTD=False
try:
    import lz4.block; HAS_LZ4=True
except ImportError: HAS_LZ4=False

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'
FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
DUMP = r'C:\Users\lando\Downloads\Fart2floatstuff\scripts_dump'

# CoreClient replaces gameclient (ref=8603); new scripts get refs 8968/8969/8970
NEW_REFS = [8968, 8969, 8970]
NEW_NAMES = ['ShopClient', 'WorldClient', 'EventClient']
SPS_REF = 8602  # StarterPlayerScripts

SCRIPT_FILES = {
    'CoreClient':  os.path.join(DUMP, 'CoreClient.lua'),
    'ShopClient':  os.path.join(DUMP, 'ShopClient.lua'),
    'WorldClient': os.path.join(DUMP, 'WorldClient.lua'),
    'EventClient': os.path.join(DUMP, 'EventClient.lua'),
}

def decomp(d, u):
    if len(d)>=4 and d[:4]==ZSTD_MAGIC and HAS_ZSTD: return zstandard.ZstdDecompressor().decompress(d)
    if HAS_LZ4 and u>0: return lz4.block.decompress(bytes(d), uncompressed_size=u)
    return bytes(d)

def ru32(d,o): return struct.unpack_from('<I',d,o)[0], o+4
def wu32(v): return struct.pack('<I',v)
def rstr(d,o):
    n,o=ru32(d,o); return d[o:o+n].decode('utf-8','replace'), o+n

def decode_refs(data, count):
    vals=[]
    for i in range(count):
        v=(data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1,len(vals)): vals[i]+=vals[i-1]
    return vals

def encode_refs(vals):
    delta=[vals[0]]+[vals[i]-vals[i-1] for i in range(1,len(vals))]
    zz=[(-v*2-1 if v<0 else v*2) for v in delta]
    count=len(zz); result=bytearray(count*4)
    for i,v in enumerate(zz):
        result[i]=(v>>24)&0xFF; result[count+i]=(v>>16)&0xFF; result[2*count+i]=(v>>8)&0xFF; result[3*count+i]=v&0xFF
    return bytes(result)

def deinterleave4(data, count):
    return [bytes([data[i],data[count+i],data[2*count+i],data[3*count+i]]) for i in range(count)]

def reinterleave4(vals):
    count=len(vals); result=bytearray(count*4)
    for i,v in enumerate(vals):
        result[i]=v[0]; result[count+i]=v[1]; result[2*count+i]=v[2]; result[3*count+i]=v[3]
    return bytes(result)

def deinterleave8(data, count):
    return [bytes([data[j*count+i] for j in range(8)]) for i in range(count)]

def reinterleave8(vals):
    count=len(vals); result=bytearray(count*8)
    for i,v in enumerate(vals):
        for j in range(8): result[j*count+i]=v[j]
    return bytes(result)

def write_unc(nm_bytes, raw):
    return nm_bytes + struct.pack('<III', 0, len(raw), 0) + raw

def make_guid():
    return ('{'+str(uuid.uuid4()).upper()+'}').encode('utf-8')

print(f"Reading {FILE} ...")
with open(FILE,'rb') as f: data=bytearray(f.read())
print(f"  Size: {len(data):,} bytes")

header=bytes(data[:32]); chunks=[]; offset=32
while offset<len(data):
    nm_bytes=bytes(data[offset:offset+4]); nm=nm_bytes.decode('latin-1')
    comp=struct.unpack_from('<I',data,offset+4)[0]; uncomp=struct.unpack_from('<I',data,offset+8)[0]
    cs=offset; offset+=16
    if comp==0: raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
    else: raw=decomp(bytes(data[offset:offset+comp]),uncomp); offset+=comp
    orig=bytes(data[cs:offset])
    chunks.append({'nm':nm,'nm_bytes':nm_bytes,'raw':bytearray(raw),'orig':orig,'modified':False})
    if nm=='END\x00': break
print(f"  Parsed {len(chunks)} chunks")

# Load Lua sources
sources={}
for name,path in SCRIPT_FILES.items():
    sources[name]=open(path,'r',encoding='utf-8').read().encode('utf-8')
    print(f"  Loaded {name}: {len(sources[name]):,} bytes")

# Build inst_map from INST chunks
inst_map={}
for ch in chunks:
    if ch['nm']!='INST': continue
    raw=bytes(ch['raw']); o=0
    tid,o=ru32(raw,o); cname,o=rstr(raw,o); svc=raw[o]; o+=1
    count,o=ru32(raw,o); refs=decode_refs(raw[o:o+count*4],count)
    inst_map[tid]=(cname,refs,svc)

ls_tid=next((t for t,(cn,_,__) in inst_map.items() if cn=='LocalScript'),None)
old_refs=inst_map[ls_tid][1]
print(f"  LocalScript tid={ls_tid}, old_refs={old_refs}")

# Parse existing Name PROP to map ref->name
old_names={}
for ch in chunks:
    if ch['nm']!='PROP': continue
    raw=bytes(ch['raw']); o=0
    tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if tid!=ls_tid or pn!='Name' or dt!=0x01: continue
    for ref in old_refs:
        sl,o=ru32(raw,o); old_names[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    break
print(f"  Old names: {old_names}")

gameclient_ref=next((r for r,n in old_names.items() if n=='gameclient'),None)
print(f"  Gameclient ref: {gameclient_ref}")

# New full ref list and name list (old order preserved)
all_refs=old_refs+NEW_REFS
new_names_map={ref: old_names.get(ref,None) for ref in old_refs}
if gameclient_ref: new_names_map[gameclient_ref]='CoreClient'
for ref,name in zip(NEW_REFS,NEW_NAMES): new_names_map[ref]=name

# Ordered name list matching all_refs order
all_names=[new_names_map[r] for r in all_refs]
print(f"  New names: {all_names}")

n_old=len(old_refs); n_new=len(NEW_REFS); n_total=n_old+n_new

# === Modify INST chunk ===
for ch in chunks:
    if ch['nm']!='INST': continue
    raw=bytes(ch['raw']); o=0
    tid,o=ru32(raw,o); cname,o=rstr(raw,o)
    if cname!='LocalScript': continue
    svc=raw[o]; o+=1; count_old,o=ru32(raw,o)
    new_raw=bytearray()
    new_raw+=wu32(tid)
    cb=cname.encode('utf-8'); new_raw+=wu32(len(cb))+cb
    new_raw+=bytes([svc]); new_raw+=wu32(n_total); new_raw+=encode_refs(all_refs)
    ch['raw']=bytes(new_raw); ch['modified']=True
    print(f"  INST modified: {count_old} -> {n_total} refs")
    break

# === Modify PRNT chunk ===
for ch in chunks:
    if ch['nm']!='PRNT': continue
    raw=bytes(ch['raw']); o=0
    ver=raw[o]; o+=1; cnt=struct.unpack_from('<I',raw,o)[0]; o+=4
    kids=decode_refs(raw[o:o+cnt*4],cnt); o+=cnt*4
    pars=decode_refs(raw[o:o+cnt*4],cnt)
    kids_new=kids+NEW_REFS; pars_new=pars+[SPS_REF]*n_new; cnt_new=len(kids_new)
    new_raw=bytearray([ver])+struct.pack('<I',cnt_new)+encode_refs(kids_new)+encode_refs(pars_new)
    ch['raw']=bytes(new_raw); ch['modified']=True
    print(f"  PRNT modified: {cnt} -> {cnt_new} pairs")
    break

# === Modify PROP chunks for LocalScript ===
for ch in chunks:
    if ch['nm']!='PROP': continue
    raw=bytes(ch['raw']); o=0
    tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if tid!=ls_tid: continue

    pn_b=pn.encode('utf-8')
    hdr=wu32(tid)+wu32(len(pn_b))+pn_b+bytes([dt])

    if dt==0x01:  # String
        # Parse existing strings
        old_strs=[]; oo=o
        for _ in old_refs:
            sl,oo=ru32(raw,oo); old_strs.append(raw[oo:oo+sl]); oo+=sl

        new_raw=bytearray(hdr)
        if pn=='Name':
            for name in all_names:
                nb=name.encode('utf-8'); new_raw+=wu32(len(nb))+nb
        elif pn=='Source':
            # Replace gameclient source; keep others; append new
            for i,ref in enumerate(old_refs):
                if ref==gameclient_ref:
                    s=sources['CoreClient']; new_raw+=wu32(len(s))+s
                else:
                    new_raw+=wu32(len(old_strs[i]))+old_strs[i]
            for name in NEW_NAMES:
                s=sources[name]; new_raw+=wu32(len(s))+s
        elif pn=='ScriptGuid':
            for s in old_strs: new_raw+=wu32(len(s))+s
            for _ in NEW_REFS: g=make_guid(); new_raw+=wu32(len(g))+g
        else:
            for s in old_strs: new_raw+=wu32(len(s))+s
            for _ in NEW_REFS: new_raw+=wu32(0)
        ch['raw']=bytes(new_raw); ch['modified']=True

    elif dt==0x02:  # Bool (1 byte per instance)
        new_raw=bytearray(hdr)+raw[o:]+bytes(n_new)
        ch['raw']=bytes(new_raw); ch['modified']=True

    elif dt==0x12:  # 4-byte interleaved enum/int32
        vals=deinterleave4(raw[o:],n_old)+[b'\x00\x00\x00\x00']*n_new
        ch['raw']=bytes(bytearray(hdr)+reinterleave4(vals)); ch['modified']=True

    elif dt==0x1b:  # 8-byte interleaved int64
        vals=deinterleave8(raw[o:],n_old)+[b'\x00\x00\x00\x00\x00\x00\x00\x00']*n_new
        ch['raw']=bytes(bytearray(hdr)+reinterleave8(vals)); ch['modified']=True

    elif dt==0x1f:  # UniqueId (16 bytes sequential)
        extra=b''.join(bytes([random.randint(0,255) for _ in range(16)]) for _ in NEW_REFS)
        ch['raw']=bytes(bytearray(hdr)+raw[o:]+extra); ch['modified']=True

    elif dt==0x21:  # Capabilities (8 bytes sequential)
        ch['raw']=bytes(bytearray(hdr)+raw[o:]+bytes(8*n_new)); ch['modified']=True

    else:
        print(f"  UNHANDLED prop={pn!r} dt=0x{dt:02x} - left as-is")

# Write output
out=bytearray(header)
mod_count=0
for ch in chunks:
    if ch['modified']: out+=write_unc(ch['nm_bytes'],ch['raw']); mod_count+=1
    else: out+=ch['orig']

with open(FILE,'wb') as f: f.write(out)
print(f"\nModified {mod_count} chunks")
print(f"Saved: {len(out):,} bytes -> {FILE}")
print("\nSPLIT COMPLETE")
