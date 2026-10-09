function [nFFL,FFL_ratio,nBIF,BIF_ratio,nBIP,BIP_ratio]=motif_index(G,K)

validateattributes(K, {'numeric'}, {'scalar','real','finite','integer','nonnegative'});
threshold = 0.9 * G.sm;

S = G.s(1:G.Ne,1:G.Ne);
Adj = G.Adj(1:G.Ne,1:G.Ne) > 0;
ind = find(Adj);
A = double(Adj & S > threshold);
A(1:size(A,1)+1:end) = 0;

[nFFL,n3loop,n4loop,nBIP,nBIF]=count_motifs(A);
FFL_ratio=safe_ratio(nFFL,n3loop);
BIF_ratio=safe_ratio(nBIF,n4loop);
BIP_ratio=safe_ratio(nBIP,n4loop);

if K>0    % surrogate test Z-score
    for k=1:K
        % tprogress(k/10);
        if ~rem(k,10)
            disp(['surrogate: ',num2str(k)]);
        end
        % % full randomization preserving structural connectivity
        S(ind)=S(ind(randperm(length(ind))));
        A_rand=double(Adj & S > threshold);
        A_rand(1:size(A_rand,1)+1:end) = 0;

        % degree_preserving randomization not preserving structural connectivity
        % A_rand=randomize_digraph(A,10*nnz(A));

        [nFFL_surr(k),n3loop_surr(k),n4loop_surr(k),nBIP_surr(k),nBIF_surr(k)]=count_motifs(A_rand);

    end
    nFFL=safe_zscore(nFFL,nFFL_surr);
    FFL_ratio=safe_zscore(FFL_ratio,safe_ratio(nFFL_surr,n3loop_surr));
    nBIF=safe_zscore(nBIF,nBIF_surr);
    BIF_ratio=safe_zscore(BIF_ratio,safe_ratio(nBIF_surr,n4loop_surr));
    nBIP=safe_zscore(nBIP,nBIP_surr);
    BIP_ratio=safe_zscore(BIP_ratio,safe_ratio(nBIP_surr,n4loop_surr));

end

end

% function mult=edge_multiplicity(i,j)
% 
% [~,~,class]=unique([make_column_vector(i),make_column_vector(j)],'rows');
% h=hist(class,1:max(class));
% mult=make_column_vector(h(class));


function [nFFL,n3loop,n4loop,nBIP,nBIF]=count_motifs(A)

At=A';
A2=A*A;
A2A=A2*A;
AAt=A*At;

nFFL=trace(A2*At); % each unique
n3loop=trace(A2A); % each counted 3x
n4loop=trace(A2A*A); % 4x

%% !!! optional remove FFL agglomerates - only 'hollow' motifs
% A2(A>0)=0; 
% AAt(A>0 | At>0)=0;

AAt=AAt-diag(diag(AAt)); % remove overrlapping paths
nBIP=sum(sum(A2.*(A2-1)))./2;   % entries where A2==0 won't contribute even though ->-1; k*(k-1) = number of combinations 
nBIF=sum(sum(AAt.*(AAt-1)))./2;


end


function ratio = safe_ratio(numerator, denominator)
% Undefined denominators remain NaN, never zero or Inf.
ratio = NaN(size(numerator));
valid = denominator ~= 0 & isfinite(denominator);
ratio(valid) = numerator(valid) ./ denominator(valid);
end

function z = safe_zscore(observed, surrogate)
% Require all requested surrogates to be defined and have nonzero variance.
z = NaN;
if isfinite(observed) && all(isfinite(surrogate)) && numel(surrogate)>1
    sigma = std(surrogate);
    if sigma > 0, z = (observed-mean(surrogate))/sigma; end
end
end
