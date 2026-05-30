#!/usr/bin/env python3
"""Inject scripts and remote events into Farttofloatdemo_v4.rbxlx"""
import struct, os, random, uuid

try: import zstandard; HAS_ZSTD=True
except: HAS_ZSTD=False
try: import lz4.block; HAS_LZ4=True
except: HAS_LZ4=False

ZSTD_MAGIC = b'\x28\xb5\x2f\xfd'
FILE = r'C:\Users\lando\Downloads\Fart2floatstuff\Farttofloatdemo_v4.rbxlx'
DUMP = r'C:\Users\lando\Downloads\Fart2floatstuff\scripts_dump'

# Known structure from analysis
LS_TID = 37; RE_TID = 58; SC_TID = 61
SPS_REF = 8601; SSS_REF = 8652; RS_REF = 8647
GAMECLIENT_REF = 8602; PLAYERSTATS_REF = 8653
# Existing LS refs [8602=gameclient, 8604=NPCDialogueHandler]
# Existing RE refs [8648=BuyFoodEvent, 8649=RegenEvent, 8650=CoinEvent, 8651=SkipIslandEvent]
# Existing SC refs [8644=CoreTextureSystem, 8653=PlayerStats, 8655=gameserver]

NEW_RE_REFS  = [8966, 8967, 8968]
NEW_RE_NAMES = ['IslandUnlockEvent', 'AnnouncementEvent', 'ServerEventNotify']
NEW_LS_REFS  = [8969, 8970, 8971]
NEW_LS_NAMES = ['ShopClient', 'WorldClient', 'EventClient']

# ── Helpers ──────────────────────────────────────────────────────────────────
def decomp(d, u):
    if len(d)>=4 and d[:4]==ZSTD_MAGIC and HAS_ZSTD: return zstandard.ZstdDecompressor().decompress(d)
    if HAS_LZ4 and u>0: return lz4.block.decompress(bytes(d), uncompressed_size=u)
    return bytes(d)
def ru32(d,o): return struct.unpack_from('<I',d,o)[0], o+4
def wu32(v): return struct.pack('<I',v)
def rstr(d,o):
    n,o=ru32(d,o); return d[o:o+n].decode('utf-8','replace'), o+n
def decode_refs(data, count):
    vals=[]
    for i in range(count):
        v=(data[i]<<24)|(data[count+i]<<16)|(data[2*count+i]<<8)|data[3*count+i]
        vals.append(-(v>>1)-1 if v&1 else v>>1)
    for i in range(1,len(vals)): vals[i]+=vals[i-1]
    return vals
def encode_refs(vals):
    delta=[vals[0]]+[vals[i]-vals[i-1] for i in range(1,len(vals))]
    zz=[(-v*2-1 if v<0 else v*2) for v in delta]
    count=len(zz); result=bytearray(count*4)
    for i,v in enumerate(zz):
        result[i]=(v>>24)&0xFF; result[count+i]=(v>>16)&0xFF
        result[2*count+i]=(v>>8)&0xFF; result[3*count+i]=v&0xFF
    return bytes(result)
def deinterleave4(data, count):
    return [bytes([data[i],data[count+i],data[2*count+i],data[3*count+i]]) for i in range(count)]
def reinterleave4(vals):
    count=len(vals); result=bytearray(count*4)
    for i,v in enumerate(vals):
        result[i]=v[0]; result[count+i]=v[1]; result[2*count+i]=v[2]; result[3*count+i]=v[3]
    return bytes(result)
def deinterleave8(data, count):
    return [bytes([data[j*count+i] for j in range(8)]) for i in range(count)]
def reinterleave8(vals):
    count=len(vals); result=bytearray(count*8)
    for i,v in enumerate(vals):
        for j in range(8): result[j*count+i]=v[j]
    return bytes(result)
def write_unc(nm_bytes, raw):
    return nm_bytes + struct.pack('<III',0,len(raw),0) + raw
def make_guid():
    return ('{'+str(uuid.uuid4()).upper()+'}').encode('utf-8')

