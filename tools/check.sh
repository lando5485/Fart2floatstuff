#!/usr/bin/env bash
# ============================================================================
# check.sh -- compile every Luau source file in a realm and report only failures
# ============================================================================
# WHY THIS EXISTS. Rojo syncs text; nothing between your editor and Studio ever
# tells you a script failed to PARSE. A syntax error means the script silently
# never runs -- no error in the output, no clue which file, just a quest that
# does nothing. This catches that in about a second.
#
#   ./tools/check.sh                # checks CandyRealm (the default)
#   ./tools/check.sh CandyRealm     # or name a realm folder
#   ./tools/check.sh .              # or check the repo you are standing in
#
# WHAT IT CATCHES: syntax errors, unbalanced end, bad escapes, anything the
# compiler refuses. WHAT IT DOES NOT: typo'd variable names (Luau has no
# undefined-global error), wrong logic, missing instances at runtime. For the
# first of those run tools/luau/luau-analyze.exe on a file directly.
#
# THE COMPILER IS UPSTREAM LUAU, NOT ROBLOX'S BUILD. They track each other
# closely and a parse error in one is a parse error in the other, but if you
# ever see this pass while Studio complains, believe Studio.
# ============================================================================
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lc="$here/luau/luau-compile.exe"
[ -x "$lc" ] || lc="$here/luau/luau-compile"

if [ ! -x "$lc" ]; then
	echo "no luau-compile in $here/luau/"
	echo "get it from https://github.com/luau-lang/luau/releases (luau-windows.zip)"
	exit 2
fi

realm="${1:-CandyRealm}"
root="$(cd "$here/.." && pwd)/$realm"
[ -d "$root/src" ] || root="$(cd "$realm" 2>/dev/null && pwd)"
if [ ! -d "$root/src" ]; then
	echo "no src/ folder found for '$realm'"
	exit 2
fi

pass=0; fail=0
while IFS= read -r f; do
	# --null compiles and throws the bytecode away: we only want the exit status.
	# Success chatters to stdout, so only stderr and a non-zero status matter.
	if out="$("$lc" --null "$f" 2>&1 >/dev/null)" && [ -z "$out" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo ""
		echo "FAIL  ${f#"$root/"}"
		echo "$out" | sed 's/^/      /'
	fi
done < <(find "$root/src" \( -name '*.lua' -o -name '*.luau' \) | sort)

echo ""
if [ "$fail" -eq 0 ]; then
	echo "OK -- $pass files compile clean ($realm)"
else
	echo "$fail of $((pass + fail)) files FAILED to compile ($realm)"
fi
exit $((fail > 0 ? 1 : 0))
