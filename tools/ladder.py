#!/usr/bin/env python3
"""
ladder.py -- replay the whole Food Realm climb from the SHIPPED files and assert the design rules.

Parses (not copies) src/shared/FlightTuning.luau, src/shared/IslandOrder.luau and the foods /
stomachTiers tables in src/server/PlayerStats.server.lua, then flies a reference player up all
13 crossings: no events, no bubbles, always buying the best-value food they have unlocked, and
always launching on the fullest tank whole servings can make.

Exit code 0 = every invariant holds. Run it after ANY tuning change:

    python tools/ladder.py

The assertions are the rules from the F2F UNIVERSAL PROGRESSION GUIDE, section 11. If this file
and the guide disagree, this file is right -- it reads the code that actually runs.
"""
import math, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def nums(text):
    return [float(x) for x in re.findall(r"-?\d+(?:\.\d+)?", text)]


# ---------------------------------------------------------------- parse FlightTuning
ft = read("src/shared/FlightTuning.luau")


def ft_const(name):
    m = re.search(r"FlightTuning\.%s\s*=\s*([-\d.]+)" % re.escape(name), ft)
    if not m:
        raise SystemExit("cannot find FlightTuning.%s" % name)
    return float(m.group(1))


FLIGHT_SECONDS = ft_const("FLIGHT_SECONDS")
COIN_PER_STUD_BASE = ft_const("COIN_PER_STUD_BASE")
SPACING_SCALE = ft_const("SPACING_SCALE")
DESCENT_PAY_MULT = ft_const("DESCENT_PAY_MULT")
COAST_DAMPING = ft_const("COAST_DAMPING")
COURTESY_FRACTION = ft_const("COURTESY_FRACTION")
COIN_PER_STUD = COIN_PER_STUD_BASE / SPACING_SCALE

m = re.search(r"local SPEED_SHAPE\s*=\s*\{([^}]*)\}", ft)
SPEED_SHAPE = nums(m.group(1))
NB = len(SPEED_SHAPE)
CUM = [0.0]
for v in SPEED_SHAPE:
    CUM.append(CUM[-1] + v / NB)

m = re.search(r"FlightTuning\.BASE_TIERS\s*=\s*\{(.*?)\n\}", ft, re.S)
TIERS = [(int(a), float(b)) for a, b in re.findall(r"maxPower\s*=\s*(\d+)\s*,\s*climb\s*=\s*([\d.]+)", m.group(1))]
TANK = [t[0] for t in TIERS]
CLIMB = [t[1] for t in TIERS]
NT = len(TIERS)

m = re.search(r"local TIER_TIME\s*=\s*\{(.*?)\n\}", ft, re.S)
TIER_TIME = [(int(a), float(b)) for a, b in re.findall(r"\{\s*(\d+)\s*,\s*([\d.]+)\s*\}", m.group(1))]


def time_scale(tank):
    for mx, f in TIER_TIME:
        if tank <= mx:
            return f
    return TIER_TIME[-1][1]


def tank_seconds(tank):
    return FLIGHT_SECONDS * time_scale(tank)


def tier_index(tank):
    for i, (mx, _) in enumerate(TIERS):
        if tank <= mx:
            return i
    return NT - 1


def climb_for(tank, power):
    if tank <= 0:
        return 0.0
    x = min(max(power / tank, 0.0), 1.0)
    j = min(NB - 1, int(x * NB))
    return CLIMB[tier_index(tank)] * (CUM[j] + (x - j / NB) * SPEED_SHAPE[j])


def power_for_climb(tank, dist):
    if tank <= 0 or dist <= 0:
        return 0.0
    y = dist / CLIMB[tier_index(tank)]
    if y >= 1:
        return tank
    for j in range(NB):
        if CUM[j + 1] >= y:
            return tank * (j / NB + (y - CUM[j]) / SPEED_SHAPE[j])
    return tank


def coast(tank):
    v = (CLIMB[tier_index(tank)] / tank_seconds(tank)) * SPEED_SHAPE[0]
    return (COAST_DAMPING * v) ** 2 / (2 * 196.2)


