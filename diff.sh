#!/usr/bin/env bash
cd "$(dirname "$0")"

CORRECT_DIR="correct"
OUT_DIR="output"

# Colors (optional)
RED="\033[31m"
GREEN="\033[32m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

PROGS=()

# Auto-detect programs that have both .out and .out.correct
for d in "$CORRECT_DIR"/*; do
  [ -d "$d" ] || continue
  prog="$(basename "$d")"
  if [ -f "$d/$prog.out.correct" ] && [ -f "$OUT_DIR/$prog.out" ]; then
    PROGS+=("$prog")
  fi
done

if [ "${#PROGS[@]}" -eq 0 ]; then
  echo -e "${RED}No matching <prog>.out and <prog>.out.correct files found.${RESET}"
  exit 1
fi

echo "OUTPUT FILE DIFFERENCES"
echo "======================"
echo

# Track matches and differences
MATCHES=0
DIFFS=0

for prog in "${PROGS[@]}"; do
  actual_file="$OUT_DIR/$prog.out"
  ref_file="$CORRECT_DIR/$prog/$prog.out.correct"

  if diff -q "$actual_file" "$ref_file" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${RESET} $prog: ${GREEN}MATCH${RESET}"
    ((MATCHES++))
  else
    echo -e "${RED}✗${RESET} $prog: ${RED}DIFF${RESET}"
    ((DIFFS++))
  fi
done

echo
echo "======================"
echo -e "Summary: ${GREEN}$MATCHES${RESET} matches, ${RED}$DIFFS${RESET} differences"
if [ "$DIFFS" -eq 0 ]; then
  exit 0
else
  exit 1
fi