# ── Lua Sources ───────────────────────────────────────────────────────────────
PLAYERSTATS_SRC = r"""print("PLAYERSTATS STARTED")
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")

local function getOrCreate(parent,cn,name)
	local o=parent:FindFirstChild(name)
	if not o then o=Instance.new(cn); o.Name=name; o.Parent=parent end; return o
end

local BuyFoodEvent=getOrCreate(RS,"RemoteEvent","BuyFoodEvent")
local RegenEvent=getOrCreate(RS,"RemoteEvent","RegenEvent")
local CoinEvent=getOrCreate(RS,"RemoteEvent","CoinEvent")
local SkipIslandEvent=getOrCreate(RS,"RemoteEvent","SkipIslandEvent")
local IslandUnlockEvent=getOrCreate(RS,"RemoteEvent","IslandUnlockEvent")
local AnnouncementEvent=getOrCreate(RS,"RemoteEvent","AnnouncementEvent")
local ServerEventNotify=getOrCreate(RS,"RemoteEvent","ServerEventNotify")

local ISLAND_DISPLAY_NAMES={"Bean Farm","Broccoli Bluff","Cabbage Cliffs","Turnip Tranquil","Coconut Cove","Bread Board","Pasta Peak","Popcorn Pinnacle","Milk Marsh","Butter Swamp","Ice Cream Isle","Burger Bluff","Burrito Barrens","Pizza Palms"}
local ISLAND_NAMES={"Island_1_BeanFarm","Island_2_BroccoliBluff","Island_3_CabbageCliffs","Island_4_TurnipTranquil","Island_5_CoconutCove","Island_6_BreadBoard","Island_7_PastaPeak","Island_8_PopcornPinnacle","Island_9_MilkMarsh","Island_10_ButterSwamp","Island_11_IceCreamIsle","Island_12_BurgerBluff","Island_13_BurritoBarrens","Island_14_PizzaPalms"}
local ISLAND_POS={{x=0,y=50,z=0},{x=120,y=600,z=60},{x=-160,y=1400,z=100},{x=180,y=2500,z=-120},{x=-200,y=4000,z=160},{x=220,y=6000,z=-180},{x=-240,y=8500,z=200},{x=260,y=11500,z=-220},{x=-280,y=15000,z=240},{x=300,y=19000,z=-260},{x=-320,y=24000,z=280},{x=340,y=30000,z=-300},{x=-360,y=37000,z=320},{x=380,y=45000,z=-340}}
local foods={{name="Beans",price=10,power=3,island=1},{name="Broccoli",price=25,power=5,island=2},{name="Cabbage",price=50,power=8,island=3},{name="Turnips",price=100,power=12,island=4},{name="Coconuts",price=250,power=18,island=5},{name="Bread",price=500,power=26,island=6},{name="Pasta",price=1000,power=37,island=7},{name="Popcorn",price=2500,power=52,island=8},{name="Milk",price=5000,power=72,island=9},{name="Butter",price=10000,power=98,island=10},{name="IceCream",price=25000,power=132,island=11},{name="Burger",price=50000,power=175,island=12},{name="Burrito",price=75000,power=225,island=13},{name="Pizza",price=100000,power=280,island=14}}

local function getFoodByName(n) for _,f in ipairs(foods) do if f.name==n then return f end end end

task.spawn(function()
	task.wait(2)
	for i,iname in ipairs(ISLAND_NAMES) do
		local model=workspace:FindFirstChild(iname)
		local pos=ISLAND_POS[i]
		if model then
			pcall(function()
				if model:IsA("Model") then
					if model.PrimaryPart then model:SetPrimaryPartCFrame(CFrame.new(pos.x,pos.y,pos.z))
					else model:MoveTo(Vector3.new(pos.x,pos.y,pos.z)) end
				end
			end)
			for _,obj in ipairs(model:GetDescendants()) do
				if obj:IsA("ProximityPrompt") and obj.ObjectText=="Stand" then
					obj:SetAttribute("IslandNumber",i); obj.Style=Enum.ProximityPromptStyle.Custom; obj.Enabled=false
				end
			end
		end
	end
	print("ISLANDS POSITIONED")
end)

local playerCoinAccum={}

Players.PlayerAdded:Connect(function(player)
	local ls=Instance.new("Folder"); ls.Name="leaderstats"; ls.Parent=player
	local coins=Instance.new("IntValue"); coins.Name="Coins"; coins.Value=50; coins.Parent=ls
	local island=Instance.new("IntValue"); island.Name="Island"; island.Value=1; island.Parent=ls
	local tfp=Instance.new("IntValue"); tfp.Name="TotalFartPower"; tfp.Value=0; tfp.Parent=ls
	local tce=Instance.new("IntValue"); tce.Name="TotalCoinsEarned"; tce.Value=0; tce.Parent=ls
	playerCoinAccum[player]=0
end)

Players.PlayerRemoving:Connect(function(player) playerCoinAccum[player]=nil end)

BuyFoodEvent.OnServerEvent:Connect(function(player,foodName)
	local food=getFoodByName(foodName); if not food then return end
	local ls=player:FindFirstChild("leaderstats"); if not ls then return end
	local coins=ls:FindFirstChild("Coins"); local tfp=ls:FindFirstChild("TotalFartPower")
	local tce=ls:FindFirstChild("TotalCoinsEarned"); local island=ls:FindFirstChild("Island")
	if not coins or not tfp or not tce then return end
	if island and food.island>island.Value then return end
	if coins.Value<food.price then return end
	coins.Value=coins.Value-food.price; tfp.Value=tfp.Value+food.power; tce.Value=tce.Value+food.price
	pcall(function() RegenEvent:FireClient(player,food.power) end)
end)

CoinEvent.OnServerEvent:Connect(function(player,amount)
	local ls=player:FindFirstChild("leaderstats"); if not ls then return end
	local coins=ls:FindFirstChild("Coins"); local tce=ls:FindFirstChild("TotalCoinsEarned")
	if not coins or not tce then return end
	local amt=tonumber(amount) or 0; if amt<=0 then return end
	playerCoinAccum[player]=(playerCoinAccum[player] or 0)+amt
	local toAdd=math.floor(playerCoinAccum[player])
	if toAdd>0 then playerCoinAccum[player]=playerCoinAccum[player]-toAdd; coins.Value=coins.Value+toAdd; tce.Value=tce.Value+toAdd end
end)

IslandUnlockEvent.OnServerEvent:Connect(function(player,islandNum)
	local ls=player:FindFirstChild("leaderstats"); if not ls then return end
	local island=ls:FindFirstChild("Island"); if not island then return end
	local n=tonumber(islandNum) or 0
	if n>island.Value and n<=14 then
		island.Value=n
		local iname=ISLAND_DISPLAY_NAMES[n] or ("Island "..n)
		pcall(function() AnnouncementEvent:FireAllClients(player.Name,n,iname) end)
	end
end)

SkipIslandEvent.OnServerEvent:Connect(function(player)
	local ls=player:FindFirstChild("leaderstats"); if not ls then return end
	local island=ls:FindFirstChild("Island"); if not island then return end
	if island.Value<14 then island.Value=island.Value+1 end
end)

local DUR=10
local eventPool={
	{name="FART_STORM",dispName="\xF0\x9F\x92\xA8 FART STORM",msg="\xF0\x9F\x92\xA8 FART STORM! Fly faster!",r=100,g=200,b=255},
	{name="COIN_RUSH",dispName="\xF0\x9F\xAA\x99 COIN RUSH",msg="\xF0\x9F\xAA\x99 COIN RUSH! Triple coins!",r=255,g=200,b=0},
	{name="LOW_GRAVITY",dispName="\xF0\x9F\x8C\x99 LOW GRAVITY",msg="\xF0\x9F\x8C\x99 LOW GRAVITY! Float!",r=150,g=100,b=255},
	{name="POWER_SURGE",dispName="\xE2\x9A\xA1 POWER SURGE",msg="\xE2\x9A\xA1 POWER SURGE! Fly higher!",r=255,g=255,b=0},
	{name="RING_FEVER",dispName="\xF0\x9F\x8E\xAF RING FEVER",msg="\xF0\x9F\x8E\xAF RING FEVER! Ring bonuses!",r=255,g=100,b=200},
}
local weatherPool={
	{name="THUNDERSTORM",dispName="\xe2\x9b\x88 THUNDERSTORM",msg="\xe2\x9b\x88 THUNDERSTORM!",r=50,g=50,b=80},
	{name="WINDSTORM",dispName="\xF0\x9F\x92\xA8 WIND STORM",msg="\xF0\x9F\x92\xA8 WIND STORM!",r=100,g=150,b=200},
}
task.spawn(function()
	task.wait(30)
	local wi=1
	while true do
		local ev=eventPool[math.random(#eventPool)]
		pcall(function() ServerEventNotify:FireAllClients(ev.name,ev.dispName,DUR,ev.msg,Color3.fromRGB(ev.r,ev.g,ev.b)) end)
		task.wait(DUR)
		pcall(function() ServerEventNotify:FireAllClients("END","",0,"",Color3.new(1,1,1)) end)
		task.wait(240)
		local we=weatherPool[wi]; wi=wi%#weatherPool+1
		pcall(function() ServerEventNotify:FireAllClients(we.name,we.dispName,DUR,we.msg,Color3.fromRGB(we.r,we.g,we.b)) end)
		task.wait(DUR)
		pcall(function() ServerEventNotify:FireAllClients("END","",0,"",Color3.new(1,1,1)) end)
		task.wait(240)
	end
end)
print("PLAYERSTATS READY")
"""

