% run_experiment_batch_cli
%
% CLI entry point used by submit_runSim4quart.sh.
%
% Usage from shell:
%   sbatch submit_runSim4quart.sh data/net_config_G_only.mat config_name
%
% The config_name argument is the name of a MATLAB function located in configs/.

function run_experiment_batch_cli(input_file, config_function_name)

    base_dir = fileparts(mfilename('fullpath'));
    addpath(base_dir);
    addpath(fullfile(base_dir, 'configs'));

    if nargin < 2
        error('Usage: run_experiment_batch_cli(input_file, config_function_name)');
    end

    if ~exist(input_file, 'file')
        error('Input file does not exist: %s', input_file);
    end

    fprintf('Loading input network from: %s\n', input_file);
    loaded = load(input_file, 'G');

    if ~isfield(loaded, 'G')
        error('Input MAT-file must contain variable G.');
    end

    G = loaded.G;

    fprintf('Loading config from: %s.m\n', config_function_name);

    if exist(config_function_name, 'file') ~= 2
        error('Config function not found on MATLAB path: %s', config_function_name);
    end

    config_fun = str2func(config_function_name);
    config = config_fun(G);

    fprintf('Starting batch simulations...\n');
    fprintf('Output directory: %s\n', config.output_dir);
    fprintf('t_run: %d s\n', config.t_run);
    fprintf('rec: %d\n', config.rec);

    results = run_batch_runSim4quart(G, config);

    save(fullfile(config.output_dir, 'results_workspace.mat'), ...
        'results', 'config', '-v7.3');

    fprintf('Batch finished.\n');

end
