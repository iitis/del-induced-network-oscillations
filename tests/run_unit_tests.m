function run_unit_tests()
% Short regression checks requiring no external scientific input data.
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(root); addpath(fullfile(root,'tests'));
    G = make_test_state();
    validate_network_state(G,true);
    for duration = [0, -1, 0.5, NaN, Inf]
        must_fail(@() runSim4quart(G,duration,false));
    end
    cfg = struct('t_run',1,'output_dir',tempname);
    cfg.rec = NaN; must_fail(@() run_batch_runSim4quart(G,cfg));
    cfg.rec = 0; cfg.seeds = -1; must_fail(@() run_batch_runSim4quart(G,cfg));
    cfg.seeds = 0.5; must_fail(@() run_batch_runSim4quart(G,cfg));
    cfg.seeds = 1; cfg.grid.lr = Inf; must_fail(@() run_batch_runSim4quart(G,cfg));
    bad = G; bad.rand_state = zeros(3,1); must_fail(@() restore_simulation_rng(bad));
    bad = rmfield(G,'rand_state'); must_fail(@() restore_simulation_rng(bad));
    original_rng = rng;
    G.esr = 0.001;
    [one,A1] = runSim4quart(G,1,true);
    [repeat,A2] = runSim4quart(G,1,true);
    assert(isequaln(one,repeat) && isequaln(A1,A2), 'Identical seeds did not replay.');
    assert(isequal(rng,original_rng), 'Simulator changed the caller RNG.');
    split = runSim4quart(one,1,false);
    whole = runSim4quart(G,2,false);
    compare_state(split,whole);
    % Historical vector rand_state must restore the same continuation.
    legacy = rmfield(one,'rng_state');
    legacy_cont = runSim4quart(legacy,1,false);
    compare_state(split,legacy_cont);
    % Verify continuation across a minute boundary.
    boundary = G; boundary.t1 = 60;
    b1 = runSim4quart(boundary,1,false);
    b2 = runSim4quart(b1,1,false);
    bw = runSim4quart(boundary,2,false);
    compare_state(b2,bw);
    % Precomputed drive has a persistent cursor; exhausted input must fail.
    drive = RandStream('mt19937ar','Seed',17);
    replay = G; replay.rand_ext = rand(drive,2,8000); replay.rand_ext_cursor = 1;
    r1 = runSim4quart(replay,1,false);
    r2 = runSim4quart(r1,1,false);
    rw = runSim4quart(replay,2,false);
    compare_state(r2,rw);
    assert(r2.rand_ext_cursor == 8001, 'External-drive cursor did not advance.');
    must_fail(@() runSim4quart(r2,1,false));
    % Force the existing recent-history stop condition without extreme drive.
    stopped = G; stopped.A = 100*ones(60,1); stopped.s_mean = ones(60,1);
    [stopped,recorded] = runSim4quart(stopped,2,true);
    assert(stopped.simulation.seconds_completed == 1 && ...
        ~stopped.simulation.completed_requested_duration && ...
        strcmp(stopped.simulation.stop_reason,'runaway_recent_mean'), 'Incorrect early-stop status.');
    assert(size(recorded,1) == 4000, 'Early-stop recording retains padding.');
    % Batch summaries must exclude deliberately different prior history.
    base = G; base.A = 20; base.s_mean = 10;
    output_dir = tempname; mkdir(output_dir);
    cleanup = onCleanup(@() rmdir(output_dir,'s'));
    config = struct('t_run',1,'rec',1,'plot',false,'output_dir',output_dir, ...
        'seeds',17,'verbose',false,'save_full_G',true,'save_recordings',true);
    results = run_batch_runSim4quart(base,config);
    assert(results.finished, 'Fixture batch failed.');
    S = load(results.output_file);
    assert(results.A_mean == mean(S.G.A(2:end)) && ...
        results.A_max == max(S.G.A(2:end)) && ...
        results.s_mean_mean == mean(S.G.s_mean(2:end)), 'Summary includes prior history.');
    assert(size(S.A1,1) == 4000*results.sim_seconds_completed, 'Incorrect recording length.');
    assert(isequaln(S.run_metadata,results), 'Saved run metadata differ from summary.');
    empty_motifs = G; empty_motifs.s = zeros(2); empty_motifs.Adj = false(2);
    [n,ratio,~,bif,~,bip] = motif_index(empty_motifs,0);
    assert(n == 0 && all(isnan([ratio,bif,bip])), 'Undefined motif ratios must be NaN.');
    [z] = motif_index(empty_motifs,2); assert(isnan(z), 'Zero-variance surrogate Z must be NaN.');
    fprintf('UNIT TESTS PASSED: input validation, RNG replay/continuation, clock boundary, external-drive cursor, early stop, summaries, save/load, motifs.\n');
end

function must_fail(action)
    failed = false;
    try, action(); catch, failed = true; end
    assert(failed, 'Expected invalid input to fail.');
end

function compare_state(a,b)
    fields = {'v','u','s','sd','STDP','I','firings','A','s_mean','ref', ...
        't1','t2','rng_state'};
    for k = 1:numel(fields)
        name = fields{k};
        assert(isequaln(a.(name),b.(name)), 'Continuation differs in %s.', name);
    end
    if isfield(a,'rand_ext_cursor')
        assert(a.rand_ext_cursor == b.rand_ext_cursor, 'Continuation cursor differs.');
    end
end