def load_and_patch(filename, substitutions=None):
    path = os.path.join(DUMP, filename)
    src = open(path, 'r', encoding='utf-8').read()
    if substitutions:
        for old, new in substitutions:
            src = src.replace(old, new)
    return src.encode('utf-8')

# Load and patch Lua sources
CORECLIENT_SRC = load_and_patch('CoreClient.lua', [
    ('UnlockIslandEvent', 'IslandUnlockEvent'),
    ('totalPower * 1.6', '8 * totalPower'),
    ('flightStartY + totalPower', '50 + totalPower'),
])
SHOPCLIENT_SRC  = load_and_patch('ShopClient.lua')
WORLDCLIENT_SRC = load_and_patch('WorldClient.lua', [
    ('UnlockIslandEvent', 'IslandUnlockEvent'),
])
EVENTCLIENT_SRC = load_and_patch('EventClient.lua')

PLAYERSTATS_BYTES = PLAYERSTATS_SRC.encode('utf-8')

print(f"Sources: PlayerStats={len(PLAYERSTATS_BYTES)} CoreClient={len(CORECLIENT_SRC)} "
      f"ShopClient={len(SHOPCLIENT_SRC)} WorldClient={len(WORLDCLIENT_SRC)} EventClient={len(EVENTCLIENT_SRC)}")

