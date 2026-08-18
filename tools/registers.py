#!/usr/bin/env python3
"""
registers.py -- peak live top-level locals per file, the one thing the compiler misses.

WHY THIS IS SEPARATE FROM check.sh. Roblox's Luau refuses more than 200 live locals in a
function, and a script's main chunk IS a function:

    PancakeMonsterQuest_AllInOne:2513: Out of local registers when trying to
    allocate animateScenery: exceeded limit 200

That is a COMPILE failure -- the whole script silently never runs. Upstream luau-compile.exe
does NOT enforce this limit (verified: 1000 top-level locals compile clean upstream), so
check.sh can never catch it. Hence this counter.

WHAT IT COUNTS. Column-0 `local` declarations only -- those are the main chunk's. Locals
inside a `do ... end` block are freed at the `end`, so the count tracks column-0 block nesting
and reports the RUNNING PEAK, not the total. A `local a, b, c` costs 3; a `local function`
costs 1; a table costs 1 no matter how many fields it has, which is the cheapest way to buy
headroom in a file that is close.

    python tools/registers.py CandyRealm          # every file, worst first
    python tools/registers.py CandyRealm 180      # only files at or above 180
"""
import os
import re
import sys

LIMIT = 200
WARN_AT = 185

# a column-0 block opener whose locals get freed again at its matching column-0 `end`
OPENS = re.compile(r'^(do|if|for|while|repeat|function|local function)\b')


def peak_locals(path):
    """Returns (peak, final) live column-0 locals."""
    src = open(path, encoding='utf-8', errors='replace').read()
    src = re.sub(r'--\[\[.*?\]\]', '', src, flags=re.S)

    live = 0            # locals currently in scope at column 0
    peak = 0
    stack = []          # locals introduced inside each open column-0 block
    depth = 0

    for raw in src.split('\n'):
        if raw.startswith('--'):
            continue
        stripped = raw.strip()

        # only column-0 constructs belong to the main chunk's own scope
        at_col0 = raw[:1] not in (' ', '\t') and raw != ''

        if at_col0 and stripped.startswith('local '):
            rest = stripped[6:]
            if rest.startswith('function '):
                n = 1
            else:
                lhs = rest.split('=')[0]
                n = len([x for x in lhs.split(',') if x.strip()])
            live += n
            if depth:
                stack[-1] += n
            peak = max(peak, live)

        if at_col0 and OPENS.match(stripped) and not stripped.startswith('local function'):
            depth += 1
            stack.append(0)
        elif at_col0 and re.match(r'^end\b', stripped) and depth:
            depth -= 1
            live -= stack.pop()

    return peak, live


def main():
    realm = sys.argv[1] if len(sys.argv) > 1 else 'CandyRealm'
    floor = int(sys.argv[2]) if len(sys.argv) > 2 else 0

    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.join(os.path.dirname(here), realm)
    if not os.path.isdir(os.path.join(root, 'src')):
        root = os.path.abspath(realm)
    if not os.path.isdir(os.path.join(root, 'src')):
        print("no src/ folder found for '%s'" % realm)
        return 2

    rows = []
    for base, _, files in os.walk(os.path.join(root, 'src')):
        for fn in files:
            if fn.endswith(('.lua', '.luau')):
                p = os.path.join(base, fn)
                pk, _ = peak_locals(p)
                if pk >= floor:
                    rows.append((pk, os.path.relpath(p, root).replace('\\', '/')))

    rows.sort(reverse=True)
    over = 0
    for pk, rel in rows:
        if pk > LIMIT:
            tag, over = 'OVER ', over + 1
        elif pk >= WARN_AT:
            tag = 'tight'
        else:
            tag = '     '
        print('  %s %3d/%d  %s' % (tag, pk, LIMIT, rel))

    print('')
    if over:
        print('%d file(s) OVER the %d limit -- those scripts will not run at all' % (over, LIMIT))
        return 1
    tight = sum(1 for pk, _ in rows if pk >= WARN_AT)
    print('all clear -- worst is %d/%d, %d file(s) within %d of the limit'
          % (rows[0][0] if rows else 0, LIMIT, tight, LIMIT - WARN_AT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
