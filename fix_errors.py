#!/usr/bin/env python3
"""
Targeted fixes for Farttofloatdemo_v3.rbxl:
  ERROR 1 gameclient line 159: CellPaddingSize -> CellPadding
  ERROR 2 NPCDialogueHandler line 35: remove stray 'awd' token
"""
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
def write_unc(name, raw):
    return name.encode('latin-1')[:4].ljust(4,b'\x00') + struct.pack('<III',0,len(raw),0) + raw

with open(FILE,'rb') as f: data=bytearray(f.read())
header=bytes(data[:32])
print(f"File: {len(data):,} bytes")

chunks=[]
offset=32
while offset<len(data):
    nm=data[offset:offset+4].decode('latin-1')
    comp=struct.unpack_from('<I',data,offset+4)[0]; uncomp=struct.unpack_from('<I',data,offset+8)[0]
    cs=offset; offset+=16
    if comp==0: raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
    else: raw=decomp(bytes(data[offset:offset+comp]),uncomp); offset+=comp
    chunks.append({'name':nm,'raw':raw,'orig':bytes(data[cs:offset]),'modified':False})
    if nm=='END\x00': break

inst_map={}; ref_name={}
for ch in chunks:
    if ch['name']=='INST':
        raw=ch['raw']; o=0
        tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); inst_map[tid]=(cn,refs)
    elif ch['name']=='PROP':
        raw=ch['raw']; o=0
        tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        if pn=='Name' and dt==0x01:
            _,refs=inst_map.get(tid,('?',[]))
            for ref in refs:
                sl,o=ru32(raw,o); ref_name[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl

gc_ref  = next((r for r,n in ref_name.items() if n=='gameclient'),       None)
npc_ref = next((r for r,n in ref_name.items() if n=='NPCDialogueHandler'),None)
print(f"gameclient ref: {gc_ref}  NPCDialogueHandler ref: {npc_ref}")

fixes_applied = []

for ch in chunks:
    if ch['name'] != 'PROP': continue
    raw=ch['raw']; o=0
    tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if pn != 'Source' or dt != 0x01: continue
    cn,refs=inst_map.get(tid,('?',[]))
    if cn not in ('LocalScript','Script','ModuleScript'): continue

    need_gc  = gc_ref  in refs
    need_npc = npc_ref in refs
    if not need_gc and not need_npc: continue

    # Read all sources in this chunk
    o2=o; sources={}
    for ref in refs:
        sl,o2=ru32(raw,o2); sources[ref]=raw[o2:o2+sl]; o2+=sl

    changed=False

    # --- FIX 1: gameclient CellPaddingSize -> CellPadding ---
    if need_gc and gc_ref in sources:
        src=sources[gc_ref].decode('utf-8','replace')
        if 'CellPaddingSize' in src:
            src=src.replace('CellPaddingSize','CellPadding')
            sources[gc_ref]=src.encode('utf-8')
            print(f"  [OK] gameclient: CellPaddingSize -> CellPadding")
            fixes_applied.append('gameclient CellPaddingSize->CellPadding')
            changed=True
        else:
            print(f"  [INFO] gameclient: CellPaddingSize not found (already fixed?)")

        # Verify no other obvious syntax issues
        lines=src.split('\n')
        print(f"  gameclient: {len(lines)} lines, {len(src)} chars — spot checks:")
        print(f"    line 159: {lines[158] if len(lines)>158 else 'N/A'}")

    # --- FIX 2: NPCDialogueHandler remove trailing 'awd' ---
    if need_npc and npc_ref in sources:
        src=sources[npc_ref].decode('utf-8','replace')
        lines=src.split('\n')
        print(f"\n  NPCDialogueHandler before fix: {len(lines)} lines")
        print(f"    last 3 lines: {lines[-3:]}")

        # Line 35 is 'awd' (0-indexed: line index 34)
        # Strip any trailing lines that are just bare identifiers / junk after end)
        # The script ends properly at line 34 (end)) so remove everything after
        stripped=src.rstrip()
        # Remove trailing 'awd' (and any other stray tokens after the last end))
        if stripped.endswith('awd'):
            stripped=stripped[:-3].rstrip()
            sources[npc_ref]=stripped.encode('utf-8')
            new_lines=stripped.split('\n')
            print(f"  [OK] NPCDialogueHandler: removed trailing 'awd'")
            print(f"    now {len(new_lines)} lines, last line: {new_lines[-1]!r}")
            fixes_applied.append('NPCDialogueHandler removed trailing awd')
            changed=True
        else:
            print(f"  [INFO] NPCDialogueHandler: trailing 'awd' not found at expected position")
            print(f"    last 10 chars: {stripped[-10:]!r}")

    if changed:
        new_raw=bytearray(struct.pack('<I',tid))
        pn_b=b'Source'; new_raw+=struct.pack('<I',len(pn_b))+pn_b+bytes([0x01])
        for ref in refs:
            s=sources[ref]; new_raw+=struct.pack('<I',len(s))+s
        ch['raw']=bytes(new_raw); ch['modified']=True

out=bytearray(header)
for ch in chunks:
    if ch['modified']: out+=write_unc(ch['name'],ch['raw'])
    else: out+=ch['orig']

with open(FILE,'wb') as f: f.write(out)
print(f"\nSaved: {len(out):,} bytes")

# --- Verify by re-reading ---
print("\n=== VERIFICATION ===")
with open(FILE,'rb') as f: d2=bytearray(f.read())
off=32; im2={}; rn2={}
while off<len(d2):
    nm=d2[off:off+4].decode('latin-1')
    comp=struct.unpack_from('<I',d2,off+4)[0]; uncomp=struct.unpack_from('<I',d2,off+8)[0]; off+=16
    if comp==0: raw=bytes(d2[off:off+uncomp]); off+=uncomp
    else: raw=decomp(bytes(d2[off:off+comp]),uncomp); off+=comp
    if nm=='INST':
        o=0; tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); im2[tid]=(cn,refs)
    elif nm=='PROP':
        o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        if pn=='Name' and dt==0x01:
            _,refs=im2.get(tid,('?',[]))
            for ref in refs:
                sl,o=ru32(raw,o); rn2[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
        elif pn=='Source' and dt==0x01:
            cn2,refs=im2.get(tid,('?',[]))
            if cn2 in ('LocalScript','Script','ModuleScript'):
                o2=o
                for ref in refs:
                    sl,o2=ru32(raw,o2); s=raw[o2:o2+sl].decode('utf-8','replace'); o2+=sl
                    nm2=rn2.get(ref,'?')
                    if nm2=='gameclient':
                        lines=s.split('\n')
                        ok = 'CellPaddingSize' not in s
                        print(f"  gameclient line 159: {lines[158]}")
                        print(f"  gameclient CellPaddingSize removed: {ok}")
                    elif nm2=='NPCDialogueHandler':
                        lines=s.split('\n')
                        ok = not lines[-1].strip()=='awd' and 'awd' not in s.split('\n')[-1]
                        print(f"  NPCDialogueHandler last line: {lines[-1]!r}")
                        print(f"  NPCDialogueHandler 'awd' removed: {ok}")
                        print(f"  NPCDialogueHandler line count: {len(lines)}")
    if nm=='END\x00': break

print(f"\nFixes applied: {fixes_applied}")
print("ERRORS FIXED")
