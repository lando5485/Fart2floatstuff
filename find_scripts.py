#!/usr/bin/env python3
import struct, zstandard, lz4.block

INFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl'
ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'

def decompress(d, u):
    if len(d)>=4 and d[:4]==ZSTD_MAGIC: return zstandard.ZstdDecompressor().decompress(d)
    return lz4.block.decompress(bytes(d), uncompressed_size=u)

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

with open(INFILE,'rb') as f: data=bytearray(f.read())
offset=32
inst_map={}; all_names={}; prnt_map={}; ref_to_class={}

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
        for ref in ids: ref_to_class[ref]=cname

    elif nm=='PROP':
        o=0; tid,o=ru32(raw,o); pname,o=rstr(raw,o); dtype=raw[o]; o+=1
        if dtype==0x01 and pname=='Name':
            _,ids=inst_map.get(tid,('?',[]))
            for ref in ids:
                slen,o=ru32(raw,o); s=raw[o:o+slen].decode('utf-8','replace')
                all_names[ref]=s; o+=slen

    elif nm=='PRNT':
        o=1; count,o=ru32(raw,o)
        children=decode_refs(raw[o:o+count*4],count); o+=count*4
        parents=decode_refs(raw[o:o+count*4],count)
        for c,p in zip(children,parents): prnt_map[c]=p

    if nm=='END\x00': break

def get_path(ref):
    chain=[all_names.get(ref,f'<{ref}>')]
    cur=ref
    for _ in range(10):
        par=prnt_map.get(cur)
        if par is None or par==-1: break
        chain.insert(0,all_names.get(par,f'<{par}>'))
        cur=par
    return '/'.join(chain)

print("All script/localscript/module instances with full path:")
for tid,(cname,ids) in inst_map.items():
    if cname in ('Script','LocalScript','ModuleScript'):
        for ref in ids:
            print(f"  {cname}: {get_path(ref)}")

print("\nStarter* children:")
for ref,name in all_names.items():
    if 'starter' in name.lower() or 'fart' in name.lower():
        cls=ref_to_class.get(ref,'?')
        print(f"  {cls}: {get_path(ref)}")
