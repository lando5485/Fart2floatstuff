"""
Re-runs every invariant the CandyRealm economy is solved against.

Nothing in the game errors when these drift apart -- islands just silently become free
or unwinnable -- so this is the check to run after ANY retune of:
    src/shared/IslandOrder.luau   (SLOT_TO_ISLAND, SLOT_POS)
    src/shared/FlightTuning.luau  (TIERS)
    src/shared/StomachTiers.luau  (LIST)
    src/shared/CandyData.luau     (FOODS)

Usage:  python tools/verify_economy.py
"""

FLIGHT_SECONDS, MARGIN, COIN_PER_STUD, R_TARGET = 45, 1.08, 0.14, 1.91

# ---- mirrors of the Luau tables (keep in step by hand) ----------------------
EXISTING_ISLANDS = [1, 2, 3, 4, 5, 8, 9, 11, 13, 14, 15]  # 6, 7, 10, 12 were never built
SLOT_TO_ISLAND   = [1, 9, 3, 13, 5, 8, 2, 11, 4, 14, 15]  # IslandOrder.SLOT_TO_ISLAND
FOOD_ISLANDS     = [1, 9, 3, 13, 5, 8, 2, 11, 4, 14, 15]  # CandyData row k's `island`
SLOT_POS_Y       = [150, 3525, 7305, 11539, 16281, 21592, 27541, 34204, 41667, 50026, 59388]

# FlightTuning.TIERS -- (maxPower, gap, speed)
TIERS = [(110, 3375, 81.0), (150, 3780, 115.0), (200, 4234, 132.1), (270, 4742, 146.9),
         (365, 5311, 164.8), (495, 5949, 184.6), (675, 6663, 206.1), (920, 7463, 231.2),
         (1260, 8359, 258.2), (1725, 9362, 289.4), (float('inf'), 10485, 420.0)]

# the ORIGINAL solved tank sizes the prices were derived against (shipped tanks carry +10)
ORIG = [100, 140, 190, 260, 355, 485, 665, 910, 1250, 1715]

# CandyData.FOODS -- (price, power), by slot
FOODS = [(21, 8), (53, 25), (79, 45), (101, 70), (118, 100), (136, 140), (147, 185),
         (156, 240), (159, 300), (160, 370), (194, 450)]

ok = True


def chk(cond, msg):
    global ok
    if not cond:
        ok = False
    print(("  OK  " if cond else " FAIL ") + msg)


print("1. slot -> island covers exactly the island models that exist")
chk(sorted(SLOT_TO_ISLAND) == EXISTING_ISLANDS, str(SLOT_TO_ISLAND))
chk(len(set(SLOT_TO_ISLAND)) == len(SLOT_TO_ISLAND), "no model used twice")
chk(SLOT_TO_ISLAND[0] == 1, "island1 pinned to slot 1 (spawn + tutorial live there)")

print()
print("2. CandyData host islands match the tower, slot for slot")
chk(FOOD_ISLANDS == SLOT_TO_ISLAND, "food row k is hosted on SLOT_TO_ISLAND[k]")

print()
print("3. gaps grow 12% per crossing")
gaps = [SLOT_POS_Y[i + 1] - SLOT_POS_Y[i] for i in range(len(SLOT_POS_Y) - 1)]
chk(len(gaps) == len(SLOT_TO_ISLAND) - 1, "%d crossings -> %s" % (len(gaps), gaps))
for i in range(1, len(gaps)):
    g = gaps[i] / gaps[i - 1]
    chk(abs(g - 1.12) < 0.002, "gap%d/gap%d = %.4f" % (i + 1, i, g))

print()
print("4. TIERS gaps match SLOT_POS gaps (one gut per crossing)")
chk(len(TIERS) - 1 == len(gaps), "%d coin tiers for %d crossings" % (len(TIERS) - 1, len(gaps)))
for i, g in enumerate(gaps):
    chk(TIERS[i][1] == g, "tier%d gap %d == %d" % (i + 1, TIERS[i][1], g))


def full_climb(maxp):
    """FlightTuning.fullTankClimb -- the taper integral."""
    s = prev = 0
    for mp, _, sp in TIERS:
        top = min(mp, maxp)
        if top > prev:
            s += sp * (top - prev)
            prev = top
        if top >= maxp:
            break
    return FLIGHT_SECONDS / maxp * s


print()
print("5. each gut clears its OWN gap, and falls SHORT of the next (the wall)")
for i, (mp, gap, _) in enumerate(TIERS[:-1]):
    c = full_climb(mp)
    chk(c > gap, "tier%-2d tank %-5d climbs %5.0f  >= own gap %d" % (i + 1, mp, c, gap))
    if i + 1 < len(TIERS) - 1:
        nxt = TIERS[i + 1][1]
        chk(c < nxt, "tier%-2d tank %-5d climbs %5.0f  <  next gap %d" % (i + 1, mp, c, nxt))
    else:
        chk(True, "tier%-2d tank %-5d climbs %5.0f  (summit, no gap above)" % (i + 1, mp, c))

print()
print("6. food prices give a flat R = %.2f, and R > 1 everywhere" % R_TARGET)
for slot, (price, power) in enumerate(FOODS, start=1):
    # the summit row has no gap above it: priced against the last crossing and the top tier
    gap = gaps[slot - 1] if slot <= len(gaps) else gaps[-1]
    tier = ORIG[slot - 1] if slot <= len(ORIG) else ORIG[-1]
    earn = gap * MARGIN * COIN_PER_STUD          # coins a full flight banks
    refill = price * (tier / power)              # coins a full refill costs
    r = earn / refill
    chk(r > 1.0 and abs(r - R_TARGET) < 0.06,
        "slot %2d  price %3d  power %3d  ->  R = %.3f" % (slot, price, power, r))

print()
print("ALL CHECKS PASSED" if ok else "*** FAILURES ABOVE -- do not ship ***")
raise SystemExit(0 if ok else 1)
