clearvars; clc; close all;

pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));
navOnlyRC = [6 46 1];     % Block TrialNum Attempt: reclassification valid for navigation only
speedLim  = [0 0.8];      % m/s, jet colour scale

P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.dirTol = 35; P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0;
P.endTol = 45; P.plateauFrac = 0.5;
P.navSpeedThr = 0.2; P.pwSpeedThr = 0.1;
P.hold = 0.25;                                   % s: runs of identical frames this long = frozen tracker
P.jumpThr = 0.05; P.yawJump = 20; P.jumpWin = 3; % stale frames at the start of a trace
P.headOff = 0.41; P.headAng = 10;                % body = head - headOff m along (yaw - headAng)
encPhases  = {'EncodingRotate%sTrace', 'PausedEncodingRotate%sTrace', 'PassiveEncode%sTrace', 'Stationary%sTraceTwo'};
respPhases = {'ResponseRotation%sTrace', 'PausedResponseRotation%sTrace', 'PassiveProd%sTrace', 'Stationary%sTraceThree'};
wrap = @(a) mod(a + 180, 360) - 180;

positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
phases = {'Navigation', 'PhysicallyWalk', 'Imagined walking'};
RC = table();
if exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end
files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

D = repmat({zeros(0, 5)}, 1, 3);   % per phase: [position index, yaw, speed, x0, z0]
for b = 1:numel(files)
    S0 = load(fullfile(files(b).folder, files(b).name));
    MD = S0.MasterData;
    for i = 1:numel(MD)
        blk = blocks(b); tn = double(MD(i).TrialNum); at = double(MD(i).Attempt); T = MD(i).Traces;
        posN = char(MD(i).Position); angN = double(MD(i).StartAngleDeg); posL = posN; excl = false;
        if ~isempty(RC)
            k = find(RC.Block == blk & RC.TrialNum == tn & RC.Attempt == at, 1, 'last');
            if ~isempty(k)
                if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude')
                    excl = true;
                else
                    posN = RC.NewPosition{k}; angN = RC.NewAngle(k);
                    if ~ismember([blk tn at], navOnlyRC, 'rows'), posL = posN; end
                end
            end
        end

        % ---- navigation ----
        if ~excl
            S = series(trim_stale(get_trace(T, 'StartPosTorsoTrace'), P), P, false);
            if ~isempty(S)
                Q = P; Q.speedThr = P.navSpeedThr;
                [a, c] = walk_period(S, angN, Q, true);
                if ~isnan(a)
                    yaw = head_yaw_mean(trim_stale(get_trace(T, 'StartPosHeadTrace'), P), S.t(a), S.t(c), P);
                    D{1}(end + 1, :) = [find(strcmp(positions, posN)), yaw, mean(S.spd(a:c)), S.x(a), S.z(a)];
                end
            end
        end

        % ---- PhysicallyWalk and imagined walking (attempts that reached imagined walking) ----
        hd = get_trace(T, 'PhysicallyWalkHeadTrace');
        iw = get_trace(T, 'ImagineWalkingHeadTrace');
        if isempty(hd) || numel(hd.time) < 3 || isempty(iw) || numel(iw.time) < 2, continue; end
        p = find(strcmp(positions, posL));
        h2 = trim_stale(hd, P);
        B  = body_from_head(h2, P);
        ok = ~isnan(B.x(:)) & ~isnan(B.z(:));
        bx = B.x(ok); bz = B.z(ok);
        st = [bx(1) bz(1)]; en = [bx(end) bz(end)];
        dist = norm(en - st);                                         % distance actually walked
        durP = max(double(hd.time(:))) - min(double(hd.time(:)));    % PhysicallyWalk trace time
        durI = max(double(iw.time(:))) - min(double(iw.time(:)));    % ImagineWalking trace time
        S = series(B, P, true);                                       % frozen head runs bridged
        if ~isempty(S)
            Q = P; Q.speedThr = P.pwSpeedThr;
            [a, c] = walk_period(S, [], Q, false);                    % walk's own direction
            if ~isnan(a)
                D{2}(end + 1, :) = [p, head_yaw_mean(h2, S.t(a), S.t(c), P), dist / durP, st];
            end
        end
        % estimated head direction during imagined walking (as imagine_walk_yaw.m, frozen frames kept; mean of the raw
        % frames, which differs from that script's 50 Hz mean by < 0.3 deg)
        imagYaw = mod(circ_mean_deg(raw_yaw(iw)), 360);
        encAct  = yaw_change(T, encPhases, 'ResponseRotation%sTrace');
        respMd  = yaw_change(T, respPhases, 'ImagineWalking%sTrace');
        if strcmp(char(MD(i).TaskType), 'P'), est = imagYaw;
        else, est = mod(imagYaw + wrap(180 - encAct) - respMd, 360); end
        D{3}(end + 1, :) = [p, est, dist / durI, en];
    end
end

% ---- averages per angle ----
AV = cell(1, 3);
for ph = 1:3
    A = nan(9, 6);     % yaw, speed, n, x0, z0, angle
    for p = 1:9
        x = D{ph}(D{ph}(:, 1) == p & ~isnan(D{ph}(:, 2)), :);
        A(p, 6) = -75 + 15 * p;
        A(p, 3) = size(x, 1);
        if isempty(x), continue; end
        A(p, 1) = mod(circ_mean_deg(x(:, 2)), 360);
        A(p, 2) = mean(x(:, 3));
        A(p, 4:5) = mean(x(:, 4:5), 1);
    end
    AV{ph} = A;
    fprintf('\n%s (%d trials)\n', phases{ph}, sum(A(:, 3)));
    disp(array2table(A(:, [6 1 2 3]), 'VariableNames', {'Angle', 'MeanYaw', 'MeanSpeed', 'n'}, 'RowNames', positions));
end

% ---- figure ----
cmap = jet(256);
scr = get(0, 'ScreenSize');                                   % fit the screen, so MATLAB does not squeeze it
figW = round(0.95 * scr(3)); figH = min(round(0.40 * figW), round(0.85 * scr(4)));
fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [20 60 figW figH]);
tl  = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for ph = 1:3
    ax = nexttile(tl); hold(ax, 'on');
    A = AV{ph};
    if ph == 2, Ls = 0.45; else, Ls = 1.0; end
    for p = 1:9
        ang = A(p, 6);
        plot(ax, [0 2 * sind(ang)], [0 -2 * cosd(ang)], ':', 'Color', [0.85 0.85 0.85]);
        if isnan(A(p, 1)), continue; end
        ci  = 1 + round((min(max(A(p, 2), speedLim(1)), speedLim(2)) - speedLim(1)) / diff(speedLim) * 255);
        col = cmap(ci, :);
        u = [sind(A(p, 1)) cosd(A(p, 1))]; n = [-u(2) u(1)]; p0 = A(p, 4:5);
        plot(ax, [p0(1) p0(1) + u(1) * Ls], [p0(2) p0(2) + u(2) * Ls], '-', 'Color', col, 'LineWidth', 3);
        tri = [p0 + u * (Ls + 0.2); p0 + u * Ls + n * 0.09; p0 + u * Ls - n * 0.09];
        patch(ax, tri(:, 1), tri(:, 2), col, 'EdgeColor', 'k', 'LineWidth', 0.8);
        plot(ax, p0(1), p0(2), 'o', 'MarkerSize', 6, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 'k');
        text(ax, 2.2 * sind(ang), -2.2 * cosd(ang), sprintf('%s\n%.2f', positions{p}, A(p, 2)), ...
            'HorizontalAlignment', 'center', 'FontSize', 8);
    end
    plot(ax, 0, 0, 'k*', 'MarkerSize', 13, 'LineWidth', 1.5);
    set(ax, 'XDir', 'reverse', 'Box', 'on', 'XGrid', 'on', 'YGrid', 'on', 'GridColor', [0.92 0.92 0.92]);
    axis(ax, 'equal'); xlim(ax, [-2.4 2.4]); ylim(ax, [-2.7 0.8]);
    title(ax, sprintf('%s  (n = %d trials)', phases{ph}, sum(A(:, 3))), 'FontWeight', 'normal', 'FontSize', 13);
    xlabel(ax, 'Room X position (m)');
    if ph == 1, ylabel(ax, 'Room Z position (m)'); end
    colormap(ax, cmap); caxis(ax, speedLim);
