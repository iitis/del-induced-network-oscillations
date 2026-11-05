function run_hourly_simulation()
% Entry point for submit_hourly_grid.sbatch; the wrapper holds the point lock.
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    root = getenv('CAMPAIGN_RUN');
    id = str2double(getenv('CAMPAIGN_ID'));
    target = str2double(getenv('CAMPAIGN_TARGET'));
    extras = str2double(getenv('CAMPAIGN_EXTRAS'));
    validateattributes(id, {'double'}, {'scalar','integer','>=',1,'<=',81});
    validateattributes(target, {'double'}, {'scalar','integer','>=',1,'<=',12});
    validateattributes(extras, {'double'}, {'scalar','binary'});
    rows = jsondecode(fileread(fullfile(root,'manifest.json')));
    row = rows(id);
    assert(row.id == id, 'Manifest row mismatch.');
    point = fullfile(root,'points',sprintf('%03d',id));
    assert(~isempty(getenv('CAMPAIGN_REVISION')), 'Use the SLURM wrapper.');
    identity = struct('input_sha256',row.sha256,'point_id',id, ...
        'revision',getenv('CAMPAIGN_REVISION'),'matlab',version,'extras',extras);
    fprintf('Point %d (%s,%s), MATLAB %s, revision %s\n',id,row.x,row.y,version,identity.revision);

    mode = getenv('CAMPAIGN_MODE');
    if strcmp(mode,'preflight') || strcmp(mode,'continuity')
        G = load_state(row.input);
        validate_network_state(G,true);
        restore_simulation_rng(G);
        check_drive(G,12*3600);
        fprintf('INPUT OK: N=%d Ne=%d t1=%d t2=%d esr=%g\n',G.N,G.Ne,G.t1,G.t2,G.esr);
        if strcmp(mode,'continuity'), continuity(G,fullfile(root,'tmp')); end
        return
    end
    assert(strcmp(mode,'run'), 'Unknown campaign mode.');
    mkdir(point);
    hours = dir(fullfile(point,'hour_*'));
    hours = hours([hours.isdir]);
    terminal = false;
    for k = 1:numel(hours)
        assert(strcmp(hours(k).name,sprintf('hour_%02d',k)) && ~terminal, ...
            'Gap or output after terminal stop.');
        folder = fullfile(point,hours(k).name);
        meta = jsondecode(fileread(fullfile(folder,'metadata.json')));
        assert(isequal(meta.identity,identity) && meta.hour == k && ...
            file_size(fullfile(folder,'checkpoint.mat')) == meta.checkpoint_bytes && ...
            file_size(fullfile(folder,'recordings.mat')) == meta.recordings_bytes, ...
            'Committed hour does not match this input, code, MATLAB version or recording configuration.');
        terminal = ~strcmp(meta.stop_reason,'completed');
        assert(terminal || meta.seconds_completed == 3600, 'Incomplete committed hour.');
    end
    if terminal || numel(hours) >= target
        fprintf('Nothing to run: %d committed segments, terminal=%d\n',numel(hours),terminal);
        return
    end
    if isempty(hours)
        G = load_state(row.input);
    else
        G = load_state(fullfile(point,hours(end).name,'checkpoint.mat'));
    end
    validate_network_state(G,true);
    restore_simulation_rng(G);
    check_drive(G,(12-numel(hours))*3600);

    for hour = numel(hours)+1:target
        clock = tic;
        [G, signals] = segment(G,3600,extras);
        assert(G.N <= double(intmax('uint16')), 'Spike counts do not fit uint16.');
        signals.A1 = uint16(signals.A1);
        signals.A1e = uint16(signals.A1e);
        if extras, signals.A1unit = uint16(signals.A1unit); end
        meta = struct('identity',identity,'input_sha256',row.sha256,'hour',hour, ...
            'seconds_completed',G.simulation.seconds_completed, ...
            'stop_reason',G.simulation.stop_reason,'simulation_wall_seconds',toc(clock));
        % Hidden staging directory on the same filesystem. Only its final rename
        % publishes the pair; a killed task can leave an ignored .partial-* dir.
        stage = fullfile(point,['.partial-' char(java.util.UUID.randomUUID())]);
        mkdir(stage);
        save(fullfile(stage,'recordings.mat'),'-struct','signals','-v7.3');
        clear signals
        save(fullfile(stage,'checkpoint.mat'),'G','-v7.3');
        meta.recordings_bytes = file_size(fullfile(stage,'recordings.mat'));
        meta.checkpoint_bytes = file_size(fullfile(stage,'checkpoint.mat'));
        write_json(fullfile(stage,'metadata.json'),meta);
        destination = fullfile(point,sprintf('hour_%02d',hour));
        assert(~isfolder(destination), 'Refusing to replace a committed hour.');
        [ok,msg] = movefile(stage,destination);
        assert(ok,'Could not publish hour: %s',msg);
        fprintf('COMMITTED hour=%d seconds=%d stop=%s wall_s=%.3f recordings_bytes=%d checkpoint_bytes=%d\n', ...
            hour,meta.seconds_completed,meta.stop_reason,toc(clock),meta.recordings_bytes,meta.checkpoint_bytes);
        if ~strcmp(meta.stop_reason,'completed'), return; end
    end
