#!/usr/bin/env python3
"""
Fix v3 RBXL (corrected refs):
 1. Fix gameclient source (ref=8631 in v3):
    a. Invite API: PromptInviteAsync -> PromptGameInvite
    b. Proximity check: handle non-BasePart parents
 2. Restore StarterCharacterScripts (ref=8632) parent from 8630 -> 8629 (StarterPlayer)
    (was wrongly reparented by previous fix run)
"""
import struct, zstandard, lz4.block

ZSTD    = b'\x28\xb5\x2f\xfd'
FILE    = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'
GC_REF  = 8631   # gameclient in v3 file
SCS_REF = 8632   # StarterCharacterScripts
SCS_CORRECT_PARENT = 8629   # StarterPlayer

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

# ---------------------------------------------------------------------------
# FIX SOURCE: invite API + proximity part check for gameclient (ref=8631)
# ---------------------------------------------------------------------------
INVITE_OLD = 'SocialService:PromptInviteAsync(player)'
INVITE_NEW = 'SocialService:PromptGameInvite(player)'

# Exact strings from the proximity detection block (5-tab indented, inside pcall/for/if)
PROX_OLD = (
    '\t\t\t\t\tif part and part:IsA("BasePart") then\n'
    '\t\t\t\t\t\tif (root.Position - part.Position).Magnitude < DIST then\n'
    '\t\t\t\t\t\t\tnearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break\n'
    '\t\t\t\t\t\tend\n'
    '\t\t\t\t\tend'
)
PROX_NEW = (
    '\t\t\t\t\tlocal _bp = part\n'
    '\t\t\t\t\tif _bp and not _bp:IsA("BasePart") then\n'
    '\t\t\t\t\t\t_bp = _bp:FindFirstChildWhichIsA("BasePart") or (_bp.Parent and _bp.Parent:IsA("BasePart") and _bp.Parent or nil)\n'
    '\t\t\t\t\tend\n'
    '\t\t\t\t\tif _bp and (root.Position - _bp.Position).Magnitude < DIST then\n'
    '\t\t\t\t\t\tnearStand=true; nearIsland=obj:GetAttribute("IslandNumber") or 1; break\n'
    '\t\t\t\t\tend'
)

source_fixed = False
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

    # Read all sources
    o2 = o; sources = {}
    for ref in refs:
        slen, o2 = ru32(raw, o2); sources[ref] = raw[o2:o2+slen]; o2 += slen

    src = sources[GC_REF].decode('utf-8', 'replace')
    print(f"  Found gameclient source: {len(src)} chars, type_id={tid}")

    # Fix invite
    if INVITE_OLD in src:
        src = src.replace(INVITE_OLD, INVITE_NEW)
        print("  [OK] Invite API fixed: PromptInviteAsync -> PromptGameInvite")
    else:
        print("  [INFO] Invite API already correct or not found")

    # Fix proximity
    if PROX_OLD in src:
        src = src.replace(PROX_OLD, PROX_NEW)
        print("  [OK] Proximity part check fixed (handles Models/Attachments)")
    else:
        print("  [WARN] Proximity pattern not found with exact tabs; checking loose match")
        if 'part:IsA("BasePart")' in src and 'nearStand=true' in src:
            # Fallback: just tolerate non-BaseParts via pcall position lookup
            src = src.replace(
                'if part and part:IsA("BasePart") then',
                'local _bp2=(part and part:IsA("BasePart")) and part or (part and part:FindFirstChildWhichIsA("BasePart")) or nil; if _bp2 then'
            )
            src = src.replace(
                'if (root.Position - part.Position).Magnitude < DIST then',
                'if (root.Position - _bp2.Position).Magnitude < DIST then'
            )
            print("  [OK] Proximity fallback applied")

    sources[GC_REF] = src.encode('utf-8')

    # Rebuild PROP chunk
    new_raw = bytearray()
    new_raw += struct.pack('<I', tid)
    pn_b = b'Source'
    new_raw += struct.pack('<I', len(pn_b)) + pn_b + bytes([0x01])
    for ref in refs:
        s = sources[ref]; new_raw += struct.pack('<I', len(s)) + s

    ch['raw'] = bytes(new_raw); ch['modified'] = True
    print(f"  Source chunk rebuilt: {len(src)} chars")
    source_fixed = True
    break

if not source_fixed:
    print("  [ERROR] gameclient source chunk not found!")

# ---------------------------------------------------------------------------
# FIX PRNT: restore StarterCharacterScripts (8632) to StarterPlayer (8629)
# ---------------------------------------------------------------------------
for ch in chunks:
    if ch['name'] != 'PRNT': continue
    raw   = ch['raw']
    ver   = raw[0]
    count = struct.unpack_from('<I', raw, 1)[0]
    child_refs  = decode_refs(raw[5          : 5+count*4], count)
    parent_refs = decode_refs(raw[5+count*4  : 5+count*8], count)

    changed = False
    if SCS_REF in child_refs:
        idx = child_refs.index(SCS_REF)
        cur = parent_refs[idx]
        if cur != SCS_CORRECT_PARENT:
            parent_refs[idx] = SCS_CORRECT_PARENT
            print(f"  [OK] PRNT: StarterCharacterScripts ({SCS_REF}) parent {cur} -> {SCS_CORRECT_PARENT} (StarterPlayer)")
            changed = True
        else:
            print(f"  [INFO] StarterCharacterScripts already has correct parent {SCS_CORRECT_PARENT}")
    else:
        print(f"  [WARN] StarterCharacterScripts ref {SCS_REF} not found in PRNT")

    if changed:
        new_raw = bytes([ver]) + struct.pack('<I', count) + encode_refs(child_refs) + encode_refs(parent_refs)
        ch['raw'] = new_raw; ch['modified'] = True
    break

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