end
cb = colorbar(ax); cb.Layout.Tile = 'east';                 % at the side, clear of the x-axis labels
% no text under the figure: the colour bar is speed in m/s (what each speed is: see the header)
exportgraphics(fig, fullfile(outDir, sprintf('average_head_direction_arrows_%s.png', pid)), 'Resolution', 200);

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

function tr = body_from_head(tr, P)
y = double(tr.yaw(:));
tr.x = double(tr.x(:)) - P.headOff * sind(y - P.headAng);
tr.z = double(tr.z(:)) - P.headOff * cosd(y - P.headAng);
end

function [t, x, z, y, frz] = frames(tr, P)
% raw frames in time order (NaNs and repeated time stamps removed); frz = frame inside a frozen run (>= P.hold s)
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z) & ~isnan(y);
[t, iu] = unique(t(ok)); x = x(ok); z = z(ok); y = y(ok); x = x(iu); z = z(iu); y = y(iu);
same = [false; diff(x) == 0 & diff(z) == 0 & diff(y) == 0];
d = diff([0; same; 0]); st = find(d == 1); en = find(d == -1) - 1;
frz = false(size(t));
for k = 1:numel(st)
    if t(en(k)) - t(st(k) - 1) >= P.hold, frz(st(k):en(k)) = true; end
