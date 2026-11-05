# TASK: hourly grid campaign

Code checkout: `/users/kdm/jpy/del-induced-task-hourly-grid`.
Existing input: `/users/project1/pt01269/in_delmean=16q_pii=0.05_zoom`.
Campaign files go under `/users/project1/pt01269/runs/`, including logs,
temporary files and both output MAT files per point-hour.

Run commands from the root of the committed code checkout on TASK.

## 1. Inventory and manifest

```bash
python3 campaign/grid.py inventory
```

Send the inventory before making the manifest so the coordinate regex can be
chosen from the actual filenames. It must match the entire filename and contain
named groups `(?P<x>...)` and `(?P<y>...)` representing numeric coordinates.
The manifest checks the full Cartesian 9x9 grid and hashes every input.
For a format other than coordinates in filenames, adapt the parser before use.

```bash
RUN=/users/project1/pt01269/runs/delmean16q_pii005_zoom_12h
python3 campaign/grid.py manifest --run "$RUN" --pattern "$COORDINATE_REGEX"
```

The manifest is exclusive-create. Do not edit it while jobs use the campaign.
Use a new directory for a different manifest or recording configuration.

## 2. Preflight and continuity

The original zoom-grid initializers may have a zero STDP array with
`2001+D` columns and no RNG state. For this known initializer format,
export `CAMPAIGN_LEGACY_INIT=1` before submission. The runner checks the
initial clock, zero STDP history, 8/4 refractory bins and empty firing history
(sentinel only), then expands the buffer in memory to `4001+D`. The input MAT
is unchanged. This is not a timestep conversion.

For inputs without RNG state, export `CAMPAIGN_INITIAL_SEED` with the
agreed integer seed. Use the same settings for preflight, continuity, pilot
and production. An existing RNG state takes precedence; resuming a checkpoint
never runs the initializer adapter. If `esr` is nonzero and no external drive
is stored, the seed controls the external forcing. Using the same seed across
points selects a shared draw sequence rather than independent streams.
Both settings are recorded in checkpoint identity.

Example resource requests below are provisional. Check quota, partition and
module availability and adapt requests on TASK.

```bash
sbatch --time=00:30:00 --mem=32G --array=1-81%4 \
  --output="$RUN/logs/preflight_%A_%a.out" --error="$RUN/logs/preflight_%A_%a.err" \
  campaign/submit_hourly_grid.sbatch "$RUN" preflight
```

Require successful preflight for every input. This checks checkpoint structure,
RNG compatibility and capacity of any stored external drive. It does not
verify the biological meaning of the grid coordinates. Then:

```bash
sbatch --time=00:30:00 --mem=32G --array=1 \
  --output="$RUN/logs/continuity_%A_%a.out" --error="$RUN/logs/continuity_%A_%a.err" \
  campaign/submit_hourly_grid.sbatch "$RUN" continuity
```

Require `CONTINUITY PASSED`: compare a continuous two-second run against two
one-second calls separated by saving/reloading G. Verify final G (excluding the
per-call duration report) and all seven signals, including RNG/cursor in G.

## 3. One-hour pilot

Use a separate run directory so the pilot with extras does not constrain the
production recording configuration:

```bash
PILOT=/users/project1/pt01269/runs/delmean16q_pii005_zoom_pilot
python3 campaign/grid.py manifest --run "$PILOT" --pattern "$COORDINATE_REGEX"
sbatch --time=24:00:00 --mem=32G --array=1 \
  --output="$PILOT/logs/pilot_%A_%a.out" --error="$PILOT/logs/pilot_%A_%a.err" \
  campaign/submit_hourly_grid.sbatch "$PILOT" run 1 1
```

Inspect `COMMITTED` in stdout and `sacct` elapsed/MaxRSS and job state. A
full hour is 3600 biological seconds. The final argument enables saving LTP,
LTD and A1unit; A1, A1e, LFP1 and LFP2 are always saved. Spike counts are
stored losslessly as uint16; LFP and plasticity signals stay double. The
simulator's existing recording mode still computes internal diagnostics even
when optional outputs are omitted from disk. Pilot disk and timing estimates
must include checkpoint size, both writes and possible staging leftovers.

## 4. Production and recovery

After reviewing the pilot, submit the wrapper with `"$RUN" run 12 0` (or
`12 1` for optional signals), using `--array=1-81%LIMIT` and resource
requests based on the measured cost. Keep MATLAB version, commit and recording
options fixed for a run directory. A lower target hour can divide the campaign
into multiple submissions; increasing the target continues the same output.

Each committed `points/NNN/hour_HH/` contains `checkpoint.mat`,
`recordings.mat` and `metadata.json`. A per-point lock prevents duplicate
writers. The checkpoint is the full G after that segment, including RNG state
and any stored external drive/cursor. Live random draws resume the state in G;
no new seed or precomputed random array is introduced. If stored drive is
insufficient, stop at preflight and resolve the scientific drive protocol.

A runaway is terminal even if the final segment reaches exactly 3600 seconds.
An unfinished segment caused by job termination does not commit a new hour.
Hidden `.partial-*` directories can remain after interruptions; review them
for disk usage after the owning job exits. Restart the same point ID with the
same settings to resume; previously published hours are preserved.

```bash
python3 campaign/grid.py status --run "$RUN"
```

Status reports completed hours and terminal reason or pending. Pending can
mean unstarted, running, or interrupted; consult SLURM before resubmitting.
The status scan checks committed metadata and file sizes, not MAT contents.
