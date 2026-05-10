#!/usr/bin/env -S NIXPKGS_ALLOW_UNFREE=1 nix develop --impure --command bash

# Anirudh's Extension: Enabled strict bash error handling to stop execution on unset variables, failed commands, and broken pipes for more reliable experiment runs.
set -euo pipefail

# Anirudh's Extension: Added environment flags to allow portable CodeQL installation paths and skip unnecessary Puppeteer downloads during execution.
export CODEQL_ALLOW_INSTALLATION_ANYWHERE=true
export PUPPETEER_SKIP_DOWNLOAD=true

QLPACK_ROOT="../qlpack"

# Anirudh's Extension: Added CSV logging support to collect timing and SLoC metrics for generating Figure 5 and Figure 6 performance plots.
TIMING_CSV="repo_timings.csv"
echo "repo,dataset,vanilla_seconds,transparent_seconds,sloc" > "$TIMING_CSV"

# -------------------------
# Process for FNR
# -------------------------
mkdir -p fnr/build
for dir in fnr/repos/*/; do
  repo_name=$(basename $dir)

  # Anirudh's Extension: Added detailed console logging to clearly track repository-wise experiment progress during long benchmark executions.
  echo "======================================"
  echo "[FNR] Processing: $repo_name"
  echo "======================================"

  # Anirudh's Extension: Computed SLoC using cloc for correlating repository size with query execution performance.
  sloc=$(cloc --csv --quiet "fnr/repos/$repo_name" 2>/dev/null | tail -n 1 | cut -d',' -f5)
  [ -z "$sloc" ] && sloc=0

  # Anirudh's Extension: Reused a shared CodeQL database for both baseline and TranSPArent queries to ensure fair comparison conditions.
  codeql database create --language javascript --source-root fnr/repos/$repo_name --overwrite fnr/build/${repo_name}_db

  # Anirudh's Extension: Added timing instrumentation for TranSPArent query execution using cold-cache measurements.
  t_transparent_start=$(date +%s)
  codeql query run --database fnr/build/${repo_name}_db --output fnr/build/${repo_name}_t.bqrs $QLPACK_ROOT/TranSPArent.ql
  t_transparent_end=$(date +%s)
  transparent_secs=$((t_transparent_end - t_transparent_start))

  # Anirudh's Extension: Added timing instrumentation for baseline CodeQL query execution to compare against TranSPArent overhead.
  t_vanilla_start=$(date +%s)
  codeql query run --database fnr/build/${repo_name}_db --output fnr/build/${repo_name}_b.bqrs $QLPACK_ROOT/Baseline.ql
  t_vanilla_end=$(date +%s)
  vanilla_secs=$((t_vanilla_end - t_vanilla_start))

  # Decode BQRS
  codeql bqrs decode --format=json fnr/build/${repo_name}_b.bqrs > fnr/build/${repo_name}_b.json
  codeql bqrs decode --format=json fnr/build/${repo_name}_t.bqrs > fnr/build/${repo_name}_t.json

  # Anirudh's Extension: Logged repository name, dataset type, execution timings, and SLoC into a CSV file for later plotting and statistical analysis.
  echo "$repo_name,fnr,$vanilla_secs,$transparent_secs,$sloc" >> "$TIMING_CSV"

  # Delete intermediate files to save space
  rm -rf fnr/build/${repo_name}_db
  rm fnr/build/${repo_name}_b.bqrs
  rm fnr/build/${repo_name}_t.bqrs

  # Anirudh's Extension: Added summarized runtime reporting for easier monitoring of benchmark completion and performance trends.
  echo "[FNR] Done $repo_name — Vanilla: ${vanilla_secs}s, TranSPArent: ${transparent_secs}s, SLoC: $sloc"
done

# -------------------------
# Process for FDR
# -------------------------
mkdir -p fdr/build
for dir in fdr/repos/*/; do
  repo_name=$(basename $dir)

  # Anirudh's Extension: Added detailed console logging to clearly track repository-wise experiment progress during long benchmark executions.
  echo "======================================"
  echo "[FDR] Processing: $repo_name"
  echo "======================================"

  # Anirudh's Extension: Computed SLoC using cloc for correlating repository size with query execution performance.
  sloc=$(cloc --csv --quiet "fdr/repos/$repo_name" 2>/dev/null | tail -n 1 | cut -d',' -f5)
  [ -z "$sloc" ] && sloc=0

  # Anirudh's Extension: Reused a shared CodeQL database for both baseline and TranSPArent queries to ensure fair comparison conditions.
  codeql database create --language javascript --source-root fdr/repos/$repo_name --overwrite fdr/build/${repo_name}_db

  # Anirudh's Extension: Added timing instrumentation for TranSPArent query execution using cold-cache measurements.
  t_transparent_start=$(date +%s)
  codeql query run --database fdr/build/${repo_name}_db --output fdr/build/${repo_name}_t.bqrs $QLPACK_ROOT/TranSPArent.ql
  t_transparent_end=$(date +%s)
  transparent_secs=$((t_transparent_end - t_transparent_start))

  # Anirudh's Extension: Added timing instrumentation for baseline CodeQL query execution to compare against TranSPArent overhead.
  t_vanilla_start=$(date +%s)
  codeql query run --database fdr/build/${repo_name}_db --output fdr/build/${repo_name}_b.bqrs $QLPACK_ROOT/Baseline.ql
  t_vanilla_end=$(date +%s)
  vanilla_secs=$((t_vanilla_end - t_vanilla_start))

  # Decode BQRS
  codeql bqrs decode --format=json fdr/build/${repo_name}_b.bqrs > fdr/build/${repo_name}_b.json
  codeql bqrs decode --format=json fdr/build/${repo_name}_t.bqrs > fdr/build/${repo_name}_t.json

  # Anirudh's Extension: Logged repository name, dataset type, execution timings, and SLoC into a CSV file for later plotting and statistical analysis.
  echo "$repo_name,fdr,$vanilla_secs,$transparent_secs,$sloc" >> "$TIMING_CSV"

  # Delete intermediate files to save space
  rm -rf fdr/build/${repo_name}_db
  rm fdr/build/${repo_name}_b.bqrs
  rm fdr/build/${repo_name}_t.bqrs

  # Anirudh's Extension: Added summarized runtime reporting for easier monitoring of benchmark completion and performance trends.
  echo "[FDR] Done $repo_name — Vanilla: ${vanilla_secs}s, TranSPArent: ${transparent_secs}s, SLoC: $sloc"
done

# -------------------------
# Anirudh's Extension: Clarified evaluation stage responsible for validating FDR samples and reproducing Table IV metrics.
# -------------------------
pushd scripts
node ./verify_fdr_sample.js
node ./calculate.js
popd

# Anirudh's Extension: Added final execution summary indicating location of generated timing dataset and plotting workflow instructions.
echo ""
echo "Timing data saved to: $TIMING_CSV"
echo "Run plot_figures.py to generate Fig 5 and Fig 6."