end
end

function S = series(tr, P, bridgeFrozen)
% 50 Hz grid, 0.5 s moving mean on position, speed; bridgeFrozen: frames in frozen runs are dropped and position
% is interpolated across them
S = [];
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
[t, x, z, ~, frz] = frames(tr, P);
if numel(t) < 3, return; end
use = true(size(t));
if bridgeFrozen, use = ~frz; if nnz(use) < 3, use(:) = true; end, end
tu = (t(1):1 / P.fs:t(end))';
w  = round(P.smoothWin * P.fs);
S.t = tu;
xi = fillmissing(interp1(t(use), x(use), tu, 'linear'), 'nearest');   % hold the edge value past the last live frame
zi = fillmissing(interp1(t(use), z(use), tu, 'linear'), 'nearest');
S.x = movmean(xi, w);
S.z = movmean(zi, w);
S.vx = gradient(S.x, 1 / P.fs); S.vz = gradient(S.z, 1 / P.fs);
S.spd = hypot(S.vx, S.vz);
xu = x(use); zu = z(use); S.xEnd = xu(end); S.zEnd = zu(end);
end

function [ia, ic] = walk_period(S, label, P, endCheck)
% epoching rules; label = [] -> the walk's own (speed-weighted) direction and no end check
ia = NaN; ic = NaN; fs = P.fs; wd = round(P.dirWin * fs);
d = atan2d(movmean(S.vx, wd), movmean(-S.vz, wd));
if isempty(label)
    mv = S.spd > P.speedThr;
    if nnz(mv) < 2, return; end
    label = atan2d(sum(S.spd(mv) .* sind(d(mv))), sum(S.spd(mv) .* cosd(d(mv))));
    endCheck = false;
end
steady = S.spd > P.speedThr & abs(mod(d - label + 180, 360) - 180) <= P.dirTol;
steady = bridge_gaps(steady, round(P.bridge * fs));
[len, i1, i2] = longest_run(steady);
if len == 0 || (i2 - i1) / fs - 2 * P.trim < P.chunk, return; end
if endCheck && abs(mod(atan2d(S.xEnd, -S.zEnd) - label + 180, 360) - 180) > P.endTol, return; end
thr = P.plateauFrac * median(S.spd(i1:i2));
a = i1; while a > 1 && S.spd(a - 1) > thr, a = a - 1; end
c = i2; while c < numel(S.spd) && S.spd(c + 1) > thr, c = c + 1; end
ia = a; ic = c;
end

function m = head_yaw_mean(tr, tA, tB, P)
% circular mean (0-360) of the raw head yaw frames between tA and tB, frozen runs left out
m = NaN;
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
[t, ~, ~, y, frz] = frames(tr, P);
k = t >= tA & t <= tB & ~frz;
if any(k), m = mod(circ_mean_deg(y(k)), 360); end
end

function y = raw_yaw(tr)
t = double(tr.time(:)); y = double(tr.yaw(:));
k = ~isnan(t) & ~isnan(y); y = y(k);
end

function d = yaw_change(T, phases, nextPhase)
% net torso yaw change over the listed phases, up to the first frame of nextPhase (from the accuracy script)
d = NaN; y = [];
for q = 1:numel(phases), y = [y; trace_yaw(T, sprintf(phases{q}, 'Torso'))]; end %#ok<AGROW>
yn = trace_yaw(T, sprintf(nextPhase, 'Torso'));
if isempty(y) || isempty(yn), return; end
yu = rad2deg(unwrap(deg2rad([y; yn(1)])));
d  = yu(end) - yu(1);
end

function y = trace_yaw(T, name)
y = [];
if ~isfield(T, name) || isempty(T.(name)) || ~isfield(T.(name), 'yaw'), return; end
t = double(T.(name).time(:)); y = double(T.(name).yaw(:));
k = ~isnan(t) & ~isnan(y); t = t(k); y = y(k);
[~, o] = sort(t); y = y(o);
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
