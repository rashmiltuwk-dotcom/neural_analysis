clearvars; clc; close all;

% file paths: MasterData folder, where the results go, and the reclassification file ('' to skip)
pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));

% same walking-period settings as the epoching script, so the thick line is the epoch window
P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.speedThr = 0.2;
P.dirTol = 35;
P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0; P.endTol = 45;
P.plateauFrac = 0.5;
P.hold    = 0.25;
P.minLive = 0.5;
P.yawBand   = 15;    % flat part: longest stretch of the walking period where torso yaw stays within this many deg
P.yawSmooth = 0.5;   % s, moving mean on torso yaw before finding the flat part

segs = {'Head', 'StartPosHeadTrace', [0.70 0.09 0.17]; 'Torso', 'StartPosTorsoTrace', [0.12 0.31 0.61]};
positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

% Y  = one row per attempt with a walking period found (goes to the CSV and the mean-yaw plot)
% W  = every attempt with both traces (goes to the yaw-over-time plot), with its walking period if found
Y = []; W = [];
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
        H = cell(1, 2); trs = cell(1, 2);
        for s = 1:2
            if isfield(MD(i).Traces, segs{s, 2}), trs{s} = MD(i).Traces.(segs{s, 2}); end
            H{s} = speed_series(trs{s}, P);
        end
        if isempty(H{1}.tu) || isempty(H{2}.tu), continue; end

        E  = walking_period(trs{2}, r.Angle, P);   % the epoching script's walking period (torso)
        ok = isempty(E.excluded); tA = E.walkStart; tB = E.walkEnd;
        w = struct('Position', r.Position, 'ws', NaN, 'we', NaN, 'fs', NaN, 'fe', NaN);
        for s = 1:2
            w.t{s}   = H{s}.tu - H{s}.tu(1);
            w.yaw{s} = H{s}.yaw;
            w.g{s}   = H{s}.gap;
        end
        if ok
            r.WalkStart = tA - H{2}.tu(1);
            r.WalkEnd   = tB - H{2}.tu(1);
            [fa, fb] = flat_window(H{2}.tu, H{2}.yaw, tA, tB, P.yawBand, round(P.yawSmooth * P.fs));
            r.FlatStart = fa - H{2}.tu(1);
            r.FlatEnd   = fb - H{2}.tu(1);
            w.ws = r.WalkStart; w.we = r.WalkEnd; w.fs = r.FlatStart; w.fe = r.FlatEnd;
            for s = 1:2
                k = w.t{s} >= r.FlatStart & w.t{s} <= r.FlatEnd & ~H{s}.gap;   % mean yaw over the flat part
                r.([segs{s, 1} 'MeanYaw']) = NaN;
                if nnz(k) >= P.minLive * P.fs
                    r.([segs{s, 1} 'MeanYaw']) = mod(circ_mean_deg(H{s}.yaw(k)), 360);
                end
            end
            Y = [Y; r]; %#ok<AGROW>
        end
        W = [W; w]; %#ok<AGROW>
    end
end
TY = struct2table(Y);
TY.Position = cellstr(TY.Position);
writetable(TY, fullfile(outDir, sprintf('setup_walk_yaw_%s.csv', pid)));

for s = 1:2
    % 1) mean yaw during the walking period, by position
    v   = TY.([segs{s, 1} 'MeanYaw']);
    col = segs{s, 3};
    fprintf('\n%s yaw during the flat part of the walk (deg, circular mean of live frames)\n', segs{s, 1});
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
    ylabel(ax, sprintf('%s yaw during flat part of walk (%s)', segs{s, 1}, char(176)));
    set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 10, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
    exportgraphics(fig, fullfile(outDir, sprintf('setup_walk_yaw_%s_%s.png', lower(segs{s, 1}), pid)), 'Resolution', 200);

    % 2) yaw over the whole set-up, with the walking period drawn thick
    fig = figure('Color', 'w', 'Position', [20 20 1600 1100]);
    tl  = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for p = 1:9
        ax = nexttile(tl, p); hold(ax, 'on');
        idx = find(strcmp({W.Position}, positions{p}));
        nW  = 0;
        for r = idx(:)'
            w = W(r);
            x = w.t{s};
            y = w.yaw{s};
            y([false; abs(diff(y)) > 180]) = NaN;
            live = y; live(w.g{s}) = NaN;
            froz = y; froz(~w.g{s}) = NaN;
            plot(ax, x, live, '-', 'Color', [col 0.35], 'LineWidth', 0.9);
            plot(ax, x, froz, ':', 'Color', [col 0.35], 'LineWidth', 0.8);
            if ~isnan(w.ws)
                nW = nW + 1;
                flat = live; flat(x < w.fs | x > w.fe) = NaN;
                plot(ax, x, flat, '-', 'Color', [col 0.95], 'LineWidth', 2.4);
                iS = find(x >= w.fs, 1); iE = find(x <= w.fe, 1, 'last');
                plot(ax, x([iS iE]), y([iS iE]), 'o', 'MarkerSize', 4, 'MarkerFaceColor', 'w', ...
                    'MarkerEdgeColor', col, 'LineWidth', 1);
            end
        end
        title(ax, sprintf('A%d (%+d%s)   n = %d, walk found in %d', p, -75 + 15 * p, char(176), numel(idx), nW), ...
            'Color', col, 'FontSize', 11, 'HorizontalAlignment', 'left', 'Units', 'normalized', ...
            'Position', [0 1.01 0]);
        xlim(ax, [0 40]); ylim(ax, [0 360]); xticks(ax, 0:10:40); yticks(ax, 0:90:360);
        set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 9, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
        if p > 6, xlabel(ax, 'Time from set-up start (s)'); else, xticklabels(ax, {}); end
        if mod(p, 3) == 1, ylabel(ax, sprintf('%s yaw (%s)', segs{s, 1}, char(176))); else, yticklabels(ax, {}); end
    end
    title(tl, sprintf(['%s yaw during set-up.  Thick = flat part (torso yaw within %g%s), used for the mean yaw ' ...
        '(circles = start/end); thin = rest of set-up; dotted = tracker frozen'], segs{s, 1}, P.yawBand, char(176)), 'FontSize', 11);
    exportgraphics(fig, fullfile(outDir, sprintf('setup_yaw_allA_%s_%s.png', lower(segs{s, 1}), pid)), 'Resolution', 200);
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

