clearvars; clc; close all;


pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));
navOnlyRC = [6 46 1];       % Block TrialNum Attempt: reclassification applies to navigation only

% walking period (navigation): same rules as the epoching script
P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.speedThr = 0.2;
P.dirTol = 35; P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0; P.endTol = 45; P.plateauFrac = 0.5;
% stale frames at the start of a trace
P.jumpThr = 0.05; P.yawJump = 20; P.jumpWin = 3;
% 50 Hz samples only between live frames no more than this far apart
P.maxDt = 0.1;

phases = {'navigation', 'StartPos', 'Time from start of walking period (s)'; ...
          'physicallywalk', 'PhysicallyWalk', 'Time from start of trace (s)'; ...
          'imagine_walk', 'ImagineWalking', 'Time from start of trace (s)'};
segs = {'Torso', [0.12 0.31 0.61]; 'Head', [0.70 0.09 0.17]};
positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);
MDs = cell(numel(files), 1);
for b = 1:numel(files)
    S0 = load(fullfile(files(b).folder, files(b).name));
    MDs{b} = S0.MasterData;
end

xlsFile = fullfile(outDir, sprintf('yaw_variability_three_phases_%s.xlsx', pid));
for ph = 1:size(phases, 1)
    % ---- each trial's window and its 50 Hz yaw samples ----
    W = [];
    for b = 1:numel(files)
        MD = MDs{b};
        for i = 1:numel(MD)
            w = struct('Block', blocks(b), 'TrialNum', double(MD(i).TrialNum), 'Attempt', double(MD(i).Attempt), ...
                'Position', char(MD(i).Position), 'Angle', double(MD(i).StartAngleDeg));
            if ~isempty(RC)
                k = find(RC.Block == w.Block & RC.TrialNum == w.TrialNum & RC.Attempt == w.Attempt, 1, 'last');
                if ~isempty(k)
                    if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude'), continue; end
                    if ~(ph > 1 && ismember([w.Block w.TrialNum w.Attempt], navOnlyRC, 'rows'))
                        w.Position = RC.NewPosition{k}; w.Angle = RC.NewAngle(k);
                    end
                end
            end
            trT = trim_stale(get_trace(MD(i).Traces, [phases{ph, 2} 'TorsoTrace']), P);
            trH = trim_stale(get_trace(MD(i).Traces, [phases{ph, 2} 'HeadTrace']), P);
            if ph == 1
                S = series(trT, P);
                if isempty(S), continue; end
                [ia, ic] = walk_period(S, w.Angle, P);
                if isnan(ia), continue; end
                w.t0 = S.t(ia); w.t1 = S.t(ic);
            else
                w.t0 = min([first_time(trT), first_time(trH)]);
                w.t1 = max([last_time(trT), last_time(trH)]);
                if isnan(w.t0), continue; end
            end
            w.G = {at50(raw_frames(trT), w.t0, w.t1, P), at50(raw_frames(trH), w.t0, w.t1, P)};   % torso, head
            W = [W; w]; %#ok<AGROW>
        end
    end
    fprintf('%s: %d trials\n', phases{ph, 1}, numel(W));

    % ---- position means: circular mean of each trial's mean yaw ----
    posMean = nan(2, 9);
    for s = 1:2
        for p = 1:9
            tm = [];
            for r = find(strcmp({W.Position}, positions{p}))
                G = W(r).G{s};
                if nnz(G.val) > 1, tm(end + 1) = circ_mean_deg(G.yq(G.val)); end %#ok<AGROW>
            end
            if ~isempty(tm), posMean(s, p) = mod(circ_mean_deg(tm), 360); end
        end
    end

    % ---- by_trial ----
    nW = numel(W);
    BT = table([W.Block]', [W.TrialNum]', [W.Attempt]', {W.Position}', [W.Angle]', [W.t1]' - [W.t0]', ...
        'VariableNames', {'Block', 'TrialNum', 'Attempt', 'Position', 'Angle', 'StableDur_s'});
    for s = 1:2
        pm = nan(nW, 1); tmn = nan(nW, 1); yv = nan(nW, 1); lt = zeros(nW, 1); fz = nan(nW, 1);
        for r = 1:nW
            p = find(strcmp(positions, W(r).Position));
            pm(r) = posMean(s, p);
            G = W(r).G{s};
            fz(r) = G.frz; lt(r) = nnz(G.val) / P.fs;
            if nnz(G.val) < 2, continue; end
            y = G.yq(G.val);
            tmn(r) = mod(circ_mean_deg(y), 360);
            yv(r)  = mean(abs(mod(y - pm(r) + 180, 360) - 180));   % mean |deviation from the position mean|, deg
        end
        BT.([segs{s, 1} 'PositionMean']) = pm;
        BT.([segs{s, 1} 'TrialMean'])    = tmn;
        BT.([segs{s, 1} 'YawVar_deg'])   = yv;
        BT.([segs{s, 1} 'LiveTime_s'])   = lt;
        BT.([segs{s, 1} 'FrozenFrac'])   = fz;
    end
    BT = sortrows(BT, {'Position', 'Block', 'TrialNum'});

    % ---- by_angleclass: every trial weighs the same ----
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
            if isempty(x), continue; end
            BA.([segs{s, 1} 'YawVar_mean'])(p, 1)   = mean(x);
            BA.([segs{s, 1} 'YawVar_SD'])(p, 1)     = std(x);
            BA.([segs{s, 1} 'YawVar_median'])(p, 1) = median(x);
        end
    end
    writetable(BT, xlsFile, 'Sheet', ['by_trial_' phases{ph, 1}], 'WriteMode', 'overwritesheet');
    writetable(BA, xlsFile, 'Sheet', ['by_angleclass_' phases{ph, 1}], 'WriteMode', 'overwritesheet');

    % ---- figures: raw yaw at 50 Hz, one panel per position, dashed line = position mean ----
    xmax = ceil(max([W.t1] - [W.t0]));
    for s = 1:2
        col = segs{s, 2};
        fig = figure('Color', 'w', 'Position', [40 40 1500 1150]);
        tl  = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
        for p = 1:9
            ax = nexttile(tl, p); hold(ax, 'on');
            idx = find(strcmp({W.Position}, positions{p}));
            dur = [];
            for r = idx
                G = W(r).G{s};
                dur(end + 1) = W(r).t1 - W(r).t0; %#ok<AGROW>
                if nnz(G.val) < 2, continue; end
                y = G.yq; y(~G.val) = NaN;
                y = y - 360 * floor(mean(y, 'omitnan') / 360);           % raw yaw, kept in 0-360
                plot(ax, G.tq - W(r).t0, y, '-', 'Color', [col 0.6], 'LineWidth', 0.9);
            end
            if ~isnan(posMean(s, p)), yline(ax, posMean(s, p), '--k', 'LineWidth', 1.6); end
            ttl = sprintf('%s (%+d%s)  n = %d', positions{p}, -75 + 15 * p, char(176), numel(idx));
            if ~isempty(dur), ttl = sprintf('%s, %.1f s', ttl, mean(dur)); end
            title(ax, ttl, 'Color', col, 'FontSize', 12, 'FontWeight', 'normal', 'HorizontalAlignment', 'left', ...
                'Units', 'normalized', 'Position', [0 1.01 0]);
            xlim(ax, [0 xmax]);
            set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 10, 'XGrid', 'on', 'YGrid', 'on', 'GridColor', [0.88 0.88 0.88]);
            if mod(p, 3) == 1, ylabel(ax, sprintf('%s yaw (%s)', segs{s, 1}, char(176))); end
            if p > 6, xlabel(ax, phases{ph, 3}); else, xticklabels(ax, {}); end
        end
        exportgraphics(fig, fullfile(outDir, sprintf('%s_yaw_%s_3x3_raw_%s.png', phases{ph, 1}, lower(segs{s, 1}), pid)), ...
            'Resolution', 200);
    end
