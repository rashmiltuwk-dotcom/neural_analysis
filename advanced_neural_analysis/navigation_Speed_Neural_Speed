clearvars; clc; close all;

% ======================= settings =======================
minSpeed = 0.6;    % m/s: an interval must AVERAGE at least this speed
minDur   = 0.5;    % s:   and last at least this long
% ========================================================

% file paths: change these to run on another computer or participant
pid     = 'p001';
behDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
megDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\preprocessed';
megFile = 'prep_p001_block%02d.mat';
outDir  = fullfile(behDir, '..', 'results', 'p001');
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));
cfg = config();   % config.m must be on the MATLAB path

% walking period: same rules as the epoching script
P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.speedThr = 0.2;
P.dirTol = 35; P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0; P.endTol = 45; P.plateauFrac = 0.5;

positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end
RC = table();
if exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(behDir, cfg.master_data_pattern));
namePattern = '^[Pp](?:articipant)?[_\- ]?(\d+)[_\- ](\d+)(?:[_\- ]|$)';
tok    = arrayfun(@(d) regexp(d.name, namePattern, 'tokens', 'once'), files, 'UniformOutput', false);
files  = files(~cellfun(@isempty, tok));  tok = tok(~cellfun(@isempty, tok));
blocks = cellfun(@(t) str2double(t{2}), tok);
[blocks, ord] = sort(blocks);
files  = files(ord);

% ---- 1. walking periods (W) and every attempt's Close Eyes times (CE, for the MEG clock) ----
W = []; CE = [];
for b = 1:numel(files)
    S0 = load(fullfile(files(b).folder, files(b).name));
    MD = S0.MasterData;
    for i = 1:numel(MD)
        T = MD(i).Traces;
        c = struct('Block', blocks(b), 'Order', i, 'TrialNum', double(MD(i).TrialNum), 'Attempt', double(MD(i).Attempt), ...
            'Status', char(MD(i).Status), ...
            'behCloseEyes',  max([last_time(get_trace(T, 'CloseEyesTorsoTrace')), last_time(get_trace(T, 'CloseEyesHeadTrace'))]), ...
            'behCloseStart', min([first_time(get_trace(T, 'CloseEyesTorsoTrace')), first_time(get_trace(T, 'CloseEyesHeadTrace'))]));
        CE = [CE; c]; %#ok<AGROW>   every attempt, in MasterData order (aborted ones included)

        w = struct('Block', blocks(b), 'TrialNum', double(MD(i).TrialNum), 'Attempt', double(MD(i).Attempt), ...
            'Position', char(MD(i).Position), 'Angle', double(MD(i).StartAngleDeg));
        if ~isempty(RC)
            k = find(RC.Block == w.Block & RC.TrialNum == w.TrialNum & RC.Attempt == w.Attempt, 1, 'last');
            if ~isempty(k)
                if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude'), continue; end
                w.Position = RC.NewPosition{k}; w.Angle = RC.NewAngle(k);
            end
        end
        S = series(get_trace(T, 'StartPosTorsoTrace'), P);
        if isempty(S), continue; end
        [a, cc] = walk_period(S, w.Angle, P);
        if isnan(a), continue; end
        w.v = S.spd(a:cc);                % speed over the walking period
        w.tBeh = S.t(a:cc);               % trace clock of each sample
        W = [W; w]; %#ok<AGROW>
    end
end
CE = struct2table(CE);

% ---- 2. fast intervals ----
minLen = round(minDur * P.fs);
E = cell(numel(W), 1);
for r = 1:numel(W), E{r} = fast_intervals(W(r).v, minSpeed, minLen); end
rows = [];
for r = 1:numel(W)
    for e = 1:size(E{r}, 1)
        s = E{r}(e, 1):E{r}(e, 2);
        rows = [rows; struct('Block', W(r).Block, 'TrialNum', W(r).TrialNum, 'Attempt', W(r).Attempt, ...
            'Position', W(r).Position, 'Angle', W(r).Angle, 'Interval', e, 'nInWalk', size(E{r}, 1), ...
            'Start_s', (s(1) - 1) / P.fs, 'End_s', s(end) / P.fs, 'Dur_s', numel(s) / P.fs, ...
            'MeanSpeed', mean(W(r).v(s)), 'PeakSpeed', max(W(r).v(s)), ...
            'behStart', W(r).tBeh(s(1)), 'behEnd', W(r).tBeh(s(end)) + 1 / P.fs)]; %#ok<AGROW>
    end