function [fa, fb] = flat_window(t, yaw, a, b, band, w)
% Longest stretch inside a-b (trace clock) where torso yaw, unwrapped and smoothed over w samples,
% stays within band deg (max - min). Returns its start and end (trace clock).
fa = NaN; fb = NaN;
idx = find(t >= a & t <= b);
if numel(idx) < 2, return; end
ys = movmean(rad2deg(unwrap(deg2rad(yaw))), w);
y = ys(idx); n = numel(y); best = -1;
for i = 1:n
    lo = y(i); hi = y(i); j = i;
    while j < n && max(hi, y(j + 1)) - min(lo, y(j + 1)) <= band
        j = j + 1; lo = min(lo, y(j)); hi = max(hi, y(j));
    end
    if j - i > best, best = j - i; fa = t(idx(i)); fb = t(idx(j)); end
end
end

% walking period: copied unchanged from the epoching script
function E = walking_period(tr, label, P)
E = struct('walkStart', NaN, 'walkEnd', NaN, 'excluded', 'no walk recording');
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z);
[t, iu] = unique(t(ok)); x = x(ok); z = z(ok); x = x(iu); z = z(iu);
if numel(t) < 2, return; end
fs = P.fs;
tu = (t(1):1/fs:t(end))';
xs = movmean(interp1(t, x, tu), round(P.smoothWin * fs));
zs = movmean(interp1(t, z, tu), round(P.smoothWin * fs));
vx = gradient(xs, 1 / fs); vz = gradient(zs, 1 / fs);
spd = hypot(vx, vz);
wd = round(P.dirWin * fs);
dirErr = mod(atan2d(movmean(vx, wd), -movmean(vz, wd)) - label + 180, 360) - 180;
steady = spd > P.speedThr & abs(dirErr) <= P.dirTol;
steady = bridge_gaps(steady, round(P.bridge * fs));
[len, i1, i2] = longest_run(steady);
if len == 0, E.excluded = 'no steady walk'; return; end
if (i2 - i1) / fs - 2 * P.trim < P.chunk
    E.excluded = 'steady walk < 1 s after trimming'; return
end
endAngle = atan2d(x(end), -z(end));
if abs(mod(endAngle - label + 180, 360) - 180) > P.endTol
    E.excluded = sprintf('ends > %g deg from start position', P.endTol); return
end
thr = P.plateauFrac * median(spd(i1:i2));
a = i1; while a > 1 && spd(a - 1) > thr, a = a - 1; end
c = i2; while c < numel(spd) && spd(c + 1) > thr, c = c + 1; end
E.walkStart = tu(a);
E.walkEnd   = tu(c);
E.excluded  = '';
end

function s = bridge_gaps(s, maxGap)
s = s(:)';
d = diff([1 s 1]);
gS = find(d == -1); gE = find(d == 1) - 1;
for k = 1:numel(gS)
    if gS(k) > 1 && gE(k) < numel(s) && (gE(k) - gS(k) + 1) < maxGap, s(gS(k):gE(k)) = true; end
end
s = s(:);
end

function [len, i1, i2] = longest_run(s)
s = s(:)';
d = diff([0 s 0]);
st = find(d == 1); en = find(d == -1) - 1;
if isempty(st), len = 0; i1 = NaN; i2 = NaN; return; end
[len, k] = max(en - st + 1);
i1 = st(k); i2 = en(k);
end