# ── Parse file ────────────────────────────────────────────────────────────────
print(f"\nReading {FILE} ...")
with open(FILE,'rb') as f: data=bytearray(f.read())
print(f"  Size: {len(data):,} bytes")

header=bytes(data[:32]); chunks=[]; offset=32
while offset<len(data):
    nm_bytes=bytes(data[offset:offset+4]); nm=nm_bytes.decode('latin-1')
    comp=struct.unpack_from('<I',data,offset+4)[0]; uncomp=struct.unpack_from('<I',data,offset+8)[0]
    cs=offset; offset+=16
    if comp==0: raw=bytes(data[offset:offset+uncomp]); offset+=uncomp
    else: raw=decomp(bytes(data[offset:offset+comp]),uncomp); offset+=comp
    orig=bytes(data[cs:offset])
    chunks.append({'nm':nm,'nm_bytes':nm_bytes,'raw':bytearray(raw),'orig':orig,'modified':False})
    if nm=='END\x00': break
print(f"  Parsed {len(chunks)} chunks")

# ── Build inst_map ─────────────────────────────────────────────────────────────
inst_map={}
for ch in chunks:
    if ch['nm']!='INST': continue
    raw=bytes(ch['raw']); o=0
    tid,o=ru32(raw,o); cname,o=rstr(raw,o); svc=raw[o]; o+=1
    count,o=ru32(raw,o); refs=decode_refs(raw[o:o+count*4],count)
    inst_map[tid]=(cname,refs,svc)

old_ls_refs = list(inst_map[LS_TID][1])  # [8602, 8604]
old_re_refs = list(inst_map[RE_TID][1])  # [8648,8649,8650,8651]
old_sc_refs = list(inst_map[SC_TID][1])  # [8644,8653,8655]

# ── INST: extend LocalScript with 3 new refs ──────────────────────────────────
new_ls_refs = old_ls_refs + NEW_LS_REFS
for ch in chunks:
    if ch['nm']!='INST': continue
    raw=bytes(ch['raw']); o=0; tid,o=ru32(raw,o); cname,o=rstr(raw,o)
    if cname!='LocalScript': continue
    svc=raw[o]; o+=1
    new_raw=bytearray()+wu32(tid)
    cb=cname.encode(); new_raw+=wu32(len(cb))+cb+bytes([svc])+wu32(len(new_ls_refs))+encode_refs(new_ls_refs)
    ch['raw']=bytes(new_raw); ch['modified']=True
    print(f"  INST LocalScript: {len(old_ls_refs)} -> {len(new_ls_refs)} refs")
    break

