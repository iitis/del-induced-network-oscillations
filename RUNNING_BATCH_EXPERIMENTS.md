# MATLAB simulator for Izhikevich/STDP network dynamics

This repository contains a standalone MATLAB implementation of a quarter-millisecond recurrent Izhikevich/STDP network simulator used in the accompanying simulations.

The main simulator is:

```text
runSim4quart.m
```

Batch execution is handled by:

```text
run_batch_runSim4quart.m
run_experiment_batch_cli.m
submit_runSim4quart.sh
submit_runSim4quart_batch.sh
```

## Project layout

```text
Sim4QuartMat/
├── README.md
├── runSim4quart.m
├── run_batch_runSim4quart.m
├── run_experiment_batch_cli.m
├── submit_runSim4quart.sh
├── submit_runSim4quart_batch.sh
├── motif_index.m
├── configs/
│   └── config_publication_example.m
├── data/
│   └── net_config_G_only.mat
├── docs/
└── logs/
```

The expected input MAT-file must contain a variable named:

```matlab
G
```

The supplied example input is:

```text
data/net_config_G_only.mat
```

`G` is a continuation state for the simulator. It must already contain the auxiliary indexing fields required by `runSim4quart`, including:

```matlab
G.delays_ref
G.pre
G.aux
```

These fields are validated by the public batch runner but are not regenerated there. Network initialization is treated as an upstream step.

## Running an example simulation

From the project directory:

```bash
sbatch submit_runSim4quart.sh data/net_config_G_only.mat config_publication_example
```

The configuration function should be located in `configs/` and should return a struct named `config`.

Important configuration fields include:

```matlab
config.t_run
config.rec
config.output_dir
config.seeds
config.grid.lr
config.grid.esr
config.grid.sm
config.use_precomputed_rand_ext
```

## Deterministic replay

For deterministic replay of externally driven simulations, set:

```matlab
config.use_precomputed_rand_ext = true;
```

The batch runner then generates and stores:

```matlab
G.rand_ext
```

with size:

```text
G.N × (4000 * config.t_run)
```

`runSim4quart.m` consumes `G.rand_ext(:,step)` as the source of externally driven stochastic spikes. This makes repeated runs consume the same external drive.

## Recording mode

If:

```matlab
config.rec = 1;
```

the simulator records dense quarter-step diagnostics:

```text
A1, A1e, LFP1, LFP2, LTP, LTD
```

Since the simulator uses 4000 time bins per biological second, a run of length `t_run` seconds produces:

```text
4000 * t_run
```

dense samples.

The batch runner also records per-second summaries such as activity, mean synaptic weight, degree summaries, delay summaries, and motif diagnostics.

## Output files

For each successful run, the runner writes one MAT-file to the configured output directory. The filename encodes the run index, parameter values, and seed.

The output directory also contains:

```text
batch_summary.mat
batch_summary.csv
results_workspace.mat
```

Failed runs are written to dedicated `*_ERROR.mat` files and do not abort the full parameter sweep.

## Checking job status on TASK

Show queued and running jobs:

```bash
squeue -u $USER
```

Inspect logs:

```bash
tail -f logs/izh_batch_<JOBID>.out
tail -f logs/izh_batch_<JOBID>.err
```

## Recommended workflow

1. Verify that the input `G` contains the required continuation and auxiliary fields.
2. Start from `configs/config_publication_example.m`.
3. Create a new configuration file for each new parameter sweep.
4. Submit using `submit_runSim4quart.sh`.
5. Inspect `batch_summary.csv` and selected run MAT-files after completion.

## Scope of this repository

This repository contains the core MATLAB simulation and batch-execution pipeline.

Network initialization and downstream analysis modules, including full experimental signal processing and figure-generation scripts, are treated as separate modules and may be added later.
