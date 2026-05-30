#!/usr/bin/env python3
import struct, zstandard, lz4.block, hashlib

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'

def decompress(d, u):
    if len(d)>=4 and d[:4]==ZSTD_MAGIC:
        return zstandard.ZstdDecompressor().decompress(d)
    if u > 0:
        return lz4.block.decompress(bytes(d), uncompressed_size=u)
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

def get_scripts(filepath):
    with open(filepath,'rb') as f: data=bytearray(f.read())
    offset=32; inst_map={}; names={}; sources={}
    while offset<len(data):
        nm=data[offset:offset+4].decode('latin-1')
        comp=struct.unpack_from('<I',data,offset+4)[0]
        uncomp=struct.unpack_from('<I',data,offset+8)[0]
        offset+=16
        if comp==0: raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
        else: raw=decompress(bytes(data[offset:offset+comp]),uncomp); offset+=comp
        if nm=='INST':
            o=0; tid,o=ru32(raw,o); cname,o=rstr(raw,o); o+=1
            count,o=ru32(raw,o); ids=decode_refs(raw[o:o+count*4],count)
            inst_map[tid]=(cname,ids)
        elif nm=='PROP':
            o=0; tid,o=ru32(raw,o); pname,o=rstr(raw,o); dtype=raw[o]; o+=1
            if dtype==0x01:
                cname,ids=inst_map.get(tid,('?',[]))
                if cname in ('Script','LocalScript','ModuleScript') and pname in ('Name','Source'):
                    strs=[]
                    for _ in ids:
                        slen,o=ru32(raw,o); s=raw[o:o+slen].decode('utf-8','replace')
                        strs.append(s); o+=slen
                    d=dict(zip(ids,strs))
                    if pname=='Name':
                        for ref,n in d.items(): names[ref]=(cname,n)
                    elif pname=='Source':
                        sources.update(d)
        if nm=='END\x00': break
    result={}
    for ref,(cls,n) in names.items():
        result[n]={'class':cls,'source':sources.get(ref,'<NO SOURCE>'), 'ref':ref}
    return result

print("="*70)
print("ORIGINAL: fart2floatbuild.rbxl")
orig = get_scripts(r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl')
for n,d in sorted(orig.items()):
    h = hashlib.md5(d['source'].encode()).hexdigest()[:8]
    print(f"  [{d['class']}] {n}: len={len(d['source'])} md5={h}")
    print(f"    first80: {d['source'][:80]!r}")

print("\n"+"="*70)
print("V3: Farttofloatdemo_v3.rbxl")
v3 = get_scripts(r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl')
for n,d in sorted(v3.items()):
    h = hashlib.md5(d['source'].encode()).hexdigest()[:8]
    print(f"  [{d['class']}] {n}: len={len(d['source'])} md5={h}")
    print(f"    first80: {d['source'][:80]!r}")

print("\n"+"="*70)
print("DIFF:")
all_names = set(list(orig.keys())+list(v3.keys()))
for n in sorted(all_names):
    o_src = orig.get(n,{}).get('source','<MISSING>')
    v_src = v3.get(n,{}).get('source','<MISSING>')
    if o_src == v_src:
        print(f"  UNCHANGED: {n}")
    else:
        print(f"  CHANGED:   {n} ({len(o_src)} -> {len(v_src)} chars)")
        print(f"    ORIG first50: {o_src[:50]!r}")
        print(f"    V3   first50: {v_src[:50]!r}")
