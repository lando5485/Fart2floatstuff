#!/usr/bin/env python3
"""Read script sources and ProximityPrompt data from v3 file."""
import struct, zstandard, lz4.block

ZSTD = b'\x28\xb5\x2f\xfd'
FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'

def decomp(d,u):
    if len(d)>=4 and d[:4]==ZSTD: return zstandard.ZstdDecompressor().decompress(d)
    return lz4.block.decompress(bytes(d),uncompressed_size=u) if u>0 else bytes(d)

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

with open(FILE,'rb') as f: data=bytearray(f.read())
offset=32; inst_map={}; all_props={}  # type_id -> {prop_name -> [values]}

while offset<len(data):
    nm=data[offset:offset+4].decode('latin-1')
    comp=struct.unpack_from('<I',data,offset+4)[0]
    uncomp=struct.unpack_from('<I',data,offset+8)[0]
    offset+=16
    if comp==0: raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
    else: raw=decomp(bytes(data[offset:offset+comp]),uncomp); offset+=comp

    if nm=='INST':
        o=0; t,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); inst_map[t]=(cn,refs)

    elif nm=='PROP':
        o=0; t,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        cn,refs=inst_map.get(t,('?',[]))

        # Collect all string props for ProximityPrompt
        if cn=='ProximityPrompt' and dt==0x01:
            strs=[]
            tmp=o
            for _ in refs:
                sl,tmp=ru32(raw,tmp); strs.append(raw[tmp:tmp+sl].decode('utf-8','replace')); tmp+=sl
            all_props.setdefault(t,{})[pn]=list(zip(refs,strs))

        # Get gameclient source
        if cn=='LocalScript' and pn=='Source' and dt==0x01:
            for ref in refs:
                sl,o=ru32(raw,o); s=raw[o:o+sl].decode('utf-8','replace'); o+=sl
                if 'FartButton' in s or 'gameclient' in s[:100]:
                    print(f"=== gameclient source ({len(s)} chars) ===")
                    print(s)
                    print("=== END ===")

    if nm=='END\x00': break

# Print ProximityPrompt properties
print("\n=== ProximityPrompt instances ===")
for t,(cn,refs) in inst_map.items():
    if cn != 'ProximityPrompt': continue
    print(f"  type_id={t}, count={len(refs)}")
    props = all_props.get(t, {})
    for pn, vals in sorted(props.items()):
        print(f"    {pn}: {vals}")
