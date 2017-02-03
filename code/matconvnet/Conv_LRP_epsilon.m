classdef Conv_LRP_epsilon < dagnn.Conv
    properties
        epsilon = 100;
    end
    
    methods
%         function outputs = forward(obj, inputs, params)
%           if ~obj.hasBias, params{2} = [] ; end
%           outputs{1} = vl_nnconv(...
%             inputs{1}, params{1}, params{2}, ...
%             'pad', obj.pad, ...
%             'stride', obj.stride, ...
%             'dilate', obj.dilate, ...
%             obj.opts{:}) ;
%         end

        function [derInputs, derParams] = backward(obj, inputs, params, derOutputs)
            if ~obj.hasBias, params{2} = [] ; end

            % differentiate w.r.t. parameters as typical
            [~, derParams{1}, derParams{2}] = vl_nnconv(...
                inputs{1}, params{1}, params{2}, derOutputs{1}, ...
                'pad', obj.pad, ...
                'stride', obj.stride, ...
                'dilate', obj.dilate, ...
                obj.opts{:}) ;

            W = params{1};
            b = params{2};
            hstride = obj.stride(1);
            wstride = obj.stride(2);

            [h_in,w_in,d_in,~] = size(inputs{1});
            size_in = size(inputs{1});
            [h_out,w_out,~,~] = size(derOutputs{1});
            [hf, wf, df, nf] = size(W);

            % deal with parallel streams scenario
            if d_in ~= df
                assert(mod(d_in, df) == 0);
                W = repmat(W, [1 1 d_in/df 1]);
                [hf, wf, df, nf] = size(W);
            end

            % add padding if necessary
            has_padding = sum(obj.pad) > 0;
            if has_padding
                pad_dims = length(obj.pad);
                switch pad_dims
                    case 1
                        X = zeros([h_in + 2*obj.pad, w_in + 2*obj.pad, size_in(3:end)], 'like', inputs{1});
                        X(obj.pad+1:obj.pad+h_in,obj.pad+1:obj.pad+w_in, :) = inputs{1};
                        relevance = zeros([h_in + 2*obj.pad, w_in + 2*obj.pad, size_in(3:end)], 'like',inputs{1});
                    case 4
                        X = zeros([h_in + sum(obj.pad(1:2)), w_in + sum(obj.pad(3:4)), size_in(3:end)], 'like',inputs{1});
                        X(obj.pad(1)+1:obj.pad(1)+h_in,obj.pad(3)+1:obj.pad(3)+w_in, :) = inputs{1};
                        relevance = zeros([h_in + sum(obj.pad(1:2)), w_in + sum(obj.pad(3:4)), size_in(3:end)], ...
                            'like', inputs{1});
                    otherwise
                        assert(false);
                end

            else
                X = inputs{1};
                relevance = zeros(size(inputs{1}), 'like', inputs{1});
            end 
            next_relevance = derOutputs{1};

            for h=1:h_out
                for w=1:w_out
                    x = X((h-1)*hstride+1:(h-1)*hstride+hf,(w-1)*wstride+1:(w-1)*wstride+wf,:); % [hf, wf, df]
                    x = repmat(x, [1 1 1 nf]); % [hf, wf, d_in, nf]
                    Z = W .* x; % [hf, wf, df, nf]

                    Zs = sum(sum(sum(Z,1),2),3); % [1 1 1 nf] (convolution summing here)
                    Zs = Zs + reshape(b, size(Zs));
                    Zs = Zs + obj.epsilon*sign(Zs);
                    Zs = repmat(Zs, [hf, wf, df, 1]);

                    zz = Z ./ Zs;

                    rr = repmat(reshape(next_relevance(h,w,:), [1 1 1 nf]), [hf, wf, df, 1]); % [hf, wf, df, nf]
                    rx = relevance((h-1)*hstride+1:(h-1)*hstride+hf,(w-1)*wstride+1:(w-1)*wstride+wf,:);
                    relevance((h-1)*hstride+1:(h-1)*hstride+hf,(w-1)*wstride+1:(w-1)*wstride+wf,:) = ...
                        rx + sum(zz .* rr, 4);
                end
            end

            if has_padding
                switch pad_dims
                    case 1
                         relevance = relevance(obj.pad+1:obj.pad+h_in, obj.pad+1:obj.pad+w_in, :);
                    case 4
                         relevance = relevance(obj.pad(1)+1:obj.pad(1)+h_in, obj.pad(3)+1:obj.pad(3)+w_in, :);
                    otherwise
                        assert(false);
                end
            end
            derInputs{1} = relevance;
            try
                assert(isequal(size(derInputs{1}),size(inputs{1})));
            catch
                assert(false);
            end
        end
        
        function obj = Conv_LRP_epsilon(varargin)
            obj.load(varargin) ;
            % normalize field by implicitly calling setters defined in
            % dagnn.Filter and here
            obj.size = obj.size ;
            obj.stride = obj.stride ;
            obj.pad = obj.pad ;
        end

    end
end