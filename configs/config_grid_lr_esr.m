function config = config_grid_lr_esr(G)

    config = struct();

    config.t_run = 60;
    config.rec = 0;

    config.output_dir = 'grid_lr_esr_60s';

    config.seeds = 1:3;

    config.grid = struct();

    config.grid.lr = [
        0.5 * G.lr, ...
        1.0 * G.lr, ...
        2.0 * G.lr
    ];

    config.grid.esr = [
        0.5 * G.esr, ...
        1.0 * G.esr, ...
        2.0 * G.esr
    ];

    config.grid.sm = G.sm;

    config.save_full_G = true;
    config.save_recordings = false;
    config.verbose = true;

end