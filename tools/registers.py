#!/usr/bin/env python3
"""
registers.py -- peak live locals in a script's MAIN CHUNK, the one thing the compiler misses.

WHY THIS IS SEPARATE FROM check.sh. Roblox's Luau refuses more than 200 live locals in a
function, and a script's main chunk IS a function:

    PancakeMonsterQuest_AllInOne:2513: Out of local registers when trying to
    allocate animateScenery: exceeded limit 200

That is a COMPILE failure -- the whole script silently never runs. Upstream luau-compile.exe
does NOT enforce this limit (verified: 1000 top-level locals compile clean upstream), so
check.sh can never catch it. Hence this counter.

WHAT COUNTS, AND WHY INDENTATION CANNOT TELL YOU. A local inside a `do` / `if` / `for` /
`while` block at the top level lives in the MAIN CHUNK's frame: it stacks on top of everything
already live and is only freed at that block's `end`. A local inside a nested `function` body
gets its own frame and does not count at all. Both are indented, so column 0 says nothing --
this walks the actual block structure (strings and comments blanked out first) and reports the
RUNNING PEAK of the main chunk's frame.

    An earlier version counted column-0 `local` lines only. It read CoreClient at 178 while the
    real peak was 200, and the next single local added to that file took the whole HUD off the
    screen with no error anywhere but the client log. Do not "simplify" it back.

A `local a, b, c` costs 3; a `local function` costs 1; a table costs 1 no matter how many
fields it has, which is the cheapest way to buy headroom in a file that is close. Assigning to
`_G.name = function() ... end` instead of `local function name()` costs ZERO.

    python tools/registers.py CandyRealm          # every file, worst first
    python tools/registers.py CandyRealm 180      # only files at or above 180
    python tools/registers.py .                   # the repo you are standing in
"""
import os
import re
import sys

LIMIT = 200
WARN_AT = 185
BS = chr(92)
NL = chr(10)


# Compiled once and matched with a `pos` argument -- never with src[i:], which copies the rest of
# the file on every character and turns this into an O(n^2) crawl on a 4,000-line script.
_LONG = re.compile(re.escape('[') + '(=*)' + re.escape('['))
_LONG_COMMENT = re.compile('--' + re.escape('[') + '(=*)' + re.escape('['))
_NEXT = re.compile('[-' + chr(34) + chr(39) + re.escape('[') + ']')


def _blank(src):
    """Replace every comment and string literal with spaces, keeping line structure intact."""
    out, i, n = [], 0, len(src)
    while i < n:
        m = _NEXT.search(src, i)
        if not m:
            out.append(src[i:])
            break
        out.append(src[i:m.start()])
        i = m.start()
        c = src[i]
        if c == '-':
            if src[i:i + 2] != '--':
                out.append(c)
                i += 1
                continue
            lm = _LONG_COMMENT.match(src, i)
            if lm:
                close = ']' + lm.group(1) + ']'
                j = src.find(close, lm.end())
                j = n if j < 0 else j + len(close)
            else:
                j = src.find(NL, i)
                j = n if j < 0 else j
        elif c == '[':
            lm = _LONG.match(src, i)
            if not lm:
                out.append(c)
                i += 1
                continue
            close = ']' + lm.group(1) + ']'
            j = src.find(close, lm.end())
            j = n if j < 0 else j + len(close)
        else:                                   # a quoted string
            j = i + 1
            while j < n and src[j] != c and src[j] != NL:
                j += 2 if src[j] == BS else 1
            j = min(j + 1, n)
        out.append(re.sub('[^' + NL + ']', ' ', src[i:j]))
        i = j
    return ''.join(out)


_IDENT = re.compile('[A-Za-z_]' + BS + 'w*$')


def _close(stack, live, fn_depth):
    """A block ends: free the locals it declared, unless they were in a nested function's frame."""
    if not stack:
        return live, fn_depth
    is_fn, declared = stack.pop()
    if is_fn:
        return live, fn_depth - 1
    if fn_depth == 0:
        live -= declared
    return live, fn_depth


def peak_locals(path):
    """Returns (peak, final) live locals in the main chunk's register frame."""
    src = _blank(open(path, encoding='utf-8', errors='replace').read())
    toks = re.findall(r'[A-Za-z_]' + BS + 'w*|[^' + BS + 'sA-Za-z_]', src)

    live = peak = 0
    stack = []          # one entry per open block: [is_function, locals_declared_directly_here]
    fn_depth = 0        # how many function bodies deep we are; >0 means a different register frame

    i, n = 0, len(toks)
    while i < n:
        t = toks[i]
        in_function = fn_depth > 0

        if t == 'local':
            if i + 1 < n and toks[i + 1] == 'function':
                if not in_function:
                    live += 1
                    if stack:
                        stack[-1][1] += 1
                    peak = max(peak, live)
                i += 1                       # let the `function` token below open the new frame
                continue
            j, count = i + 1, 0
            while j < n and _IDENT.match(toks[j]):
                count += 1
                j += 1
                if j < n and toks[j] == ',':
                    j += 1
                    continue
                break
            if not in_function and count:
                live += count
                if stack:
                    stack[-1][1] += count
                peak = max(peak, live)
            i = j
            continue

        if t == 'function':
            stack.append([True, 0])
            fn_depth += 1
        elif t == 'then' or t == 'do' or t == 'repeat':
            stack.append([False, 0])
        elif t == 'elseif':
            live, fn_depth = _close(stack, live, fn_depth)   # this branch's scope ends here...
        elif t == 'else':
            live, fn_depth = _close(stack, live, fn_depth)   # ...and the else body is its own scope
            stack.append([False, 0])
        elif t == 'end' or t == 'until':
            live, fn_depth = _close(stack, live, fn_depth)
        i += 1

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
