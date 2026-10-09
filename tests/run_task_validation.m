function run_task_validation(input_file)
% Unit regressions plus a one-second smoke batch on the external fixed state.
    root = fileparts(fileparts(mfilename('fullpath')));
    cd(root); addpath(root); addpath(fullfile(root,'configs')); addpath(fullfile(root,'tests'));
    fprintf('MATLAB: %s\nPlatform: %s\nRepository: %s\n',version,computer,root);
    run_unit_tests;
    assert(nargin == 1 && isfile(input_file), 'validation:MissingData', 'Supply the external network MAT file.');
    fprintf('External input: %s\n',input_file);
    S = load(input_file,'G'); assert(isfield(S,'G'), 'Input must contain G.');
    validate_network_state(S.G,true);
    assert(isfield(S.G,'Adj'), 'Recording requires G.Adj.');
    config = config_publication_example(S.G);
    config.t_run = 1;
    % Test the actual input state's model parameters; do not alter scientific input.
    config.grid.lr = S.G.lr; config.grid.esr = S.G.esr; config.grid.sm = S.G.sm;
    config.output_dir = fullfile(root,'validation_results', ...
        ['task_' datestr(now,'yyyymmdd_HHMMSS')]);
    fprintf('Validation outputs: %s\n',config.output_dir);
    R = run_batch_runSim4quart(S.G,config);
    assert(numel(R) == 1 && R.finished, 'validation:SimulationFailed', 'External-state smoke run failed.');
    output = load(R.output_file);
    assert(size(output.A1,1) == 4000*R.sim_seconds_completed, 'Incorrect dense recording length.');
    assert(numel(output.G.A)-numel(S.G.A) == R.sim_seconds_completed, 'Incorrect completed duration.');
    assert(isequaln(output.run_metadata,R), 'Metadata/summary mismatch.');
    assert(all(isfinite(output.A1)) && all(isfinite(output.LFP1)) && ...
        all(isfinite(output.LFP2)), 'Nonfinite smoke recordings.');
    fprintf('External state: completed=%g/%g seconds; stop_reason=%s\n', ...
        R.sim_seconds_completed,R.sim_seconds_requested,R.stop_reason);
    fprintf('TASK VALIDATION PASSED.\n');
end
