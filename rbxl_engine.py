#!/usr/bin/env python3
"""RBXL binary format read/write engine."""
import struct, zstandard, lz4.block

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'

def decompress_data(data_bytes, uncomp_len):
    if len(data_bytes) >= 4 and data_bytes[:4] == ZSTD_MAGIC:
        return zstandard.ZstdDecompressor().decompress(data_bytes)
    if uncomp_len > 0:
        return lz4.block.decompress(bytes(data_bytes), uncompressed_size=uncomp_len)
    return bytes(data_bytes)

def compress_data(raw):
    cctx = zstandard.ZstdCompressor(level=3)
    return cctx.compress(raw)

def ru32(d, o): return struct.unpack_from('<I', d, o)[0], o+4
def rstr(d, o):
    n, o = ru32(d, o)
    return d[o:o+n].decode('utf-8', 'replace'), o+n

def decode_refs(data, count):
    vals = []
    for i in range(count):
        v = (data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1, len(vals)): vals[i] += vals[i-1]
    return vals

def parse_file(filepath):
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())
    header = bytes(data[0:32])
    chunks = []  # list of [name, raw, orig_comp_len, orig_uncomp_len, orig_bytes]
    offset = 32
    while offset < len(data):
        name = data[offset:offset+4].decode('latin-1')
        comp  = struct.unpack_from('<I', data, offset+4)[0]
        uncomp= struct.unpack_from('<I', data, offset+8)[0]
        orig_start = offset
        offset += 16
        if comp == 0:
            raw = bytes(data[offset:offset+uncomp])
            offset += uncomp
        else:
            raw = decompress_data(bytes(data[offset:offset+comp]), uncomp)
            offset += comp
        orig_bytes = bytes(data[orig_start:offset])
        chunks.append([name, raw, comp, uncomp, orig_bytes])
        if name == 'END\x00': break
    return header, chunks

def build_inst_map(chunks):
    inst_map = {}
    for name, raw, *_ in chunks:
        if name != 'INST': continue
        o = 0
        tid, o = ru32(raw, o)
        cname, o = rstr(raw, o)
        o += 1  # is_service
        count, o = ru32(raw, o)
        ids = decode_refs(raw[o:o+count*4], count)
        inst_map[tid] = (cname, ids)
    return inst_map

def build_prop_names(chunks, inst_map):
    names = {}  # ref -> name
    for name, raw, *_ in chunks:
        if name != 'PROP': continue
        o = 0
        tid, o = ru32(raw, o)
        pname, o = rstr(raw, o)
        dtype = raw[o]; o += 1
        if dtype != 0x01 or pname != 'Name': continue
        _, ids = inst_map.get(tid, ('?', []))
        for ref in ids:
            slen, o = ru32(raw, o)
            s = raw[o:o+slen].decode('utf-8', 'replace')
            names[ref] = s
            o += slen
    return names

def modify_source_chunk(raw, inst_ids, ref_to_new_source):
    """Given a decoded Source PROP chunk raw bytes, replace sources for specified refs."""
    o = 0
    tid, o = ru32(raw, o)
    pname, o = rstr(raw, o)
    dtype = raw[o]; o += 1
    assert dtype == 0x01, f"Expected string type, got {dtype}"

    # Read all strings
    strings = []
    for _ in inst_ids:
        slen, o = ru32(raw, o)
        s = raw[o:o+slen]
        strings.append(s)
        o += slen

    # Apply modifications
    for i, ref in enumerate(inst_ids):
        if ref in ref_to_new_source:
            strings[i] = ref_to_new_source[ref].encode('utf-8')

    # Re-encode
    result = bytearray()
    result += struct.pack('<I', tid)
    pname_b = pname.encode('utf-8')
    result += struct.pack('<I', len(pname_b)) + pname_b
    result += bytes([0x01])
    for s in strings:
        result += struct.pack('<I', len(s)) + s
    return bytes(result)

def encode_chunk(name, raw):
    name_b = name.encode('latin-1')[:4].ljust(4, b'\x00')
    comp = compress_data(raw)
    return name_b + struct.pack('<III', len(comp), len(raw), 0) + comp

def write_file(filepath, header, chunks):
    out = bytearray(header)
    for name, raw, comp, uncomp, orig_bytes in chunks:
        if raw is None:
            out += orig_bytes
        elif comp == -1:  # modified - recompress
            out += encode_chunk(name, raw)
        else:
            out += orig_bytes
    with open(filepath, 'wb') as f:
        f.write(out)