end

function G = load_state(path)
    data = load(path,'G');
    assert(isfield(data,'G'),'Missing G in %s',path);
    G = data.G;
end

function check_drive(G,seconds)
    if isfield(G,'rand_ext') && ~isempty(G.rand_ext)
        cursor = 1;
        if isfield(G,'rand_ext_cursor'), cursor = G.rand_ext_cursor; end
        validateattributes(cursor,{'numeric'},{'scalar','integer','positive'});
        assert(size(G.rand_ext,1)==G.N && size(G.rand_ext,2)-cursor+1>=4000*seconds, ...
            'Stored rand_ext does not cover the campaign. Do not change drive mode silently.');
        fprintf('Drive: stored rand_ext, cursor=%d, bytes=%g\n',cursor,numel(G.rand_ext)*8);
    else
        fprintf('Drive: live mt19937ar restored from G; no seed reset.\n');
    end
end

function [G,out] = segment(G,seconds,extras)
    if extras
        [G,A1,A1e,LFP1,LFP2,LTP,LTD,~,~,~,A1unit] = runSim4quart(G,seconds,true);
        out = struct('A1',A1,'A1e',A1e,'LFP1',LFP1,'LFP2',LFP2, ...
            'LTP',LTP,'LTD',LTD,'A1unit',A1unit);
    else
        [G,A1,A1e,LFP1,LFP2] = runSim4quart(G,seconds,true);
        out = struct('A1',A1,'A1e',A1e,'LFP1',LFP1,'LFP2',LFP2);
    end
end

function continuity(G,tmp)
    [whole,reference] = segment(G,2,true);
    [first,a] = segment(G,1,true);
    file = [tempname(tmp) '.mat'];
    cleanup = onCleanup(@() delete_if_present(file));
    G = first;
    save(file,'G','-v7.3');
    [split,b] = segment(load_state(file),1,true);
    assert(whole.simulation.seconds_completed==2 && split.simulation.seconds_completed==1 && ...
        strcmp(whole.simulation.stop_reason,'completed') && strcmp(split.simulation.stop_reason,'completed'), ...
        'Continuity input stopped early.');
    assert(isequaln(rmfield(whole,'simulation'),rmfield(split,'simulation')), 'Final states differ.');
    for field = fieldnames(reference)'
        name = field{1};
        assert(isequaln(reference.(name),[a.(name); b.(name)]),'Recording differs: %s',name);
    end
    fprintf('CONTINUITY PASSED: serialized checkpoint, final G and all requested signals.\n');
end

function delete_if_present(file)
    if isfile(file), delete(file); end
end

function bytes = file_size(file)
    entry = dir(file);
    bytes = entry.bytes;
end

function write_json(file,value)
    fid = fopen(file,'w');
    assert(fid>=0,'Cannot open metadata file.');
    written = fprintf(fid,'%s\n',jsonencode(value));
    status = fclose(fid);
    assert(written>0 && status==0,'Could not write metadata.');
end
