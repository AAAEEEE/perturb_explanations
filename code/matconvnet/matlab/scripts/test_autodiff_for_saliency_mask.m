opts = curr_opts;
opts.img_i = 42;
opts.spatial_mask = true;
opts.lambda = 0;

type = 'single';
type_fh = @single;
net_t = convert_net_value_type(net, type_fh);

img_size = size(net_t.meta.normalization.averageImage);
img = type_fh(imdb.images.data(:,:,:,opts.batch_range(opts.img_i)));
rf_info = get_rf_info(net_t);

% get maximum feature map (similar to Fergus and Zeiler, 2014)
[~, max_feature_idx] = max(sum(sum(res(layer+1).x(:,:,:,opts.img_i),1),2));

% prepare truncated network
target_class = type_fh(imdb.images.labels(opts.batch_range(opts.img_i))) + opts.class_offset;
net_t.layers{end}.class = target_class;
% res_null = vl_simplenn(net, opts.null_img, 1);

tnet = truncate_net(net_t, layer+1, length(net_t.layers));
orig_err = -log(exp(res(end-1).x(:,:,target_class,opts.img_i))/(...
    sum(exp(res(end-1).x(:,:,:,opts.img_i)))));

actual_feats = type_fh(res(layer+1).x(:,:,:,opts.img_i));
size_feats = size(actual_feats);
% null_feats = res_null(layer+1).x;

if opts.spatial_mask
    mask = rand(size_feats(1:2),type);
    mask_t = zeros([size_feats(1:2) opts.num_iters],type);
else
    mask = rand(size_feats,type);
    mask_t = zeros([size_feats opts.num_iters],type);
end

E = zeros([3 opts.num_iters]);
E_autodiff = zeros([3 opts.num_iters]);

%x_original = Input();
out = Layer(tnet);
x_original = out.find('input',1);
label = out.find('label',1);
mask_param = Param('value', rand(size_feats(1:2),type));
x_new = x_original .* repmat(mask_param,1,1,size_feats(3));

c = out.find('pool5',1);
c.inputs{1} = x_new; % todo: confirm that it's 'input'

%res_mask = vl_simplenn(tnet, x_new);
%loss = res_mask(end).x;

Layer.workspaceNames();
net_loss = Net(out);

net_loss.setValue(x_original, actual_feats);
net_loss.setValue(label, target_class);

mask = net_loss.getValue(mask_param);

fig = figure;
for t=1:opts.num_iters,
    if opts.spatial_mask
        mask_t(:,:,t) = mask;
        % x = actual_feats .* mask + null_feats .* (1 - mask);
        x = bsxfun(@times, actual_feats, mask);
    else
        mask_t(:,:,:,t) = mask;
        x = actual_feats .* mask;
    end
    
    net_loss.eval();
    
    der = net_loss.getDer(mask_param);
    E_autodiff(1,t) = net_loss.getValue(out);
    
    if mod(t-1,10) == 0
        fprintf('epoch %d - autodiff loss: %f, der: %f\n', t, ...
            E_autodiff(1,t), mean(der(:)));
    end
    
    tres = vl_simplenn(tnet, x, 1);
    E(1,t) = tres(end).x;
    E(2,t) = opts.lambda * sum(abs(mask(:)));
    E(3,t) = E(1,t) + E(2,t);
    if opts.spatial_mask
        softmax_der = sum(tres(1).dzdx.*actual_feats,3);
        reg_der = sum(sign(mask),3);
    else
        softmax_der = tres(1).dzdx.*actual_feats;
        reg_der = sign(mask);
    end
    
    if mod(t-1,10) == 0
%         fprintf(strcat('loss at epoch %d : orig: %f, softmax: %f, reg: %f, tot: %f\n', ...
%         'derivs at epoch %d: softmax: %f, reg (unnorm): %f, reg (norm): %f\n'), ...
%         t, orig_err, E(1,t), E(2,t), E(3,t), t, mean(softmax_der(:)), ...
%         mean(reg_der(:)), opts.lambda * mean(reg_der(:)));
        fprintf('epoch %d - self-calculated loss: %f, der: %f\n', t, ...
            E(1,t), mean(softmax_der(:)));

    end

    net_loss.setValue(mask_param, net_loss.getValue(mask_param) ...
        - opts.learning_rate*net_loss.getDer(mask_param));
    mask_edit = net_loss.getValue(mask_param);
    mask_edit(mask_edit > 1) = 1;
    mask_edit(mask_edit < 0) = 0;
    net_loss.setValue(mask_param, mask_edit);
    
    mask = mask - opts.learning_rate*(softmax_der+opts.lambda*reg_der);
    mask(mask > 1) = 1;
    mask(mask < 0) = 0;
    
