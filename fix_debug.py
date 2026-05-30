#!/usr/bin/env python3
"""
Comprehensive debug fix for Farttofloatdemo_v3.rbxl:
 1. Pre-place BuyFoodEvent/RegenEvent/CoinEvent/SkipIslandEvent in ReplicatedStorage
 2. Rewrite gameclient with debug prints, non-blocking event fetch, pcall error capture
 3. Verify PlayerStats event handlers
"""
import struct, zstandard, lz4.block

ZSTD = b'\x28\xb5\x2f\xfd'
FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
EVENT_NAMES = ["BuyFoodEvent", "RegenEvent", "CoinEvent", "SkipIslandEvent"]

# ---------------------------------------------------------------------------
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
def encode_refs(vals):
    if not vals: return b''
    count=len(vals)
    deltas=[vals[0]]+[vals[i]-vals[i-1] for i in range(1,count)]
    zz=[(-d*2-1)&0xFFFFFFFF if d<0 else (d*2)&0xFFFFFFFF for d in deltas]
    result=bytearray(count*4)
    for i,v in enumerate(zz):
        result[i]=(v>>24)&0xFF; result[count+i]=(v>>16)&0xFF; result[2*count+i]=(v>>8)&0xFF; result[3*count+i]=v&0xFF
    return bytes(result)
def write_unc(name, raw):
    return name.encode('latin-1')[:4].ljust(4,b'\x00') + struct.pack('<III',0,len(raw),0) + raw

# ---------------------------------------------------------------------------
# Parse file
with open(FILE,'rb') as f: data=bytearray(f.read())
header=bytearray(data[:32])
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
print(f"Parsed {len(chunks)} chunks")