# ---------------------------------------------------------------- parse IslandOrder
io_src = read("src/shared/IslandOrder.luau")
m = re.search(r"IslandOrder\.SLOT_POS\s*=\s*\{(.*?)\n\}", io_src, re.S)
SLOT_Y = [float(y) for y in re.findall(r"y\s*=\s*([-\d.]+)", m.group(1))]
IO_SCALE = float(re.search(r"IslandOrder\.SPACING_SCALE\s*=\s*([\d.]+)", io_src).group(1))
GAPS = [SLOT_Y[i + 1] - SLOT_Y[i] for i in range(len(SLOT_Y) - 1)]
NC = len(GAPS)

# ---------------------------------------------------------------- parse PlayerStats tables
ps = read("src/server/PlayerStats.server.lua")
m = re.search(r"local foods\s*=\s*\{(.*?)\n\}", ps, re.S)
FOOD = [(n, int(p), int(w), int(i)) for n, p, w, i in
        re.findall(r'name="(\w+)",\s*price=(\d+),\s*power=(\d+),\s*island=(\d+)', m.group(1))]
m = re.search(r"local stomachTiers\s*=\s*\{(.*?)\n\}", ps, re.S)
GUTS = [(n, int(mp), int(c), r == "true", int(isl)) for n, mp, c, r, isl in
        re.findall(r'name="([^"]+)",\s*maxPower=(\d+),\s*cost=(\d+),\s*robux=(true|false),\s*island=(\d+)', m.group(1))]
COIN_GUTS = [g for g in GUTS if not g[3]]
START_COINS = int(re.search(r"DEFAULT_COINS, DEFAULT_STOMACH, DEFAULT_ISLAND\s*=\s*(\d+)", ps).group(1))

# which tier covers which crossing: tier 0 -> c1, tier k -> c(2k), c(2k+1)
TIER_OF = [0] + [k for k in range(1, NT) for _ in (0, 1)]
TIER_OF = TIER_OF[:NC]

# ---------------------------------------------------------------- checks
fails = []


def chk(ok, msg):
    print(("  OK   " if ok else "  FAIL ") + msg)
    if not ok:
        fails.append(msg)


print("FOOD")
eff = [w / p for (_, p, w, _) in FOOD]
chk(all(eff[i] <= eff[i + 1] + 1e-9 for i in range(len(eff) - 1)), "food value never decreases up the tower")
chk(all(FOOD[i][2] <= FOOD[i + 1][2] for i in range(len(FOOD) - 1)), "food power never decreases up the tower")
chk(eff[-1] / eff[0] >= 1.5, "late food is a real upgrade (%.2fx the value of the first food)" % (eff[-1] / eff[0]))

print("GUTS")
chk(len(COIN_GUTS) == NT, "exactly %d coin guts -- gut upgrades stay milestones" % NT)
chk([g[1] for g in COIN_GUTS] == TANK, "StomachTiers tanks == FlightTuning tanks")
chk(all(TANK[i] < TANK[i + 1] for i in range(NT - 1)), "tanks strictly increasing")
chk(all(COIN_GUTS[i][2] < COIN_GUTS[i + 1][2] for i in range(1, NT - 1)), "gut prices strictly increasing")
chk(COURTESY_FRACTION == 0, "a purchased gut arrives empty (COURTESY_FRACTION = 0)")
chk(abs(sum(SPEED_SHAPE) / NB - 1.0) < 1e-9, "SPEED_SHAPE averages exactly 1.0")
chk(abs(IO_SCALE - SPACING_SCALE) < 1e-9, "SPACING_SCALE matches in IslandOrder and FlightTuning")
growth = [CLIMB[i + 1] / CLIMB[i] for i in range(NT - 1)]
chk(all(1.35 <= g <= 1.50 for g in growth), "tier climb growth stays in 1.35-1.50 (%s)" % ", ".join("%.2f" % g for g in growth))
speeds = [CLIMB[k] / tank_seconds(TANK[k]) for k in range(NT)]
chk(all(speeds[i] < speeds[i + 1] for i in range(NT - 1)), "speed rises with every gut (%s)" % ", ".join("%.1f" % s for s in speeds))

