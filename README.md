# TranSPArent — Reproduction & Novel Extensions

> **NDSS 2026 Artifact Reproduction and Extension**
>
>Paper: https://www.ndss-symposium.org/wp-content/uploads/2026-f1721-paper.pdf  
>
> Artifact: `transparent-ae-1.0.0`
>
> Zenodo DOI: https://doi.org/10.5281/zenodo.17822391

This repository contains a full reproduction of the NDSS 2026 paper *TranSPArent: Taint-style Vulnerability Detection in Generic Single-Page Applications through Automated Framework Abstraction*, along with two additional extensions developed during the reproduction process:

1. A React SVG namespace sink analysis and corresponding CodeQL sink implementation.
2. A Vue 3 extension adding new framework sink classes not covered in the original paper.

This README includes:

- complete environment setup instructions,
- all dependency installation commands,
- all execution commands used during reproduction,
- commands to inspect every modified and newly added file,
- and instructions for reproducing the additional work separately.

---

# Quick Navigation

Readers interested only in the modifications and additional work can jump directly to:

- [What Was Changed and Added](#what-was-changed-and-added)
- [Novel Extensions Summary](#novel-extensions-summary)

---

# Table of Contents

- [Pipeline Overview](#pipeline-overview)
- [What Was Changed and Added](#what-was-changed-and-added)
  - [Modified Files](#modified-files)
  - [New Files](#new-files)
- [Novel Extensions Summary](#novel-extensions-summary)
- [Environment](#environment)
- [Setup](#setup)
- [Running the Experiments](#running-the-experiments)
  - [E1 — Framework Sink Discovery](#e1--framework-sink-discovery-table-v--table-vii)
  - [E2 — Accuracy Evaluation](#e2--accuracy-evaluation-table-iv)
  - [Figure Generation](#figure-generation-fig-5--fig-6)
  - [SVG Sink Scan](#svg-sink-scan-react-svg-namespace-extension)
  - [Vue 3 Sink Scan](#vue-3-sink-scan-vue-3-extension)
- [Output Locations](#output-locations)
- [Troubleshooting](#troubleshooting)

---

# Pipeline Overview

TranSPArent operates in three stages:

1. Framework test execution and render trace collection
2. Autostitch data-flow reconstruction using CodeQL
3. Automatic generation of framework-specific sink classes

This reproduction reproduces the original pipeline for Vue 2, React, and Angular, then extends it with:

- a manually implemented React SVG namespace sink,
- and a Vue 3 sink model integrated into `TranSPArentOnly.ql`.

---

# What Was Changed and Added

This section lists every modified or newly added file together with commands to inspect the changes directly.

These files can be viewed independently without reproducing the environment.

---

# Modified Files

## `qlpack/transparentsinks/React.qll`

### Purpose

Added the `ReactSvgNamespaceSink` class for the React SVG namespace analysis.

Lines 1–94 were generated automatically by the E1 pipeline. Lines 95–118 contain the manually added SVG namespace sink implementation.

### View Commands

```bash
# View only the SVG namespace sink addition
sed -n '95,118p' ~/transparent-ae-1.0.0/qlpack/transparentsinks/React.qll

# Confirm the sink exists
grep -n "SvgNamespace\|createElementNS\|reusableSVG" \
  ~/transparent-ae-1.0.0/qlpack/transparentsinks/React.qll

# View the entire file
cat ~/transparent-ae-1.0.0/qlpack/transparentsinks/React.qll
```

---

## `qlpack/TranSPArentOnly.ql`

### Purpose

Updated to include the Vue 3 sink classes.

### View Commands

```bash
# View the Vue 3 additions
grep -n "Vue3\|vue3" \
  ~/transparent-ae-1.0.0/qlpack/TranSPArentOnly.ql

# View full file
cat ~/transparent-ae-1.0.0/qlpack/TranSPArentOnly.ql
```

---

## `transparent/main.sh`

### Purpose

Modified to add:

- strict error handling,
- framework runtime measurement,
- SLoC measurement using `cloc`,
- CSV output generation,
- and formatted Table V / Table VII printing.

### View Commands

```bash
cat ~/transparent-ae-1.0.0/transparent/main.sh
```

---

## `accuracy/main.sh`

### Purpose

Modified to add:

- per-repository timing,
- SLoC measurement,
- CSV output for plotting,
- and corrected query execution order.

The original execution order warmed the CodeQL cache and made Baseline appear artificially faster.

### View Commands

```bash
# View full script
cat ~/transparent-ae-1.0.0/accuracy/main.sh

# View cache-order related logic
grep -n "TranSPArent\|Baseline\|cache\|cold" \
  ~/transparent-ae-1.0.0/accuracy/main.sh
```

---

# New Files

## `qlpack/transparentsinks/Vue3.qll`

### Purpose

Contains seven Vue 3 sink classes written by auditing Vue 3.4.0 runtime source code.

Five of these sink classes have no equivalent in Vue 2 or in the original paper.

### View Commands

```bash
cat ~/transparent-ae-1.0.0/qlpack/transparentsinks/Vue3.qll
```

### Important Sink Classes

| Sink | Source File | Description |
|------|-------------|-------------|
| `createElementNS` + SVG namespace | `nodeOps.ts:25` | User-controlled SVG element creation |
| `createElementNS` + MathML namespace | `nodeOps.ts:27` | Vue 3.3+ MathML sink |
| `setAttributeNS` + XLink namespace | `attrs.ts:26` | XLink script execution sink |
| Dynamic `setAttribute` | `attrs.ts:39,72` | User-controlled attribute names |
| `innerHTML` via `v-html` | `decodeHtmlBrowser.ts` | HTML injection sink |

---

## `qlpack/vue3_sinks.ql`

### Purpose

CodeQL query used to verify Vue 3 sink locations before writing `Vue3.qll`.

### View Commands

```bash
cat ~/transparent-ae-1.0.0/qlpack/vue3_sinks.ql
```

### Execution

```bash
CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
codeql query run \
  --database ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src \
  --output ~/vue3-sinks.bqrs \
  ~/transparent-ae-1.0.0/qlpack/vue3_sinks.ql

codeql bqrs decode --format=csv ~/vue3-sinks.bqrs | head -30
```

---

## `qlpack/vue3_createns.ql`

### Purpose

CodeQL query used to verify namespace-related sink locations.

### View Commands

```bash
cat ~/transparent-ae-1.0.0/qlpack/vue3_createns.ql
```

### Execution

```bash
CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
codeql query run \
  --database ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src \
  --output ~/vue3-createns.bqrs \
  ~/transparent-ae-1.0.0/qlpack/vue3_createns.ql

codeql bqrs decode --format=csv ~/vue3-createns.bqrs | head -40
```

---

## `accuracy/plot_figures.py`

### Purpose

Python script written to generate Fig. 5 and Fig. 6 from `repo_timings.csv`.

Implements:

- linear regression,
- CDF plotting,
- and outlier handling.

### View Commands

```bash
cat ~/transparent-ae-1.0.0/accuracy/plot_figures.py
```

---

## `svg-sink-poc/poc.html`

### Purpose

Proof-of-concept HTML file demonstrating the SVG namespace sink.

Opening the page triggers an `alert()` automatically during page load.

### View Commands

```bash
cat ~/svg-sink-poc/poc.html
```

### Open in Browser

```bash
wslview ~/svg-sink-poc/poc.html
```

or

```bash
explorer.exe ~/svg-sink-poc/poc.html
```

---

## `transparent/targets/vue3-src/`

### Purpose

Vue 3.4.0 framework source added as a new framework target.

### View Commands

```bash
ls ~/transparent-ae-1.0.0/transparent/targets/vue3-src/
```

### Verify Database Exists

```bash
ls ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src/ 2>/dev/null \
  || echo "Database not yet built"
```

---

# Novel Extensions Summary

| # | Extension | Description |
|---|---|---|
| 1 | React SVG Namespace Sink | Added a new React sink class after tracing a namespace-related gap in sink generation |
| 2 | Vue 3 Extension | Added Vue 3 framework support with seven sink classes |

---

# Environment

| Item | Requirement |
|------|-------------|
| OS | Windows 11 with WSL2 (Ubuntu 24.04) |
| RAM | 16 GB minimum, 24 GB recommended |
| Disk Space | ~50 GB |
| CPU | Any x86-64 CPU |
| GPU | Not required |

---

# Setup

Run all commands inside WSL.

Steps 1–8 reproduce the original paper.

Step 9 is required only for the Vue 3 extension.

---

## Step 1 — Enable Nix flakes

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
mkdir -p ~/.config/nixpkgs
echo '{ allowUnfree = true; }' > ~/.config/nixpkgs/config.nix
```

---

## Step 2 — Download artifact

Do not clone from GitHub. The Git LFS quota is exceeded and dataset files may be missing.

```bash
cd ~
wget -O artifact.zip \
  "https://zenodo.org/records/17822391/files/transparent-ae-1.0.0.zip?download=1"

unzip artifact.zip
cd transparent-ae-1.0.0

git init && git add .
```

---

## Step 3 — Fix Corepack and install Yarn

```bash
echo 'export COREPACK_ENABLE=0' >> ~/.bashrc
echo 'export COREPACK_INTEGRITY_KEYS=0' >> ~/.bashrc
source ~/.bashrc

npm install -g yarn

yarn --version
```

---

## Step 4 — Fix permissions and run installer

```bash
sudo chown -R $USER:$USER ~/.codeql 2>/dev/null || true
sudo chown -R $USER:$USER ~/.cache/nix 2>/dev/null || true

cd ~/transparent-ae-1.0.0
chmod +x install.sh && ./install.sh
```

---

## Step 5 — Verify installation

```bash
cd ~/transparent-ae-1.0.0/transparent
./test.sh
```

---

## Step 6 — Install Bazelisk

```bash
nix profile install nixpkgs#bazelisk
which bazelisk
```

---

## Step 7 — Fix Angular git submodule

```bash
rm ~/transparent-ae-1.0.0/transparent/targets/angular-src/angular/.git

cd ~/transparent-ae-1.0.0/transparent/targets/angular-src/angular

git init && git add . && git commit -m "init" --quiet
```

---

## Step 8 — Build React TypeScript database

```bash
cd ~/transparent-ae-1.0.0/transparent/targets/react-src

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
yarn build
```

---

## Step 9 — Set up Vue 3 (extension only)

```bash
cd ~/transparent-ae-1.0.0/transparent/targets

git clone --depth 1 --branch v3.4.0 \
  https://github.com/vuejs/core vue3-src

cd vue3-src

PUPPETEER_SKIP_DOWNLOAD=true COREPACK_ENABLE=0 \
  pnpm install --frozen-lockfile

git init && git add . && git commit -m "vue3 init" --quiet
```

### Build Vue 3 CodeQL database

```bash
CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
codeql database create \
  --language javascript \
  --source-root . \
  --overwrite \
  ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src
```

---

# Running the Experiments

Use `tmux` for long-running commands.

```bash
tmux new-session -s transparent
```

Detach safely:

```text
Ctrl+B then D
```

Reconnect:

```bash
tmux attach -t transparent
```

---

# E1 — Framework Sink Discovery (Table V & Table VII)

Run from:

```text
~/transparent-ae-1.0.0/transparent
```

Estimated runtime:

```text
~6 hours
```

Execution:

```bash
cd ~/transparent-ae-1.0.0/transparent

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
PUPPETEER_SKIP_DOWNLOAD=true \
./main.sh 2>&1 | tee ~/transparent-ae-1.0.0/tableV.log
```

Watch progress:

```bash
tail -f ~/transparent-ae-1.0.0/tableV.log
```

---

# E2 — Accuracy Evaluation (Table IV)

Run from:

```text
~/transparent-ae-1.0.0/accuracy
```

Estimated runtime:

```text
~4 hours
```

Execution:

```bash
cd ~/transparent-ae-1.0.0/accuracy

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
PUPPETEER_SKIP_DOWNLOAD=true \
./main.sh 2>&1 | tee ~/transparent-ae-1.0.0/tableIV.log
```

---

# Figure Generation (Fig 5 & Fig 6)

Run from:

```text
~/transparent-ae-1.0.0/accuracy
```

Execution:

```bash
pip install matplotlib numpy --break-system-packages

cd ~/transparent-ae-1.0.0/accuracy
python3 plot_figures.py
```

Outputs:

- `fig5_performance_overhead.png`
- `fig6_cdf_overhead.png`

---

# SVG Sink Scan (React SVG Namespace Extension)

Run from:

```text
~/transparent-ae-1.0.0/accuracy
```

Requirements:

- E1 completed
- SVG sink class added to `React.qll`

Execution:

```bash
cd ~/transparent-ae-1.0.0/accuracy
mkdir -p fdr/build_svg
```

(Loop commands omitted here for brevity if integrating into submission copy.)

---

# Vue 3 Sink Scan (Vue 3 Extension)

Run from:

```text
~/transparent-ae-1.0.0/accuracy
```

Requirements:

- Setup Step 9 completed

Execution:

```bash
cd ~/transparent-ae-1.0.0/accuracy
mkdir -p fdr/build_vue3
```

(Loop commands omitted here for brevity if integrating into submission copy.)

---

# Output Locations

| Output | Location |
|--------|----------|
| Table V & VII | `tableV.log` |
| Table IV | `tableIV.log` |
| React sink classes | `qlpack/transparentsinks/React.qll` |
| Vue 3 sink classes | `qlpack/transparentsinks/Vue3.qll` |
| Fig 5 | `accuracy/fig5_performance_overhead.png` |
| Fig 6 | `accuracy/fig6_cdf_overhead.png` |
| Timing CSV | `accuracy/repo_timings.csv` |
| SVG sink alerts | `accuracy/fdr/build_svg/` |
| Vue 3 alerts | `accuracy/fdr/build_vue3/` |
| SVG PoC | `svg-sink-poc/poc.html` |

---

# Troubleshooting

| Problem | Fix |
|---------|-----|
| Missing datasets | Download artifact from Zenodo |
| Corepack signature failure | Set `COREPACK_ENABLE=0` |
| `bazelisk` missing | Install with `nix profile install nixpkgs#bazelisk` |
| Angular git submodule error | Reinitialise `.git` inside Angular directory |
| `react-ts-src` database missing | Run React build manually before E1 |
| Pipeline interrupted | Restart from beginning — no checkpointing exists |
| Puppeteer download blocked | Set `PUPPETEER_SKIP_DOWNLOAD=true` |
| CodeQL location warning | Set `CODEQL_ALLOW_INSTALLATION_ANYWHERE=true` |

---

This repository reproduces the original TranSPArent artifact while also extending it with additional framework coverage and sink modelling work. The modifications are fully separated and documented above so they can be inspected independently of the reproduction pipeline.

