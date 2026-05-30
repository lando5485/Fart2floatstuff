#!/usr/bin/env python3
"""Show exact source sections needed for fix planning."""
import struct, zstandard, lz4.block
ZSTD=b'\x28\xb5\x2f\xfd'
FILE=r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
def decomp(d,u):
    if len(d)>=4 and d[:4]==ZSTD: return zstandard.ZstdDecompressor().decompress(d)
    return lz4.block.decompress(bytes(d),uncompressed_size=u) if u>0 else bytes(d)
def ru32(d,o): return struct.unpack_from('<I',d,o)[0],o+4
def rstr(d,o): n,o=ru32(d,o); return d[o:o+n].decode('utf-8','replace'),o+n
def decode_refs(data,count):
    vals=[]
    for i in range(count):
        v=(data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1,len(vals)): vals[i]+=vals[i-1]
    return vals
with open(FILE,'rb') as f: data=bytearray(f.read())
off=32; im={}; rn={}; srcs={}
while off<len(data):
    nm=data[off:off+4].decode('latin-1'); comp=struct.unpack_from('<I',data,off+4)[0]; uncomp=struct.unpack_from('<I',data,off+8)[0]; off+=16
    if comp==0: raw=bytes(data[off:off+uncomp]); off+=uncomp
    else: raw=decomp(bytes(data[off:off+comp]),uncomp); off+=comp
    if nm=='INST':
        o=0; tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); im[tid]=(cn,refs)
    elif nm=='PROP':
        o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        cn,refs=im.get(tid,('?',[]))
        if pn=='Name' and dt==0x01:
            for ref in refs:
                sl,o=ru32(raw,o); rn[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
        elif pn=='Source' and dt==0x01 and cn in ('LocalScript','Script'):
            for ref in refs:
                sl,o=ru32(raw,o); srcs[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    if nm=='END\x00': break

gc=next((r for r,n in rn.items() if n=='gameclient'),None)
npc=next((r for r,n in rn.items() if n=='NPCDialogueHandler'),None)
ps=next((r for r,n in rn.items() if n=='PlayerStats'),None)

src=srcs.get(gc,'')
lines=src.split('\n')

def show(label, start, end):
    print(f"\n--- {label} ---")
    for i,l in enumerate(lines[start-1:end],start=start):
        print(f"{i:4d}| {l}")

# Key sections for fixes
show("FIX1: coin block (heartbeat, ~line 328)", 322, 345)
show("FIX2: updateMeter function", 228, 235)
show("FIX2: startFlying function", 304, 312)
show("FIX2: stopFlying function", 313, 320)
show("FIX2: updateHotbar function", 254, 260)
show("FIX2: mkCard function", 185, 196)
show("FIX2: premPanel & premTitle lines", 173, 203)
show("FIX3: variables near top", 17, 32)
show("FIX3: skipBadge + GUIS BUILT boundary", 210, 217)
show("FIX4: NPC full", 1, 34)

# NPCDialogueHandler
print("\n\n=== NPCDialogueHandler full ===")
ns=srcs.get(npc,'')
for i,l in enumerate(ns.split('\n'),1):
    print(f"{i:3d}| {l}")

# PlayerStats CoinEvent section
print("\n\n=== PlayerStats CoinEvent lines ===")
ps_src=srcs.get(ps,'')
for i,l in enumerate(ps_src.split('\n'),1):
    if 'Coin' in l or 'coin' in l:
        print(f"{i:3d}| {l}")