end
fprintf('Saved %s\n  sheets: by_trial_<phase>, by_angleclass_<phase> for navigation, physicallywalk, imagine_walk\n', xlsFile);

% ---------------------------------------------------------------------------------------------------

function m = circ_mean_deg(a)
a = a(~isnan(a));
m = atan2d(mean(sind(a)), mean(cosd(a)));
end

function G = at50(F, t0, t1, P)
% 50 Hz yaw samples between t0 and t1. val = the sample lies between two consecutive frames that are both live and
% <= P.maxDt apart. frz = fraction of the frames in the window that repeat the previous frame.
G = struct('tq', [], 'yq', [], 'val', false(0, 1), 'frz', NaN);
if isempty(F.t), return; end
t = F.t;
tq = (t0:1 / P.fs:t1)';
tq = tq(tq >= t(1) & tq <= t(end));
if isempty(tq), return; end
k = discretize(tq, t);                        % interval index: t(k) <= tq < t(k+1)
k(isnan(k)) = numel(t) - 1;                   % tq == t(end)
live = ~F.rep;
G.tq  = tq;
G.yq  = interp1(t, F.y, tq, 'linear');
G.val = live(k) & live(k + 1) & (t(k + 1) - t(k)) <= P.maxDt;
inw = t >= t0 & t <= t1;
if any(inw), G.frz = mean(F.rep(inw)); end
end

function tr = get_trace(traces, name)
tr = [];
if isfield(traces, name), tr = traces.(name); end
end

function t = first_time(tr)
t = NaN;
if ~isempty(tr) && isfield(tr, 'time') && ~isempty(tr.time), t = min(double(tr.time(:))); end
end

function t = last_time(tr)
t = NaN;
if ~isempty(tr) && isfield(tr, 'time') && ~isempty(tr.time), t = max(double(tr.time(:))); end
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
[t, iu] = unique(t); y = y(iu); x = x(iu); z = z(iu);
if numel(t) < 2, return; end
F.t = t;
F.y = rad2deg(unwrap(deg2rad(y)));
F.rep = [false; diff(x) == 0 & diff(z) == 0 & diff(y) == 0];
end

function S = series(tr, P)
% P.fs grid: smoothed position -> speed
S = [];
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z) & ~isnan(y);
t = t(ok); x = x(ok); z = z(ok);
[t, iu] = unique(t); x = x(iu); z = z(iu);
if numel(t) < 3, return; end
tu = (t(1):1 / P.fs:t(end))';
w  = round(P.smoothWin * P.fs);
xs = movmean(interp1(t, x, tu), w); zs = movmean(interp1(t, z, tu), w);
S.t = tu; S.vx = gradient(xs, 1 / P.fs); S.vz = gradient(zs, 1 / P.fs);
S.spd = hypot(S.vx, S.vz);
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
