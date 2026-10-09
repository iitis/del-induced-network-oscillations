# Reproducibility and validation

This code accompanies **Delay-induced network oscillations shape epileptic fast ripple activity in a computational model based on human epileptic tissue data**.

## Fixed network input

Each parameter/seed run starts from a copy of the same externally supplied continuation state `G`, prepared during earlier experiments. A fixed state is the chosen input for this study. Upstream initialization generators are outside this release's scope. Scientific input provenance, version, license and checksum must accompany the separate Zenodo dataset; see `data/README.md`.

The public code covers simulation and batch execution. It does not by itself reproduce upstream network preparation or the complete manuscript signal-processing and figure pipeline.

## RNG and continuation

Batch runs reset the generator to their configured scalar seed. Direct simulator calls restore `G.rng_state`, or the historical `G.rand_state` scalar/vector. Returned states contain an mt19937ar state vector in both fields, plus `rng_type`. Invalid RNG input causes an error; no clock-based shuffle fallback is used. The caller's global RNG stream is restored on exit.

Optional precomputed external drive is an N-by-(4000*t_run) array of uniform samples. Fresh batch runs reset `rand_ext_cursor` to 1. Direct continuation consumes subsequent columns and saves the cursor. There must be enough unconsumed columns for the requested duration; exhausted arrays cause an error. Replaying an earlier segment requires its original network state and drive/cursor. A final state with cursor reset to 1 is not a replay of the earlier network dynamics.

Precomputed drive does not consume the simulator's live RNG stream. Changing a continued state from precomputed to live drive therefore does not preserve the same external forcing. Preserve the selected mode when testing continuation. Bitwise reproduction can depend on MATLAB version and numerical environment.

## Revised output semantics

Summary means/maxima describe the new simulated segment. Prior histories remain in `G`, and original runaway thresholds still use recent activity including prior history. `finished` indicates no simulator exception; duration completion and stop reason are separate fields. Early-stop recordings are trimmed. Undefined motif ratios and surrogate Z scores are NaN, not zero. These changes affect bookkeeping and continuation reproducibility relative to older source versions.

The optional legacy fourth argument for external raster scripts has been replaced by an options struct, e.g. `struct('plot',true)`. Those external raster helpers were not included in this release.

## Short validation

From the repository root:

```bash
python3 tests/check_repository_static.py
matlab -batch "addpath('tests'); run_task_validation('data/net_config_G_only.mat')"
```

Use the actual scientific input path. The validation function retains its historical name `run_task_validation` but can run in any supported MATLAB environment. On a cluster, follow the local policy for allocating compute resources.

For SLURM execution:

```bash
mkdir -p logs
MATLAB_MODULE=YOUR_MATLAB_MODULE sbatch --export=ALL --partition=YOUR_PARTITION submit_validation.sh data/net_config_G_only.mat
```

Replace the module and partition placeholders with values available at your site. Adapt time and memory requests to the selected partition. Bundled wrapper defaults are development-environment examples. Create logs before submission because SLURM opens log files before the shell runs.

Technical regression tests use a tiny fixture, not a scientific network generator. They cover invalid durations/seeds/flags/parameters, RNG replay and split continuation, minute boundaries, external-drive cursors, early-stop status and recording length, current-segment summaries, saved metadata, and undefined motif statistics.

The real-state smoke test validates the supplied G and runs one second with its lr/esr/sm, seed 1, recording enabled and precomputed drive. It saves results under a new timestamped `validation_results/` directory. The input file is not overwritten. Runaway status is reported even if it occurs on the last requested second; a successful test is not evidence of physiological validity or scientific convergence.

Keep complete stdout/stderr logs, including MATLAB version, platform, code commit and working-tree status, input SHA-256, and stack traces. Successful full validation is reported at the end of stdout. Short validation passed on 2026-10-08 with MATLAB R2024b Update 4 on Linux; this does not imply validation of all production configurations.
