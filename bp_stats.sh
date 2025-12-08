#!/usr/bin/env bash
cd "$(dirname "$0")"

# Directory containing *.log files
LOG_DIR="output"   # change to "output" or wherever your .log files live

# Colors (optional)
RED="\033[31m"
GREEN="\033[32m"
CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

shopt -s nullglob
LOG_FILES=("$LOG_DIR"/*.log)
shopt -u nullglob

if [ "${#LOG_FILES[@]}" -eq 0 ]; then
  echo -e "${RED}No .log files found in '$LOG_DIR'.${RESET}"
  exit 1
fi

echo "BRANCH PREDICTOR ACCURACY SUMMARY"
echo

# Header
printf '%-20s %-15s %-20s %-15s\n' "Program" "TotalBranches" "CorrectPredictions" "Accuracy(%)"
printf '%-20s %-15s %-20s %-15s\n' \
  "--------------------" "---------------" "--------------------" "-------------"

total_branches_all=0
total_correct_all=0

for logfile in "${LOG_FILES[@]}"; do
  prog="$(basename "$logfile" .log)"

  # Extract fields from the log
  total_branches=$(
    awk '/Total branches/ {print $NF; exit}' "$logfile"
  )
  correct_preds=$(
    awk '/Correct predictions/ {print $NF; exit}' "$logfile"
  )
  accuracy=$(
    awk '/Accuracy/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /%$/) {
          gsub(/%/, "", $i);
          print $i;
          exit;
        }
      }
    }' "$logfile"
  )

  # Skip if we couldn't parse this file
  if [ -z "$total_branches" ] || [ -z "$correct_preds" ] || [ -z "$accuracy" ]; then
    echo -e "${RED}Warning:${RESET} Could not parse stats from $logfile"
    continue
  fi

  # Accumulate for global stats
  total_branches_all=$(( total_branches_all + total_branches ))
  total_correct_all=$(( total_correct_all + correct_preds ))

  # Color by accuracy if you want
  color="$GREEN"
  if awk -v a="$accuracy" 'BEGIN { if (a < 70.0) exit 0; else exit 1 }'; then
    color="$RED"
  fi

  printf '%-20s %-15s %-20s %b%-15.2f%b\n' \
    "$prog" "$total_branches" "$correct_preds" "$color" "$accuracy" "$RESET"
done

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
  echo -e "${RED}No valid stats found in any log files.${RESET}"
fi
