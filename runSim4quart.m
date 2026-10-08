% runSim4quart
%
% MATLAB implementation of the quarter-millisecond
% Izhikevich/STDP network simulator used in the accompanying simulations.
%
% The simulator continues from a saved network state G. Important continuation
% fields include G.s, G.sd, G.STDP, G.I, G.firings, G.delays_ref, G.pre,
% and G.aux.
%
% Time is discretized into 4000 bins per biological second.
%
% If rec == 1, dense per-step diagnostics are recorded:
%   A1, A1e, LFP1, LFP2, LTP, LTD.
%
% This file contains the core simulator used by the MATLAB batch pipeline.



function [G,A1,A1e,LFP1,LFP2,LTP,LTD,in_degs,out_degs,dels,A1unit,nFFL,FFL_ratio,nBIF,BIF_ratio,nBIP,BIP_ratio]=runSim4quart(G,t_run,rec,varargin)
% Inputs:
%   G      continuation state of the network
%   t_run  number of biological seconds to simulate
%   rec    if true, record dense diagnostics and per-second summaries
%
% Outputs:
%   G      updated continuation state
%   A1,A1e,LFP1,LFP2,LTP,LTD
%          dense quarter-step diagnostics, returned when rec == true
if nargin == 4
    if exist('init_rasters', 'file') ~= 2
        error('Optional raster initialization requested, but init_rasters.m is not available.');
    end
    init_rasters;
end





try
    defaultStream = RandStream('mt19937ar','Seed',uint32(G.rand_state));
    RandStream.setGlobalStream(defaultStream);
catch
    disp(['reinitializing random number generator...'])
    defaultStream = RandStream('mt19937ar','Seed','shuffle');
    RandStream.setGlobalStream(defaultStream);
end

A1=[]; A1e=[]; LFP1=[]; LFP2=[]; LTP=[]; LTD=[];
in_degs=[]; out_degs=[]; dels=[]; A1unit=[];
nFFL=[]; FFL_ratio=[]; nBIF=[]; BIF_ratio=[]; nBIP=[]; BIP_ratio=[];

if rec
    A1=zeros(t_run*4000,1); tt_A1=1;
    A1e=zeros(t_run*4000,1);
    LFP1=zeros(t_run*4000,1);
    LFP2=zeros(t_run*4000,1);
    LTP=zeros(t_run*4000,1);
    LTD=zeros(t_run*4000,1);
    in_degs=zeros(t_run,G.Ne); tt_degs=1;
    out_degs=zeros(t_run,G.Ne);
    dels=zeros(t_run,max(max(G.delays)));
    A1unit=zeros(t_run,G.N);
    nFFL=zeros(t_run,1);
    FFL_ratio=zeros(t_run,1);
    nBIF=zeros(t_run,1);
    BIF_ratio=zeros(t_run,1);
    nBIP=zeros(t_run,1);
    BIP_ratio=zeros(t_run,1);
end

% Lazy-update bookkeeping for synaptic derivatives. st stores the last
% quarter-step at which each synapse was brought up to date.
st=ones(size(G.s));
sd_table=(1-0.00025*G.lr).^[0:4000]';
stop=false; tic

% Optional deterministic replay mode: use precomputed random numbers for
% externally driven stochastic spikes. This makes repeated runs consume the
% exact same rand_ext(:,step) columns.
rand_ext_col = 1;
use_rand_ext = isfield(G,'rand_ext') && ~isempty(G.rand_ext);
if use_rand_ext
    if size(G.rand_ext,1) ~= G.N
        error('G.rand_ext must have G.N rows.');
    end
end

