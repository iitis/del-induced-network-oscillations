% run_batch_runSim4quart
%
% Batch runner for the MATLAB simulator.
%
% The runner loads an input MAT-file containing variable G, applies a config
% function, runs the requested parameter grid, and saves one result file per
% grid point.
%
% Relevant config fields include:
%   t_run                      simulation duration in biological seconds
%   rec                        dense recording flag
%   output_dir                 output directory
%   seeds                      list of random seeds
%   grid.lr, grid.esr, grid.sm parameter grid
%   use_precomputed_rand_ext   precompute external stochastic drive for deterministic replay
%
% If requested, rand_ext is generated once and saved with the run, enabling
% deterministic replay of the external stochastic drive.

function results = run_batch_runSim4quart(baseG, config)
%RUN_BATCH_RUNSIM4QUART Run a batch of runSim4quart simulations.
%
%   RESULTS = RUN_BATCH_RUNSIM4QUART(BASEG, CONFIG) executes a parameter
%   sweep for the MATLAB simulator runSim4quart.m.
%
%   Required CONFIG fields:
%       config.t_run              Requested simulation length in seconds
%
%   Optional CONFIG fields:
%       config.rec                Recording flag passed to runSim4quart
%                                 Default: 0
%       config.output_dir         Directory for per-run outputs and summary
%                                 Default: 'batch_results'
%       config.seeds              Scalar RNG seeds for independent runs
%                                 Default: 1
%       config.grid.lr            Values assigned to G.lr
%                                 Default: baseG.lr
%       config.grid.esr           Values assigned to G.esr
%                                 Default: baseG.esr
%       config.grid.sm            Values assigned to G.sm
%                                 Default: baseG.sm
%       config.save_full_G        Save final G struct for each run
%                                 Default: true
%       config.save_recordings    Save recording arrays when rec == 1
%                                 Default: config.rec
%       config.plot               Enable raster plotting; default false
%       config.verbose            Print progress information
%                                 Default: true
%       config.use_precomputed_rand_ext
%                                 If true, generate G.rand_ext so MATLAB can
%                                 reuse the same external random drive
%                                 Default: false
%
%   Output:
%       results                   Struct array with one entry per run
%
%   Files written to config.output_dir:
%       batch_summary.mat
%       batch_summary.csv         if struct2table/writetable are available
%       one MAT-file per successful run, depending on save options
%       one ERROR MAT-file per failed run
%
%   Notes:
%       - This runner assumes that baseG is a valid network struct.
%       - The input network state G must already contain auxiliary fields
%         required by runSim4quart: G.delays_ref, G.pre, and G.aux.
%       - A failed run does not abort the entire parameter sweep.

    %% --------------------------------------------------------------------
    %  Validate and complete configuration
    %  --------------------------------------------------------------------

    if nargin < 2
        error('run_batch_runSim4quart requires baseG and config.');
    end

    if ~isstruct(baseG) || ~isscalar(baseG)
        error('baseG must be a struct.');
    end

    if ~isstruct(config) || ~isscalar(config)
        error('config must be a struct.');
    end

    if ~isfield(config, 't_run') || isempty(config.t_run)
        error('config.t_run is required.');
    end

    validateattributes(config.t_run, {'numeric'}, {'scalar','real','finite','integer','positive'});

    if ~isfield(config, 'rec') || isempty(config.rec)
        config.rec = 0;
    end

    validateattributes(config.rec, {'numeric','logical'}, {'scalar','real','finite','binary'});
    config.rec = logical(config.rec);

    if ~isfield(config, 'output_dir') || isempty(config.output_dir)
        config.output_dir = 'batch_results';
    end

    if ~ischar(config.output_dir)
        error('config.output_dir must be a character vector.');
    end

    if ~isfield(config, 'seeds') || isempty(config.seeds)
        config.seeds = 1;
    end

    validateattributes(config.seeds, {'numeric'}, {'vector','real','finite','integer','nonnegative','<=',double(intmax('uint32'))});

    if ~isfield(config, 'save_full_G') || isempty(config.save_full_G)
        config.save_full_G = true;
    end
    validateattributes(config.save_full_G, {'numeric','logical'}, {'scalar','real','finite','binary'});
    config.save_full_G = logical(config.save_full_G);

    if ~isfield(config, 'save_recordings') || isempty(config.save_recordings)
        config.save_recordings = config.rec;
    end
    validateattributes(config.save_recordings, {'numeric','logical'}, {'scalar','real','finite','binary'});
    config.save_recordings = logical(config.save_recordings);

    if ~isfield(config, 'verbose') || isempty(config.verbose)
        config.verbose = true;
    end
    validateattributes(config.verbose, {'numeric','logical'}, {'scalar','real','finite','binary'});
    config.verbose = logical(config.verbose);

    if ~isfield(config, 'use_precomputed_rand_ext') || isempty(config.use_precomputed_rand_ext)
        config.use_precomputed_rand_ext = false;
    end
    validateattributes(config.use_precomputed_rand_ext, {'numeric','logical'}, {'scalar','real','finite','binary'});
    config.use_precomputed_rand_ext = logical(config.use_precomputed_rand_ext);

    if ~isfield(config,'plot') || isempty(config.plot), config.plot = false; end
    validateattributes(config.plot, {'numeric','logical'}, {'scalar','real','finite','binary'});
    if config.save_recordings && ~config.rec
        error('batch:InvalidConfig', 'save_recordings=true requires rec=true.');
    end

    if ~isfield(config, 'grid') || isempty(config.grid)
        config.grid = struct();
    end

    validateattributes(config.grid, {'struct'}, {'scalar'});

    requiredBaseFields = {'lr', 'esr', 'sm'};
    for iField = 1:numel(requiredBaseFields)
        fieldName = requiredBaseFields{iField};
        if ~isfield(baseG, fieldName)
            error('baseG.%s is required to build the default parameter grid.', fieldName);
        end
    end

    if ~isfield(config.grid, 'lr') || isempty(config.grid.lr)
        config.grid.lr = baseG.lr;
    end

    if ~isfield(config.grid, 'esr') || isempty(config.grid.esr)
        config.grid.esr = baseG.esr;
    end

    if ~isfield(config.grid, 'sm') || isempty(config.grid.sm)
        config.grid.sm = baseG.sm;
    end

    validateattributes(config.grid.lr, {'numeric'}, {'vector','real','finite','nonnegative','<=',4000});
    validateattributes(config.grid.esr, {'numeric'}, {'vector','real','finite','>=',0,'<=',4});
    validateattributes(config.grid.sm, {'numeric'}, {'vector','real','finite','positive'});
    % Validate the input once, before any dense external-drive allocation.
    validate_network_state(baseG, config.rec);

    if ~exist(config.output_dir, 'dir')
        mkdir(config.output_dir);
    end

    lr_vals = config.grid.lr(:).';
    esr_vals = config.grid.esr(:).';
    sm_vals = config.grid.sm(:).';
    seeds = config.seeds(:).';

    n_runs = numel(lr_vals) * numel(esr_vals) * numel(sm_vals) * numel(seeds);

    %% --------------------------------------------------------------------
    %  Preallocate results structure
    %  --------------------------------------------------------------------

    results = repmat(struct( ...
        'run_id', [], ...
        'seed', [], ...
        'lr', [], ...
        'esr', [], ...
        'sm', [], ...
        'finished', false, ...
        'completed_requested_duration', false, ...
        'stop_reason', '', ...
        'sim_seconds_requested', [], ...
        'sim_seconds_completed', [], ...
        'A_final', NaN, ...
        'A_mean', NaN, ...
        'A_max', NaN, ...
        's_mean_final', NaN, ...
        's_mean_mean', NaN, ...
        'runaway', false, ...
        'output_file', ''), n_runs, 1);

    run_id = 0;

    %% --------------------------------------------------------------------
    %  Execute parameter sweep
    %  --------------------------------------------------------------------

    for lr = lr_vals
        for esr = esr_vals
            for sm = sm_vals
                for seed = seeds

                    run_id = run_id + 1;

                    if config.verbose
                        fprintf('\n========================================\n');
                        fprintf('Run %d / %d\n', run_id, n_runs);
                        fprintf('lr   = %.12g\n', lr);
                        fprintf('esr  = %.12g\n', esr);
                        fprintf('sm   = %.12g\n', sm);
                        fprintf('seed = %.12g\n', seed);
                        fprintf('========================================\n');
                    end

                    % Create an independent copy of the input network.
                    G = baseG;

                    % Apply the current parameter combination.
                    G.lr = lr;
                    G.esr = esr;
                    G.sm = sm;
                    G.rand_state = seed;
                    G.rng_type = 'mt19937ar';
                    if isfield(G,'rng_state'), G = rmfield(G,'rng_state'); end
                    if isfield(G,'rand_ext_cursor'), G = rmfield(G,'rand_ext_cursor'); end

                    % Build a filesystem-safe and reasonably informative run tag.
                    run_tag = sprintf('run_%04d_lr_%g_esr_%g_sm_%g_seed_%g', ...
                        run_id, lr, esr, sm, seed);
                    run_tag = strrep(run_tag, '.', 'p');
                    run_tag = strrep(run_tag, '-', 'm');

                    % Store the run name in G if downstream code uses it.
                    G.name = run_tag;

                    % Keep track of the pre-existing length of G.A so that
                    % completed simulation time can be estimated correctly
                    % even when a network is resumed from a previous run.
                    A_length_before = 0;
                    if isfield(G, 'A') && ~isempty(G.A)
                        A_length_before = numel(G.A);
                    end

                    s_length_before = numel(G.s_mean);
                    % Run the simulator. Recording outputs are captured only when needed.
                    try
                        % Optional deterministic replay mode: precompute the exact random
                        % numbers used for externally driven stochastic spikes.
                        % runSim4quart.m consumes G.rand_ext(:,step).
                        if config.use_precomputed_rand_ext
                            rand_stream = RandStream('mt19937ar','Seed',uint32(seed));
                            G.rand_ext = rand(rand_stream, G.N, config.t_run * 4000);
                            G.rand_ext_cursor = 1;
                            if config.verbose
                                fprintf('Generated G.rand_ext: [%d x %d] (~%.3f MB)\n', ...
                                    size(G.rand_ext,1), size(G.rand_ext,2), ...
                                    numel(G.rand_ext) * 8 / 1024^2);
                            end
                        elseif isfield(G, 'rand_ext')
                            G = rmfield(G, 'rand_ext');
                        end

                        if config.rec
                            [G, A1, A1e, LFP1, LFP2, LTP, LTD, ...
                                in_degs, out_degs, dels, A1unit, ...
                                nFFL, FFL_ratio, nBIF, BIF_ratio, ...
                                nBIP, BIP_ratio] = ...
                                runSim4quart(G, config.t_run, config.rec, struct('plot',config.plot));
                        else
                            G = runSim4quart(G, config.t_run, config.rec, struct('plot',config.plot));
                        end

                        finished = true;

                    catch ME
                        finished = false;
                        warning('Run %d failed during runSim4quart: %s', run_id, ME.message);

                        error_file = fullfile(config.output_dir, [run_tag, '_ERROR.mat']);
                        save(error_file, 'ME', 'G', 'config', '-v7.3');

                        results(run_id) = fill_failed_result( ...
                            results(run_id), run_id, seed, lr, esr, sm, ...
                            config.t_run, error_file);

                        continue
                    end

                    %% ----------------------------------------------------
                    %  Compute summary metrics
                    %  ----------------------------------------------------

                    sim_seconds_completed = estimate_completed_seconds(G, A_length_before);

                    runaway = startsWith(G.simulation.stop_reason, 'runaway_');

                    results(run_id).run_id = run_id;
                    results(run_id).seed = seed;
                    results(run_id).lr = lr;
                    results(run_id).esr = esr;
                    results(run_id).sm = sm;
                    results(run_id).finished = finished;
                    results(run_id).sim_seconds_requested = config.t_run;
                    results(run_id).sim_seconds_completed = sim_seconds_completed;
                    results(run_id).runaway = runaway;
                    results(run_id).completed_requested_duration = G.simulation.completed_requested_duration;
                    results(run_id).stop_reason = G.simulation.stop_reason;

                    if isfield(G, 'A') && ~isempty(G.A)
                        results(run_id).A_final = G.A(end);
                        results(run_id).A_mean = mean(G.A(A_length_before+1:end));
                        results(run_id).A_max = max(G.A(A_length_before+1:end));
                    end

                    if isfield(G, 's_mean') && ~isempty(G.s_mean)
                        results(run_id).s_mean_final = G.s_mean(end);
                        results(run_id).s_mean_mean = mean(G.s_mean(s_length_before+1:end));
                    end

                    %% ----------------------------------------------------
                    %  Save outputs
                    %  ----------------------------------------------------

                    output_file = fullfile(config.output_dir, [run_tag, '.mat']);
                    results(run_id).output_file = output_file;
                    run_metadata = results(run_id);

                    if config.save_full_G && config.save_recordings && config.rec
                        save(output_file, ...
                            'G', 'A1', 'A1e', 'LFP1', 'LFP2', 'LTP', 'LTD', ...
                            'in_degs', 'out_degs', 'dels', 'A1unit', ...
                            'nFFL', 'FFL_ratio', 'nBIF', 'BIF_ratio', ...
                            'nBIP', 'BIP_ratio', ...
                            'config', 'run_metadata', '-v7.3');

                    elseif config.save_full_G
                        save(output_file, 'G', 'config', 'run_metadata', '-v7.3');

                    elseif config.save_recordings && config.rec
                        save(output_file, ...
                            'A1', 'A1e', 'LFP1', 'LFP2', 'LTP', 'LTD', ...
                            'in_degs', 'out_degs', 'dels', 'A1unit', ...
                            'nFFL', 'FFL_ratio', 'nBIF', 'BIF_ratio', ...
                            'nBIP', 'BIP_ratio', ...
                            'config', 'run_metadata', '-v7.3');
                    else
                        save(output_file, 'config', 'run_metadata', '-v7.3');
                    end

                    if config.verbose
                        fprintf('Completed simulation seconds: %.12g\n', sim_seconds_completed);
                        fprintf('A_final      = %.12g\n', results(run_id).A_final);
                        fprintf('A_max        = %.12g\n', results(run_id).A_max);
                        fprintf('s_mean_final = %.12g\n', results(run_id).s_mean_final);
                        fprintf('runaway      = %d\n', runaway);
                    end

                end
            end
        end
    end

    %% --------------------------------------------------------------------
    %  Save batch-level summary
    %  --------------------------------------------------------------------

    summary_file = fullfile(config.output_dir, 'batch_summary.mat');
    save(summary_file, 'results', 'config', '-v7.3');

    try
        T = struct2table(results);
        writetable(T, fullfile(config.output_dir, 'batch_summary.csv'));
    catch ME
        warning('Could not export batch_summary.csv: %s', ME.message);
    end

end

%% ========================================================================
%  Local helper functions
%  ========================================================================

function result = fill_failed_result(result, run_id, seed, lr, esr, sm, t_run, output_file)
%FILL_FAILED_RESULT Fill summary fields for a failed batch run.

    result.run_id = run_id;
    result.seed = seed;
    result.lr = lr;
    result.esr = esr;
    result.sm = sm;
    result.finished = false;
    result.completed_requested_duration = false;
    result.stop_reason = 'error';
    result.sim_seconds_requested = t_run;
    result.sim_seconds_completed = NaN;
    result.runaway = false;
    result.output_file = output_file;

end

function sim_seconds_completed = estimate_completed_seconds(G, A_length_before)
%ESTIMATE_COMPLETED_SECONDS Estimate the number of newly simulated seconds.
%
%   runSim4quart appends one activity entry per simulated second. If G.A
%   already contained values before the run, only the newly appended entries
%   should count toward the duration completed in this batch call.

    if isfield(G, 'A') && ~isempty(G.A)
        sim_seconds_completed = numel(G.A) - A_length_before;
    else
        sim_seconds_completed = NaN;
    end

end
