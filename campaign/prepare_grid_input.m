function G = prepare_grid_input(G,legacy,seed)
% Adapt original grid inputs only. Never call this on a resumed checkpoint.
    assert(any(strcmp(legacy,{'','0','1'})), 'CAMPAIGN_LEGACY_INIT must be 0 or 1.');
    if strcmp(legacy,'1') && size(G.STDP,2) < 4001+G.D
        assert(G.t1==1 && G.t2==1 && isequal(size(G.STDP),[G.Ne,2001+G.D]) && ...
            nnz(G.STDP)==0 && all(G.ref_duration(1:G.Ne)==8) && ...
            all(G.ref_duration(G.Ne+1:end)==4) && ...
            isequal(double(G.firings),[-double(G.D),0]), ...
            'Short STDP buffer does not match the zero-history grid initializer.');
        G.STDP(:,4001+G.D) = 0;
        fprintf('INPUT ADAPTATION: expanded zero STDP buffer from %d to %d columns.\n',2001+G.D,4001+G.D);
    end
    fprintf('Input esr=%g; stored external drive=%d\n',G.esr,isfield(G,'rand_ext') && ~isempty(G.rand_ext));
    missing = (~isfield(G,'rng_state') || isempty(G.rng_state)) && ...
        (~isfield(G,'rand_state') || isempty(G.rand_state));
    if missing
        assert(~isempty(seed),'Input has no RNG state; specify CAMPAIGN_INITIAL_SEED explicitly.');
        value = str2double(seed);
        validateattributes(value,{'double'},{'scalar','real','finite','integer','nonnegative','<=',double(intmax('uint32'))});
        G.rand_state = value;
        fprintf('INPUT ADAPTATION: initialized mt19937ar from explicit seed %.0f.\n',value);
    end
end