% The membrane equation is integrated by two half-steps per 0.25 ms bin.
% Simulations are organized into biological seconds. G.t1 stores the second
% within the current minute and G.t2 stores the minute counter.
while 1
    % ----------------------------------- simulation body  ---------------------------------
    t1=G.t1;
    for t1=t1:60
        toc; tic
        disp([G.name,sprintf('\t%1g min %1g sec',G.t2-1,G.t1-1)]);
        
	% Keep only spikes from the last G.D quarter-steps so delayed transmissions
	% can still be delivered after crossing the one-second boundary.
        ind = find(G.firings(:,1) >= (4000)+1-G.D);
        G.firings=[-G.D 0;G.firings(ind,1)-4000,G.firings(ind,2)];

        for t=1:4000
            fired = find(G.v>=30);							% internal spikes

            if use_rand_ext
                if rand_ext_col > size(G.rand_ext,2)
                    error('G.rand_ext has too few columns for this run.');
                end
                rand_vec = G.rand_ext(:,rand_ext_col);
                rand_ext_col = rand_ext_col + 1;
            else
                rand_vec = rand(G.N,1);
            end
            fired=union(fired,find(rand_vec<0.25*G.esr));
            if size(fired,2)>1
                fired=fired';
            end

            % Reset fired neurons and start their absolute refractory period.
            G.v(fired)=-65;
            G.u(fired)=G.u(fired)+G.d(fired);
            G.ref(fired)=G.ref_duration(fired);

            if rec
                A1(tt_A1)=nnz(fired);
                A1e(tt_A1)=nnz(fired(fired<=G.Ne));
                % Local spike-unit LFP contribution: cells within 150 um contribute with
		% linear distance-dependent decay.
                LFP2(tt_A1)=sum(max(0,0.15-G.r(fired)));
            end

            G.firings=[G.firings;t*ones(length(fired),1),fired];
            
            fired=fired(fired<=G.Ne);
            G.STDP(fired,t+G.D)=1;
            for k=1:length(fired)
                ind=G.pre{fired(k)};							% LTP
                % LTP for excitatory neurons that fired in the current quarter-step.
		% G.pre contains incoming PY->PY synapses affected by the presynaptic spike.
		% G.aux stores linear-index offsets used to read the relevant postsynaptic
		% STDP traces at axonal-transmission time.
                temp=G.sd(ind);
                G.sd(ind)=sd_table(t-st(ind)+1).*G.sd(ind);
                G.s(ind)=max(0,min(G.sm,G.s(ind)+temp-G.sd(ind)));      % already slowed down by modified sd table
                st(ind)=t;
                if rec
                    LTP(tt_A1)=LTP(tt_A1)+sum(min(G.sm,G.s(ind)+G.sd(ind)+sum(G.STDP(G.Ne*t+G.aux{fired(k)})))-G.s(ind)-G.sd(ind)); % corrected by asymptotic synaptic strength at the moment
                end
                G.sd(ind)=G.sd(ind)+G.STDP(G.Ne*t+G.aux{fired(k)});   % bimodal
                if rec
                    LTP(tt_A1)=LTP(tt_A1)+sum(G.STDP(G.Ne*t+G.aux{fired(k)}));
                end
            end
            
            G.I=[G.I(:,2:end),zeros(G.N,1)];   
            k=size(G.firings,1);
            while t-G.firings(k,1)<G.D

                ind=G.delays_ref{G.firings(k,2),t-G.firings(k,1)+1};
                if  ~isempty(ind)
                    ind1=ind(ind<=G.Ne);
                    if ~isempty(ind1) && G.firings(k,2)<=G.Ne							% LTD
                        
                        % Decay the synaptic derivative to the current time before applying LTD.
			% This preserves the intended lazy-update semantics: the effective weight
			% G.s is first brought up to date using the previous derivative, and the LTD
			% decrement is then applied to G.sd.
                        temp=G.sd(G.firings(k,2),ind1);
                        G.sd(G.firings(k,2),ind1)=sd_table(t-st(G.firings(k,2),ind1)+1)'.*G.sd(G.firings(k,2),ind1);
                        G.s(G.firings(k,2),ind1)=max(0,min(G.sm,G.s(G.firings(k,2),ind1)+temp-G.sd(G.firings(k,2),ind1)));
                        st(G.firings(k,2),ind1)=t;
                        if rec
                            LTD(tt_A1)=LTD(tt_A1)+sum(max(0,G.s(G.firings(k,2),ind1)+G.sd(G.firings(k,2),ind1)-1.2*G.STDP(ind1,t+G.D)')...
                                -G.s(G.firings(k,2),ind1)-G.sd(G.firings(k,2),ind1));
                        end
                        G.sd(G.firings(k,2),ind1)=G.sd(G.firings(k,2),ind1)-1.2*G.STDP(ind1,t+G.D)'; % Apply LTD decrement to the synaptic derivative.
                        if rec
                            LTD(tt_A1)=LTD(tt_A1)-1.2*sum(G.STDP(ind1,t+G.D));
                        end
                    end
                    % Add the dendritic-current template generated by the delivered spikes.
                    G.I(ind,:)=G.I(ind,:)+repmat(G.s(G.firings(k,2),ind)',1,G.sI_Tmax).*G.sI_template(G.delays_dend(G.firings(k,2),ind),:);

                end

                k=k-1;
            end

           
            ind=~G.ref;
            G.v(ind)=G.v(ind)+0.125*((0.04*G.v(ind)+5).*G.v(ind)+140-G.u(ind)+G.I(ind,1));    % Integrate membrane voltage using two half-steps within the 0.25 ms bin.
            G.v(ind)=G.v(ind)+0.125*((0.04*G.v(ind)+5).*G.v(ind)+140-G.u(ind)+G.I(ind,1));    % --
            G.v(G.v>30)=30;
            G.u(ind)=G.u(ind)+0.25.*G.a(ind).*(0.2*G.v(ind)-G.u(ind));
            G.ref=max(0,G.ref-1);

            G.STDP(:,t+G.D+1)=(0.95.^0.25)*G.STDP(:,t+G.D);
            G.t1=t1+1;

            if rec
                % Postsynaptic-current LFP contribution after synaptic delivery
                % and current-buffer advancement for this quarter-step.
                LFP1(tt_A1)=sum(G.I(1:G.Ne,1)./G.r(1:G.Ne));

                if isnan(LFP1(tt_A1))
                    error('NaN encountered in LFP1.');
                end

                tt_A1=tt_A1+1;
            end

        end   

        temp=G.sd(G.s_ind);
        G.sd(G.s_ind)=sd_table(4001-st(G.s_ind)+1).*G.sd(G.s_ind);
        G.s(G.s_ind)=max(0,min(G.sm,G.s(G.s_ind)+temp-G.sd(G.s_ind)));
        st(G.s_ind)=1;

        G.STDP(:,1:G.D+1)=G.STDP(:,4001:4001+G.D);
        %% basic plots
        if rec && ~nargout && nargin<4
            figure(5); clf; plot(G.firings(:,1)./4,G.firings(:,2),'.'); axis([0 1000 0 G.N]);
            figure(4); plot(G.s_mean);
            figure(3); plot(G.A);
            ind=max(1,tt_A1-4000):tt_A1-1;
            figure(6); plot([1:4000]/4,10^-5.*LFP1(ind)+LFP2(ind)); 
        end
        drawnow
        %% single cell raster + population histograms
        if nargin==4
            if exist('plot_rasters', 'file') ~= 2
                error('Optional raster plotting requested, but plot_rasters.m is not available.');
            end
            plot_rasters;
        end
        %% recordings
        if rec
            in_degs(tt_degs,:)=sum(G.s(1:G.Ne,1:G.Ne),1);
            out_degs(tt_degs,:)=sum(G.s(1:G.Ne,1:G.Ne),2)';
            for k=1:max(max(G.delays))
                dels(tt_degs,k)=mean(G.s(G.delays==k & G.Adj==1));
            end
            for k=1:G.N
                A1unit(tt_degs,k)=nnz(find(G.firings(:,1)>0 & G.firings(:,2)==k));
            end

            [nFFL(tt_degs),FFL_ratio(tt_degs),nBIF(tt_degs),BIF_ratio(tt_degs),nBIP(tt_degs),BIP_ratio(tt_degs)]=motif_index(G,0);
            tt_degs=tt_degs+1;
         
        else
            figure(1); plot(G.firings(:,1)./4,G.firings(:,2),'.'); xlim([0 1000]); drawnow;
        end

        G.A=[G.A;nnz(G.firings(2:end,2)<=G.Ne)/double(G.Ne)];       % activity recording in exc population
        G.s_mean=[G.s_mean;mean(G.s(G.s_ind))];             % mean exc-exc synaptic weight recording

%% sim continued
        t_run=t_run-1;
        % runaway excitation if avg >100 spikes/sec or 60s avg > 30 spikes/sec in PYR -> break
        if G.A(end)>100 || mean(G.A(end-min(60,length(G.A))+1:end))>30 || ~t_run     
            stop=true; break
        end

    end 
    
    if stop; break; end
    G.t1=1;
    G.t2=G.t2+1;
end
G.rand_state = defaultStream.State;


