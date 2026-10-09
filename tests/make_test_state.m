function G = make_test_state()
% Tiny technical fixture, not a scientific network initialization generator.
    G = struct('N',2,'Ne',2,'D',1,'lr',0.1,'esr',0,'sm',1, ...
        't1',1,'t2',1,'name','test_fixture','rand_state',17,'sI_Tmax',1);
    G.s = [0 0.5; 0 0]; G.sd = zeros(2);
    G.Adj = logical(G.s); G.delays = double(G.Adj);
    G.delays_dend = double(G.Adj);
    G.delays_ref = {2; []};
    G.s_ind = find(G.Adj);
    G.pre = {[]; 3}; G.aux = {[]; 1};
    G.STDP = zeros(2,4002); G.I = zeros(2,1); G.sI_template = 1;
    G.v = [-65;-65]; G.u = 0.2*G.v;
    G.a = [0.02;0.02]; G.d = [8;8];
    G.ref = zeros(2,1); G.ref_duration = ones(2,1);
    G.firings = [-1 0]; G.A = []; G.s_mean = []; G.r = [0.1;0.2];
end