# ── INST: extend RemoteEvent with 3 new refs ──────────────────────────────────
new_re_refs = old_re_refs + NEW_RE_REFS
for ch in chunks:
    if ch['nm']!='INST': continue
    raw=bytes(ch['raw']); o=0; tid,o=ru32(raw,o); cname,o=rstr(raw,o)
    if cname!='RemoteEvent': continue
    svc=raw[o]; o+=1
    new_raw=bytearray()+wu32(tid)
    cb=cname.encode(); new_raw+=wu32(len(cb))+cb+bytes([svc])+wu32(len(new_re_refs))+encode_refs(new_re_refs)
    ch['raw']=bytes(new_raw); ch['modified']=True
    print(f"  INST RemoteEvent: {len(old_re_refs)} -> {len(new_re_refs)} refs")
    break

# ── PRNT: add new parent-child pairs ─────────────────────────────────────────
for ch in chunks:
    if ch['nm']!='PRNT': continue
    raw=bytes(ch['raw']); o=0; ver=raw[o]; o+=1
    cnt=struct.unpack_from('<I',raw,o)[0]; o+=4
    kids=decode_refs(raw[o:o+cnt*4],cnt); o+=cnt*4
    pars=decode_refs(raw[o:o+cnt*4],cnt)
    new_kids = kids + NEW_RE_REFS + NEW_LS_REFS
    new_pars = pars + [RS_REF]*3 + [SPS_REF]*3
    new_raw=bytearray([ver])+struct.pack('<I',len(new_kids))+encode_refs(new_kids)+encode_refs(new_pars)
    ch['raw']=bytes(new_raw); ch['modified']=True
    print(f"  PRNT: {cnt} -> {len(new_kids)} pairs")
    break

