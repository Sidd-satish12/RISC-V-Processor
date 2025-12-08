#!/usr/bin/env bash
cd "$(dirname "$0")"

OUT_FWD="output_fwd"
OUT_NOFWD="output_nofwd"

RED="\033[31m"
GREEN="\033[32m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

PROGS=()

# Auto-detect programs: need .cpi in both directories
for f in "$OUT_FWD"/*.cpi; do
  [ -f "$f" ] || continue
  prog="$(basename "$f" .cpi)"
  if [ -f "$OUT_NOFWD/$prog.cpi" ]; then
    PROGS+=("$prog")
  fi
done

if [ "${#PROGS[@]}" -eq 0 ]; then
  echo -e "${RED}No matching <prog>.cpi files in $OUT_FWD and $OUT_NOFWD.${RESET}"
  exit 1
fi

echo "STORE QUEUE FORWARDING EFFECTIVENESS"
echo

printf '%-20s %-12s %-12s %-12s\n' "Program" "CPI_fwd" "CPI_noFwd" "noFwd/fwd"
printf '%-20s %-12s %-12s %-12s\n' \
  "--------------------" "------------" "------------" "------------"

sum_fwd=0
sum_nofwd=0
count=0

for prog in "${PROGS[@]}"; do
  file_fwd="$OUT_FWD/$prog.cpi"
  file_nofwd="$OUT_NOFWD/$prog.cpi"

  cpi_fwd=$(awk '/CPI/ {print $(NF-1); exit}' "$file_fwd")
  cpi_nofwd=$(awk '/CPI/ {print $(NF-1); exit}' "$file_nofwd")

  # ratio (how much worse without forwarding)
  ratio=$(awk -v a="$cpi_fwd" -v b="$cpi_nofwd" 'BEGIN { if (a==0) print "inf"; else printf "%.3f", b/a }')

  # Color if forwarding clearly helps
  color="$RESET"
  if awk -v a="$cpi_fwd" -v b="$cpi_nofwd" 'BEGIN { exit (b > a + 1e-6) ? 0 : 1 }'; then
    color="$GREEN"
  elif awk -v a="$cpi_fwd" -v b="$cpi_nofwd" 'BEGIN { exit (b < a - 1e-6) ? 0 : 1 }'; then
    color="$RED"
  fi

  printf '%-20s %-12s %-12s %b%-12s%b\n' \
    "$prog" "$cpi_fwd" "$cpi_nofwd" "$color" "$ratio" "$RESET"

  sum_fwd=$(awk -v s="$sum_fwd" -v x="$cpi_fwd" 'BEGIN { printf "%.10f", s + x }')
  sum_nofwd=$(awk -v s="$sum_nofwd" -v x="$cpi_nofwd" 'BEGIN { printf "%.10f", s + x }')
  count=$((count + 1))
done

echo
echo "OVERALL AVERAGE CPI (UNWEIGHTED ACROSS $count PROGRAMS)"
avg_fwd=$(awk -v s="$sum_fwd" -v n="$count" 'BEGIN { printf "%.6f", s / n }')
avg_nofwd=$(awk -v s="$sum_nofwd" -v n="$count" 'BEGIN { printf "%.6f", s / n }')
ratio_overall=$(awk -v a="$avg_fwd" -v b="$avg_nofwd" 'BEGIN { if (a==0) print "inf"; else printf "%.3f", b/a }')

echo "Avg CPI with SQ forwarding    : $avg_fwd"
echo "Avg CPI *without* forwarding  : $avg_nofwd"
echo "Overall noFwd/fwd CPI ratio   : $ratio_overall"
