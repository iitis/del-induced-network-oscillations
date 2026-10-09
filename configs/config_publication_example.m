function config = config_publication_example(G)
%CONFIG_PUBLICATION_EXAMPLE Minimal example configuration for the MATLAB simulator.
%
% This configuration is intentionally short. It is intended to verify that
% the supplied continuation state G, batch runner, simulator, recordings,
% deterministic external drive, and motif diagnostics work together.
%
% Longer production simulations can be created by copying this file and
% increasing config.t_run.

    %#ok<INUSD>

    config.t_run = 2;
    config.plot = false;
    config.rec = 1;

    config.output_dir = 'results_publication/example_2s';

    config.seeds = 1;

    config.grid.lr = 0.1;
    config.grid.esr = 0.001;
    config.grid.sm = 10;

    config.save_full_G = true;
    config.save_recordings = true;
    config.verbose = true;

    config.use_precomputed_rand_ext = true;
end