%         if mod(t-1,10) == 0
%             ex = rand(size(mask), 'single');
%             eta = 0.0001;
%             xp = bsxfun(@times, actual_feats, mask + eta * ex);
%             tresp = vl_simplenn(tnet, xp, 1);
%             dzdx_emp = 1 * (tresp(end).x - tres(end).x) / eta;
%             dzdx_comp = sum(sr_der(:) .* ex(:));
%             fprintf('der: emp: %f, comp: %f, error %.2f %%\n', ...
%                 dzdx_emp, dzdx_comp, abs(1 - dzdx_emp/dzdx_comp)*100);
%         end

    % plotting
    if t == 1 || t == opts.num_iters || (opts.debug && mod(t-1,opts.plot_step) == 0)
        if opts.spatial_mask
            subplot(3,4,1);
            actual_max_feat_map = res(layer+1).x(:,:,max_feature_idx,opts.img_i);
            curr_saliency_map = get_saliency_map_from_difference_map(...
                actual_max_feat_map - x(:,:,max_feature_idx), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Diff Max Feat Saliency');

            subplot(3,4,2);
            curr_saliency_map = get_saliency_map_from_difference_map(mean(res(layer+1).x(:,:,:,opts.img_i) ...
                - x,3), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Diff Avg Feats Saliency');

            subplot(3,4,3);
            curr_saliency_map = get_saliency_map_from_difference_map(mask, layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Mask Saliency');

            subplot(3,4,4);
            imagesc(mask);
            colorbar;
            axis square;
            title('mask');
            
            subplot(3,4,5);
            actual_max_feat_map = res(layer+1).x(:,:,max_feature_idx,opts.img_i);
            xx = net_loss.getValue(x_new);
            curr_saliency_map = get_saliency_map_from_difference_map(...
                actual_max_feat_map - xx(:,:,max_feature_idx), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Diff Max Feat Saliency');

            subplot(3,4,6);
            curr_saliency_map = get_saliency_map_from_difference_map(mean(res(layer+1).x(:,:,:,opts.img_i) ...
                - net_loss.getValue(x_new),3), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Diff Avg Feats Saliency');

            subplot(3,4,7);
            curr_saliency_map = get_saliency_map_from_difference_map(net_loss.getValue(mask_param), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Mask Saliency (autodiff)');

            subplot(3,4,8);
            imagesc(net_loss.getValue(mask_param));
            colorbar;
            axis square;
            title('mask (autodiff)');

            subplot(3,4,9);
            plot(transpose(E(1,1:t)));
            hold on;
            %plot(transpose(E(3,1:t)));
            plot(transpose(E_autodiff(1,1:t)));
            plot(repmat(orig_err, [1 t]));
            hold off;
            axis square;
            %legend('Softmax Loss','Tot Loss','Orig SM Loss');
            legend('Self','Autodiff','Original');
            
            subplot(3,4,10);
            imagesc(softmax_der(:,:,1));
            title('self computed der');
            colorbar;
            subplot(3,4,11);
            imagesc(der(:,:,1));
            colorbar;
            title('autodiff der');
            subplot(3,4,12);
            imagesc(softmax_der - der);
            colorbar;
            title('self - autodiff');
%             subplot(3,3,12);
%             imagesc((softmax_der(:,:,1))/(der(:,:,1)));
%             colorbar;
%             title('self/autodiff');
        
            drawnow;
        else
            subplot(3,3,1);
            actual_max_feat_map = res(layer+1).x(:,:,max_feature_idx,opts.img_i);
            curr_saliency_map = get_saliency_map_from_difference_map(...
                actual_max_feat_map - x_new(:,:,max_feature_idx), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Diff Max Feat Saliency');

            subplot(3,3,2);
            curr_saliency_map = get_saliency_map_from_difference_map(mean(res(layer+1).x(:,:,:,opts.img_i) ...
                - x_new,3), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Diff Avg Feats Saliency');

            subplot(3,3,3);
            curr_saliency_map = get_saliency_map_from_difference_map(mean(mask,3), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Mean Mask Saliency');

            subplot(3,3,4);
            curr_saliency_map = get_saliency_map_from_difference_map(mask(:,:,max_feature_idx), layer, rf_info, img_size);
            curr_saliency_map_rep = repmat(normalize(curr_saliency_map),[1 1 3]);
            imshow(normalize((img+imdb.images.data_mean).*curr_saliency_map_rep));
            title('Max Mask Saliency');
            
            subplot(3,3,5);
            imagesc(mask(:,:,max_feature_idx));
            colorbar;
            axis square;
            title('Max Mask');

            subplot(3,3,6);
            plot(transpose(E(1,1:t)));
            hold on;
            plot(transpose(E(3,1:t)));
            plot(repmat(orig_err, [1 t]));
            hold off;
            axis square;
            %legend('Softmax Loss','Tot Loss','Orig SM Loss');

            subplot(3,3,7);
            imagesc(softmax_der(:,:,1));
            title('self computed der');
            colorbar;
            subplot(3,3,8);
            imagesc(der(:,:,1));
            colorbar;
            title('autodiff der');
%             subplot(3,3,8);
%             imagesc(softmax_der - der);
%             colorbar;
%             title('self - autodiff');
            subplot(3,3,9);
            imagesc((softmax_der(:,:,1))/(der(:,:,1)));
            colorbar;
            title('self/autodiff');

            drawnow;
        end
        fprintf(strcat('loss at epoch %d : orig: %f, softmax: %f, reg: %f, tot: %f\n', ...
            'derivs at epoch %d: softmax: %f, reg (unnorm): %f, reg (norm): %f\n'), ...
            t, orig_err, E(1,t), E(2,t), E(3,t), t, mean(softmax_der(:)), ...
            mean(reg_der(:)), opts.lambda * mean(reg_der(:)));

    end
end

if ~strcmp(opts.save_fig_path, ''),
    print(fig, opts.save_fig_path, '-djpeg');
end

new_res = struct();

new_res.mask = mask_t;
new_res.error = E;
new_res.optimized_feats = x_new;

if ~strcmp(opts.save_res_path, ''),
    save(opts.save_res_path, 'new_res');
end
