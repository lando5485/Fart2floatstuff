#!/usr/bin/env python3
"""Read gameclient and NPCDialogueHandler sources from v3 file."""
import struct, zstandard, lz4.block

ZSTD = b'\x28\xb5\x2f\xfd'
FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'

def decomp(d, u):
    if len(d) >= 4 and d[:4] == ZSTD: return zstandard.ZstdDecompressor().decompress(d)
    return lz4.block.decompress(bytes(d), uncompressed_size=u) if u > 0 else bytes(d)
def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o+4
def rstr(d, o): n,o=ru32(d,o); return d[o:o+n].decode('utf-8','replace'), o+n
def decode_refs(data, count):
    vals=[]
    for i in range(count):
        v=(data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1,len(vals)): vals[i]+=vals[i-1]
    return vals

with open(FILE,'rb') as f: data=bytearray(f.read())
offset=32; inst_map={}; ref_name={}; sources={}

while offset < len(data):
    nm=data[offset:offset+4].decode('latin-1')
    comp=struct.unpack_from('<I',data,offset+4)[0]; uncomp=struct.unpack_from('<I',data,offset+8)[0]
    offset+=16
    if comp==0: raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
    else: raw=decomp(bytes(data[offset:offset+comp]),uncomp); offset+=comp
    if nm=='INST':
        o=0; tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); inst_map[tid]=(cn,refs)
    elif nm=='PROP':
        o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        cn,refs=inst_map.get(tid,('?',[]))
        if pn=='Name' and dt==0x01:
            for ref in refs:
                sl,o=ru32(raw,o); ref_name[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
        elif pn=='Source' and dt==0x01 and cn in ('LocalScript','Script','ModuleScript'):
            for ref in refs:
                sl,o=ru32(raw,o); sources[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    if nm=='END\x00': break

# Find target refs by name
targets = {n:r for r,n in ref_name.items() if n in ('gameclient','NPCDialogueHandler')}
print(f"Found: {targets}")

for name, ref in targets.items():
    src = sources.get(ref,'<NOT FOUND>')
    lines = src.split('\n')
    print(f"\n{'='*60}")
    print(f"=== {name} ({len(src)} chars, {len(lines)} lines) ===")
    print(f"{'='*60}")
    # Print with line numbers around critical areas
    if name == 'gameclient':
        # Show lines 155-165 (around the CellPaddingSize error)
        print(f"\n--- Lines 155-165 ---")
        for i, line in enumerate(lines[154:165], start=155):
            print(f"{i:4d}: {line}")
    elif name == 'NPCDialogueHandler':
        # Print all with line numbers
        print(f"\n--- Full source with line numbers ---")
        for i, line in enumerate(lines, start=1):
            print(f"{i:4d}: {line}")
