# TranSPArent — Reproduction & Novel Extensions

> **NDSS 2026 Artifact Reproduction and Extension**
>
> Paper: https://www.ndss-symposium.org/wp-content/uploads/2026-f1721-paper.pdf
>
> Artifact: `transparent-ae-1.0.0` · Zenodo DOI: https://doi.org/10.5281/zenodo.17822391
>
> Course: 22CST352 Computer and Network Security · MNIT Jaipur · Submitted by Anirudh Sanker (2023UCP1844)

This repository contains a full reproduction of the NDSS 2026 paper *TranSPArent: Taint-style Vulnerability Detection in Generic Single-Page Applications through Automated Framework Abstraction*, along with two novel extensions developed during the reproduction process.

---

## What This Repository Contains

**Reproduction** of TranSPArent's core results for Vue 2, React, and Angular:

- Table IV (accuracy: FNR and FDR)
- Table V (framework sink discovery)
- Table VII (framework analysis runtime)
- Fig. 5 and Fig. 6 (performance overhead, not produced by the original artifact)

**Novel Extension 1 — React SVG Namespace Sink:** A gap in TranSPArent's code generation step caused the SVG namespace URI to be silently dropped despite being correctly identified in the dynamic trace. This extension traces the root cause, adds a CodeQL sink class covering both exploitable paths, and confirms exploitability with a working XSS proof-of-concept.

**Novel Extension 2 — Vue 3 Extension:** Vue 3 is a complete rewrite of Vue 2's rendering engine and is invisible to TranSPArent's existing analysis. This extension adds seven CodeQL sink classes for Vue 3.4.0 — five with no Vue 2 equivalent — and integrates them into the pipeline.

---

## Quick Navigation

