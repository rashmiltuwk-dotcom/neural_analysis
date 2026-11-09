clearvars; clc; close all;


% file paths: MasterData folder, where the results go, and the reclassification file ('' to skip)
pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));

% walking period: same rules as the epoching script
P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.speedThr = 0.2;
P.dirTol = 35; P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0; P.endTol = 45; P.plateauFrac = 0.5;
% stable-yaw stretch
P.yawBand   = 15;     % deg
P.yawSmooth = 0.5;    % s, moving mean on torso yaw (only for finding the stretch)
% stale frames at the start of a trace (tracker holding an old pose): start after the last single-frame jump
% > P.jumpThr m or > P.yawJump deg within the first P.jumpWin s
P.jumpThr = 0.05; P.yawJump = 20; P.jumpWin = 3;
% yaw variability: only intervals between two live frames no more than this far apart count
P.maxDt = 0.1;

segs = {'Torso', 'StartPosTorsoTrace', [0.12 0.31 0.61]; 'Head', 'StartPosHeadTrace', [0.70 0.09 0.17]};
positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

% ---- find each walk's stable-yaw stretch and keep its raw frames ----
W = [];
for b = 1:numel(files)
    S0 = load(fullfile(files(b).folder, files(b).name));
    MD = S0.MasterData;
    for i = 1:numel(MD)
        w = struct('Block', blocks(b), 'TrialNum', double(MD(i).TrialNum), 'Attempt', double(MD(i).Attempt), ...
            'Position', char(MD(i).Position), 'Angle', double(MD(i).StartAngleDeg));
        if ~isempty(RC)
            k = find(RC.Block == w.Block & RC.TrialNum == w.TrialNum & RC.Attempt == w.Attempt, 1, 'last');
            if ~isempty(k)
                if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude'), continue; end
                w.Position = RC.NewPosition{k}; w.Angle = RC.NewAngle(k);
            end
        end
        trT = trim_stale(get_trace(MD(i).Traces, segs{1, 2}), P);
        trH = trim_stale(get_trace(MD(i).Traces, segs{2, 2}), P);
        S = series(trT, P);
        if isempty(S), continue; end
        [ia, ic] = walk_period(S, w.Angle, P);
        if isnan(ia), continue; end
        ys = movmean(S.yu, round(P.yawSmooth * P.fs));
        [ja, jb] = band_window(ys, ia, ic, P.yawBand);
        w.t0 = S.t(ja); w.t1 = S.t(jb);
        w.F = {raw_frames(trT), raw_frames(trH)};          % raw frames: torso, head
        for s = 1:2
            w.k{s} = w.F{s}.t >= w.t0 & w.F{s}.t <= w.t1;  % frames inside the stretch
        end
        W = [W; w]; %#ok<AGROW>
    end
end
fprintf('%d navigation walks with a stable-yaw stretch\n', numel(W));

% ---- position means (dashed line): circular mean of each trial's mean raw yaw in the stretch ----
posMean = nan(2, 9);
for s = 1:2
    for p = 1:9
        tm = [];
        for r = find(strcmp({W.Position}, positions{p}))
            if nnz(W(r).k{s}) > 1, tm(end + 1) = circ_mean_deg(W(r).F{s}.y(W(r).k{s})); end %#ok<AGROW>
        end
        if ~isempty(tm), posMean(s, p) = mod(circ_mean_deg(tm), 360); end
    end
end

% ---- yaw variability per trial ----
nW = numel(W);
BT = table([W.Block]', [W.TrialNum]', [W.Attempt]', {W.Position}', [W.Angle]', [W.t1]' - [W.t0]', ...
    'VariableNames', {'Block', 'TrialNum', 'Attempt', 'Position', 'Angle', 'StableDur_s'});
for s = 1:2
    pm = nan(nW, 1); tmn = nan(nW, 1); yv = nan(nW, 1); lt = zeros(nW, 1); fz = nan(nW, 1);
    for r = 1:nW
        p = find(strcmp(positions, W(r).Position));
        pm(r) = posMean(s, p);
        k = W(r).k{s};
        if nnz(k) < 2, continue; end
        t = W(r).F{s}.t(k); y = W(r).F{s}.y(k); live = ~W(r).F{s}.rep(k);
        d = mod(y - pm(r) + 180, 360) - 180;                 % deviation from the position mean, deg
        [yv(r), lt(r)] = tw_mean_abs(t, d, live, P.maxDt);
        if any(live), tmn(r) = mod(circ_mean_deg(y(live)), 360); end
        fz(r) = mean(~live);
    end
    BT.([segs{s, 1} 'PositionMean']) = pm;
    BT.([segs{s, 1} 'TrialMean'])    = tmn;
    BT.([segs{s, 1} 'YawVar_deg'])   = yv;
    BT.([segs{s, 1} 'LiveTime_s'])   = lt;
    BT.([segs{s, 1} 'FrozenFrac'])   = fz;
