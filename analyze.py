#!/usr/bin/env python3
import struct
try:
    import zstandard as zstd; HAS_ZSTD=True
except: HAS_ZSTD=False
try:
    import lz4.block; HAS_LZ4=True
except: HAS_LZ4=False

ZSTD_MAGIC=b'\x28\xb5\x2f\xfd'
FILE=r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'

def decomp(d,u):
    if len(d)>=4 and d[:4]==ZSTD_MAGIC and HAS_ZSTD: return zstd.ZstdDecompressor().decompress(d)
    if HAS_LZ4 and u>0: return lz4.block.decompress(bytes(d),uncompressed_size=u)
    return bytes(d)
def ru32(d,o): return struct.unpack_from('<I',d,o)[0],o+4
def rstr(d,o):
    n,o=ru32(d,o); return d[o:o+n].decode('utf-8','replace'),o+n
def decode_refs(data,count):
    vals=[]
    for i in range(count):
        v=(data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1,len(vals)): vals[i]+=vals[i-1]
    return vals

with open(FILE,'rb') as f: raw=bytearray(f.read())
chunks=[]; o=32
while o<len(raw):
    nm=bytes(raw[o:o+4]).decode('latin-1')
    comp=struct.unpack_from('<I',raw,o+4)[0]; uncomp=struct.unpack_from('<I',raw,o+8)[0]
    o+=16
    if comp==0: body=bytes(raw[o:o+uncomp]); o+=uncomp
    else: body=decomp(bytes(raw[o:o+comp]),uncomp); o+=comp
    chunks.append({'nm':nm,'raw':body})
    if nm=='END\x00': break

inst_map={}
for ch in chunks:
    if ch['nm']!='INST': continue
    r=ch['raw']; o=0
    tid,o=ru32(r,o); cn,o=rstr(r,o); svc=r[o]; o+=1; cnt,o=ru32(r,o)
    refs=decode_refs(r[o:o+cnt*4],cnt)
    inst_map[tid]=(cn,refs,svc)

ref_name={}
for ch in chunks:
    if ch['nm']!='PROP': continue
    r=ch['raw']; o=0
    tid,o=ru32(r,o); pn,o=rstr(r,o); dt=r[o]; o+=1
    if pn!='Name' or dt!=1: continue
    if tid not in inst_map: continue
    for ref in inst_map[tid][1]:
        sl,o=ru32(r,o); ref_name[ref]=r[o:o+sl].decode('utf-8','replace'); o+=sl

prnt_pairs=[]
for ch in chunks:
    if ch['nm']!='PRNT': continue
    r=ch['raw']; o=0; ver=r[o]; o+=1
    cnt=struct.unpack_from('<I',r,o)[0]; o+=4
    kids=decode_refs(r[o:o+cnt*4],cnt); o+=cnt*4
    pars=decode_refs(r[o:o+cnt*4],cnt)
    prnt_pairs=list(zip(kids,pars)); break

SCRIPTS={'Script','LocalScript','ModuleScript'}
print("=== SCRIPT INSTANCES ===")
for tid,(cn,refs,svc) in sorted(inst_map.items()):
    if cn not in SCRIPTS: continue
    print(f"\n{cn} type_id={tid} count={len(refs)}")
    for ref in refs:
        nm=ref_name.get(ref,'?'); par=next((p for c,p in prnt_pairs if c==ref),None)
        print(f"  ref={ref} name={nm!r} parent_ref={par} parent_name={ref_name.get(par,'?')!r}")

print("\n=== LocalScript PROP CHUNKS ===")
ls_tid=next((t for t,(cn,_,__) in inst_map.items() if cn=='LocalScript'),None)
if ls_tid:
    ls_count=len(inst_map[ls_tid][1])
    for ch in chunks:
        if ch['nm']!='PROP': continue
        r=ch['raw']; o=0
        tid,o=ru32(r,o); pn,o=rstr(r,o); dt=r[o]; o+=1
        if tid!=ls_tid: continue
        remaining=len(r)-o
        print(f"  prop={pn!r} dtype=0x{dt:02x} value_bytes={remaining} (for {ls_count} instances)")
        if pn=='Name' and dt==1:
            oo=o
            for i,ref in enumerate(inst_map[ls_tid][1]):
                sl,oo=ru32(r,oo); print(f"    [{i}] ref={ref}: {r[oo:oo+sl].decode('utf-8','replace')!r}"); oo+=sl

print("\n=== MAX REF ===")
all_refs=[ref for (cn,refs,svc) in inst_map.values() for ref in refs]
print(f"  max_ref={max(all_refs)}")

print("\n=== StarterPlayerScripts CHILDREN ===")
sps_tid=next((t for t,(cn,_,__) in inst_map.items() if cn=='StarterPlayerScripts'),None)
if sps_tid:
    for ref in inst_map[sps_tid][1]:
        print(f"  SPS ref={ref} name={ref_name.get(ref,'?')!r}")
        kids=[c for c,p in prnt_pairs if p==ref]
        for k in kids: print(f"    child ref={k} name={ref_name.get(k,'?')!r} class={next((cn for (cn,refs,__) in inst_map.values() if k in refs),'?')}")
