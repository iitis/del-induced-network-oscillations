# Reproducibility notes

This repository contains the public MATLAB implementation used for delay-induced network-oscillation simulations associated with the manuscript

**Statistical Mechanics of Spike Trains: Self-Consistent Activity Ensembles and Phase Transitions**.

## Scope of this public release

This public release contains the MATLAB code only. C/C++ implementations, compiled binaries, large MATLAB data files, and build artifacts are intentionally excluded from this repository.

## Repository structure

- `configs/` — configuration files.
- `data/` — placeholder directory for external data files.
- `docs/` — documentation, if present.
- `motif_index.m` — motif-index helper routine.
- `runSim4quart.m` — main MATLAB simulation routine.
- `run_batch_runSim4quart.m` — batch runner.
- `run_experiment_batch_cli.m` — command-line batch entry point.
- `submit_runSim4quart*.sh` — SLURM submission scripts.

## External data

Large MATLAB data files are not included in this GitHub repository. If required for full reproduction, they should be archived separately in a versioned data repository such as Zenodo.

## Notes on stochasticity

The simulations involve stochastic biologically motivated spiking-network dynamics and may depend on random seeds, MATLAB version, and run configuration. Exact bitwise reproduction may require matching the original execution environment.

## License

GPL-3.0-only.