end
BT = sortrows(BT, {'Position', 'Block', 'TrialNum'});

% ---- per position (angle class): every trial weighs the same ----
BA = table(positions(:), (-75 + 15 * (1:9))', 'VariableNames', {'Position', 'Angle'});
BA.n = arrayfun(@(p) nnz(strcmp(BT.Position, positions{p})), (1:9)');
for s = 1:2
    v = BT.([segs{s, 1} 'YawVar_deg']);
    BA.([segs{s, 1} 'PositionMean']) = posMean(s, :)';
    BA.(['n' segs{s, 1}]) = zeros(9, 1);
    for f = {'YawVar_mean', 'YawVar_SD', 'YawVar_median'}, BA.([segs{s, 1} f{1}]) = nan(9, 1); end
    for p = 1:9
        x = v(strcmp(BT.Position, positions{p}) & ~isnan(v));
        BA.(['n' segs{s, 1}])(p, 1) = numel(x);
        BA.([segs{s, 1} 'YawVar_mean'])(p, 1)   = mean(x);
        BA.([segs{s, 1} 'YawVar_SD'])(p, 1)     = std(x);
        BA.([segs{s, 1} 'YawVar_median'])(p, 1) = median(x);
    end
end
xlsFile = fullfile(outDir, sprintf('navigation_yaw_variability_%s.xlsx', pid));
writetable(BT, xlsFile, 'Sheet', 'by_trial', 'WriteMode', 'overwritesheet');
writetable(BA, xlsFile, 'Sheet', 'by_angleclass', 'WriteMode', 'overwritesheet');
fprintf('Saved %s (sheets: by_trial, by_angleclass)\n', xlsFile);

% ---- figures: raw yaw in the stretch, one panel per position, dashed line = position mean ----
for s = 1:2
    col = segs{s, 3};
    fig = figure('Color', 'w', 'Position', [40 40 1500 1150]);
    tl  = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for p = 1:9
        ax = nexttile(tl, p); hold(ax, 'on');
        idx = find(strcmp({W.Position}, positions{p}));
        dur = [];
        for r = idx
            k = W(r).k{s};
            if nnz(k) < 2, continue; end
            t = W(r).F{s}.t(k) - W(r).t0;
            y = W(r).F{s}.y(k); y = y - 360 * floor(mean(y) / 360);   % raw yaw, kept in 0-360
            live = ~W(r).F{s}.rep(k);
            plot(ax, t, y, '-', 'Color', [col 0.4], 'LineWidth', 0.8);
            plot(ax, t(live), y(live), '.', 'Color', col, 'MarkerSize', 5);
            dur(end + 1) = W(r).t1 - W(r).t0; %#ok<AGROW>
        end
        if ~isnan(posMean(s, p)), yline(ax, posMean(s, p), '--k', 'LineWidth', 1.6); end
        ttl = sprintf('%s (%+d%s)  n = %d', positions{p}, -75 + 15 * p, char(176), numel(idx));
        if ~isempty(dur), ttl = sprintf('%s, %.1f s', ttl, mean(dur)); end
        title(ax, ttl, 'Color', col, 'FontSize', 12, 'FontWeight', 'normal', 'HorizontalAlignment', 'left', ...
            'Units', 'normalized', 'Position', [0 1.01 0]);
        xlim(ax, [0 4.2]);
        set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 10, 'XGrid', 'on', 'YGrid', 'on', 'GridColor', [0.88 0.88 0.88]);
        if mod(p, 3) == 1, ylabel(ax, sprintf('%s yaw (%s)', segs{s, 1}, char(176))); end
        if p > 6, xlabel(ax, 'Time from start of stable stretch (s)'); else, xticklabels(ax, {}); end
    end
    exportgraphics(fig, fullfile(outDir, sprintf('navigation_stable_yaw_%s_3x3_raw_%s.png', lower(segs{s, 1}), pid)), ...
        'Resolution', 200);
end

% ---------------------------------------------------------------------------------------------------

function m = circ_mean_deg(a)
a = a(~isnan(a));
m = atan2d(mean(sind(a)), mean(cosd(a)));
end

function tr = get_trace(traces, name)
tr = [];
if isfield(traces, name), tr = traces.(name); end
end

function tr = trim_stale(tr, P)
% start the trace after the last single-frame jump (> P.jumpThr m or > P.yawJump deg) in its first P.jumpWin s
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
dyaw = abs(mod(diff(y) + 180, 360) - 180);
k = find((hypot(diff(x), diff(z)) > P.jumpThr | dyaw > P.yawJump) & (t(2:end) - t(1)) <= P.jumpWin, 1, 'last');
if isempty(k), return; end
n = numel(tr.time); f = fieldnames(tr);
for q = 1:numel(f)
    v = tr.(f{q});
    if numel(v) == n, v = v(:); tr.(f{q}) = v(k + 1:end); end
end
end

function F = raw_frames(tr)
% raw tracker frames in time order: time, unwrapped yaw (deg), and whether the frame repeats the previous one
F = struct('t', [], 'y', [], 'rep', []);
if isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); y = double(tr.yaw(:)); x = double(tr.x(:)); z = double(tr.z(:));
ok = ~isnan(t) & ~isnan(y);
t = t(ok); y = y(ok); x = x(ok); z = z(ok);
[t, o] = sort(t); y = y(o); x = x(o); z = z(o);
F.t = t;
F.y = rad2deg(unwrap(deg2rad(y)));
F.rep = [false; diff(x) == 0 & diff(z) == 0 & diff(y) == 0];
end