end
if isempty(rows), error('No interval averages >= %g m/s for >= %g s.', minSpeed, minDur); end
IV = struct2table(rows);

% ---- 3. MEG: triggers per block, clock fit, interval samples ----
if isempty(which('spm'))
    error('SPM is not on the MATLAB path: addpath(''<your spm folder>'') and run again.');
end
spm('defaults', 'eeg');
if isempty(which('ft_warning'))
    addpath(fullfile(spm('Dir'), 'external', 'fieldtrip'));
    ft_defaults;
end
CE.megClose = nan(height(CE), 1);
M = struct('block', {}, 'file', {}, 'fs', {}, 'tZero', {});
for b = 1:numel(blocks)
    f = fullfile(megDir, sprintf(megFile, blocks(b)));
    D = spm_eeg_load(f);
    fs = D.fsample;
    % sync pulse = all sync channels rising together; the first one is t_zero, later ones are abort marks
    syncData = D(D.indchannel(cfg.sync_trigger_channels), :, 1);
    [tZero, abortMarks] = detect_sync(syncData, cfg.sync_thresh, cfg.simultaneous_tol);
    if isempty(tZero), error('Block %d: no sync pulse found on the trigger channels.', blocks(b)); end
    % condition trigger onsets, minus any that coincide with an abort mark
    condData = D(D.indchannel(cfg.trigger_channels), :, 1);
    on = cell(1, numel(cfg.trigger_channels));
    for c = 1:numel(cfg.trigger_channels)
        e = find(diff(condData(c, :) > cfg.sync_thresh) == 1) + 1;
        e = e(~any(abs(e(:) - abortMarks(:)') <= cfg.simultaneous_tol, 2));
        on{c} = e(:);
    end
    closeOn = on{strcmp(cfg.cond_labels, 'Close Eyes')};
    openOn  = on{strcmp(cfg.cond_labels, 'Open Eyes')};
    % Close Eyes + Open Eyes together = pause marker: drop both
    isPause = false(size(closeOn)); usedOpen = false(size(openOn));
    for k = 1:numel(closeOn)
        m = find(~usedOpen & abs(openOn - closeOn(k)) <= cfg.simultaneous_tol, 1);
        if ~isempty(m), isPause(k) = true; usedOpen(m) = true; end
    end
    closeOn = closeOn(~isPause); openOn = openOn(~usedOpen);
    % one Close Eyes per attempt (aborted included), one Open Eyes per attempt not aborted
    rr   = find(CE.Block == blocks(b));
    isAb = strcmp(CE.Status(rr), 'Aborted_Mid_Trial');
    if numel(closeOn) ~= numel(rr) || numel(openOn) ~= sum(~isAb)
        error(['Block %d: trigger counts do not match the behavioural attempts ', ...
            '(expected %d Close Eyes and %d Open Eyes).'], blocks(b), numel(rr), sum(~isAb));
    end
    CE.megClose(rr) = closeOn;           % k-th Close Eyes trigger <-> k-th attempt of the block
    M(end + 1) = struct('block', blocks(b), 'file', f, 'fs', fs, 'tZero', tZero); %#ok<SAGROW>
end
% behavioural Close Eyes time = end of the Close Eyes phase minus its usual length
dCE = CE.behCloseEyes - CE.behCloseStart;
closeOffset_s = median(dCE(dCE <= min(dCE) + 0.1), 'omitnan');
behCloseTrig = CE.behCloseEyes - closeOffset_s;
fit = struct('block', {}, 'a', {}, 'b', {});
for mm = 1:numel(M)
    all_ = find(CE.Block == M(mm).block);
    ok   = ~isnan(behCloseTrig(all_));
    coef = [ones(sum(ok), 1), behCloseTrig(all_(ok))] \ CE.megClose(all_(ok));
    fit(mm) = struct('block', M(mm).block, 'a', coef(1), 'b', coef(2));
end
IV.File = cell(height(IV), 1);
IV.begsample = nan(height(IV), 1); IV.endsample = nan(height(IV), 1);
IV.nSamples = nan(height(IV), 1); IV.timeRelSyncStart_s = nan(height(IV), 1);
for r = 1:height(IV)
    mm = find([M.block] == IV.Block(r));
    IV.File{r}      = M(mm).file;
    IV.begsample(r) = round(fit(mm).a + fit(mm).b * IV.behStart(r));
    IV.endsample(r) = round(fit(mm).a + fit(mm).b * IV.behEnd(r)) - 1;   % behEnd is the end edge of the last sample
    IV.nSamples(r)  = IV.endsample(r) - IV.begsample(r) + 1;
    IV.timeRelSyncStart_s(r) = (IV.begsample(r) - M(mm).tZero) / M(mm).fs;
end

% ---- 4. figure ----
scr = get(0, 'ScreenSize');
fig = figure('Color', 'w', 'Units', 'pixels', 'Position', [20 40 round(0.92 * scr(3)) round(0.88 * scr(4))], ...
    'Name', 'Navigation fast intervals');
tl = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
for p = 1:9
    ax = nexttile(tl, p); hold(ax, 'on');
    idx = find(strcmp({W.Position}, positions{p}));
    nI = 0; nW = 0; tot = 0;
    for r = idx
        plot(ax, (0:numel(W(r).v) - 1) / P.fs, W(r).v, '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.8);
        if ~isempty(E{r}), nW = nW + 1; end
        for e = 1:size(E{r}, 1)
            s = E{r}(e, 1):E{r}(e, 2);
            plot(ax, (s - 1) / P.fs, W(r).v(s), '-', 'Color', [0.165 0.471 0.839], 'LineWidth', 2.6);
            nI = nI + 1; tot = tot + numel(s) / P.fs;
        end
    end
    yline(ax, minSpeed, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 1);
    xlim(ax, [0 6]); ylim(ax, [0 0.9]);
    set(ax, 'Box', 'off', 'TickDir', 'out', 'XGrid', 'on', 'YGrid', 'on', 'GridColor', [0.9 0.9 0.9], 'FontSize', 9);
    title(ax, {sprintf('%s (%+d%s)', positions{p}, -75 + 15 * p, char(176)), ...
        sprintf('%d intervals, %d/%d walks, %.1f s', nI, nW, numel(idx), tot)}, 'FontWeight', 'normal', 'FontSize', 10);
    if mod(p, 3) == 1, ylabel(ax, 'Torso speed (m/s)'); end
    if p > 6, xlabel(ax, 'Time from start of walking period (s)'); end
end

% ---- 5. save: Excel (tables), .mat (settings + MEG clock), figure, all named after the settings ----
tag = sprintf('speed%03d_dur%03d', round(minSpeed * 100), round(minDur * 100));
xlsFile = fullfile(outDir, sprintf('navigation_fast_intervals_%s_%s.xlsx', tag, pid));
if exist(xlsFile, 'file')                               % same settings again: replace the old file (no stale sheets)
    ws = warning('off', 'all'); delete(xlsFile); warning(ws);
    if exist(xlsFile, 'file')                           % could not delete = open in Excel (or Explorer's preview):
        tag = [tag '_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))];   % save all three under a time-stamped name
        warning('%s is open, so this run is saved as ..._%s_%s.* instead.', xlsFile, tag, pid);
        xlsFile = fullfile(outDir, sprintf('navigation_fast_intervals_%s_%s.xlsx', tag, pid));
    end
end
key = IV.Block * 1e4 + IV.TrialNum * 10 + IV.Attempt;
BA = table(positions(:), (-75 + 15 * (1:9))', 'VariableNames', {'Position', 'Angle'});
BA.nWalks             = arrayfun(@(p) nnz(strcmp({W.Position}, positions{p})), (1:9)');
BA.nIntervals         = arrayfun(@(p) nnz(strcmp(IV.Position, positions{p})), (1:9)');
BA.nWalksWithInterval = arrayfun(@(p) numel(unique(key(strcmp(IV.Position, positions{p})))), (1:9)');
BA.TotalDur_s         = arrayfun(@(p) sum(IV.Dur_s(strcmp(IV.Position, positions{p}))), (1:9)');
BA.MeanSpeed          = arrayfun(@(p) mean(IV.MeanSpeed(strcmp(IV.Position, positions{p}))), (1:9)');
writetable(IV, xlsFile, 'Sheet', 'intervals');
writetable(BA, xlsFile, 'Sheet', 'by_angleclass');
runTime = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
save(fullfile(outDir, sprintf('navigation_fast_intervals_%s_%s.mat', tag, pid)), ...
    'minSpeed', 'minDur', 'P', 'M', 'fit', 'closeOffset_s', 'IV', 'BA', 'runTime');
exportgraphics(fig, fullfile(outDir, sprintf('navigation_fast_intervals_%s_%s.png', tag, pid)), 'Resolution', 200);

% ---------------------------------------------------------------------------------------------------

function E = fast_intervals(v, vmin, minLen)
% non-overlapping intervals [first last] (sample indices) whose mean is >= vmin and length >= minLen samples;
% the longest one first, then the longest in what is left, and so on
E = zeros(0, 2);
free = [1 numel(v)];
while true
    best = [];
    for f = 1:size(free, 1)
        [i, j] = longest_ok(v(free(f, 1):free(f, 2)) - vmin, minLen);
        if ~isempty(i) && (isempty(best) || j - i > best(2) - best(1))
            best = [i j] + free(f, 1) - 1;
        end
    end
    if isempty(best), break; end
    E(end + 1, :) = best; %#ok<AGROW>
    nf = zeros(0, 2);
    for f = 1:size(free, 1)
        a = free(f, 1); b = free(f, 2);
        if b < best(1) || a > best(2), nf(end + 1, :) = [a b]; continue; end %#ok<AGROW>
        if a <= best(1) - 1, nf(end + 1, :) = [a best(1) - 1]; end %#ok<AGROW>
        if best(2) + 1 <= b, nf(end + 1, :) = [best(2) + 1 b]; end %#ok<AGROW>
    end
    free = nf;
end
E = sortrows(E);
end

function [i, j] = longest_ok(w, minLen)
% longest stretch with sum(w) >= 0 (ties: the larger sum), at least minLen samples; [] if none
i = []; j = [];
c = [0; cumsum(w(:))]; n = numel(w);
for L = n:-1:minLen
    s = c(L + 1:end) - c(1:end - L);
    ok = s >= -1e-12;
    if any(ok)
        s(~ok) = -Inf; [~, i] = max(s); j = i + L - 1;
        return
    end
end
end

function [tZero, abortMarks] = detect_sync(trig, thresh, tol)
% rising edges on all sync channels within tol samples of each other = one sync pulse;
% the first is t_zero, any later ones are abort marks
edges = [];
for c = 1:size(trig, 1)
    on = find(diff(trig(c, :) > thresh) == 1) + 1;
    edges = [edges; on(:), repmat(c, numel(on), 1)]; %#ok<AGROW>
end
tZero = []; abortMarks = [];
if isempty(edges), return; end
edges = sortrows(edges, 1);
rise = [];
i = 1;
while i <= size(edges, 1)
    j = i;
    while j < size(edges, 1) && edges(j + 1, 1) - edges(i, 1) <= tol, j = j + 1; end
    if numel(unique(edges(i:j, 2))) >= size(trig, 1), rise(end + 1) = round(mean(edges(i:j, 1))); end %#ok<AGROW>
    i = j + 1;
end
if isempty(rise), return; end
tZero = rise(1);
abortMarks = rise(2:end);
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

function S = series(tr, P)
% P.fs grid: 0.5 s moving mean on position -> speed (same as the epoching script)
S = [];
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z);
[t, iu] = unique(t(ok)); x = x(ok); z = z(ok); x = x(iu); z = z(iu);
if numel(t) < 3, return; end
tu = (t(1):1 / P.fs:t(end))';
w  = round(P.smoothWin * P.fs);
xs = movmean(interp1(t, x, tu), w); zs = movmean(interp1(t, z, tu), w);
S.t = tu; S.vx = gradient(xs, 1 / P.fs); S.vz = gradient(zs, 1 / P.fs);
S.spd = hypot(S.vx, S.vz);
S.xEnd = x(end); S.zEnd = z(end);
end

function [ia, ic] = walk_period(S, label, P)
% epoching-script walking period (indices into S.t); NaN if the walk fails the criteria
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
