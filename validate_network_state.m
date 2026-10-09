function validate_network_state(G, rec)
% Validate the supplied continuation state without regenerating the network.
    if nargin < 2, rec = false; end
    validateattributes(G, {'struct'}, {'scalar'});
    required = {'N','Ne','D','lr','esr','sm','s','sd','STDP','I','firings', ...
        'delays_ref','pre','aux','v','u','d','a','ref','ref_duration', ...
        'delays','delays_dend','sI_Tmax','sI_template','s_ind','t1','t2','A','s_mean'};
    for k = 1:numel(required)
        assert(isfield(G, required{k}), 'simulation:MissingField', 'Missing G.%s.', required{k});
    end
    for name = {'N','Ne','D','sI_Tmax','t1','t2'}
        validateattributes(G.(name{1}), {'numeric'}, {'scalar','real','finite','integer','positive'}, '', ['G.' name{1}]);
    end
    assert(G.Ne <= G.N && G.t1 <= 61, 'simulation:InvalidState', 'Invalid Ne or t1.');
    assert(G.D <= 4000, 'simulation:InvalidState', 'This implementation requires D <= 4000 quarter-steps.');
    validateattributes(G.lr, {'numeric'}, {'scalar','real','finite','nonnegative','<=',4000});
    validateattributes(G.esr, {'numeric'}, {'scalar','real','finite','>=',0,'<=',4});
    validateattributes(G.sm, {'numeric'}, {'scalar','real','finite','positive'});
    for name = {'s','sd','delays','delays_dend'}
        value = G.(name{1});
        validateattributes(value, {'numeric'}, {'real','finite','size',[G.N G.N]}, '', ['G.' name{1}]);
    end
    for name = {'v','u','d','a','ref','ref_duration'}
        validateattributes(G.(name{1}), {'numeric'}, {'real','finite','size',[G.N 1]}, '', ['G.' name{1}]);
    end
    validateattributes(G.ref, {'numeric'}, {'nonnegative','integer'});
    validateattributes(G.ref_duration, {'numeric'}, {'nonnegative','integer'});
    validateattributes(G.I, {'numeric'}, {'real','finite','size',[G.N G.sI_Tmax]});
    validateattributes(G.STDP, {'numeric'}, {'real','finite','2d'});
    assert(size(G.STDP,1) == G.Ne, 'simulation:InvalidState', 'G.STDP requires Ne rows.');
    assert(size(G.STDP,2) >= 4001 + G.D, 'simulation:InvalidState', 'G.STDP buffer is too short.');
    validateattributes(G.firings, {'numeric'}, {'real','finite','2d','nonempty'});
    assert(size(G.firings,2) == 2, 'simulation:InvalidState', 'G.firings requires two columns.');
    assert(isequal(double(G.firings(1,:)), [-double(G.D) 0]), ...
        'simulation:InvalidState', 'G.firings must start with the [-D, 0] sentinel.');
    ids = G.firings(2:end,2);
    assert(all(ids >= 1 & ids <= G.N & ids == fix(ids)), 'simulation:InvalidState', 'Invalid firing neuron IDs.');
    assert(all(diff(G.firings(:,1)) >= 0), 'simulation:InvalidState', 'Firings must be time ordered.');
    assert(iscell(G.delays_ref) && isequal(size(G.delays_ref),[G.N G.D]), ...
        'simulation:InvalidState', 'G.delays_ref must have size [N,D].');
    assert(iscell(G.pre) && numel(G.pre) >= G.Ne && iscell(G.aux) && numel(G.aux) >= G.Ne, ...
        'simulation:InvalidState', 'G.pre and G.aux require Ne entries.');
    for k = 1:G.Ne
        assert(numel(G.pre{k}) == numel(G.aux{k}), 'simulation:InvalidState', 'pre/aux lengths differ.');
        validate_indices(G.pre{k}, numel(G.s), 'pre');
        offsets = G.aux{k};
        validateattributes(offsets, {'numeric'}, {'real','finite','integer'});
        assert(all(G.Ne + double(offsets(:)) >= 1) && ...
            all(4000*G.Ne + double(offsets(:)) <= numel(G.STDP)), ...
            'simulation:InvalidState', 'G.aux offsets address outside STDP.');
    end
    for k = 1:numel(G.delays_ref)
        validate_indices(G.delays_ref{k}, G.N, 'delays_ref');
    end
    validate_indices(G.s_ind, numel(G.s), 's_ind');
    validateattributes(G.sI_template, {'numeric'}, {'real','finite','2d'});
    assert(size(G.sI_template,2) == G.sI_Tmax, 'simulation:InvalidState', 'Invalid current-template width.');
    mask = false(G.N); mask(G.s_ind) = true;
    for k = 1:G.N
        for delay = 1:G.D
            mask(k,G.delays_ref{k,delay}) = true;
        end
    end
    dend = G.delays_dend(mask);
    assert(all(dend >= 1 & dend == fix(dend) & dend <= size(G.sI_template,1)), ...
        'simulation:InvalidState', 'Invalid dendritic-template indices.');
    for name = {'A','s_mean'}
        value = G.(name{1});
        if ~isempty(value), validateattributes(value, {'numeric'}, {'column','real','finite'}); end
    end
    assert(numel(G.A) == numel(G.s_mean), 'simulation:InvalidState', 'History lengths differ.');
    if rec
        assert(isfield(G,'r') && isfield(G,'Adj'), 'simulation:MissingField', 'Recording requires r and Adj.');
        validateattributes(G.r, {'numeric'}, {'size',[G.N 1],'real','finite','positive'});
        validateattributes(G.Adj, {'numeric','logical'}, {'size',[G.N G.N],'real','finite'});
        validateattributes(G.delays, {'numeric'}, {'nonnegative','integer'});
    end
end

function validate_indices(value, upper, name)
    validateattributes(value, {'numeric'}, {'real','finite','integer'});
    assert(all(value(:) >= 1 & value(:) <= upper), 'simulation:InvalidState', 'Invalid indices in G.%s.', name);
end
