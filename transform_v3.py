#!/usr/bin/env python3
"""Apply all v3 changes to fart2floatbuild.rbxl -> Farttofloatdemo_v3.rbxl"""
import sys, os
sys.path.insert(0, r'C:\Users\lando\Downloads\Fart2floatstuff')

from rbxl_engine import (
    parse_file, build_inst_map, build_prop_names,
    modify_source_chunk, encode_chunk, write_file,
    ru32, rstr
)
from sources_server import GAMESERVER_SOURCE, PLAYERSTATS_SOURCE
from sources_client import GAMECLIENT_SOURCE

INFILE  = r'C:\Users\lando\Downloads\Fart2floatstuff\fart2floatbuild.rbxl'
OUTFILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v3.rbxl'

print("Parsing file...")
header, chunks = parse_file(INFILE)
inst_map   = build_inst_map(chunks)
all_names  = build_prop_names(chunks, inst_map)  # ref -> name

# Reverse: for each script type, map ref -> name
print("\nScript types found:")
script_ref_to_name = {}
for tid, (cname, ids) in inst_map.items():
    if cname in ('Script', 'LocalScript', 'ModuleScript'):
        for ref in ids:
            script_ref_to_name[ref] = all_names.get(ref, f'<{ref}>')
        print(f"  type_id={tid} class={cname} count={len(ids)}")
        for ref in ids:
            print(f"    ref={ref} name={all_names.get(ref,'?')}")

# Build lookup: name -> ref  for scripts we care about
name_to_ref = {v: k for k, v in script_ref_to_name.items()}
print("\nTarget script refs:")
for n in ('gameserver', 'gameclient', 'PlayerStats'):
    print(f"  {n} -> ref={name_to_ref.get(n)}")

# ----------------------------------------------------------------
# Modifications to apply: ref -> new_source
# ----------------------------------------------------------------
mods = {}

ref_gameserver = name_to_ref.get('gameserver')
ref_gameclient = name_to_ref.get('gameclient')
ref_playerstats= name_to_ref.get('PlayerStats')

if ref_gameserver:
    mods[ref_gameserver] = GAMESERVER_SOURCE
    print(f"Will disable gameserver (ref={ref_gameserver})")
else:
    print("WARNING: gameserver not found")

if ref_gameclient:
    mods[ref_gameclient] = GAMECLIENT_SOURCE
    print(f"Will rewrite gameclient as FartButton (ref={ref_gameclient})")
else:
    print("WARNING: gameclient not found")

if ref_playerstats:
    mods[ref_playerstats] = PLAYERSTATS_SOURCE
    print(f"Will rewrite PlayerStats (ref={ref_playerstats})")
else:
    print("WARNING: PlayerStats not found")

# ----------------------------------------------------------------
# Walk chunks and modify Source PROP chunks
# ----------------------------------------------------------------
modified_count = 0

for i, (chunk_name, raw, comp, uncomp, orig_bytes) in enumerate(chunks):
    if chunk_name != 'PROP':
        continue

    # Read prop header
    o = 0
    tid, o = ru32(raw, o)
    pname, o = rstr(raw, o)
    dtype = raw[o]

    if pname != 'Source' or dtype != 0x01:
        continue

    cname, ids = inst_map.get(tid, ('?', []))
    if cname not in ('Script', 'LocalScript'):
        continue

    # Check if any refs in this chunk need modification
    needs_mod = any(ref in mods for ref in ids)
    if not needs_mod:
        continue

    print(f"\nModifying Source PROP chunk for type_id={tid} ({cname}), {len(ids)} instances:")
    for ref in ids:
        if ref in mods:
            name = all_names.get(ref, f'<{ref}>')
            print(f"  -> Replacing source for '{name}' (ref={ref}), new_len={len(mods[ref])}")

    new_raw = modify_source_chunk(raw, ids, mods)
    chunks[i] = [chunk_name, new_raw, -1, len(new_raw), orig_bytes]  # comp=-1 = needs recompression
    modified_count += 1

print(f"\nModified {modified_count} PROP chunk(s)")

# ----------------------------------------------------------------
# Write output
# ----------------------------------------------------------------
print(f"Writing {OUTFILE} ...")

out = bytearray(header)
for chunk_name, raw, comp, uncomp, orig_bytes in chunks:
    if comp == -1:
        # Recompress
        out += encode_chunk(chunk_name, raw)
    else:
        out += orig_bytes

with open(OUTFILE, 'wb') as f:
    f.write(out)

size_in  = os.path.getsize(INFILE)
size_out = os.path.getsize(OUTFILE)
print(f"Input size:  {size_in:,} bytes")
print(f"Output size: {size_out:,} bytes")
print("\nV3 COMPLETE")
