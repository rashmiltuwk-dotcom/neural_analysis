clearvars; clc; close all;

% file paths: MasterData folder, where the results go, and the reclassification file ('' to skip)
pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));

smoothWin = 0.5;   % s, moving-mean window on yaw
epochLen  = 10;    % s, analyse the first 10 s of each physical walk (less if the trace ends sooner)

segs = {'Head', 'PhysicallyWalkHeadTrace', [0.70 0.09 0.17]; 'Torso', 'PhysicallyWalkTorsoTrace', [0.12 0.31 0.61]};
positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

Y = []; TR = {};   % TR{n, s} = [t yaw] smoothed trace for row n, segment s
for b = 1:numel(files)
    S  = load(fullfile(files(b).folder, files(b).name));
    MD = S.MasterData;
    for i = 1:numel(MD)
        r = struct();
        r.Block    = blocks(b);
        r.TrialNum = double(MD(i).TrialNum);
        r.Attempt  = double(MD(i).Attempt);
        r.Position = char(MD(i).Position);
        r.Angle    = double(MD(i).StartAngleDeg);
        if ~isempty(RC)
            k = find(RC.Block == r.Block & RC.TrialNum == r.TrialNum & RC.Attempt == r.Attempt, 1, 'last');
            if ~isempty(k)
                if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude'), continue; end
                r.Position = RC.NewPosition{k}; r.Angle = RC.NewAngle(k);
            end
        end
        tr2 = cell(1, 2);
        for s = 1:2
            r.([segs{s, 1} 'MeanYaw'])  = NaN;
            r.([segs{s, 1} 'EpochDur']) = 0;
            if ~isfield(MD(i).Traces, segs{s, 2}), continue; end
            [t, y] = smooth_yaw(MD(i).Traces.(segs{s, 2}), smoothWin);
            if isempty(t), continue; end
            t = t - t(1);
            keep = t <= epochLen;            % first 10 s, or up to where the trace ends
            t = t(keep); y = y(keep);
            r.([segs{s, 1} 'MeanYaw'])  = mod(circ_mean_deg(y), 360);
            r.([segs{s, 1} 'EpochDur']) = t(end);
            tr2{s} = [t, y];
        end
        Y = [Y; r]; TR = [TR; tr2]; %#ok<AGROW>
    end
end
TY = struct2table(Y);
TY.Position = cellstr(TY.Position);
writetable(TY, fullfile(outDir, sprintf('physical_walk_yaw_%s.csv', pid)));

for s = 1:2
    v   = TY.([segs{s, 1} 'MeanYaw']);
    col = segs{s, 3};

    % 1) mean yaw per attempt, by position
    fprintf('\n%s yaw during the physical walk (deg, circular mean of the first %g s of the smoothed trace)\n', segs{s, 1}, epochLen);
    nShort = nnz(TY.([segs{s, 1} 'EpochDur']) < epochLen - 0.05);
    fprintf('%d of %d attempts ended before %g s and use only the data they have\n', nShort, height(TY), epochLen);
    fprintf('%-4s %5s %3s | %7s %9s\n', 'Pos', 'angle', 'n', 'mean', 'range');
    fig = figure('Color', 'w', 'Position', [100 100 900 520]);
    ax  = axes(fig); hold(ax, 'on');
    rng(1); mu = nan(1, 9);
    for p = 1:9
        x = v(strcmp(TY.Position, positions{p}) & ~isnan(v));
        if isempty(x), continue; end
        scatter(ax, p + 0.12 * (rand(numel(x), 1) - 0.5), x, 18, col, 'filled', 'MarkerFaceAlpha', 0.35, ...
            'MarkerEdgeColor', 'none');
        mu(p) = mod(circ_mean_deg(x), 360);
        fprintf('%-4s %+5d %3d | %7.1f %4.0f-%4.0f\n', positions{p}, -75 + 15 * p, numel(x), mu(p), min(x), max(x));
    end
    plot(ax, 1:9, mu, '-o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 7, 'LineWidth', 1.4);
    xticks(ax, 1:9);
    xticklabels(ax, arrayfun(@(p) sprintf('%s (%+d%s)', positions{p}, -75 + 15 * p, char(176)), 1:9, 'UniformOutput', false));
    xlim(ax, [0.4 9.6]); ylim(ax, [0 360]); yticks(ax, 0:45:360);
    ylabel(ax, sprintf('%s yaw during physical walk (%s)', segs{s, 1}, char(176)));
    set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 10, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
    exportgraphics(fig, fullfile(outDir, sprintf('physical_walk_yaw_%s_%s.png', lower(segs{s, 1}), pid)), 'Resolution', 200);

    % 2) the smoothed yaw traces themselves, one panel per position
    fig = figure('Color', 'w', 'Position', [100 100 1100 800]);
    tl  = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for p = 1:9
        ax = nexttile(tl); hold(ax, 'on');
        rows = find(strcmp(TY.Position, positions{p}));
        for n = rows'
            if isempty(TR{n, s}), continue; end
            plot(ax, TR{n, s}(:, 1), TR{n, s}(:, 2), 'Color', [col 0.4], 'LineWidth', 0.8);
        end
        title(ax, sprintf('%s (%+d%s), n = %d', positions{p}, -75 + 15 * p, char(176), numel(rows)), 'FontWeight', 'normal');
        xlim(ax, [0 epochLen]); ylim(ax, [0 360]); yticks(ax, 0:90:360);
        set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 9, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
    end
    xlabel(tl, 'Time from start of physical walk (s)');
    ylabel(tl, sprintf('%s yaw (%s)', segs{s, 1}, char(176)));
    exportgraphics(fig, fullfile(outDir, sprintf('physical_walk_yaw_traces_%s_%s.png', lower(segs{s, 1}), pid)), 'Resolution', 200);
end

function m = circ_mean_deg(a)
m = atan2d(mean(sind(a)), mean(cosd(a)));
end

function [t, y] = smooth_yaw(tr, win)
% drop NaNs and repeated timestamps, unwrap, moving mean over win seconds, wrap back to 0-360
t = []; y = [];
if isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(y);
t = t(ok); y = y(ok);
[t, iu] = unique(t); y = y(iu);
if numel(t) < 2, t = []; y = []; return; end
y = mod(movmean(rad2deg(unwrap(deg2rad(y))), win, 'SamplePoints', t), 360);
end