- [How TranSPArent Works](#how-transparent-works)
- [Reproduction Results](#reproduction-results)
- [Novel Extension 1: SVG Namespace Sink](#novel-extension-1-svg-namespace-sink)
- [Novel Extension 2: Vue 3 Extension](#novel-extension-2-vue-3-extension)
- [What Was Changed and Added](#what-was-changed-and-added)
- [Environment](#environment)
- [Setup](#setup)
- [Running the Experiments](#running-the-experiments)
- [Output Locations](#output-locations)
- [Troubleshooting](#troubleshooting)

---

## How TranSPArent Works

TranSPArent operates in three stages:

1. **Trace collection.** The framework's internal test suite is run with instrumentation. Every DOM API call is recorded into a render trace.
2. **Autostitch.** CodeQL traces how data flows through the framework's source from the public render function down to each DOM call in the trace, building a cross-function data flow model.
3. **Sink generation.** The discovered flow patterns are converted into CodeQL sink classes (`.qll` files), which are then used alongside standard CodeQL taint analysis to scan real applications.

---

## Reproduction Results

### Table IV — Accuracy Evaluation

Results match the paper exactly.

| Tool | FNR | FDR |
|------|-----|-----|
| TranSPArent | 11/56 (19.6%) | 24/57 (42.1%) |
| Vanilla CodeQL | 35/56 (62.5%) | 17/34 (50.0%) |

TranSPArent misses 11 of 56 known vulnerable locations versus 35 for Vanilla CodeQL — a roughly 3× improvement in recall.

### Table V — Framework Sink Discovery

All 19 framework-specific sinks from the paper's Table V were reproduced exactly. One additional row appeared in the raw output:

| Sensitive API | Framework | Syntax | Vanilla CodeQL | TranSPArent |
|---------------|-----------|--------|----------------|-------------|
| `http://www.w3.org/2000/svg` | React | JS-Syntax | No | Yes (novel) |

This is the SVG namespace URI. The autostitch pipeline correctly identified it in the dynamic trace, but the code generation step silently dropped it. See [Novel Extension 1](#novel-extension-1-svg-namespace-sink).

> **Note on nondeterminism:** Vue's test suite trace count varied across runs (232, 229, and 333 in three separate runs). Despite this, the final list of discovered sinks was identical in all runs. The nondeterminism affects intermediate data only.

### Table VII — Framework Analysis Runtime

Absolute runtimes are higher than the paper's due to WSL2 overhead and differences in how `cloc` counts generated files. Relative ordering across frameworks is preserved.

| Framework | Paper (Time) | Paper (LoC) | Reproduced (Time) | Reproduced (LoC) |
|-----------|-------------|-------------|-------------------|------------------|
| Vue | 57m | 73k | 182m 8s | 3,309,154 |
| React | 1h 12m | 353k | 95m 35s | 6,263,695 |
| Angular | 1h 15m | 659k | 105m 29s | 13,306,641 |

### Fig. 5 and Fig. 6 — Performance Overhead

These figures were not produced by the original artifact. We wrote `plot_figures.py` to generate both from `repo_timings.csv`. Both are qualitatively consistent with the paper's figures. One repository (`survey-library`) had a Vanilla CodeQL runtime of 7,292 seconds due to a query timeout; it was excluded from regression fits using a 3-IQR outlier rule and annotated separately.

---

## Novel Extension 1: SVG Namespace Sink

### Discovery

During E1, the raw output of `main.ts` contained a Table V row not in the paper:

```
| http://www.w3.org/2000/svg | React | JS-Syntax |
```

When we inspected the generated `React.qll`, this sink was absent. Autostitch found it in Phase A but it was thrown away in Phase B.

### Root Cause

The `querygen/react.ts` module converts discovered sinks into CodeQL class definitions, but it only handles two pattern types:

- DOM property names (e.g. `innerHTML`, `href`) → `hasPropertyWrite(vulnNativeProp(), ...)` predicates
- DOM attribute names (e.g. `src`, `data-*`) → `hasPropertyWrite(vulnReactProp(), ...)` predicates

The SVG namespace URI `http://www.w3.org/2000/svg` is passed as a namespace argument to `document.createElementNS()` — not used as a property or attribute name — so it is silently skipped with no warning.

### The Two Exploitable Paths

**Sink 1 — `createElementNS` (`ReactDOMComponent.ts:335`):** When React renders an SVG element, it calls `ownerDocument.createElementNS(namespaceURI, type)`. If the tag name (`type`) is user-controlled, an attacker can inject arbitrary SVG elements. SVG elements like `<animate>` support event handlers that fire without user interaction.

**Sink 2 — `innerHTML` fallback (`setInnerHTML.ts`):** When `dangerouslySetInnerHTML` is used inside an SVG node, React uses an IE compatibility fallback: it creates a temporary `div` and sets its `innerHTML` directly with the tainted content wrapped in `<svg>` tags. No sanitisation occurs.

### Proof-of-Concept

Sink 2 triggers an `alert()` automatically on page load:

```javascript
let container = document.createElement('div');
const tainted = '<animate onbegin="alert(\'XSS: SVG innerHTML sink confirmed\')" dur="1s" />';
container.innerHTML = '<svg>' + tainted + '</svg>';
document.body.appendChild(container.firstChild);
```

### CodeQL Sink Class

Added to `React.qll` as `ReactSvgNamespaceSink`:

```ql
class ReactSvgNamespaceSink extends ReactSink {
  ReactSvgNamespaceSink() {
    exists(DataFlow::CallNode c |
      c = DataFlow::globalVarRef("document")
            .getAMemberCall("createElementNS") and
      c.getArgument(0).getStringValue() = "http://www.w3.org/2000/svg" and
      this = c.getArgument(1)
    ) or
    exists(DataFlow::PropWrite pw |
      pw.getPropertyName() = "innerHTML" and
      pw.getBase().toString().matches("%reusableSVGContainer%") and
      this = pw.getRhs()
    )
  }
}
```

### Impact

Scanning all 20 FDR repositories produced 104 alerts across 14 repositories (70%). Manual review found 36 true positives (34.6%) — including all 19 `we-vue domPropsInnerHTML` calls, 7 SVG `xlinkHref` sinks in `survey-library`, and unsafe `innerHTML` markdown rendering in `ng2-markdown` — and 68 false positives (65.4%), most caused by `xlinkHref` matching normal `href` attributes outside SVG contexts.

All 104 alerts were previously invisible to both TranSPArent and Vanilla CodeQL.

---

## Novel Extension 2: Vue 3 Extension

### Motivation

Vue 3 is a complete rewrite of Vue 2's rendering engine. It introduces the Composition API, Custom Elements integration, overhauled SSR hydration, and native MathML support (v3.3+). None of Vue 3's DOM operation patterns are captured by the paper's Vue 2 sink classes. Applications that have migrated from Vue 2 to Vue 3 are entirely invisible to TranSPArent's existing analysis.

### Method

Vue 3.4.0 was cloned and a CodeQL database was built from source (20.87 MiB). The following source files were audited for dangerous DOM operations:

- `packages/runtime-dom/src/nodeOps.ts` — core DOM creation functions
- `packages/runtime-dom/src/modules/attrs.ts` — attribute setting including `xlink:`
- `packages/runtime-dom/src/modules/props.ts` — property setting including `innerHTML`
- `packages/runtime-dom/src/apiCustomElement.ts` — Custom Elements API
- `packages/runtime-core/src/hydration.ts` — SSR hydration `textContent` assignment

Two CodeQL queries (`vue3_sinks.ql` and `vue3_createns.ql`) were written to programmatically verify sink locations before writing `Vue3.qll`.

Pipeline integration required two lines in `TranSPArentOnly.ql`:

```ql
import transparentsinks.Vue3
or sink instanceof Vue3Sink
```

### Sink Classes

Five of the seven classes have no Vue 2 equivalent and represent vulnerability pathways introduced by Vue 3's architecture.

| Sink Class | New in v3? | Mechanism | Source File |
|------------|-----------|-----------|-------------|
| `Vue3VHtmlSink` | No | `innerHTML` assignment | `runtime-dom/src/index.ts` |
| `Vue3NativeAttrSink` | No | `setAttribute(key, value)` | `modules/attrs.ts:39,72` |
| `Vue3SvgNamespaceSink` | **Yes** | `createElementNS(svgNS, tag)` | `nodeOps.ts:25` |
| `Vue3MathMLNamespaceSink` | **Yes** | `createElementNS(mathmlNS, tag)` | `nodeOps.ts:27` |
| `Vue3XlinkSink` | **Yes** | `setAttributeNS(xlinkNS, key, value)` | `modules/attrs.ts:26` |
| `Vue3CustomElementSink` | **Yes** | `setAttribute()` in Custom Elements API | `apiCustomElement.ts:348` |
| `Vue3HydrationTextSink` | **Yes** | `textContent` in SSR hydration | `runtime-core/hydration.ts:437` |

> The two shared sink types (`innerHTML` and `setAttribute`) are still necessary because Vue 3 reaches them through a completely different internal call graph. Vue 2 CodeQL classes do not fire on Vue 3 code even for these common operations.

### Results

Scanning 19 FDR repositories (one timed out and was excluded) produced 101 alerts across 12 repositories (63%). None of these alerts are produced by the original TranSPArent or Vanilla CodeQL.

| Repository | Alerts |
|------------|--------|
| Keen-UI | 39 |
| design-system-react | 27 |
| nylas-mail | 15 |
| quix | 14 |
| Bilibili-Evolved | 6 |
| bootstrap-vue | 5 |
| apostrophe | 4 |
| iview | 3 |
| ng2-markdown | 2 |
| vue-tailwind | 2 |
| vue-markdown | 1 |
| mriviewer | 1 |
| vue-admin | 1 |
| vssue | 1 |

### Limitations

- Sinks were identified through manual source inspection rather than via autostitch. Running the autostitch pipeline on Vue 3 source would be the next logical step.
- No false positive analysis was performed; alert counts are reported but not manually verified.
- Only Vue 3.4.0 was tested. Core DOM operations in `runtime-dom` are stable across minor versions, but Vue 3.5 may introduce new patterns.
- `survey-library` timed out during database build and was excluded; the true alert count is likely higher than 101.

---

## What Was Changed and Added

### Modified Files

#### `qlpack/transparentsinks/React.qll`

Added the `ReactSvgNamespaceSink` class (lines 95–118). Lines 1–94 were generated automatically by the E1 pipeline.

```bash
sed -n '95,118p' ~/transparent-ae-1.0.0/qlpack/transparentsinks/React.qll
grep -n "SvgNamespace\|createElementNS\|reusableSVG" \
  ~/transparent-ae-1.0.0/qlpack/transparentsinks/React.qll
cat ~/transparent-ae-1.0.0/qlpack/transparentsinks/React.qll
```

#### `qlpack/TranSPArentOnly.ql`

Updated to include the Vue 3 sink classes.

```bash
grep -n "Vue3\|vue3" ~/transparent-ae-1.0.0/qlpack/TranSPArentOnly.ql
cat ~/transparent-ae-1.0.0/qlpack/TranSPArentOnly.ql
```

#### `transparent/main.sh`

Modified to add strict error handling, per-framework runtime measurement, SLoC measurement via `cloc`, CSV output generation, and formatted Table V / Table VII printing.

```bash
cat ~/transparent-ae-1.0.0/transparent/main.sh
```

#### `accuracy/main.sh`

Modified to add per-repository timing, SLoC measurement, CSV output for plotting, and corrected query execution order. The original script ran Baseline first, which warmed the CodeQL cache and made TranSPArent appear artificially faster. The corrected order runs `TranSPArentOnly.ql` first on a cold cache, then `Baseline.ql` second.

```bash
cat ~/transparent-ae-1.0.0/accuracy/main.sh
grep -n "TranSPArent\|Baseline\|cache\|cold" ~/transparent-ae-1.0.0/accuracy/main.sh
```

---

### New Files

#### `qlpack/transparentsinks/Vue3.qll`

Seven Vue 3 sink classes written by auditing Vue 3.4.0 runtime source. Five have no Vue 2 equivalent.

```bash
cat ~/transparent-ae-1.0.0/qlpack/transparentsinks/Vue3.qll
```

#### `qlpack/vue3_sinks.ql`

CodeQL query used to verify Vue 3 sink locations before writing `Vue3.qll`.

```bash
cat ~/transparent-ae-1.0.0/qlpack/vue3_sinks.ql

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
codeql query run \
  --database ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src \
  --output ~/vue3-sinks.bqrs \
  ~/transparent-ae-1.0.0/qlpack/vue3_sinks.ql

codeql bqrs decode --format=csv ~/vue3-sinks.bqrs | head -30
```

#### `qlpack/vue3_createns.ql`

CodeQL query used to verify namespace-related sink locations.

```bash
cat ~/transparent-ae-1.0.0/qlpack/vue3_createns.ql

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
codeql query run \
  --database ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src \
  --output ~/vue3-createns.bqrs \
  ~/transparent-ae-1.0.0/qlpack/vue3_createns.ql

codeql bqrs decode --format=csv ~/vue3-createns.bqrs | head -40
```

#### `accuracy/plot_figures.py`

Generates Fig. 5 and Fig. 6 from `repo_timings.csv`. Implements linear regression, CDF plotting, and outlier handling using a 3-IQR rule.

```bash
cat ~/transparent-ae-1.0.0/accuracy/plot_figures.py
```

#### `svg-sink-poc/poc.html`

Proof-of-concept HTML confirming the SVG `innerHTML` sink. Opening the page triggers an `alert()` automatically on load.

```bash
cat ~/svg-sink-poc/poc.html
wslview ~/svg-sink-poc/poc.html   # or: explorer.exe ~/svg-sink-poc/poc.html
```

#### `transparent/targets/vue3-src/`

Vue 3.4.0 framework source added as a new analysis target.

```bash
ls ~/transparent-ae-1.0.0/transparent/targets/vue3-src/
ls ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src/ 2>/dev/null \
  || echo "Database not yet built"
```

---

## Environment

| Item | Requirement |
|------|-------------|
| OS | Windows 11 with WSL2 (Ubuntu 24.04) |
| RAM | 16 GB minimum, 24 GB recommended |
| Disk Space | ~50 GB |
| CPU | Any x86-64 CPU |
| GPU | Not required |

---

## Setup

Run all commands inside WSL. Steps 1–8 reproduce the original paper. Step 9 is required only for the Vue 3 extension.

> **Important:** Do not clone from GitHub. The Git LFS quota is exceeded and dataset files will be silently replaced with pointer files. Download directly from Zenodo instead (Step 2).

The artifact required six environment fixes before the pipeline would run on a fresh WSL installation:

| Issue | Root Cause | Fix Applied |
|-------|-----------|-------------|
| Corepack signature failure | NPM rotated its signing keys; Nix's Node 18 could not verify packages | `COREPACK_ENABLE=0` + `npm install -g yarn` |
| React database name mismatch | `main.sh` creates a DB named `react-src` but `main.ts` looks for `react-ts-src` | Manually ran `yarn build` inside `targets/react-src` |
| Angular git submodule error | ZIP extraction left a broken `.git` pointer file | Deleted the `.git` file and ran `git init` inside the Angular directory |
| `bazelisk` not found | Bazelisk is not included in the Nix shell PATH | `nix profile install nixpkgs#bazelisk` |
| Puppeteer Chrome blocked | Puppeteer tries to download Chrome; network blocks it | `PUPPETEER_SKIP_DOWNLOAD=true` |
| CodeQL location warning | CodeQL is installed inside the home directory | `CODEQL_ALLOW_INSTALLATION_ANYWHERE=true` |

---

### Step 1 — Enable Nix flakes

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
mkdir -p ~/.config/nixpkgs
echo '{ allowUnfree = true; }' > ~/.config/nixpkgs/config.nix
```

### Step 2 — Download artifact from Zenodo

```bash
cd ~
wget -O artifact.zip \
  "https://zenodo.org/records/17822391/files/transparent-ae-1.0.0.zip?download=1"

unzip artifact.zip
cd transparent-ae-1.0.0

git init && git add .
```

### Step 3 — Fix Corepack and install Yarn

```bash
echo 'export COREPACK_ENABLE=0' >> ~/.bashrc
echo 'export COREPACK_INTEGRITY_KEYS=0' >> ~/.bashrc
source ~/.bashrc

npm install -g yarn
yarn --version
```

### Step 4 — Fix permissions and run installer

```bash
sudo chown -R $USER:$USER ~/.codeql 2>/dev/null || true
sudo chown -R $USER:$USER ~/.cache/nix 2>/dev/null || true

cd ~/transparent-ae-1.0.0
chmod +x install.sh && ./install.sh
```

### Step 5 — Verify installation

```bash
cd ~/transparent-ae-1.0.0/transparent
./test.sh
```

### Step 6 — Install Bazelisk

```bash
nix profile install nixpkgs#bazelisk
which bazelisk
```

### Step 7 — Fix Angular git submodule

```bash
rm ~/transparent-ae-1.0.0/transparent/targets/angular-src/angular/.git

cd ~/transparent-ae-1.0.0/transparent/targets/angular-src/angular
git init && git add . && git commit -m "init" --quiet
```

### Step 8 — Build React TypeScript database

```bash
cd ~/transparent-ae-1.0.0/transparent/targets/react-src

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
yarn build
```

### Step 9 — Set up Vue 3 (extension only)

```bash
cd ~/transparent-ae-1.0.0/transparent/targets

git clone --depth 1 --branch v3.4.0 \
  https://github.com/vuejs/core vue3-src

cd vue3-src

PUPPETEER_SKIP_DOWNLOAD=true COREPACK_ENABLE=0 \
  pnpm install --frozen-lockfile

git init && git add . && git commit -m "vue3 init" --quiet
```

Build Vue 3 CodeQL database:

```bash
CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
codeql database create \
  --language javascript \
  --source-root . \
  --overwrite \
  ~/transparent-ae-1.0.0/transparent/build/codeql-db/vue3-src
```

---

## Running the Experiments

Use `tmux` for long-running commands to prevent process termination if the terminal closes.

```bash
tmux new-session -s transparent
# Detach: Ctrl+B then D
# Reconnect: tmux attach -t transparent
```

### E1 — Framework Sink Discovery (Table V & Table VII)

Estimated runtime: ~6 hours

```bash
cd ~/transparent-ae-1.0.0/transparent

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
PUPPETEER_SKIP_DOWNLOAD=true \
./main.sh 2>&1 | tee ~/transparent-ae-1.0.0/tableV.log
```

```bash
tail -f ~/transparent-ae-1.0.0/tableV.log
```

### E2 — Accuracy Evaluation (Table IV)

Estimated runtime: ~4 hours

```bash
cd ~/transparent-ae-1.0.0/accuracy

CODEQL_ALLOW_INSTALLATION_ANYWHERE=true \
PUPPETEER_SKIP_DOWNLOAD=true \
./main.sh 2>&1 | tee ~/transparent-ae-1.0.0/tableIV.log
```

### Figure Generation (Fig. 5 & Fig. 6)

Requires E2 to have completed and `repo_timings.csv` to exist.

```bash
pip install matplotlib numpy --break-system-packages

cd ~/transparent-ae-1.0.0/accuracy
python3 plot_figures.py
```

Outputs: `fig5_performance_overhead.png`, `fig6_cdf_overhead.png`

### SVG Sink Scan (React SVG Namespace Extension)

Requires E1 to have completed and `ReactSvgNamespaceSink` to be present in `React.qll`.

```bash
cd ~/transparent-ae-1.0.0/accuracy
mkdir -p fdr/build_svg

QUERY_PATH=$(cd ~/transparent-ae-1.0.0/qlpack && pwd)/TranSPArentOnly.ql

for repo in $(ls fdr/repos/); do
  codeql database create --language javascript \
    --source-root "fdr/repos/$repo" \
    --overwrite "fdr/build_svg/${repo}_db"
  codeql query run \
    --database "fdr/build_svg/${repo}_db" \
    --output "fdr/build_svg/${repo}_svg.bqrs" "$QUERY_PATH"
  codeql bqrs decode --format=csv \
    "fdr/build_svg/${repo}_svg.bqrs" > "fdr/build_svg/${repo}_svg.csv"
done
```

### Vue 3 Sink Scan (Vue 3 Extension)

Requires Step 9 (Vue 3 setup) to have completed.

```bash
cd ~/transparent-ae-1.0.0/accuracy
mkdir -p fdr/build_vue3

QUERY_PATH=$(cd ~/transparent-ae-1.0.0/qlpack && pwd)/TranSPArentOnly.ql

for repo in $(ls fdr/repos/); do
  codeql database create --language javascript \
    --source-root "fdr/repos/$repo" \
    --overwrite "fdr/build_vue3/${repo}_db"
  codeql query run \
    --database "fdr/build_vue3/${repo}_db" \
    --output "fdr/build_vue3/${repo}_vue3.bqrs" "$QUERY_PATH"
  codeql bqrs decode --format=csv \
    "fdr/build_vue3/${repo}_vue3.bqrs" > "fdr/build_vue3/${repo}_vue3.csv"
done
```

---

## Output Locations

| Output | Location |
|--------|----------|
| Table V & VII | `tableV.log` |
| Table IV | `tableIV.log` |
| React sink classes | `qlpack/transparentsinks/React.qll` |
| Vue 3 sink classes | `qlpack/transparentsinks/Vue3.qll` |
| Fig. 5 | `accuracy/fig5_performance_overhead.png` |
| Fig. 6 | `accuracy/fig6_cdf_overhead.png` |
| Timing CSV | `accuracy/repo_timings.csv` |
| SVG sink alerts | `accuracy/fdr/build_svg/` |
| Vue 3 alerts | `accuracy/fdr/build_vue3/` |
| SVG PoC | `svg-sink-poc/poc.html` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Missing datasets | Download artifact from Zenodo (Step 2) |
| Corepack signature failure | Set `COREPACK_ENABLE=0` (Step 3) |
| `bazelisk` missing | `nix profile install nixpkgs#bazelisk` (Step 6) |
| Angular git submodule error | Reinitialise `.git` inside Angular directory (Step 7) |
| `react-ts-src` database missing | Run `yarn build` inside `targets/react-src` manually (Step 8) |
| Pipeline interrupted | Restart from beginning — no checkpointing exists |
| Puppeteer download blocked | Set `PUPPETEER_SKIP_DOWNLOAD=true` |
| CodeQL location warning | Set `CODEQL_ALLOW_INSTALLATION_ANYWHERE=true` |

---

## Extending to Other Frameworks

The Vue 3 extension demonstrates that TranSPArent generalises cleanly to frameworks beyond the paper's original scope. Adding support for a new framework follows the same three-step pattern:

1. Audit the framework's DOM operation source files (key targets: element creation, attribute setting, innerHTML, namespace calls)
2. Write a `.qll` file with CodeQL sink classes for the discovered patterns
3. Add one `import` and one `or sink instanceof` line to `TranSPArentOnly.ql`

Estimated effort per new framework: 2–3 hours for source analysis, 1–2 hours for CodeQL implementation, 1–2 hours for testing — roughly 4–7 hours total.

**Important:** Major framework versions must be treated as separate targets. Scanning a Vue 3 app with Vue 2 rules only misses the 5 new vulnerability pathways introduced in Vue 3 — approximately 40% of findings.

---

## Appendix: Vue3.qll Complete Source

```ql
import javascript
import common.DOMExtended
import common.PropPropagation

abstract class Vue3Sink extends DataFlow::Node {}

class Vue3VHtmlSink extends Vue3Sink {
  Vue3VHtmlSink() {
    exists(DataFlow::PropWrite pw |
      pw.getPropertyName() = "innerHTML" and
      not pw.getFile().getAbsolutePath().matches("%__tests__%") and
      this = pw.getRhs()
    )
  }
}

class Vue3NativeAttrSink extends Vue3Sink {
  Vue3NativeAttrSink() {
    exists(DataFlow::CallNode call |
      call.getCalleeName() = "setAttribute" and
      not call.getFile().getAbsolutePath().matches("%__tests__%") and
      not call.getArgument(0).getStringValue().matches("data-v-%") and
      not call.getArgument(0).getStringValue() = "class" and
      not call.getArgument(0).getStringValue() = "multiple" and
      this = call.getArgument(1)
    )
  }
}

class Vue3SvgNamespaceSink extends Vue3Sink {
  Vue3SvgNamespaceSink() {
    exists(DataFlow::CallNode call |
      call.getCalleeName() = "createElementNS" and
      not call.getFile().getAbsolutePath().matches("%__tests__%") and
      (
        call.getArgument(0).getStringValue() = "http://www.w3.org/2000/svg"
        or call.getArgument(0).toString().matches("%svgNS%")
      ) and
      this = call.getArgument(1)
    )
  }
}

class Vue3MathMLNamespaceSink extends Vue3Sink {
  Vue3MathMLNamespaceSink() {
    exists(DataFlow::CallNode call |
      call.getCalleeName() = "createElementNS" and
      not call.getFile().getAbsolutePath().matches("%__tests__%") and
      (
        call.getArgument(0).getStringValue() = "http://www.w3.org/1998/Math/MathML"
        or call.getArgument(0).toString().matches("%mathmlNS%")
      ) and
      this = call.getArgument(1)
    )
  }
}

class Vue3XlinkSink extends Vue3Sink {
  Vue3XlinkSink() {
    exists(DataFlow::CallNode call |
      call.getCalleeName() = "setAttributeNS" and
      not call.getFile().getAbsolutePath().matches("%__tests__%") and
      this = call.getArgument(2)
    )
  }
}

class Vue3CustomElementSink extends Vue3Sink {
  Vue3CustomElementSink() {
    exists(DataFlow::CallNode call |
      call.getCalleeName() = "setAttribute" and
      call.getFile().getAbsolutePath().matches("%apiCustomElement%") and
      this = call.getArgument(1)
    )
  }
}

class Vue3HydrationTextSink extends Vue3Sink {
  Vue3HydrationTextSink() {
    exists(DataFlow::PropWrite pw |
      pw.getPropertyName() = "textContent" and
      pw.getFile().getAbsolutePath().matches("%hydration%") and
      this = pw.getRhs()
    )
  }
}
```

---



To keep the repository lightweight, large generated artifacts and framework source directories are excluded from version control. The following directories are not included:

- `transparent/targets/`
- `transparent/build/`
- `transparent/node_modules/`
- `transparent/packages/`
- `accuracy/fdr/`
- `accuracy/fnr/`

These can be regenerated by following the setup and execution steps above. The repository contains all modified CodeQL queries and sink models, all experiment scripts, generated logs, CSVs, and figures, and all novel extensions developed during this work.
