#!/usr/bin/env python3
"""
Fix Farttofloatdemo_v3.rbxl:
 1. Reparent gameclient LocalScript to StarterPlayerScripts (it was a direct
    child of StarterPlayer which never auto-runs LocalScripts)
 2. Fix invite API: SocialService:PromptInviteAsync -> PromptGameInvite
 3. Fix proximity part check: handle ProximityPrompts parented to Models
"""
import struct, zstandard, lz4.block

ZSTD    = b'\x28\xb5\x2f\xfd'
FILE    = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
GC_REF  = 8632   # gameclient referent

# ---------------------------------------------------------------------------
def decomp(d, u):
    if len(d) >= 4 and d[:4] == ZSTD:
        return zstandard.ZstdDecompressor().decompress(d)
    return lz4.block.decompress(bytes(d), uncompressed_size=u) if u > 0 else bytes(d)

def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o + 4
def rstr(d, o):
    n, o = ru32(d, o); return d[o:o+n].decode('utf-8', 'replace'), o + n

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1, len(vals)): vals[i] += vals[i-1]
    return vals

def encode_refs(vals):
    if not vals: return b''
    count = len(vals)
    deltas = [vals[0]] + [vals[i]-vals[i-1] for i in range(1, count)]
    zz = [(-d*2-1) & 0xFFFFFFFF if d < 0 else (d*2) & 0xFFFFFFFF for d in deltas]
    result = bytearray(count * 4)
    for i, v in enumerate(zz):
        result[i]           = (v >> 24) & 0xFF
        result[count+i]     = (v >> 16) & 0xFF
        result[2*count+i]   = (v >>  8) & 0xFF
        result[3*count+i]   =  v        & 0xFF
    return bytes(result)

def write_unc(name, raw):
    nb = name.encode('latin-1')[:4].ljust(4, b'\x00')
    return nb + struct.pack('<III', 0, len(raw), 0) + raw

# ---------------------------------------------------------------------------
with open(FILE, 'rb') as f: data = bytearray(f.read())
header = bytes(data[:32])
print(f"File: {len(data):,} bytes")

chunks = []
offset = 32
while offset < len(data):
    name  = data[offset:offset+4].decode('latin-1')
    comp  = struct.unpack_from('<I', data, offset+4)[0]
    uncomp= struct.unpack_from('<I', data, offset+8)[0]
    cs    = offset; offset += 16
    if comp == 0: raw = bytes(data[offset:offset+uncomp]); offset += uncomp
    else:         raw = decomp(bytes(data[offset:offset+comp]), uncomp); offset += comp
    orig  = bytes(data[cs:offset])
    chunks.append({'name':name, 'raw':raw, 'orig':orig, 'modified':False})
    if name == 'END\x00': break
print(f"Parsed {len(chunks)} chunks")

# Build instance map
inst_map = {}
for ch in chunks:
    if ch['name'] != 'INST': continue
    raw = ch['raw']; o = 0
    tid, o  = ru32(raw, o)
    cname,o = rstr(raw, o)
    o += 1
    count,o = ru32(raw, o)
    refs    = decode_refs(raw[o:o+count*4], count)
    inst_map[tid] = (cname, refs)

# Find StarterPlayerScripts ref
sps_ref = None
for tid, (cname, refs) in inst_map.items():
    if cname == 'StarterPlayerScripts' and refs:
        sps_ref = refs[0]
        print(f"StarterPlayerScripts: type_id={tid} ref={sps_ref}")
        break

if sps_ref is None:
    print("ERROR: StarterPlayerScripts not found in file!"); raise SystemExit(1)

# ---------------------------------------------------------------------------
# FIX 1 (source) + FIX 2 (source): invite API + proximity part check
# ---------------------------------------------------------------------------
INVITE_OLD  = 'SocialService:PromptInviteAsync(player)'
INVITE_NEW  = 'SocialService:PromptGameInvite(player)'

# The exact block (5-tabs = inside for-loop body inside pcall inside while true)
PROX_OLD = (
    '\t\t\t\t\tif part and part:IsA("BasePart") then\n'
    '\t\t\t\t\t\tif (root.Position - part.Position).Magnitude < DIST then\n'
    '\t\t\t\t\t\t\tnearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break\n'
    '\t\t\t\t\t\tend\n'
    '\t\t\t\t\tend'
)
PROX_NEW = (
    '\t\t\t\t\tlocal _p=nil; pcall(function()\n'
    '\t\t\t\t\t\tif part then\n'
    '\t\t\t\t\t\t\tif part:IsA("BasePart") then _p=part.Position\n'
    '\t\t\t\t\t\t\telseif part.Parent and part.Parent:IsA("BasePart") then _p=part.Parent.Position\n'
    '\t\t\t\t\t\t\telse local b=part:FindFirstChildWhichIsA("BasePart"); if b then _p=b.Position end\n'
    '\t\t\t\t\t\t\tend\n'
    '\t\t\t\t\t\tend\n'
    '\t\t\t\t\tend)\n'
    '\t\t\t\t\tif _p and (root.Position - _p).Magnitude < DIST then\n'
    '\t\t\t\t\t\tnearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break\n'
    '\t\t\t\t\tend'
)

