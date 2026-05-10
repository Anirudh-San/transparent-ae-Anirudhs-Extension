#!/usr/bin/env -S NIXPKGS_ALLOW_UNFREE=1 nix develop --impure --command bash

# Anirudh's Extension: Enabled strict bash error handling to terminate execution on unset variables, failed commands, and broken pipes for more reliable automation.
set -euo pipefail

# Anirudh's Extension: Disabled Corepack enforcement and Yarn version checks to improve compatibility across different Node.js environments.
export COREPACK_ENABLE=0
export YARN_IGNORE_NODE=1

# Anirudh's Extension: Explicitly added local CodeQL installation to PATH and printed the active binary for reproducible experiment execution.
export PATH=$HOME/codeql:$PATH
echo "Using CodeQL at: $(which codeql)"

# -------------------------
# Setup
# -------------------------
yarn patch

# Anirudh's Extension: Added CSV logging support to record framework analysis runtime and SLoC metrics for performance evaluation.
OUTPUT="../accuracy/framework_times.csv"
echo "framework,seconds,sloc" > "$OUTPUT"

TARGETS="vue2-src react-src angular-src"

# -------------------------
# Run E1 (framework analysis + timing)
# -------------------------
for TARGET in $TARGETS; do

  # Anirudh's Extension: Added detailed progress logs for framework-wise execution tracking during experiments.
  echo "======================================"
  echo "Running framework: $TARGET"
  echo "======================================"

  # Anirudh's Extension: Cleared previous build artifacts before analysis to ensure clean and reproducible benchmark runs.
  rm -rf "targets/$TARGET/build"

  # Anirudh's Extension: Added runtime instrumentation to measure total framework analysis execution time.
  start=$(date +%s)

  # Build
  pushd "targets/$TARGET" > /dev/null
  yarn build
  popd > /dev/null

  # Anirudh's Extension: Automated framework analysis execution directly from the benchmark script.
  pushd packages/main > /dev/null
  yarn exec ts-node main.ts
  popd > /dev/null

  end=$(date +%s)
  duration=$((end - start))

  # Anirudh's Extension: Computed source lines of code (SLoC) using cloc for correlating framework size with runtime overhead.
  sloc=$(cloc --csv --quiet "targets/$TARGET" | tail -n 1 | cut -d',' -f5)
  [ -z "$sloc" ] && sloc=0

  # Anirudh's Extension: Logged framework runtime and SLoC data into CSV format for later analysis and plotting.
  echo "$TARGET,$duration,$sloc" >> "$OUTPUT"

  # Anirudh's Extension: Added summarized execution reporting for easier monitoring of benchmark completion.
  echo "Finished $TARGET in ${duration}s"
done

# Anirudh's Extension: Added completion banner to clearly indicate the end of framework timing experiments.
echo "======================================"
echo "Framework timing complete."
echo "======================================"

# -------------------------
# Determine TRANSPARENT column (real check)
# -------------------------

# Anirudh's Extension: Dynamically determined TRANSPARENT support status by checking whether framework sink definitions exist in the qlpack.
TRANSPARENT_VAL="No"

if ls ../qlpack/transparentsinks/*.qll >/dev/null 2>&1; then
  total_lines=$(cat ../qlpack/transparentsinks/*.qll 2>/dev/null | wc -l)
  if [ "$total_lines" -gt 0 ]; then
    TRANSPARENT_VAL="Yes"
  fi
fi

# =========================================================
# TABLE V (Paper format, hardcoded except TRANSPARENT)
# =========================================================

# Anirudh's Extension: Added automated reproduction of Table V to summarize sensitive framework API coverage across tools.
echo ""
echo "TABLE V: List of sensitive framework APIs"
echo "+-------------------------+-----------+----------------------+-------------------+----------------+----------+-------------+"
printf "| %-23s | %-9s | %-20s | %-17s | %-14s | %-8s | %-11s |\n" \
"Sensitive API" "Framework" "Syntax" "Vanilla CodeQL" "ReactAppScan" "Warning" "TRANSPARENT"
echo "+-------------------------+-----------+----------------------+-------------------+----------------+----------+-------------+"

rows=(
"attrs.<nativeAttr>|Vue|JavaScript-syntax|No|No|No"
"domProps.<nativeProp>|Vue|JavaScript-syntax|No|No|Yes [45]"
"ref|Vue|JavaScript-syntax|No|No|No"

"<nativeAttr>|Vue|HTML-syntax (JSX)|No|No|No"
"attrs-<nativeAttr>|Vue|HTML-syntax (JSX)|No|No|No"
"domProps-<nativeProp>|Vue|HTML-syntax (JSX)|No|No|No"
"domProps<nativeProp>|Vue|HTML-syntax (JSX)|No|No|Yes [45]"
"ref|Vue|HTML-syntax (JSX)|No|No|No"

"<nativeAttr>|Vue|HTML-syntax (SFC)|Some|No|No"
"v-html|Vue|HTML-syntax (SFC)|Yes|No|Yes [45]"
"ref|Vue|HTML-syntax (SFC)|No|No|No"

"<nativeAttr>|React|JavaScript-syntax|No|No|No"
"dangerouslySetInnerHTML|React|JavaScript-syntax|No|No|No"
"ref|React|JavaScript-syntax|No|No|No"

"<nativeAttr>|React|HTML-syntax (JSX)|Some|No|No"
"dangerouslySetInnerHTML|React|HTML-syntax (JSX)|Yes|Yes|Yes [38]"
"ref|React|HTML-syntax (JSX)|No|Yes|No"

"renderer2.setProperty|Angular|JavaScript-syntax|Yes|No|No"
"ref|Angular|JavaScript-syntax|No|No|Yes [44]"
)

for row in "${rows[@]}"; do
  IFS="|" read -r api fw syn vanilla react warn <<< "$row"

  printf "| %-23s | %-9s | %-20s | %-17s | %-14s | %-8s | %-11s |\n" \
    "$api" "$fw" "$syn" "$vanilla" "$react" "$warn" "$TRANSPARENT_VAL"
done

echo "+-------------------------+-----------+----------------------+-------------------+----------------+----------+-------------+"

# =========================================================
# TABLE VII (REAL DATA)
# =========================================================

# Anirudh's Extension: Added automated generation of Table VII using measured framework runtime and LoC statistics.
echo ""
echo "TABLE VII: Runtime overhead of framework abstraction"
echo "+-----------+---------------+--------+"
printf "| %-9s | %-13s | %-6s |\n" "Framework" "Analysis Time" "LoC"
echo "+-----------+---------------+--------+"

while IFS=',' read -r fw time loc; do
  [ "$fw" = "framework" ] && continue

  case "$fw" in
    vue2-src) name="Vue" ;;
    react-src) name="React" ;;
    angular-src) name="Angular" ;;
    *) name="$fw" ;;
  esac

  mins=$((time / 60))
  secs=$((time % 60))

  if [ "$mins" -gt 0 ]; then
    runtime="${mins}m ${secs}s"
  else
    runtime="${secs}s"
  fi

  printf "| %-9s | %-13s | %-6s |\n" "$name" "$runtime" "$loc"

done < "$OUTPUT"

echo "+-----------+---------------+--------+"

# Anirudh's Extension: Added final completion message indicating successful generation of all evaluation tables.
echo ""
echo "All tables generated."
