# External scientific input data

Scientific MAT files are intentionally excluded from Git and will be published in a separate Zenodo archive. The example path used in the commands is:

```text
data/net_config_G_only.mat
```

The filename is an example, not a file shipped with the source release. Supply the actual input path to the batch or validation wrapper.

This MAT file is a saved simulation checkpoint: connectivity, neuronal state, synaptic weights and derivatives, buffered currents, STDP traces and auxiliary indices. It is not a CSV-like spike list, raw experimental recording, or parameter-only configuration. `G_only` is a naming convention; only the top-level variable `G` is loaded by the batch entry point, and other variables are ignored. A relative or absolute path and a different filename can be used.

## Input contract

The MAT file must contain a scalar struct `G`, a fixed continuation state prepared during earlier experiments. The code does not regenerate that state. Required fields include:

- Dimensions and clock: `N`, `Ne`, `D`, `t1`, `t2`.
- Model parameters: `lr`, `esr`, `sm`.
- Neurons: `v`, `u`, `a`, `d`, `ref`, `ref_duration` (N-by-1 vectors).
- Synapses: `s`, `sd`, `delays`, `delays_dend` (N-by-N), and `s_ind`.
- Buffers: `I` (N-by-sI_Tmax), `sI_Tmax`, `sI_template`, `STDP` (Ne rows, at least 4001+D columns), and time-ordered `firings` beginning with the sentinel `[-D, 0]`.
- Auxiliary indices: `delays_ref` (N-by-D cell array), `pre`, `aux` (at least Ne cells with matching per-cell lengths).
- Histories: `A`, `s_mean`, equal-length column vectors or empty arrays.
- Recording inputs: `Adj` (N-by-N) and positive distances `r` (N-by-1).
- Direct continuation RNG: `rng_state` or historical `rand_state` (a scalar seed or mt19937ar state vector). The batch runner resets RNG to each configured seed.

`validate_network_state.m` checks these structural requirements. This implementation supports positive delays up to 4000 quarter-steps. Units and preparation choices for the scientific input must be documented by the data archive, not inferred from field names alone.

## Index and buffer consistency

All numerical state arrays must be real and finite. Excitatory neurons are indexed `1:Ne`. Synaptic matrices use presynaptic rows and postsynaptic columns, and `s_ind`/`pre` use MATLAB column-major, one-based linear indices. `delays_ref{i,k}` lists postsynaptic target IDs addressed by presynaptic neuron `i` in delay slot `k`.

For each excitatory neuron `i`, `pre{i}` contains the linear synapse indices used by the plasticity update and `aux{i}` the corresponding STDP offsets. The simulator reads these trace values as `STDP(Ne*t + aux{i})` for quarter-step `t`. Their paired lengths must match, and all addressed indices must fit the buffers. `delays_dend` entries used for transmission must be positive integer row indices into `sI_template`.

The caches, delays, connectivity and current/trace buffers must describe the same network checkpoint. The validation routine checks shapes, ranges and selected consistency conditions; it does not reconstruct caches or prove their semantic agreement. Do not fill missing caches with zeros merely to satisfy size checks.

`t1` is an integer in `1:61`, with 61 accepted as a minute-boundary continuation value; `t2` is a positive integer minute counter. The per-second history vectors must have the same length and must be columns when nonempty. For recorded runs, `r` must be strictly positive to avoid undefined LFP divisions, and axonal delays must be nonnegative integer bins.

Scalar parameters must satisfy `0 <= lr <= 4000`, `0 <= esr <= 4` and `sm > 0`; these are implementation limits, not biological recommendations. The batches override these parameters and RNG seed according to the configuration while retaining the copied network state.

## Preflight check in MATLAB

Run from the repository root with your actual MAT path:

```matlab
input_file = 'data/net_config_G_only.mat';
whos('-file', input_file);
loaded = load(input_file, 'G');
assert(isfield(loaded, 'G'), 'Input MAT file must contain variable G.');
validate_network_state(loaded.G, true);
```

Use `false` instead of `true` only for runs without recordings. A direct simulator call also needs a valid RNG representation; check it with `restore_simulation_rng(loaded.G)`. A scalar seed must be a nonnegative integer no larger than `intmax('uint32')`; a state vector must be compatible with `mt19937ar`. If `rng_type` is present, it must identify that generator.

For optional `rand_ext`, provide an `N x K` numeric array of finite uniform samples in `[0,1)` and a positive integer `rand_ext_cursor` (default 1 for an input without a cursor). Direct continuation requires at least `4000*t_run` unconsumed columns. A fresh batch generates or removes this array according to its configuration.

A file satisfying this contract can run the simulator, but reproduction of the manuscript requires the specific study state and matching experiment configuration. The tiny fixture in `tests/make_test_state.m` is for technical regression tests only.

## Metadata required for the Zenodo archive

Before publication, supply the actual filename, byte size, SHA-256, dataset version and DOI, authors, data license, and the software release used for validation. Explain how the fixed network was prepared, the saved simulation time, parameter values and units, and which experimental inputs informed that preparation. State whether the archive contains a model state only or also experimental tissue measurements; do not conflate the two.

No dataset DOI or checksum is currently assigned here. Network generators may be added later; they are not required to use the archived fixed state.