function S = series(tr, P)
% P.fs grid: smoothed position -> speed; yaw unwrapped
S = [];
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z) & ~isnan(y);
t = t(ok); x = x(ok); z = z(ok); y = y(ok);
[t, iu] = unique(t); x = x(iu); z = z(iu); y = y(iu);
if numel(t) < 3, return; end
tu = (t(1):1 / P.fs:t(end))';
w  = round(P.smoothWin * P.fs);
xs = movmean(interp1(t, x, tu), w); zs = movmean(interp1(t, z, tu), w);
S.t = tu; S.vx = gradient(xs, 1 / P.fs); S.vz = gradient(zs, 1 / P.fs);
S.spd = hypot(S.vx, S.vz);
S.yu  = interp1(t, rad2deg(unwrap(deg2rad(y))), tu, 'linear');
S.xEnd = x(end); S.zEnd = z(end);
end

function [ia, ic] = walk_period(S, label, P)
% epoching-script walking period on the torso trace (indices into S.t)
ia = NaN; ic = NaN; fs = P.fs;
d = atan2d(movmean(S.vx, round(P.dirWin * fs)), -movmean(S.vz, round(P.dirWin * fs)));
steady = S.spd > P.speedThr & abs(mod(d - label + 180, 360) - 180) <= P.dirTol;
steady = bridge_gaps(steady, round(P.bridge * fs));
[len, i1, i2] = longest_run(steady);
if len == 0 || (i2 - i1) / fs - 2 * P.trim < P.chunk, return; end
if abs(mod(atan2d(S.xEnd, -S.zEnd) - label + 180, 360) - 180) > P.endTol, return; end
thr = P.plateauFrac * median(S.spd(i1:i2));
a = i1; while a > 1 && S.spd(a - 1) > thr, a = a - 1; end
c = i2; while c < numel(S.spd) && S.spd(c + 1) > thr, c = c + 1; end
ia = a; ic = c;
end

function [ja, jb] = band_window(ys, ia, ic, band)
% longest stretch inside ia:ic where ys stays within band (max - min)
y = ys(ia:ic); n = numel(y); best = -1; ja = ia; jb = ia;
for i = 1:n
    lo = y(i); hi = y(i); j = i;
    while j < n && max(hi, y(j + 1)) - min(lo, y(j + 1)) <= band
        j = j + 1; lo = min(lo, y(j)); hi = max(hi, y(j));
    end
    if j - i > best, best = j - i; ja = ia + i - 1; jb = ia + j - 1; end
end
end

function [v, den] = tw_mean_abs(t, d, live, maxDt)
% time-weighted mean of |d|: trapezoid over intervals whose two frames are both live and <= maxDt apart,
% divided by the total time of those intervals (so the result does not depend on the trial's length)
a = abs(d(:)); dt = diff(t(:));
ok = live(1:end - 1) & live(2:end) & dt > 0 & dt <= maxDt;
den = sum(dt(ok));
v = NaN;
if den > 0, v = sum(0.5 * (a([ok; false]) + a([false; ok])) .* dt(ok)) / den; end
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
