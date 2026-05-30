#!/usr/bin/env python3
import struct, zstandard, lz4.block
ZSTD=b'\x28\xb5\x2f\xfd'
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
with open(r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl','rb') as f: data=bytearray(f.read())
offset=32; inst_map={}; prnt={}; names={}; sources={}
while offset<len(data):
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
        if dt==0x01:
            cn,refs=inst_map.get(tid,('?',[]))
            if cn in ('LocalScript','Script') and pn in ('Name','Source'):
                tmp=o
                for ref in refs:
                    sl,tmp=ru32(raw,tmp); s=raw[tmp:tmp+sl].decode('utf-8','replace'); tmp+=sl
                    if pn=='Name': names[ref]=s
                    else: sources[ref]=s
    elif nm=='PRNT':
        ver=raw[0]; count=struct.unpack_from('<I',raw,1)[0]
        cr=decode_refs(raw[5:5+count*4],count)
        pr=decode_refs(raw[5+count*4:5+count*8],count)
        prnt=dict(zip(cr,pr))
    if nm=='END\x00': break

def refname(r):
    if r==-1: return 'ROOT'
    n=names.get(r)
    if n: return n
    for tid,(cn,rs) in inst_map.items():
        if r in rs: return '['+cn+']'
    return 'ref='+str(r)

print('=== Script location & source check ===')
for ref in sorted(set(list(names.keys())+list(sources.keys()))):
    n=names.get(ref,'?'); src=sources.get(ref,''); par=prnt.get(ref,-1); gpar=prnt.get(par,-1)
    print('  '+repr(n))
    print('    parent: '+refname(par)+' -> '+refname(gpar))
    no_old_invite = 'PromptInviteAsync' not in src
    print('    src_len='+str(len(src))+' | invite_fixed='+str(no_old_invite))
    if n=='gameclient':
        print('    PromptGameInvite present: '+str('PromptGameInvite' in src))
        print('    robust_prox (_bp): '+str('_bp' in src))
        print('    src first line: '+src.split('\n')[0])

print()
print('=== gameclient ancestry ===')
gcref=next((r for r,n in names.items() if n=='gameclient'),None)
if gcref:
    r=gcref; path=[]
    while r!=-1 and len(path)<6:
        path.append(refname(r)); r=prnt.get(r,-1)
    print(' -> '.join(path))
print()
print('=== NPCDialogueHandler ancestry ===')
npcref=next((r for r,n in names.items() if n=='NPCDialogueHandler'),None)
if npcref:
    r=npcref; path=[]
    while r!=-1 and len(path)<6:
        path.append(refname(r)); r=prnt.get(r,-1)
    print(' -> '.join(path))