print("GATES")
for k in range(NT):
    own = [GAPS[c] for c in range(NC) if TIER_OF[c] == k]
    chk(CLIMB[k] >= max(own) - 1e-6, "tier %d climb %.1f reaches its longest gap %.1f" % (k + 1, CLIMB[k], max(own)))
    if k < NT - 1:
        nxt = min(GAPS[c] for c in range(NC) if TIER_OF[c] == k + 1)
        chk(CLIMB[k] < nxt, "tier %d climb does NOT reach the next tier's shortest gap (%.1f < %.1f)" % (k + 1, CLIMB[k], nxt))
        chk(CLIMB[k] + coast(TANK[k]) < nxt,
            "tier %d reaches climb + coast %.1f and still cannot make the next gap -- gut stays MANDATORY" % (k + 1, CLIMB[k] + coast(TANK[k])))

# ---------------------------------------------------------------- replay the climb
print("THE CLIMB")
coins = float(START_COINS)
tier, tank, fuel = 0, TANK[0], 0.0
curve, ladders, afford, R_list, earned = [], [], [], [], []
flat = 0
early90 = False
worst = 0.0
unlocked = 1


CONTINUOUS = "--continuous" in sys.argv   # the guide's idealised model: fuel is bought by the coin, not the serving


def best_fill(tank, fuel, coins, unlocked, gap):
    """How a sensible player shops, in whole servings:
       - if some affordable combination of unlocked foods CLEARS the gap, buy the cheapest one that does;
       - otherwise BUY MAX the way the shop does: best fuel-per-coin first, as many whole servings as the
         coins and the tank allow, then top up leftover room with the next-best food. (Never substituting
         worse-value food for coins -- that is what turns R into 1.0 and flat-lines a crossing.)
       With --continuous, fuel is bought fractionally at the best unlocked value (an idealised model)."""
    menu = sorted([f for f in FOOD if f[3] <= unlocked], key=lambda f: (-f[2] / f[1], -f[2]))
    room = int(tank - fuel)
    if room <= 0 or not menu:
        return fuel, coins
    if CONTINUOUS:
        best = menu[0]
        add = min(float(room), coins * best[2] / best[1])
        return fuel + add, coins - add * best[1] / best[2]
    INF = float("inf")
    cost = [INF] * (room + 1)           # cost[p] = cheapest way to add exactly p power
    cost[0] = 0.0
    for q in range(1, room + 1):
        for (_, price, power, _) in menu:
            if power <= q and cost[q - power] + price < cost[q]:
                cost[q] = cost[q - power] + price
    need = power_for_climb(tank, gap) - fuel
    clears = [q for q in range(room + 1) if cost[q] <= coins and q >= need]
    if clears:
        q = min(clears, key=lambda q: cost[q])
        return fuel + q, coins - cost[q]
    # cannot clear this flight: buy the best-value food first, then top up leftover room with the rest
    for (_, price, power, _) in menu:
        while coins >= price and fuel + power <= tank:
            coins -= price
            fuel += power
    return fuel, coins


