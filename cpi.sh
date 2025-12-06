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

# Auto-detect programs that have both .cpi and .cpi.correct
for d in "$CORRECT_DIR"/*; do
  [ -d "$d" ] || continue
  prog="$(basename "$d")"
  if [ -f "$d/$prog.cpi.correct" ] && [ -f "$OUT_DIR/$prog.cpi" ]; then
    PROGS+=("$prog")
  fi
done

if [ "${#PROGS[@]}" -eq 0 ]; then
  echo -e "${RED}No matching <prog>.cpi and <prog>.cpi.correct files found.${RESET}"
  exit 1
fi

echo "TABLE VI"
echo "PERFORMANCE SUMMARY"
echo

# Header
printf '%-20s %-12s %-12s %-15s %-10s\n' "Program" "CPI" "CPI_ref" "Time (ns)" "Compare"
printf '%-20s %-12s %-12s %-15s %-10s\n' \
  "--------------------" "------------" "------------" "---------------" "----------"

for prog in "${PROGS[@]}"; do
  actual_file="$OUT_DIR/$prog.cpi"
  ref_file="$CORRECT_DIR/$prog/$prog.cpi.correct"

  # Extract CPI from actual .cpi (field before 'CPI' on the line containing 'CPI')
  actual_cpi=$(awk '/CPI/ {print $(NF-1); exit}' "$actual_file")

  # Extract time (ns) from actual .cpi (field before 'ns' on the line containing 'ns total time')
  actual_time=$(awk '/ns total time/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "ns") { print $(i-1); exit }
      }
    }' "$actual_file")

  # Extract reference CPI from .cpi.correct
  ref_cpi=$(awk '/CPI/ {print $(NF-1); exit}' "$ref_file")

  # Compare CPI with a small tolerance
  cmp="DIFF"
  if awk -v a="$actual_cpi" -v b="$ref_cpi" 'BEGIN {
        diff = a - b;
        if (diff < 0) diff = -diff;
        if (diff < 1e-6) exit 0; else exit 1;
      }'
  then
    cmp="MATCH"
    cmp_color="$GREEN"
  else
    cmp_color="$RED"
  fi

  printf '%-20s %-12s %-12s %-15s %b%-10s%b\n' \
    "$prog" "$actual_cpi" "$ref_cpi" "$actual_time" "$cmp_color" "$cmp" "$RESET"
done