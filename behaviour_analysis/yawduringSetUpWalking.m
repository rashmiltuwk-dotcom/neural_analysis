clearvars; clc; close all;

% file paths: MasterData folder, where the figures go, and the reclassification file ('' to skip)
pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));

P.fs   = 50;
P.hold = 0.25;

segs = {'Head', 'StartPosHeadTrace'; 'Torso', 'StartPosTorsoTrace'};
clr  = [0.267 0.005 0.329; 0.281 0.161 0.473; 0.241 0.296 0.540; 0.186 0.419 0.557; 0.142 0.526 0.556;
        0.123 0.637 0.529; 0.246 0.739 0.452; 0.497 0.826 0.306; 0.794 0.881 0.120];
titleClr = clr; titleClr(7:9, :) = repmat([0.35 0.50 0.10], 3, 1);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

W = [];
for b = 1:numel(files)
    S  = load(fullfile(files(b).folder, files(b).name));
    MD = S.MasterData;
    for i = 1:numel(MD)
        w = struct();
        w.Block    = blocks(b);
        w.TrialNum = double(MD(i).TrialNum);
        w.Attempt  = double(MD(i).Attempt);
        w.Position = char(MD(i).Position);
        if ~isempty(RC)
            k = find(RC.Block == w.Block & RC.TrialNum == w.TrialNum & RC.Attempt == w.Attempt, 1, 'last');
            if ~isempty(k)
                if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude'), continue; end
                w.Position = RC.NewPosition{k};
            end
        end
        ok = true;
        for s = 1:2
            tr = [];
            if isfield(MD(i).Traces, segs{s, 2}), tr = MD(i).Traces.(segs{s, 2}); end
            [w.t{s}, w.yaw{s}, w.g{s}] = yaw_series(tr, P);
            ok = ok && ~isempty(w.t{s});
        end
        if ok, W = [W; w]; end %#ok<AGROW>
    end
end

for s = 1:2
    fig = figure('Color', 'w', 'Position', [20 20 1600 1100]);
    tl  = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for p = 1:9
        ax = nexttile(tl, p); hold(ax, 'on');
        idx = find(strcmp({W.Position}, sprintf('A%d', p)));
        for r = idx
            w = W(r);
            x = w.t{s};
            y = w.yaw{s};
            y([false; abs(diff(y)) > 180]) = NaN;
            live = y; live(w.g{s}) = NaN;
            froz = y; froz(~w.g{s}) = NaN;
            plot(ax, x, live, '-', 'Color', [clr(p, :) 0.75], 'LineWidth', 1.1);
            plot(ax, x, froz, ':', 'Color', [clr(p, :) 0.5], 'LineWidth', 0.8);
        end
        title(ax, sprintf('A%d (%+d%s)   n = %d', p, -75 + 15 * p, char(176), numel(idx)), 'Color', titleClr(p, :), ...
            'FontSize', 11, 'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.01 0]);
        xlim(ax, [0 40]); ylim(ax, [0 360]); xticks(ax, 0:10:40); yticks(ax, 0:90:360);
        set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 9, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
        if p > 6, xlabel(ax, 'Time from set-up start (s)'); else, xticklabels(ax, {}); end
        if mod(p, 3) == 1, ylabel(ax, sprintf('%s yaw (%s)', segs{s, 1}, char(176))); else, yticklabels(ax, {}); end
    end
    exportgraphics(fig, fullfile(outDir, sprintf('setup_yaw_allA_%s_%s.png', lower(segs{s, 1}), pid)), 'Resolution', 200);
end

function [tu, yaw, gap] = yaw_series(tr, P)
tu = []; yaw = []; gap = [];
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z) & ~isnan(y);
t = t(ok); x = x(ok); z = z(ok); y = y(ok);
[t, iu] = unique(t); x = x(iu); z = z(iu); y = y(iu);
if numel(t) < 2, return; end
same = [false; diff(x) == 0 & diff(z) == 0 & diff(y) == 0];
d  = diff([0; same; 0]);
st = find(d == 1); en = find(d == -1) - 1;
tq  = (t(1):1 / P.fs:t(end))';
gap = false(size(tq));
for k = 1:numel(st)
    if t(en(k)) - t(st(k) - 1) < P.hold, continue; end
    t0 = t(st(k) - 1);
    if en(k) < numel(t), t1 = t(en(k) + 1); else, t1 = Inf; end
    gap = gap | (tq > t0 & tq < t1);
end
yaw = mod(interp1(t, rad2deg(unwrap(deg2rad(y))), tq, 'linear'), 360);
tu  = tq - tq(1);
end
