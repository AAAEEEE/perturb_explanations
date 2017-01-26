net = load('/home/ruthfong/packages/matconvnet/data/models/imagenet-caffe-alex.mat');
imdb_paths = load('/data/ruthfong/ILSVRC2012/val_imdb_paths.mat');

img_idx = [1,2,5,8,3,6,7,20,57,12,14,18,21,27,37,41,61,70,76,91];
%img_idx = [1];

opts = struct();
opts.l1_ideal = 1;

% opts.lambda = 1e-7;
% opts.tv_lambda = 1e-5;
% opts.beta = 2.5;

opts.learning_rate = 1e1;
opts.num_iters = 200;
opts.adam.beta1 = 0.999;
opts.adam.beta2 = 0.999;
opts.adam.epsilon = 1e-8;
opts.lambda = 1e-1;
opts.tv_lambda = 1e-0;
opts.beta = 2;

opts.noise.use = true;
opts.noise.mean = 0;
opts.noise.std = 1e-3;
opts.mask_params.type = 'direct';
opts.update_func = 'adam';
% opts.mask_params.type = 'superpixels';
% opts.superpixels.opts.num_superpixels = 500;

% opts.learning_rate = 1e-1;
% opts.noise.use = true;
% opts.noise.mean = 0;
% opts.noise.std = 1e-2;
% opts.tv_lambda = 0;
% opts.l1_ideal = 0;
% opts.lambda = 1e-5;
% opts.mask_params.type = 'square_occlusion';
% opts.square_occlusion.opts.size = 25;
% opts.square_occlusion.opts.aff_idx = 1:6;
% opts.square_occlusion.opts.num_transforms = 3;
% opts.plot_step = 50;
% opts.update_func = 'adam';
% opts.adam.beta1 = 0.9;


net.layers{end} = struct(...
    'type','mseloss',...
    'class',zeros([1 1 1000], 'single'));

parfor i=1:length(img_idx)
    curr_opts = opts;
    img_i = img_idx(i);
    img = cnn_normalize(net.meta.normalization, ...
        imread(imdb_paths.images.paths{img_i}), true);
    
    target_class = imdb_paths.images.labels(img_i);
    res = vl_simplenn(net, img);
    gradient = 1;
%     gradient = zeros(size(res(end).x), 'single');
% %     gradient(target_class) = -1;
%     [~,top_idx] = sort(squeeze(res(end).x), 'descend');
%     gradient(top_idx(1:5)) = 1;
    
    %curr_opts.null_img = imgaussfilt(img, 10);
    
    curr_opts.save_fig_path = fullfile(sprintf(strcat('/home/ruthfong/neural_coding/figures9/', ...
        'imagenet/L0/min_mseloss_replace_%s_no_blur/lr_%f_reg_lambda_%f_tv_norm_%f_beta_%f_num_iters_%d_noise_%d_%s/', ...
        '%d_mask_dim_2.jpg'), ...
     curr_opts.mask_params.type, curr_opts.learning_rate, curr_opts.lambda, curr_opts.tv_lambda, ...
     curr_opts.beta, curr_opts.num_iters, curr_opts.noise.use, curr_opts.update_func), num2str(img_i));
    curr_opts.save_res_path = fullfile(sprintf(strcat('/home/ruthfong/neural_coding/results9/', ...
        'imagenet/L0/min_mseloss_replace_%s_no_blur/lr_%f_reg_lambda_%f_tv_norm_%f_beta_%f_num_iters_%d_noise_%d_%s/', ...
        '%d_mask_dim_2.mat'), ...
     curr_opts.mask_params.type, curr_opts.learning_rate, curr_opts.lambda, curr_opts.tv_lambda, ...
     curr_opts.beta, curr_opts.num_iters, curr_opts.noise.use, curr_opts.update_func), num2str(img_i));
    
    mask_res = optimize_mask(net, img, gradient, curr_opts);
end