# Build maps
inst_map={}; ref_class={}; ref_name={}
prnt={}; prnt_cr=[]; prnt_pr=[]; prnt_idx=None; prnt_ver=0; prnt_cnt=0
for idx,ch in enumerate(chunks):
    if ch['name']=='INST':
        raw=ch['raw']; o=0
        tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); inst_map[tid]=(cn,refs)
        for r in refs: ref_class[r]=cn
    elif ch['name']=='PROP':
        raw=ch['raw']; o=0
        tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        if pn=='Name' and dt==0x01:
            _,refs=inst_map.get(tid,('?',[]))
            for ref in refs:
                sl,o=ru32(raw,o); ref_name[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    elif ch['name']=='PRNT':
        raw=ch['raw']; prnt_ver=raw[0]; prnt_cnt=struct.unpack_from('<I',raw,1)[0]
        prnt_cr=list(decode_refs(raw[5:5+prnt_cnt*4],prnt_cnt))
        prnt_pr=list(decode_refs(raw[5+prnt_cnt*4:5+prnt_cnt*8],prnt_cnt))
        prnt=dict(zip(prnt_cr,prnt_pr)); prnt_idx=idx

# ---------------------------------------------------------------------------
# 1. CHECK / ADD REMOTEEVENTS IN REPLICATEDSTORAGE
# ---------------------------------------------------------------------------
rs_ref=None
for tid,(cn,refs) in inst_map.items():
    if cn=='ReplicatedStorage' and refs: rs_ref=refs[0]; break
print(f"\nReplicatedStorage ref: {rs_ref}")

rs_children={ref_name.get(r,'?'):r for r,p in prnt.items() if p==rs_ref}
print(f"RS children: {sorted(rs_children.keys())}")
missing=[n for n in EVENT_NAMES if n not in rs_children]
print(f"Missing events: {missing}")

extra_chunks_before_prnt=[]  # new INST/PROP to insert before PRNT

if missing:
    all_refs=set(ref_class.keys())
    max_ref=max(all_refs) if all_refs else 9000
    max_tid=max(inst_map.keys()) if inst_map else 100

    # Find or create RemoteEvent type
    re_tid=None
    for tid,(cn,_) in inst_map.items():
        if cn=='RemoteEvent': re_tid=tid; break

    new_refs=[max_ref+1+i for i in range(len(missing))]
    print(f"New event refs: {new_refs}")

    if re_tid is None:
        re_tid=max_tid+1
        print(f"Creating new RemoteEvent type_id={re_tid}")
        # New INST chunk
        cn_b=b'RemoteEvent'
        inst_raw=struct.pack('<I',re_tid)+struct.pack('<I',len(cn_b))+cn_b+bytes([0])+struct.pack('<I',len(new_refs))+encode_refs(new_refs)
        extra_chunks_before_prnt.append(write_unc('INST',inst_raw))
        # Update num_types in header
        old_types=struct.unpack_from('<I',header,16)[0]
        struct.pack_into('<I',header,16,old_types+1)
    else:
        print(f"Appending to existing RemoteEvent type_id={re_tid}")
        for ch_idx,ch in enumerate(chunks):
            if ch['name']!='INST': continue
            raw=ch['raw']; o=0; tid2,o=ru32(raw,o); cn2,o=rstr(raw,o); o+=1; c2,o=ru32(raw,o)
            if tid2==re_tid:
                ex_refs=list(decode_refs(raw[o:o+c2*4],c2))+new_refs
                cn_b=cn2.encode('utf-8')
                new_inst_raw=struct.pack('<I',re_tid)+struct.pack('<I',len(cn_b))+cn_b+bytes([0])+struct.pack('<I',len(ex_refs))+encode_refs(ex_refs)
                chunks[ch_idx]['raw']=new_inst_raw; chunks[ch_idx]['modified']=True
                break

    # PROP Name chunk for new events
    name_raw=bytearray(struct.pack('<I',re_tid))
    pn=b'Name'; name_raw+=struct.pack('<I',len(pn))+pn+bytes([0x01])
    for n in missing:
        nb=n.encode('utf-8'); name_raw+=struct.pack('<I',len(nb))+nb
    extra_chunks_before_prnt.append(write_unc('PROP',bytes(name_raw)))

    # Update PRNT chunk
    prnt_cr.extend(new_refs)
    prnt_pr.extend([rs_ref]*len(new_refs))
    prnt_cnt+=len(new_refs)
    new_prnt_raw=bytes([prnt_ver])+struct.pack('<I',prnt_cnt)+encode_refs(prnt_cr)+encode_refs(prnt_pr)
    chunks[prnt_idx]['raw']=new_prnt_raw; chunks[prnt_idx]['modified']=True

    # Update num_instances in header
    old_insts=struct.unpack_from('<I',header,20)[0]
    struct.pack_into('<I',header,20,old_insts+len(missing))

    print(f"Added {len(missing)} RemoteEvent(s) to ReplicatedStorage: {missing}")
else:
    print("All 4 RemoteEvents already present in ReplicatedStorage")

# ---------------------------------------------------------------------------
# 2. MODIFY GAMECLIENT SOURCE
# ---------------------------------------------------------------------------
gc_ref=next((r for r,n in ref_name.items() if n=='gameclient' and ref_class.get(r)=='LocalScript'), None)
if gc_ref is None:
    gc_ref=next((r for r,n in ref_name.items() if n=='gameclient'), None)
print(f"\ngameclient ref: {gc_ref}")

for ch in chunks:
    if ch['name']!='PROP': continue
    raw=ch['raw']; o=0
    tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if pn!='Source' or dt!=0x01: continue
    cn,refs=inst_map.get(tid,('?',[]))
    if cn not in ('LocalScript','Script'): continue
    if gc_ref not in refs: continue

    o2=o; sources={}
    for ref in refs:
        sl,o2=ru32(raw,o2); sources[ref]=raw[o2:o2+sl]; o2+=sl
    src=sources[gc_ref].decode('utf-8','replace')
    print(f"Source: {len(src)} chars — applying changes...")
    applied=[]

    # Change 1: GAMECLIENT STARTED at very top
    A1='-- Fart to Float v3 - Game Client (FartButton)\n'
    B1='print("GAMECLIENT STARTED")\n-- Fart to Float v3 - Game Client (FartButton)\n'
    if A1 in src: src=src.replace(A1,B1,1); applied.append('GAMECLIENT STARTED print')
    else: print("  WARN: start anchor not found")

    # Change 2: Replace blocking pcall-wrapped WaitForChild block + add GUIS BUILT
    A2=(
        'local RS = game:GetService("ReplicatedStorage")\n'
        'local BuyFoodEvent, RegenEvent, CoinEvent, SkipIslandEvent\n'
        'pcall(function()\n'
        '\tBuyFoodEvent   = RS:WaitForChild("BuyFoodEvent", 10)\n'
        '\tRegenEvent     = RS:WaitForChild("RegenEvent", 10)\n'
        '\tCoinEvent      = RS:WaitForChild("CoinEvent", 10)\n'
        '\tSkipIslandEvent= RS:WaitForChild("SkipIslandEvent", 10)\n'
        'end)'
    )
    B2=(
        'print("GUIS BUILT")\n'
        'local RS = game:GetService("ReplicatedStorage")\n'
        'local BuyFoodEvent, RegenEvent, CoinEvent, SkipIslandEvent\n'
        'BuyFoodEvent    = RS:FindFirstChild("BuyFoodEvent")    or RS:WaitForChild("BuyFoodEvent",    10)\n'
        'RegenEvent      = RS:FindFirstChild("RegenEvent")      or RS:WaitForChild("RegenEvent",      10)\n'
        'CoinEvent       = RS:FindFirstChild("CoinEvent")       or RS:WaitForChild("CoinEvent",       10)\n'
        'SkipIslandEvent = RS:FindFirstChild("SkipIslandEvent") or RS:WaitForChild("SkipIslandEvent", 10)\n'
        'if not BuyFoodEvent    then print("ERROR: BuyFoodEvent not in RS") end\n'
        'if not RegenEvent      then print("ERROR: RegenEvent not in RS") end\n'
        'if not CoinEvent       then print("ERROR: CoinEvent not in RS") end\n'
        'if not SkipIslandEvent then print("ERROR: SkipIslandEvent not in RS") end'
    )
    if A2 in src: src=src.replace(A2,B2,1); applied.append('event WaitForChild + GUIS BUILT')
    else: print("  WARN: RS event block not found — trying partial")

    # Change 3: leaderstats non-blocking with error check
    A3='local leaderstats\npcall(function() leaderstats = player:WaitForChild("leaderstats", 10) end)'
    B3=(
        'local leaderstats = player:FindFirstChild("leaderstats") or player:WaitForChild("leaderstats", 10)\n'
        'if not leaderstats then print("ERROR: leaderstats missing — is PlayerStats script running?") end'
    )
    if A3 in src: src=src.replace(A3,B3,1); applied.append('leaderstats non-blocking')
    else: print("  WARN: leaderstats block not found")

    # Change 4: EVENTS CONNECTED print + PROXIMITY LOOP STARTED + pcall error capture
    A4=(
        '-- ===== PROXIMITY DETECTION (own task.spawn) =====\n'
        'task.spawn(function()\n'
        '\tlocal DIST = 20\n'
        '\twhile true do\n'
        '\t\ttask.wait(0.1)\n'
        '\t\tlocal _pok,_perr=pcall(function()'
    )
    B4=(
        'print("EVENTS CONNECTED")\n'
        '-- ===== PROXIMITY DETECTION (own task.spawn) =====\n'
        'task.spawn(function()\n'
        '\tprint("PROXIMITY LOOP STARTED")\n'
        '\tlocal DIST = 20\n'
        '\twhile true do\n'
        '\t\ttask.wait(0.1)\n'
        '\t\tlocal _pok,_perr=pcall(function()'
    )
    # If pcall was already changed by previous run, just add prints
    A4_orig=(
        '-- ===== PROXIMITY DETECTION (own task.spawn) =====\n'
        'task.spawn(function()\n'
        '\tlocal DIST = 20\n'
        '\twhile true do\n'
        '\t\ttask.wait(0.1)\n'
        '\t\tpcall(function()'
    )
    B4_orig=(
        'print("EVENTS CONNECTED")\n'
        '-- ===== PROXIMITY DETECTION (own task.spawn) =====\n'
        'task.spawn(function()\n'
        '\tprint("PROXIMITY LOOP STARTED")\n'
        '\tlocal DIST = 20\n'
        '\twhile true do\n'
        '\t\ttask.wait(0.1)\n'
        '\t\tlocal _pok,_perr=pcall(function()'
    )
    if A4 in src:
        src=src.replace(A4,B4,1); applied.append('EVENTS CONNECTED + PROXIMITY LOOP STARTED (already had _pok)')
    elif A4_orig in src:
        src=src.replace(A4_orig,B4_orig,1); applied.append('EVENTS CONNECTED + PROXIMITY LOOP STARTED + pcall capture')
    else:
        print("  WARN: proximity header not found")

    # Change 5: Add pcall error print at end of proximity while loop
    # Pattern: closing of pcall end) followed by end (while) and end) (task.spawn)
    A5='\t\tend)\n\tend\nend)\n\nupdateFartBtn()'
    B5='\t\tend)\n\t\tif not _pok then print("PROX ERR: "..tostring(_perr)) end\n\tend\nend)\n\nupdateFartBtn()'
    if A5 in src: src=src.replace(A5,B5,1); applied.append('pcall error print in proximity loop')
    else:
        # Already has error print from previous run
        if '_pok' in src and 'PROX ERR' in src: applied.append('pcall error print already present')
        else: print("  WARN: proximity tail not found")

    # Change 6: Ensure FoodShopGui starts Enabled=false (verify)
    if 'FoodShopGui.Enabled=false' in src or 'FoodShopGui.Enabled = false' in src:
        applied.append('FoodShopGui.Enabled=false confirmed')
    else:
        print("  WARN: FoodShopGui Enabled=false not found")

    print(f"  Applied: {applied}")
    print(f"  New source length: {len(src)} chars")

    sources[gc_ref]=src.encode('utf-8')

    new_raw=bytearray(struct.pack('<I',tid))
    pn_b=b'Source'; new_raw+=struct.pack('<I',len(pn_b))+pn_b+bytes([0x01])
    for ref in refs:
        s=sources[ref]; new_raw+=struct.pack('<I',len(s))+s
    ch['raw']=bytes(new_raw); ch['modified']=True
    break

# ---------------------------------------------------------------------------
# 3. VERIFY PLAYERSTATS SOURCE
# ---------------------------------------------------------------------------
ps_ref=next((r for r,n in ref_name.items() if n=='PlayerStats'),None)
print(f"\nPlayerStats ref: {ps_ref}")
for ch in chunks:
    if ch['name']!='PROP': continue
    raw=ch['raw']; o=0
    tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if pn!='Source' or dt!=0x01: continue
    cn,refs=inst_map.get(tid,('?',[]))
    if cn not in ('Script','LocalScript'): continue
    if ps_ref not in refs: continue
    o2=o
    for ref in refs:
        sl,o2=ru32(raw,o2); s=raw[o2:o2+sl].decode('utf-8','replace'); o2+=sl
        if ref==ps_ref:
            has_buy  = 'BuyFoodEvent' in s and 'OnServerEvent' in s
            has_regen= 'RegenEvent'   in s and 'FireClient'    in s
            has_coin = 'CoinEvent'    in s and 'OnServerEvent' in s
            print(f"  BuyFoodEvent.OnServerEvent connected: {has_buy}")
            print(f"  RegenEvent:FireClient present:        {has_regen}")
            print(f"  CoinEvent.OnServerEvent connected:    {has_coin}")
            print(f"  getOrCreate helper present:           {'getOrCreate' in s}")
            print(f"  Source length: {len(s)} chars")
    break

# ---------------------------------------------------------------------------
# Write output — new INST/PROP chunks inserted just before PRNT
# ---------------------------------------------------------------------------
print("\nWriting output...")
out=bytearray(bytes(header))
for ch in chunks:
    if ch['name']=='PRNT' and extra_chunks_before_prnt:
        for ec in extra_chunks_before_prnt:
            out+=ec
    if ch['modified']: out+=write_unc(ch['name'],ch['raw'])
    else: out+=ch['orig']

with open(FILE,'wb') as f: f.write(out)
print(f"Saved: {len(out):,} bytes -> {FILE}")

# ---------------------------------------------------------------------------
# Quick re-read verify
print("\n=== VERIFICATION (re-reading saved file) ===")
with open(FILE,'rb') as f: d2=bytearray(f.read())
off=32; im2={}; rn2={}; rc2={}; pr2={}
while off<len(d2):
    nm=d2[off:off+4].decode('latin-1')
    comp=struct.unpack_from('<I',d2,off+4)[0]; uncomp=struct.unpack_from('<I',d2,off+8)[0]; off+=16
    if comp==0: raw=bytes(d2[off:off+uncomp]); off+=uncomp
    else: raw=decomp(bytes(d2[off:off+comp]),uncomp); off+=comp
    if nm=='INST':
        o=0; tid,o=ru32(raw,o); cn,o=rstr(raw,o); o+=1; c,o=ru32(raw,o)
        refs=decode_refs(raw[o:o+c*4],c); im2[tid]=(cn,refs)
        for r in refs: rc2[r]=cn
    elif nm=='PROP':
        o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        if pn=='Name' and dt==0x01:
            _,refs=im2.get(tid,('?',[]))
            for ref in refs:
                sl,o=ru32(raw,o); rn2[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    elif nm=='PRNT':
        ver=raw[0]; cnt=struct.unpack_from('<I',raw,1)[0]
        cr2=decode_refs(raw[5:5+cnt*4],cnt); pr2_=decode_refs(raw[5+cnt*4:5+cnt*8],cnt)
        pr2=dict(zip(cr2,pr2_))
    if nm=='END\x00': break

rs2=next((refs[0] for tid,(cn,refs) in im2.items() if cn=='ReplicatedStorage'),None)
rs_kids={rn2.get(r,'?'):(rc2.get(r,'?')) for r,p in pr2.items() if p==rs2}
re_kids={n:c for n,c in rs_kids.items() if c=='RemoteEvent'}
print(f"ReplicatedStorage RemoteEvent children: {sorted(re_kids.keys())}")

def path2(ref):
    r=ref; p=[]
    while r!=-1:
        p.append(rn2.get(r) or '['+rc2.get(r,'?')+']'); r=pr2.get(r,-1)
    p.reverse(); return ' > '.join(p)

print(f"gameclient path:  {path2(next((r for r,n in rn2.items() if n=='gameclient'),-1))}")
print(f"PlayerStats path: {path2(next((r for r,n in rn2.items() if n=='PlayerStats'),-1))}")

# Check gameclient source for debug prints
gc2=next((r for r,n in rn2.items() if n=='gameclient'),-1)
for ch_nm in ['PROP']:
    pass
off=32
while off<len(d2):
    nm=d2[off:off+4].decode('latin-1')
    comp=struct.unpack_from('<I',d2,off+4)[0]; uncomp=struct.unpack_from('<I',d2,off+8)[0]; off+=16
    if comp==0: raw=bytes(d2[off:off+uncomp]); off+=uncomp
    else: raw=decomp(bytes(d2[off:off+comp]),uncomp); off+=comp
    if nm=='PROP':
        o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
        if pn=='Source' and dt==0x01:
            _,refs=im2.get(tid,('?',[]))
            if gc2 in refs:
                o2=o
                for ref in refs:
                    sl,o2=ru32(raw,o2); s=raw[o2:o2+sl].decode('utf-8','replace'); o2+=sl
                    if ref==gc2:
                        print(f"\ngameclient source ({len(s)} chars):")
                        print(f"  has GAMECLIENT STARTED: {'GAMECLIENT STARTED' in s}")
                        print(f"  has GUIS BUILT:         {'GUIS BUILT' in s}")
                        print(f"  has EVENTS CONNECTED:   {'EVENTS CONNECTED' in s}")
                        print(f"  has PROXIMITY LOOP:     {'PROXIMITY LOOP STARTED' in s}")
                        print(f"  has pcall error print:  {'PROX ERR' in s}")
                        print(f"  has PromptGameInvite:   {'PromptGameInvite' in s}")
                        print(f"  FoodShopGui Enabled=false: {'FoodShopGui.Enabled=false' in s or 'FoodShopGui.Enabled = false' in s}")
                        print(f"  first 3 lines: {s[:100]!r}")
    if nm=='END\x00': break

print("\nDEBUG VERSION SAVED")
