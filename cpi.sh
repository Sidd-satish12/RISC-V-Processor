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

# Header: CPI, cache hitrates, BP accuracy
printf '%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n' \
  "Program" "CPI" "CPI_ref" "Time(ns)" "IHit(%)" "DHit(%)" "BPAcc(%)" "Compare"
printf '%-20s %-10s %-10s %-10s %-10s %-10s %-10s %-10s\n' \
  "--------------------" "--------" "--------" "--------" "--------" "--------" "--------" "----------"

# For overall averages
sum_actual=0
sum_ref=0
count=0

# For overall branch predictor stats
total_branches_all=0
total_correct_all=0

for prog in "${PROGS[@]}"; do
  actual_file="$OUT_DIR/$prog.cpi"
  ref_file="$CORRECT_DIR/$prog/$prog.cpi.correct"
  log_file="$OUT_DIR/$prog.log"   # assumes <prog>.log lives here

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

  # Defaults for cache + BP stats
  icache_hit_pct="NA"
  dcache_hit_pct="NA"
  bp_acc="NA"
  total_branches=""
  correct_preds=""

  # Parse cache hitrates + BP stats from .log if available
  if [ -f "$log_file" ]; then
    # ICACHE STATS block: line with 'hitrate  = XX.XX%'
    icache_hit_pct=$(awk '
      /ICACHE STATS/ {flag=1; next}
      flag && /hitrate/ {
        v=$NF; gsub("%","",v); print v; exit
      }' "$log_file")
    [ -z "$icache_hit_pct" ] && icache_hit_pct="NA"

    # D-CACHE LOAD STATS block: line with 'hitrate  = XX.XX%'
    dcache_hit_pct=$(awk '
      /D-CACHE LOAD STATS/ {flag=1; next}
      flag && /hitrate/ {
        v=$NF; gsub("%","",v); print v; exit
      }' "$log_file")
    [ -z "$dcache_hit_pct" ] && dcache_hit_pct="NA"

    # Branch predictor stats (same format as in your bp.sh example)
    total_branches=$(
      awk '/Total branches/ {print $NF; exit}' "$log_file"
    )
    correct_preds=$(
      awk '/Correct predictions/ {print $NF; exit}' "$log_file"
    )
    bp_acc=$(
      awk '/Accuracy/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /%$/) {
            v=$i; gsub("%","",v); print v; exit
          }
        }
      }' "$log_file"
    )
    [ -z "$bp_acc" ] && bp_acc="NA"

    # Accumulate global BP stats if we have counts
    if [ -n "$total_branches" ] && [ -n "$correct_preds" ]; then
      total_branches_all=$(( total_branches_all + total_branches ))
      total_correct_all=$(( total_correct_all + correct_preds ))
    fi
  fi

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

  printf '%-20s %-10s %-10s %-10s %-10s %-10s %-10s %b%-10s%b\n' \
    "$prog" "$actual_cpi" "$ref_cpi" "$actual_time" "$icache_hit_pct" "$dcache_hit_pct" "$bp_acc" "$cmp_color" "$cmp" "$RESET"

  # Update sums for CPI averages
  sum_actual=$(awk -v s="$sum_actual" -v x="$actual_cpi" 'BEGIN { printf "%.10f", s + x }')
  sum_ref=$(awk -v s="$sum_ref" -v x="$ref_cpi" 'BEGIN { printf "%.10f", s + x }')
  count=$((count + 1))
done

echo
echo "OVERALL AVERAGE CPI (unweighted across $count programs)"
if [ "$count" -gt 0 ]; then
  avg_actual=$(awk -v s="$sum_actual" -v n="$count" 'BEGIN { printf "%.6f", s / n }')
  avg_ref=$(awk -v s="$sum_ref" -v n="$count" 'BEGIN { printf "%.6f", s / n }')

  echo "Our CPU avg CPI   : $avg_actual"
  echo "Reference avg CPI : $avg_ref"
else
  echo -e "${RED}No programs counted for averages.${RESET}"
fi

echo
echo "OVERALL BRANCH PREDICTOR ACCURACY (AGGREGATED)"
if [ "$total_branches_all" -gt 0 ]; then
  overall_acc=$(awk -v tot="$total_branches_all" -v cor="$total_correct_all" \
    'BEGIN { printf "%.2f", (100.0 * cor / tot) }')
  printf '%-20s %-15s %-20s %-15s\n' " " "TotalBranches" "CorrectPredictions" "Accuracy(%)"
  printf '%-20s %-15s %-20s %-15s\n' \
    "--------------------" "---------------" "--------------------" "-------------"
  printf '%-20s %-15d %-20d %-15.2f\n' \
    "ALL_PROGRAMS" "$total_branches_all" "$total_correct_all" "$overall_acc"
else
  echo -e "${RED}No valid branch predictor stats found in any log files.${RESET}"
fi
