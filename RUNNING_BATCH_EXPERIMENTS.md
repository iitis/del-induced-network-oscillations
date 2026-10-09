# Running batch experiments

See `README.md` for scope, external data and validation. Execute commands from the repository root, with the fixed input MAT available separately.

```bash
mkdir -p logs
MATLAB_MODULE=YOUR_MATLAB_MODULE sbatch --export=ALL --partition=YOUR_PARTITION submit_runSim4quart.sh data/net_config_G_only.mat config_publication_example
```

`submit_runSim4quart_batch.sh` is a compatibility alias using the same implementation. Both retain SLURM directives for old submission commands. Wrappers read input/config from environment variables inside MATLAB, so filenames are not interpolated into MATLAB source. Submit from the root; output directories in configs are relative to the submission working directory.

Replace `YOUR_MATLAB_MODULE` and `YOUR_PARTITION` with values available in your environment. Module names and scheduling policies are site specific. Set `MATLAB_MODULE` and adjust wall time, memory and partition using sbatch flags; bundled defaults are examples from the development environment. Create `logs/` before submission. The 15-minute example allocation is not a guaranteed duration for production sweeps.

Without SLURM, run directly wherever MATLAB is available:

```bash
matlab -batch "run_experiment_batch_cli('data/net_config_G_only.mat','config_publication_example')"
```

On managed clusters, execute this command only on resources allocated according to local policy.

## Configuration

Configuration functions in `configs/` receive the input G and return a scalar struct:

| Field | Meaning/default |
| --- | --- |
| `t_run` | Required positive, finite integer number of biological seconds |
| `rec` | Record dense/per-second diagnostics; false by default |
| `plot` | Enable raster plots independently; false by default |
| `output_dir` | Output directory; `batch_results` by default |
| `seeds` | Nonnegative integer seeds up to uint32 maximum; 1 by default |
| `grid.lr`, `grid.esr`, `grid.sm` | Parameter vectors; defaults from input G |
| `save_full_G` | Save final continuation state; true by default |
| `save_recordings` | Save recordings; defaults to rec and requires rec=true when enabled |
| `verbose` | Batch progress messages; true by default |
| `use_precomputed_rand_ext` | Generate/store uniform external drive per run; false by default |

Flag fields must be scalar 0/1 values. Parameter limits reflect this implementation: 0<=lr<=4000 (nonnegative derivative-decay factor), 0<=esr<=4 (0.25*esr is a probability), sm>0. These are numerical validity limits, not recommended biological parameters. Each grid combination and seed starts from an independent copy of input G.

`config_publication_example` is a two-second functional check with dense recording and precomputed external drive; it is not the full paper experiment. `config_grid_lr_esr` defines 27 runs of 60 seconds without dense recordings. Use separate output directories for different experiments to avoid overwriting results.

## Recordings and external drive

When rec=true, dense outputs A1, A1e, LFP1, LFP2, LTP and LTD have 4000 rows per completed second. Per-second outputs include degrees, delay-conditioned weights, unit activity and motif diagnostics. With rec=false these extra arrays are absent, while G.A and G.s_mean still accumulate per-second histories.

The precomputed uniform drive occupies approximately 8*N*4000*t_run bytes, in addition to states and recordings. Fresh batches reset its cursor. Direct continuation requires enough unused columns and preserves the cursor. Do not reset only the cursor and call that a replay; replay needs the original network state as well.

## Outputs

Successful calls save one run MAT, even with both data-saving options disabled (metadata/config only). Saved run_metadata identifies seed, parameters, completion, stopping and current-segment summary statistics. Final G is saved only if requested. If recordings are requested, arrays are trimmed to the actual completed duration.

`finished=true` means the simulator returned without exception. `completed_requested_duration` and `stop_reason` distinguish duration completion from runaway termination. Undefined motif ratios and zero-variance/undefined surrogate Z scores are NaN.

Batch summaries are `batch_summary.mat` and, if export succeeds, `batch_summary.csv`; the CLI also saves `results_workspace.mat`. Run-specific simulator errors are saved in `*_ERROR.mat` and remaining runs continue. Configuration/input validation errors stop before the sweep. After summaries are saved, the CLI exits with failure if any run failed. Matching output filenames are overwritten.

## Job inspection

```bash
squeue -u "$USER"
tail -f logs/izh_batch_JOBID.out
```

For validation, retain the complete `logs/izh_validation_JOBID.out` and `.err` logs, including version information and any stack traces.
