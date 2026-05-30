#!/usr/bin/env python3
"""Check what compression each chunk uses in the original file."""
import struct, zstandard, lz4.block

INFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl'
ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'
LZ4F_MAGIC = b'\x04\x22\x4d\x18'

with open(INFILE,'rb') as f: data=bytearray(f.read())

offset=32
chunk_types={}  # compression_type -> count
first_prop_raw = None
first_prop_comp = None

for _ in range(200):  # check first 200 chunks
    if offset >= len(data): break
    nm=data[offset:offset+4].decode('latin-1','replace')
    comp=struct.unpack_from('<I',data,offset+4)[0]
    uncomp=struct.unpack_from('<I',data,offset+8)[0]
    offset+=16

    if comp==0:
        raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
        ctype='UNCOMPRESSED'
    else:
        chunk_data = bytes(data[offset:offset+comp])
        first4 = chunk_data[:4]
        if first4==ZSTD_MAGIC: ctype='ZSTD'
        elif first4==LZ4F_MAGIC: ctype='LZ4F'
        else: ctype=f'OTHER({first4.hex()})'
        # Try decompress
        try:
            raw=zstandard.ZstdDecompressor().decompress(chunk_data)
        except:
            try:
                raw=lz4.block.decompress(chunk_data, uncompressed_size=uncomp)
                ctype='LZ4BLOCK'
            except Exception as e:
                ctype=f'FAIL({e})'
                raw=b''
        offset+=comp

    key=f'{nm}:{ctype}'
    chunk_types[key]=chunk_types.get(key,0)+1

    if nm=='PROP' and first_prop_raw is None:
        first_prop_raw=raw
        first_prop_comp=bytes(data[offset-comp:offset]) if comp>0 else None
        first_prop_comp_type=ctype
        first_prop_comp_len=comp
        first_prop_uncomp_len=uncomp

    if nm=='END\x00': break

print("Chunk compression types (first 200 chunks):")
for k,v in sorted(chunk_types.items()):
    print(f"  {k}: {v}")

print(f"\nFirst PROP chunk:")
print(f"  comp_type={first_prop_comp_type}")
print(f"  comp_len={first_prop_comp_len}, uncomp_len={first_prop_uncomp_len}")
if first_prop_raw:
    print(f"  raw first 20 bytes: {first_prop_raw[:20].hex()}")

# Now check the V3 file's modified chunks
print("\n\nChecking V3 file's modified PROP chunks...")
V3FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
with open(V3FILE,'rb') as f: data2=bytearray(f.read())
offset=32
found=0
for _ in range(2000):
    if offset>=len(data2) or found>=5: break
    nm=data2[offset:offset+4].decode('latin-1','replace')
    comp=struct.unpack_from('<I',data2,offset+4)[0]
    uncomp=struct.unpack_from('<I',data2,offset+8)[0]
    offset+=16
    if comp==0: raw=bytes(data2[offset:offset+uncomp]); offset+=uncomp; ctype='UNCOMPRESSED'
    else:
        chunk_data=bytes(data2[offset:offset+comp])
        first4=chunk_data[:4]
        if first4==ZSTD_MAGIC: ctype='ZSTD'
        elif first4==LZ4F_MAGIC: ctype='LZ4F'
        else: ctype=f'OTHER({first4.hex()})'
        try: raw=zstandard.ZstdDecompressor().decompress(chunk_data)
        except:
            try: raw=lz4.block.decompress(chunk_data,uncompressed_size=uncomp); ctype='LZ4BLOCK'
            except: raw=b''; ctype='FAIL'
        offset+=comp
    if nm=='PROP' and comp>0 and ctype not in ('ZSTD',):
        # Show any PROP chunks NOT using zstd
        print(f"  PROP chunk at uses {ctype}, comp={comp}, uncomp={uncomp}")
        found+=1
    if nm=='END\x00': break

# Spot check: does V3 file parse OK with zstd?
print("\nSpot-checking V3 Source chunks decode correctly...")
offset=32; inst_map={}
while offset<len(data2):
    nm=data2[offset:offset+4].decode('latin-1','replace')
    comp=struct.unpack_from('<I',data2,offset+4)[0]
    uncomp=struct.unpack_from('<I',data2,offset+8)[0]
    offset+=16
    if comp==0: raw=bytes(data2[offset:offset+uncomp]); offset+=uncomp
    else:
        cd=bytes(data2[offset:offset+comp])
        try: raw=zstandard.ZstdDecompressor().decompress(cd)
        except: raw=lz4.block.decompress(cd,uncompressed_size=uncomp)
        offset+=comp
    if nm=='INST':
        o=0; tid,o=struct.unpack_from('<I',raw,o)[0],o+4
        n=struct.unpack_from('<I',raw,o)[0]; cname=raw[o+4:o+4+n].decode('utf-8','replace'); o+=4+n+1
        count=struct.unpack_from('<I',raw,o)[0]
        inst_map[tid]=(cname,count)
    if nm=='END\x00': break

print("  Instance type counts from V3:")
for tid,(cn,cnt) in sorted(inst_map.items()):
    print(f"    [{tid}] {cn}: {cnt} instances")
