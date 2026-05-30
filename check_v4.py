import struct
try: import zstandard; HAS_ZSTD=True
except: HAS_ZSTD=False
try: import lz4.block; HAS_LZ4=True
except: HAS_LZ4=False
ZSTD_MAGIC=b'\x28\xb5\x2f\xfd'
def decomp(d,u):
    if len(d)>=4 and d[:4]==ZSTD_MAGIC and HAS_ZSTD: return zstandard.ZstdDecompressor().decompress(d)
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
with open('Farttofloatdemo_v4.rbxlx','rb') as f: raw=bytearray(f.read())
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
for chk in [('Script',61),('LocalScript',37),('RemoteEvent',58)]:
    name,tid=chk
    print(f'=== {name} (tid={tid}) refs={inst_map[tid][1]} ===')
    for ch in chunks:
        if ch['nm']!='PROP': continue
        r=ch['raw']; o=0
        t2,o=ru32(r,o); pn,o=rstr(r,o); dt=r[o]; o+=1
        if t2!=tid: continue
        remaining=len(r)-o
        print(f'  prop={repr(pn)} dtype=0x{dt:02x} remaining={remaining}')
        if pn=='Name' and dt==1:
            refs=inst_map[tid][1]
            for ref in refs:
                sl,o=ru32(r,o)
                val=r[o:o+sl].decode('utf-8','replace')
                print(f'    ref={ref}: {repr(val)}')
                o+=sl
        elif pn=='Source' and dt==1:
            refs=inst_map[tid][1]
            for ref in refs:
                sl,o=ru32(r,o)
                print(f'    ref={ref}: source_len={sl}')
                o+=sl
    print()