for ch in chunks:
    if ch['name'] != 'PROP': continue
    raw = ch['raw']; o = 0
    tid, o  = ru32(raw, o)
    pname,o = rstr(raw, o)
    dtype   = raw[o]; o += 1
    if pname != 'Source' or dtype != 0x01: continue
    cname, refs = inst_map.get(tid, ('?', []))
    if cname not in ('LocalScript', 'Script'): continue
    if GC_REF not in refs: continue

    # Read all sources in this chunk
    o2 = o; sources = {}
    for ref in refs:
        slen, o2 = ru32(raw, o2); sources[ref] = raw[o2:o2+slen]; o2 += slen

    src = sources[GC_REF].decode('utf-8', 'replace')

    # Apply invite fix
    if INVITE_OLD in src:
        src = src.replace(INVITE_OLD, INVITE_NEW)
        print("  [OK] Invite API fixed: PromptInviteAsync -> PromptGameInvite")
    else:
        print("  [WARN] Invite pattern not found in source")

    # Apply proximity fix
    if PROX_OLD in src:
        src = src.replace(PROX_OLD, PROX_NEW)
        print("  [OK] Proximity part check fixed (now handles Models)")
    else:
        print("  [WARN] Proximity pattern not found exactly — trying fallback")
        # Fallback: at least clear the IsA("BasePart") restriction
        if 'part:IsA("BasePart")' in src:
            src = src.replace(
                'if part and part:IsA("BasePart") then',
                'local _pp=part; if _pp and not _pp:IsA("BasePart") then _pp=_pp:FindFirstChildWhichIsA("BasePart") or nil end; if _pp then'
            )
            src = src.replace(
                'if (root.Position - part.Position).Magnitude < DIST then',
                'if _pp and (root.Position - _pp.Position).Magnitude < DIST then'
            )
            print("  [OK] Proximity fallback applied")

    sources[GC_REF] = src.encode('utf-8')

    # Rebuild PROP chunk raw
    new_raw = bytearray()
    new_raw += struct.pack('<I', tid)
    pn_b = b'Source'
    new_raw += struct.pack('<I', len(pn_b)) + pn_b + bytes([0x01])
    for ref in refs:
        s = sources[ref]; new_raw += struct.pack('<I', len(s)) + s

    ch['raw'] = bytes(new_raw); ch['modified'] = True
    print(f"  Source chunk rebuilt: {len(src)} chars")
    break

# ---------------------------------------------------------------------------
# FIX 3: Reparent gameclient in PRNT chunk
# ---------------------------------------------------------------------------
prnt_fixed = False
for ch in chunks:
    if ch['name'] != 'PRNT': continue
    raw   = ch['raw']
    ver   = raw[0]
    count = struct.unpack_from('<I', raw, 1)[0]
    child_refs  = decode_refs(raw[5          : 5+count*4], count)
    parent_refs = decode_refs(raw[5+count*4  : 5+count*8], count)

    if GC_REF in child_refs:
        idx       = child_refs.index(GC_REF)
        old_par   = parent_refs[idx]
        parent_refs[idx] = sps_ref
        print(f"  [OK] PRNT: gameclient parent {old_par} -> {sps_ref} (StarterPlayerScripts)")
        new_raw = bytes([ver]) + struct.pack('<I', count) + encode_refs(child_refs) + encode_refs(parent_refs)
        ch['raw'] = new_raw; ch['modified'] = True
        prnt_fixed = True
    else:
        print(f"  [WARN] gameclient ref {GC_REF} not found in PRNT chunk")
    break

if not prnt_fixed:
    print("  [WARN] PRNT chunk was not modified")

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
out = bytearray(header)
for ch in chunks:
    if ch['modified']: out += write_unc(ch['name'], ch['raw'])
    else:              out += ch['orig']

with open(FILE, 'wb') as f: f.write(out)
print(f"\nOutput: {len(out):,} bytes -> {FILE}")
print("FIXES COMPLETE")
