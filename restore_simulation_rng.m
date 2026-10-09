function stream = restore_simulation_rng(G)
% Restore an mt19937ar stream; support historical scalar/vector rand_state.
    stream = RandStream('mt19937ar', 'Seed', 0);
    if isfield(G,'rng_type') && ~strcmp(G.rng_type, 'mt19937ar')
        error('simulation:InvalidRNG', 'Only mt19937ar continuation states are supported.');
    end
    if isfield(G, 'rng_state') && ~isempty(G.rng_state)
        state = G.rng_state;
    elseif isfield(G, 'rand_state') && ~isempty(G.rand_state)
        state = G.rand_state;
    else
        error('simulation:MissingRNG', 'G.rng_state or G.rand_state is required.');
    end
    validateattributes(state, {'numeric'}, {'real','finite','nonnegative','integer','vector'});
    if any(double(state(:)) > double(intmax('uint32')))
        error('simulation:InvalidRNG', 'RNG values must fit uint32.');
    end
    if isscalar(state)
        stream = RandStream('mt19937ar', 'Seed', double(state));
    else
        if numel(state) ~= numel(stream.State)
            error('simulation:InvalidRNG', 'Invalid mt19937ar state length.');
        end
        stream.State = uint32(state(:));
    end
end
