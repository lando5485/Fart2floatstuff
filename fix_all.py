#!/usr/bin/env python3
"""Apply 4 fixes to Farttofloatdemo_v3.rbxl"""
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

gc_ref  = next((r for r,n in ref_name.items() if n=='gameclient'), None)
npc_ref = next((r for r,n in ref_name.items() if n=='NPCDialogueHandler'), None)
print(f"gameclient={gc_ref}, NPCDialogueHandler={npc_ref}")

# Low fuel GUI block — inserted before print("GUIS BUILT")
LOW_FUEL_BLOCK = (
    '\n-- ===== GUI 9: LOW FUEL WARNING =====\n'
    'local LowFuelGui = Instance.new("ScreenGui"); LowFuelGui.Name="LowFuelGui"; LowFuelGui.ResetOnSpawn=false; LowFuelGui.Parent=PlayerGui\n'
    'local lowFuelCard = mkFrame(LowFuelGui, {Size=UDim2.new(0,260,0,90), Position=UDim2.new(1,10,0.5,-45), AnchorPoint=Vector2.new(0,0.5), BackgroundColor3=Color3.fromRGB(220,50,50)}); mkCorner(lowFuelCard,14); mkStroke(lowFuelCard, Color3.fromRGB(255,120,120), 3)\n'
    'mkLabel(lowFuelCard, {Text="⚠ LOW FUEL!", Font=Enum.Font.GothamBold, TextSize=22, TextColor3=Color3.new(1,1,1), Size=UDim2.new(1,-10,0,40), Position=UDim2.new(0,5,0,8), TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})\n'
    'mkLabel(lowFuelCard, {Text="Buy food to keep flying!", Font=Enum.Font.Gotham, TextSize=14, TextColor3=Color3.fromRGB(255,200,200), Size=UDim2.new(1,-10,0,28), Position=UDim2.new(0,5,0,50), TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})\n'
    '\n'
    'local function showLowFuelPopup()\n'
    '\tif lowFuelShownThisFlight then return end\n'
    '\tlowFuelShownThisFlight = true\n'
    '\tTweenService:Create(lowFuelCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position=UDim2.new(1,-270,0.5,-45)}):Play()\n'
    'end\n'
    'local function hideLowFuelPopup()\n'
    '\tTweenService:Create(lowFuelCard, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position=UDim2.new(1,10,0.5,-45)}):Play()\n'
    'end\n'
)

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

    o2=o; sources={}
    for ref in refs:
        sl,o2=ru32(raw,o2); sources[ref]=raw[o2:o2+sl]; o2+=sl

    changed=False

    # ===== GAMECLIENT FIXES =====
    if need_gc and gc_ref in sources:
        src = sources[gc_ref].decode('utf-8', 'replace')
        orig = src

        # FIX 1: coin block — remove silent pcall, use clear names, add print
        old1 = (
            '\tif coinTimer >= 0.1 then\n'
            '\t\tcoinTimer=0\n'
            '\t\tlocal h = math.max(0, hrp.Position.Y-5)\n'
            '\t\tlocal cpt = math.floor(h/10)*0.1\n'
            '\t\tif cpt > 0 then\n'
            '\t\t\tpcall(function() if CoinEvent then CoinEvent:FireServer(cpt) end end)\n'
            '\t\t\tcpsLabel.Text = "+"..math.floor(cpt*10).."/sec"; cpsLabel.Visible=true\n'
            '\t\tend\n'
            '\tend'
        )
        new1 = (
            '\tif coinTimer >= 0.1 then\n'
            '\t\tcoinTimer=0\n'
            '\t\tlocal height = math.max(0, hrp.Position.Y - 5)\n'
            '\t\tlocal coinsPerTick = math.floor(height / 10) * 0.1\n'
            '\t\tif coinsPerTick > 0 then\n'
            '\t\t\tif CoinEvent then CoinEvent:FireServer(coinsPerTick) end\n'
            '\t\t\tprint("COIN EARNED", coinsPerTick)\n'
            '\t\t\tcpsLabel.Text = "+"..math.floor(coinsPerTick*10).."/sec"; cpsLabel.Visible=true\n'
            '\t\tend\n'
            '\tend'
        )
        if old1 in src:
            src = src.replace(old1, new1, 1); fixes_applied.append('FIX1 coin block'); print('  [OK] FIX1: coin block')
        else:
            print('  [WARN] FIX1: coin block not found')

        # FIX 2a: panel height 560 -> 600
        old2a = 'Size=UDim2.new(0,700,0,560), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(255,248,200)})'
        new2a = 'Size=UDim2.new(0,700,0,600), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=Color3.fromRGB(255,248,200)})'
        if old2a in src:
            src = src.replace(old2a, new2a, 1); fixes_applied.append('FIX2a panel height'); print('  [OK] FIX2a: panel height 560->600')
        else:
            print('  [WARN] FIX2a: panel height anchor not found')

        # FIX 2b: title PREMIUM SHOP -> SHOP
        old2b = 'Text="PREMIUM SHOP",'
        new2b = 'Text="SHOP",'
        if old2b in src:
            src = src.replace(old2b, new2b, 1); fixes_applied.append('FIX2b title'); print('  [OK] FIX2b: title -> SHOP')
        else:
            print('  [WARN] FIX2b: PREMIUM SHOP not found')

        # FIX 2c: card height 180 -> 200
        old2c = 'Size=UDim2.new(0,200,0,180),'
        new2c = 'Size=UDim2.new(0,200,0,200),'
        if old2c in src:
            src = src.replace(old2c, new2c, 1); fixes_applied.append('FIX2c card height'); print('  [OK] FIX2c: card height 180->200')
        else:
            print('  [WARN] FIX2c: card height not found')

        # FIX 2d: desc label height 30 -> 40
        old2d = 'Size=UDim2.new(1,-10,0,30), Position=UDim2.new(0,5,0,90), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})'
        new2d = 'Size=UDim2.new(1,-10,0,40), Position=UDim2.new(0,5,0,90), TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, BackgroundTransparency=1})'
        if old2d in src:
            src = src.replace(old2d, new2d, 1); fixes_applied.append('FIX2d desc height'); print('  [OK] FIX2d: desc height 30->40')
        else:
            print('  [WARN] FIX2d: desc label not found')

        # FIX 2e: price label y 122 -> 132
        old2e = 'Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,0,122),'
        new2e = 'Size=UDim2.new(1,-10,0,18), Position=UDim2.new(0,5,0,132),'
        if old2e in src:
            src = src.replace(old2e, new2e, 1); fixes_applied.append('FIX2e price y'); print('  [OK] FIX2e: price y 122->132')
        else:
            print('  [WARN] FIX2e: price y not found')

        # FIX 2f: section 2 label y 288 -> 308
        old2f = 'Position=UDim2.new(0,10,0,288),'
        new2f = 'Position=UDim2.new(0,10,0,308),'
        if old2f in src:
            src = src.replace(old2f, new2f, 1); fixes_applied.append('FIX2f section y'); print('  [OK] FIX2f: section label y 288->308')
        else:
            print('  [WARN] FIX2f: section label y not found')

        # FIX 2g: mkCard x/y positions — even spacing in 700px panel
        card_moves = [
            ('mkCard(premPanel,10,95,"PWR",',   'mkCard(premPanel,25,98,"PWR",',   'PWR 10,95->25,98'),
            ('mkCard(premPanel,220,95,"GLTR",',  'mkCard(premPanel,250,98,"GLTR",',  'GLTR 220,95->250,98'),
            ('mkCard(premPanel,430,95,"CLR",',   'mkCard(premPanel,475,98,"CLR",',   'CLR 430,95->475,98'),
            ('mkCard(premPanel,10,315,"2XHR",',  'mkCard(premPanel,25,335,"2XHR",',  '2XHR 10,315->25,335'),
            ('mkCard(premPanel,220,315,"RCHG",', 'mkCard(premPanel,250,335,"RCHG",', 'RCHG 220,315->250,335'),
            ('mkCard(premPanel,430,315,"SKIP",', 'mkCard(premPanel,475,335,"SKIP",', 'SKIP 430,315->475,335'),
        ]
        for old, new, tag in card_moves:
            if old in src:
                src = src.replace(old, new, 1); fixes_applied.append(f'FIX2g {tag}'); print(f'  [OK] FIX2g: {tag}')
            else:
                print(f'  [WARN] FIX2g: {tag} not found')

        # FIX 3a: add lowFuelShownThisFlight variable after nearIslandNumber
        old3a = 'local nearIslandNumber = 1\n'
        new3a = 'local nearIslandNumber = 1\nlocal lowFuelShownThisFlight = false\n'
        if old3a in src and 'lowFuelShownThisFlight' not in src:
            src = src.replace(old3a, new3a, 1); fixes_applied.append('FIX3a var'); print('  [OK] FIX3a: lowFuelShownThisFlight var added')
        elif 'lowFuelShownThisFlight' in src:
            print('  [INFO] FIX3a: lowFuelShownThisFlight already present')
        else:
            print('  [WARN] FIX3a: nearIslandNumber anchor not found')

        # FIX 3b: insert LowFuelGui + show/hide functions before GUIS BUILT print
        if 'LowFuelGui' not in src:
            anchor = '\nprint("GUIS BUILT")\n'
            if anchor in src:
                src = src.replace(anchor, LOW_FUEL_BLOCK + anchor, 1)
                fixes_applied.append('FIX3b LowFuelGui'); print('  [OK] FIX3b: LowFuelGui inserted')
            else:
                print('  [WARN] FIX3b: GUIS BUILT anchor not found')
        else:
            print('  [INFO] FIX3b: LowFuelGui already present')

        # FIX 3c: updateMeter — add low fuel check
        old3c = ('\tgasPowerText.Text = math.floor(gasMeter).." / "..math.floor(maxGas)\n'
                 'end\n'
                 '\n'
                 'local function updateFartBtn()')
        new3c = ('\tgasPowerText.Text = math.floor(gasMeter).." / "..math.floor(maxGas)\n'
                 '\tif isFlying and fill < 0.25 then showLowFuelPopup() end\n'
                 'end\n'
                 '\n'
                 'local function updateFartBtn()')
        if old3c in src:
            src = src.replace(old3c, new3c, 1); fixes_applied.append('FIX3c updateMeter'); print('  [OK] FIX3c: updateMeter low fuel check')
        else:
            print('  [WARN] FIX3c: updateMeter anchor not found')

        # FIX 3d: startFlying — reset lowFuelShownThisFlight
        old3d = ('local function startFlying()\n'
                 '\tif gasMeter <= 0 or not hrp then return end\n'
                 '\tisFlying = true\n'
                 '\tif bv then bv:Destroy() end')
        new3d = ('local function startFlying()\n'
                 '\tif gasMeter <= 0 or not hrp then return end\n'
                 '\tisFlying = true\n'
                 '\tlowFuelShownThisFlight = false\n'
                 '\tif bv then bv:Destroy() end')
        if old3d in src:
            src = src.replace(old3d, new3d, 1); fixes_applied.append('FIX3d startFlying'); print('  [OK] FIX3d: startFlying reset flag')
        else:
            print('  [WARN] FIX3d: startFlying anchor not found')

        # FIX 3e: stopFlying — call hideLowFuelPopup
        old3e = ('\tcpsLabel.Visible = false\n'
                 '\tupdateFartBtn()\n'
                 'end')
        new3e = ('\tcpsLabel.Visible = false\n'
                 '\thideLowFuelPopup()\n'
                 '\tupdateFartBtn()\n'
                 'end')
        if old3e in src:
            src = src.replace(old3e, new3e, 1); fixes_applied.append('FIX3e stopFlying'); print('  [OK] FIX3e: stopFlying hide popup')
        else:
            print('  [WARN] FIX3e: stopFlying anchor not found')

        if src != orig:
            sources[gc_ref] = src.encode('utf-8')
            changed = True

    # ===== NPC FIXES =====
    if need_npc and npc_ref in sources:
        src = sources[npc_ref].decode('utf-8', 'replace')
        orig = src

        # FIX 4: pcall + timeout for WaitForChild("DialogueGui")
        old4 = ('local gui = player:WaitForChild("PlayerGui"):WaitForChild("DialogueGui")\n'
                 'local textLabel = gui:WaitForChild("DialogueText")')
        new4 = ('local ok, gui = pcall(function() return player:WaitForChild("PlayerGui"):WaitForChild("DialogueGui", 5) end)\n'
                 'if not ok or not gui then return end\n'
                 'local textLabel = gui:WaitForChild("DialogueText", 5)\n'
                 'if not textLabel then return end')
        if old4 in src:
            src = src.replace(old4, new4, 1); fixes_applied.append('FIX4 NPC pcall'); print('  [OK] FIX4: NPC DialogueGui pcall+timeout')
        else:
            lines = src.split('\n')
            print('  [WARN] FIX4: NPC anchor not found')
            print(f'    line 5: {repr(lines[4] if len(lines)>4 else "N/A")}')
            print(f'    line 6: {repr(lines[5] if len(lines)>5 else "N/A")}')

        if src != orig:
            sources[npc_ref] = src.encode('utf-8')
            changed = True

    if changed:
        new_raw = bytearray(struct.pack('<I', tid))
        pn_b = b'Source'
        new_raw += struct.pack('<I', len(pn_b)) + pn_b + bytes([0x01])
        for ref in refs:
            s = sources[ref]
            new_raw += struct.pack('<I', len(s)) + s
        ch['raw'] = bytes(new_raw)
        ch['modified'] = True

out = bytearray(header)
for ch in chunks:
    if ch['modified']: out += write_unc(ch['name'], ch['raw'])
    else: out += ch['orig']

with open(FILE, 'wb') as fh: fh.write(out)
print(f"\nSaved: {len(out):,} bytes")
print(f"\nFixes applied ({len(fixes_applied)}):")
for fx in fixes_applied:
    print(f"  {fx}")
print("\nALL FIXES DONE")