# ── PROP chunks: LocalScript ──────────────────────────────────────────────────
# Parse existing LS Name PROP to get old names
old_ls_names={}
for ch in chunks:
    if ch['nm']!='PROP': continue
    raw=bytes(ch['raw']); o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if tid!=LS_TID or pn!='Name' or dt!=0x01: continue
    for ref in old_ls_refs:
        sl,o=ru32(raw,o); old_ls_names[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    break

# Build full LS name list (rename gameclient->CoreClient, append 3 new)
ls_all_refs = old_ls_refs + NEW_LS_REFS
ls_all_names = []
for r in old_ls_refs:
    ls_all_names.append('CoreClient' if r==GAMECLIENT_REF else old_ls_names.get(r,'?'))
ls_all_names += NEW_LS_NAMES

# Source map for LS
ls_sources = {}
for r in old_ls_refs:
    if r == GAMECLIENT_REF: ls_sources[r] = CORECLIENT_SRC
    # others unchanged - will be read from existing source prop
ls_new_sources = [SHOPCLIENT_SRC, WORLDCLIENT_SRC, EVENTCLIENT_SRC]

n_old_ls = len(old_ls_refs); n_new_ls = len(NEW_LS_REFS)

# Also handle Source for SC_TID (Script) - replace PlayerStats
old_sc_names={}
for ch in chunks:
    if ch['nm']!='PROP': continue
    raw=bytes(ch['raw']); o=0; tid,o=ru32(raw,o); pn,o=rstr(raw,o); dt=raw[o]; o+=1
    if tid!=SC_TID or pn!='Name' or dt!=0x01: continue
    for ref in old_sc_refs:
        sl,o=ru32(raw,o); old_sc_names[ref]=raw[o:o+sl].decode('utf-8','replace'); o+=sl
    break

n_old_re = len(old_re_refs); n_new_re = len(NEW_RE_REFS)

def extend_prop(raw, o, dt, old_count, n_new, old_sources=None, new_sources=None,
                old_names=None, new_names=None, replace_map=None, prop_name=None,
                all_names=None):
    """Return extended raw bytes after the header (starting from values)."""
    pn_part = b''  # Not needed here, caller reassembles header
    if dt == 0x01:
        old_strs = []
        oo = o
        for _ in range(old_count):
            sl,oo = ru32(raw,oo); old_strs.append(raw[oo:oo+sl]); oo+=sl
        result = bytearray()
        if prop_name == 'Name' and all_names is not None:
            for nm in all_names:
                nb = nm.encode('utf-8'); result += wu32(len(nb))+nb
        elif prop_name == 'Source':
            for i,s in enumerate(old_strs):
                ref_val = None
                if replace_map and i < len(replace_map):
                    ref_val = replace_map[i]
                result += wu32(len(ref_val))+ref_val if ref_val else wu32(len(s))+s
            if new_sources:
                for s in new_sources: result += wu32(len(s))+s
        elif prop_name == 'ScriptGuid':
            for s in old_strs: result += wu32(len(s))+s
            for _ in range(n_new): g=make_guid(); result += wu32(len(g))+g
        else:
            for s in old_strs: result += wu32(len(s))+s
            for _ in range(n_new): result += wu32(0)
        return bytes(result)
    elif dt == 0x02:
        return raw[o:] + bytes(n_new)
    elif dt == 0x12:
        vals = deinterleave4(raw[o:], old_count) + [b'\x00\x00\x00\x00']*n_new
        return reinterleave4(vals)
    elif dt == 0x1b:
        vals = deinterleave8(raw[o:], old_count) + [b'\x00'*8]*n_new
        return reinterleave8(vals)
    elif dt == 0x1f:
        return raw[o:] + b''.join(bytes([random.randint(0,255) for _ in range(16)]) for _ in range(n_new))
    elif dt == 0x21:
        return raw[o:] + bytes(8*n_new)
    else:
        return raw[o:]  # unchanged

for ch in chunks:
    if ch['nm'] != 'PROP': continue
    raw = bytes(ch['raw']); o = 0
    tid,o = ru32(raw,o); pn,o = rstr(raw,o); dt = raw[o]; o += 1

    if tid == LS_TID:
        pn_b = pn.encode('utf-8'); hdr = wu32(tid)+wu32(len(pn_b))+pn_b+bytes([dt])
        if pn == 'Name':
            vals = extend_prop(raw,o,dt,n_old_ls,n_new_ls,prop_name='Name',all_names=ls_all_names)
        elif pn == 'Source':
            replace_map = []
            for ref in old_ls_refs:
                replace_map.append(ls_sources.get(ref, None))
            vals = extend_prop(raw,o,dt,n_old_ls,n_new_ls,prop_name='Source',
                               replace_map=replace_map, new_sources=ls_new_sources)
        else:
            vals = extend_prop(raw,o,dt,n_old_ls,n_new_ls,prop_name=pn)
        ch['raw'] = bytes(bytearray(hdr)+vals); ch['modified'] = True

    elif tid == RE_TID:
        pn_b = pn.encode('utf-8'); hdr = wu32(tid)+wu32(len(pn_b))+pn_b+bytes([dt])
        if pn == 'Name':
            # existing names + new names
            old_strs=[]; oo=o
            for _ in range(n_old_re):
                sl,oo=ru32(raw,oo); old_strs.append(raw[oo:oo+sl].decode('utf-8','replace')); oo+=sl
            all_re_names = old_strs + NEW_RE_NAMES
            vals_b = bytearray()
            for nm in all_re_names:
                nb=nm.encode('utf-8'); vals_b+=wu32(len(nb))+nb
            ch['raw']=bytes(bytearray(hdr)+vals_b); ch['modified']=True
        else:
            vals = extend_prop(raw,o,dt,n_old_re,n_new_re,prop_name=pn)
            ch['raw'] = bytes(bytearray(hdr)+vals); ch['modified'] = True

    elif tid == SC_TID and pn == 'Source' and dt == 0x01:
        # Replace PlayerStats source
        pn_b = pn.encode('utf-8'); hdr = wu32(tid)+wu32(len(pn_b))+pn_b+bytes([dt])
        old_strs=[]; oo=o
        for _ in range(len(old_sc_refs)):
            sl,oo=ru32(raw,oo); old_strs.append(raw[oo:oo+sl]); oo+=sl
        new_raw = bytearray(hdr)
        for i,ref in enumerate(old_sc_refs):
            if ref == PLAYERSTATS_REF:
                new_raw += wu32(len(PLAYERSTATS_BYTES))+PLAYERSTATS_BYTES
            else:
                new_raw += wu32(len(old_strs[i]))+old_strs[i]
        ch['raw']=bytes(new_raw); ch['modified']=True

# ── Write output ──────────────────────────────────────────────────────────────
out = bytearray(header)
mod_count = sum(1 for ch in chunks if ch['modified'])
for ch in chunks:
    if ch['modified']: out += write_unc(ch['nm_bytes'], ch['raw'])
    else: out += ch['orig']

with open(FILE,'wb') as f: f.write(out)
print(f"\nModified {mod_count} chunks")
print(f"Saved: {len(out):,} bytes -> {FILE}")
print("\nV4 COMPLETE")