for c, gap in enumerate(GAPS):
    need = TIER_OF[c]
    food = [f for f in FOOD if f[3] == c + 1][0]
    R = (food[2] / food[1]) * COIN_PER_STUD * (1 + DESCENT_PAY_MULT) * CLIMB[need] / TANK[need]
    R_list.append(R)
    flights, ladder, hold0 = 0, [], None
    while True:
        if tier < need and coins >= COIN_GUTS[need][2] and unlocked >= COIN_GUTS[need][4]:
            coins -= COIN_GUTS[need][2]
            tier, tank = need, TANK[need]
            fuel = min(fuel, tank)
        if hold0 is None:
            hold0 = coins
        fuel, coins = best_fill(tank, fuel, coins, unlocked, gap)
        if fuel <= 0:
            # anti-strand: one serving of the local food
            coins = float(food[1])
            fuel, coins = best_fill(tank, fuel, coins, unlocked, gap)
        d = climb_for(tank, fuel)
        flights += 1
        if d >= gap:
            coins += gap * COIN_PER_STUD
            fuel -= power_for_climb(tank, gap)
            unlocked = c + 2
            break
        pct = 100.0 * d / gap
        if ladder and pct - ladder[-1] < 3.0:
            flat += 1
        ladder.append(pct)
        coins += d * COIN_PER_STUD * (1 + DESCENT_PAY_MULT)
        fuel = 0.0
        if flights > 200:
            break
    for i, p in enumerate(ladder):
        worst = max(worst, p)
        if p >= 90 and i != len(ladder) - 1:
            early90 = True
    curve.append(flights)
    ladders.append(ladder)
    afford.append((hold0, food[1]))
    earned.append(sum(p / 100.0 * gap * COIN_PER_STUD * (1 + DESCENT_PAY_MULT) for p in ladder) + gap * COIN_PER_STUD)
    print("  c%-2d gap %7.1f  tier %d  %2d flights   %s" % (c + 1, gap, need + 1, flights,
          " -> ".join("%.0f%%" % p for p in ladder)))

print("  FLIGHT CURVE %s   total %d" % (curve, sum(curve)))
print("  R %s" % ", ".join("%.3f" % r for r in R_list))
print("  speeds %s" % ", ".join("%.1f" % s for s in speeds))

print("FLIGHT-1 AFFORDABILITY")
for c, (h, p) in enumerate(afford):
    print("  c%-2d holds %6.0f vs %5d %s" % (c + 1, h, p, "OK" if h >= p else "SHORT"))

print("RULES")
chk(min(R_list) * SPEED_SHAPE[0] > 1, "R x SPEED_SHAPE[1] > 1 everywhere (a dribble flight still pays)")
chk(min(R_list) >= 1.15, "R never drops so low the ladder must step through the 90s (min %.3f >= 1.15)" % min(R_list))
chk(all(h >= p for h, p in afford), "every crossing can afford its best food on flight 1")
chk(min(curve) >= 3, "no crossing is under 3 flights (min %d)" % min(curve))
chk(curve[0] <= 4, "the opening crossing stays short (%d <= 4)" % curve[0])
chk(max(curve[-4:]) >= 8, "the late game reaches 8+ flights (%d)" % max(curve[-4:]))
h = NC // 2
chk(sum(curve[h:]) > sum(curve[:h]), "flights generally increase: the back half is longer than the front")
chk(not early90, "90%+ misses only ever happen on the last try before clearing")
chk(worst < 98, "worst failed flight is %.0f%% and it is a final-try near-miss" % worst)
chk(flat <= 1, "at most one flat flight in the whole tower (%d)" % flat)
# a meal = one serving of the crossing's own food, against everything the crossing pays the reference player
meal_share = [([f for f in FOOD if f[3] == c + 1][0][1]) / earned[c] for c in range(NC)]
chk(max(meal_share[1:]) <= 0.20, "no meal past the tutorial exceeds 20%% of its crossing (worst %.0f%%)" % (100 * max(meal_share[1:])))
# the anti-strand meal: one serving of the local food, how far it flies against the crossing
free_meal = max(climb_for(TANK[TIER_OF[c]], [f for f in FOOD if f[3] == c + 1][0][2]) / GAPS[c] for c in range(NC))
chk(free_meal < 1.0, "the free meal peaks at %.0f%% of a crossing (< 100%%)" % (100 * free_meal))
chk(all(COIN_GUTS[k][2] < GAPS[2 * k - 2] * COIN_PER_STUD for k in range(1, NT)),
    "every gut costs less than the crossing before its wall pays out")

print()
if fails:
    print("%d FAILURE(S)" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("ALL INVARIANTS HOLD -- %d flights, summit Y %.1f, total climb %.1f" % (sum(curve), SLOT_Y[-1], SLOT_Y[-1] - SLOT_Y[0]))
