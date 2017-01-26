function lrp_layer = create_lrp_epsilon_conv_layer(conv_layer, epsilon)    
    assert(strcmp(conv_layer.type, 'conv'));
    lrp_layer = conv_layer;
    lrp_layer.type = 'custom';
    lrp_layer.epsilon = epsilon;
    lrp_layer.forward = @lrp_epsilon_forward;
    lrp_layer.backward = @lrp_epsilon_backward;
end
    
function res_ = lrp_epsilon_forward(l, res, res_)
    res_.x = vl_nnconv(res.x, l.weights{1}, l.weights{2}, ...
        'pad', l.pad, ...
        'stride', l.stride, ...
        'dilate', l.dilate, ...
        l.opts{:});
end

function res = lrp_epsilon_backward(l, res, res_)
    W = l.weights{1};
    b = l.weights{2};
    hstride = l.stride(1);
    wstride = l.stride(2);

    [h_in,w_in,d_in,~] = size(res.x);
    size_in = size(res.x);
    [h_out,w_out,~,~] = size(res_.x);
    [hf, wf, df, nf] = size(W);
    
    % deal with parallel streams scenario
    if d_in ~= df
        assert(mod(d_in, df) == 0);
        W = repmat(W, [1 1 d_in/df 1]);
        [hf, wf, df, nf] = size(W);
    end

    % add padding if necessary
    has_padding = sum(l.pad) > 0;
    if has_padding
        pad_dims = length(l.pad);
        switch pad_dims
            case 1
                X = zeros([h_in + 2*l.pad, w_in + 2*l.pad, size_in(3:end)], 'single');
                X(l.pad+1:l.pad+h_in,l.pad+1:l.pad+w_in, :) = res.x;
                relevance = zeros([h_in + 2*l.pad, w_in + 2*l.pad, size_in(3:end)], 'single');
            case 4
                X = zeros([h_in + sum(l.pad(1:2)), w_in + sum(l.pad(1:2)), size_in(3:end)], 'single');
                X(l.pad(1)+1:l.pad(1)+h_in,l.pad(3)+1:l.pad(3)+w_in, :) = res.x;
                relevance = zeros([h_in + sum(l.pad(1:2)), w_in + sum(l.pad(1:2)), size_in(3:end)], 'single');
            otherwise
                assert(false);
        end
        
    else
        X = res.x;
        relevance = zeros(size(res.x), 'single');
    end
    next_relevance = res_.dzdx;

    for h=1:h_out
        for w=1:w_out
            x = X((h-1)*hstride+1:(h-1)*hstride+hf,(w-1)*wstride+1:(w-1)*wstride+wf,:); % [hf, wf, df]
            x = repmat(x, [1 1 1 nf]); % [hf, wf, d_in, nf]
            Z = W .* x; % [hf, wf, df, nf]

            Zs = sum(sum(sum(Z,1),2),3); % [1 1 1 nf] (convolution summing here)
            Zs = Zs + reshape(b, size(Zs));
            Zs = Zs + l.epsilon*sign(Zs);
            Zs = repmat(Zs, [hf, wf, df, 1]);

            zz = Z ./ Zs;

            rr = repmat(reshape(next_relevance(h,w,:), [1 1 1 nf]), [hf, wf, df, 1]); % [hf, wf, df, nf]
            rx = relevance((h-1)*hstride+1:(h-1)*hstride+hf,(w-1)*wstride+1:(w-1)*wstride+wf,:);
            relevance((h-1)*hstride+1:(h-1)*hstride+hf,(w-1)*wstride+1:(w-1)*wstride+wf,:) = ...
                rx + sum(zz .* rr, 4);
%             % not maintaining conservation principle when there's padding
%             if has_padding
%                 switch pad_dims
%                     case 1
%                         if (h-l.pad)
%                     case 4
%                         assert(false);
%                     otherwise
%                         assert(false);
%                 end
%             else
%                             
%             end
%             % account for padding
%             h1 = max(1, (h-1)*hstride+1);
%             h2 = min(h_in, (h-1)*hstride+hf);
%             w1 = max(1, (w-1)*wstride+1);
%             w2 = min(w_in, (w-1)*wstride+wf);
%             rx = relevance(h1:h2, w1:w2, :);
%             contribution = sum(zz .* rr, 4);
%             % not maintaining conservation principle when there's padding
%             contribution = contribution(max(1,2-((h-1)*hstride+1)):...
%                 hf - max((h-1)*hstride+hf-h_in, 0),...
%                 max(1,2-((w-1)*wstride+1)):...
%                 wf - max((w-1)*wstride+wf-w_in, 0), :);
%             relevance(h1:h2, w1:w2,:) = rx + contribution;
%             if size(contribution,1) ~= hf || size(contribution,2) ~= wf
%                 disp('here');
%             end
        end
    end
    
    if has_padding
        switch pad_dims
            case 1
                 relevance = relevance(l.pad+1:l.pad+h_in, l.pad+1:l.pad+w_in, :);
            case 4
                 relevance = relevance(l.pad(1)+1:l.pad(1)+h_in, l.pad(3)+1:l.pad(3)+w_in, :);
            otherwise
                assert(false);
        end
    end
    res.dzdx = relevance;
    try
        assert(isequal(size(res.dzdx),size(res.x)));
    catch
        assert(false);
    end
end