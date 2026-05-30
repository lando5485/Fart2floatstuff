#!/usr/bin/env python3
import struct, zstandard, lz4.block

INFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
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
print(f"File size: {len(data):,}")

offset=32; inst_map={}; prop_names={}; prop_sources={}

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
            if cname in ('Script','LocalScript') and pname in ('Name','Source'):
                strs=[]
                for _ in ids:
                    slen,o=ru32(raw,o); s=raw[o:o+slen].decode('utf-8','replace')
                    strs.append(s); o+=slen
                d=dict(zip(ids,strs))
                if pname=='Name': prop_names[tid]=d
                elif pname=='Source': prop_sources[tid]=d

    if nm=='END\x00': break

print("\n=== VERIFICATION ===")
checks = {
    'gameserver should start with "return"': None,
    'gameclient should contain FartButton code': None,
    'PlayerStats should contain foods table': None,
}

for tid,(cname,ids) in inst_map.items():
    if cname not in ('Script','LocalScript'): continue
    names = prop_names.get(tid,{})
    sources = prop_sources.get(tid,{})
    for ref in ids:
        name = names.get(ref,'?')
        src  = sources.get(ref,'')
        print(f"\n  [{cname}] {name}")
        print(f"    len={len(src)}")
        print(f"    first_line={src.split(chr(10))[0]!r}")
        print(f"    has_foods={'local foods' in src}")
        print(f"    has_GasMeterGui={'GasMeterGui' in src}")
        print(f"    has_FartButtonGui={'FartButtonGui' in src}")
        print(f"    has_proximity={'proximity' in src.lower() or 'ProximityPrompt' in src}")
        print(f"    has_task_spawn={'task.spawn' in src}")
        print(f"    has_pcall={'pcall' in src}")
        if name=='gameserver': print(f"    DISABLED={src.startswith('return')}")
        if name=='gameclient': print(f"    HAS_8_GUIS={'HotbarGui' in src}")
