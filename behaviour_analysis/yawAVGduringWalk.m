clearvars; clc; close all;

% file paths: MasterData folder, where the results go, and the reclassification file ('' to skip)
pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));

P.fs        = 50;
P.smoothWin = 0.5;
P.dirWin    = 1.5;
P.speedThr  = 0.2;
P.dirTol    = 30;
P.bridge    = 0.3;
P.hold      = 0.25;
P.minLive   = 0.5;

segs = {'Head', 'StartPosHeadTrace', [0.70 0.09 0.17]; 'Torso', 'StartPosTorsoTrace', [0.12 0.31 0.61]};
positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

Y = [];
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
        H = cell(1, 2);
        for s = 1:2
            tr = [];
            if isfield(MD(i).Traces, segs{s, 2}), tr = MD(i).Traces.(segs{s, 2}); end
            H{s} = speed_series(tr, P);
        end
        if isempty(H{1}.tu) || isempty(H{2}.tu), continue; end
        [ok, tA, tB] = steady_walk(H{2}, r.Angle, P);
        if ~ok, continue; end
        r.WalkStart = tA - H{2}.tu(1);
        r.WalkEnd   = tB - H{2}.tu(1);
        for s = 1:2
            t = H{s}.tu - H{s}.tu(1);
            k = t >= r.WalkStart & t <= r.WalkEnd & ~H{s}.gap;
            r.([segs{s, 1} 'MeanYaw']) = NaN;
            if nnz(k) >= P.minLive * P.fs
                r.([segs{s, 1} 'MeanYaw']) = mod(circ_mean_deg(H{s}.yaw(k)), 360);
            end
        end
        Y = [Y; r]; %#ok<AGROW>
    end
end
TY = struct2table(Y);
TY.Position = cellstr(TY.Position);
writetable(TY, fullfile(outDir, sprintf('setup_walk_yaw_%s.csv', pid)));

for s = 1:2
    v   = TY.([segs{s, 1} 'MeanYaw']);
    col = segs{s, 3};
    fprintf('\n%s yaw during the walking period (deg, circular mean of live frames)\n', segs{s, 1});
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
    xlim(ax, [0.4 9.6]); ylim(ax, [60 270]); yticks(ax, 90:30:270);
    ylabel(ax, sprintf('%s yaw during walk (%s)', segs{s, 1}, char(176)));
    set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 10, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
    exportgraphics(fig, fullfile(outDir, sprintf('setup_walk_yaw_%s_%s.png', lower(segs{s, 1}), pid)), 'Resolution', 200);
end

function m = circ_mean_deg(a)
m = atan2d(mean(sind(a)), mean(cosd(a)));
end

function H = speed_series(tr, P)
H = struct('tu', [], 'speed', [], 'vx', [], 'vz', [], 'gap', [], 'yaw', []);
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z) & ~isnan(y);
t = t(ok); x = x(ok); z = z(ok); y = y(ok);
[t, iu] = unique(t); x = x(iu); z = z(iu); y = y(iu);
if numel(t) < 2, return; end
same = [false; diff(x) == 0 & diff(z) == 0 & diff(y) == 0];
d  = diff([0; same; 0]);
st = find(d == 1); en = find(d == -1) - 1;
bad = false(size(t)); keepRun = false(size(st));
for k = 1:numel(st)
    if t(en(k)) - t(st(k) - 1) >= P.hold
        bad(st(k):en(k)) = true; keepRun(k) = true;
    end
end
st = st(keepRun); en = en(keepRun);
use = ~bad;
if nnz(use) < 2, use(:) = true; end
tu = (t(1):1 / P.fs:t(end))';
w  = round(P.smoothWin * P.fs);
xs = movmean(fillmissing(interp1(t(use), x(use), tu, 'linear'), 'nearest'), w);
zs = movmean(fillmissing(interp1(t(use), z(use), tu, 'linear'), 'nearest'), w);
vx = gradient(xs, 1 / P.fs); vz = gradient(zs, 1 / P.fs);
gap = false(size(tu));
for k = 1:numel(st)
    t0 = t(st(k) - 1);
    if en(k) < numel(t), t1 = t(en(k) + 1); else, t1 = Inf; end
    gap = gap | (tu > t0 & tu < t1);
end
H.tu = tu; H.vx = vx; H.vz = vz; H.speed = hypot(vx, vz); H.gap = gap;
H.yaw = mod(interp1(t, rad2deg(unwrap(deg2rad(y))), tu, 'linear'), 360);
end

function [ok, tA, tB] = steady_walk(T, angle, P)
ok = false; tA = NaN; tB = NaN;
wd   = round(P.dirWin * P.fs);
dirT = atan2d(movmean(T.vx, wd), -movmean(T.vz, wd));
s    = T.speed > P.speedThr & abs(mod(dirT - angle + 180, 360) - 180) <= P.dirTol;
s    = s(:)';
d = diff([1 s 1]); gS = find(d == -1); gE = find(d == 1) - 1;
for k = 1:numel(gS)
    if gS(k) > 1 && gE(k) < numel(s) && (gE(k) - gS(k) + 1) < round(P.bridge * P.fs)
        s(gS(k):gE(k)) = true;
    end
end
d = diff([0 s 0]); st = find(d == 1); en = find(d == -1) - 1;
if isempty(st), return; end
[~, k] = max(en - st + 1);
ok = true; tA = T.tu(st(k)); tB = T.tu(en(k));
end
