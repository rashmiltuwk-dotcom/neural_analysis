clearvars; clc; close all;

pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));
navOnlyRC = [6 46 1];      % Block TrialNum Attempt: reclassification applies to navigation only

% walking period (navigation): same rules as the epoching script
P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.speedThr = 0.2;
P.dirTol = 35; P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0; P.endTol = 45; P.plateauFrac = 0.5;
% yaw average
P.hold = 0.25;      % s, frozen run length that is left out
P.minLive = 0.5;    % s of live 50 Hz samples needed
% stale frames at the start of the PhysicallyWalk / ImagineWalking traces
P.jumpThr = 0.05; P.yawJump = 20; P.jumpWin = 3;

phases = {'navigation', 'StartPos'; 'physicallywalk', 'PhysicallyWalk'; 'imagine_walk', 'ImagineWalking'};
segs   = {'head', 'Head'; 'torso', 'Torso'};
positions = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
if ~exist(outDir, 'dir'), mkdir(outDir); end

RC = table();
if ~isempty(rcFile) && exist(rcFile, 'file'), RC = readtable(rcFile, 'TextType', 'char'); end

files  = dir(fullfile(dataDir, 'P*_MasterData.mat'));
blocks = arrayfun(@(d) str2double(regexp(d.name, '^P\d+_(\d+)_', 'tokens', 'once')), files);
[blocks, ord] = sort(blocks);
files  = files(ord);

R = cell(3, 2);            % rows per phase x segment
for b = 1:numel(files)
    S0 = load(fullfile(files(b).folder, files(b).name));
    MD = S0.MasterData;
    for i = 1:numel(MD)
        base = struct('Block', blocks(b), 'TrialNum', double(MD(i).TrialNum), 'Attempt', double(MD(i).Attempt), ...
            'Status', char(MD(i).Status), 'TaskType', char(MD(i).TaskType), 'Position', char(MD(i).Position), ...
            'Angle', double(MD(i).StartAngleDeg), 'OrigPosition', char(MD(i).Position), ...
            'OrigAngle', double(MD(i).StartAngleDeg), 'Reclassified', false, 'DistCode', char(MD(i).DistCode));
        k = [];
        if ~isempty(RC), k = find(RC.Block == base.Block & RC.TrialNum == base.TrialNum & RC.Attempt == base.Attempt, 1, 'last'); end
        isNavOnly = ismember([base.Block base.TrialNum base.Attempt], navOnlyRC, 'rows');

        for ph = 1:3
            r = base;
            if ~isempty(k)
                if ismember('Action', RC.Properties.VariableNames) && strcmp(RC.Action{k}, 'exclude')
                    if ph == 1, continue; end                     % exclusion: navigation only
                elseif ~(ph > 1 && isNavOnly)
                    r.Position = RC.NewPosition{k}; r.Angle = RC.NewAngle(k); r.Reclassified = true;
                end
            end
            trT = get_trace(MD(i).Traces, [phases{ph, 2} 'TorsoTrace']);
            trH = get_trace(MD(i).Traces, [phases{ph, 2} 'HeadTrace']);
            note = '';
            if ph == 1
                [tA, tB] = walk_period(trT, r.Angle, P);
                if isnan(tA), note = 'no walking period'; end
                t0 = first_time(trT);
            else
                trT = trim_stale(trT, P); trH = trim_stale(trH, P);
                if isnan(first_time(trT)) && isnan(first_time(trH)), continue; end
                tA = min([first_time(trH), first_time(trT)]);     % whole trace
                tB = max([last_time(trH), last_time(trT)]);
                t0 = tA;
            end
            tr2 = {trH, trT};
            for s = 1:2
                [m, sd, live, frz] = mean_yaw(tr2{s}, tA, tB, P);
                q = r;
                q.WindowStart_s = tA - t0; q.WindowEnd_s = tB - t0; q.WindowDur_s = tB - tA;
                q.LiveDur_s = live; q.FrozenFrac = frz;
                q.MeanYaw_deg = m;                                      % 0-360
                q.MeanYawSigned_deg = mod(m + 180, 360) - 180;          % -180 to 180
                q.WithinTrialSD_deg = sd;                               % circular SD of the 50 Hz samples
                if isempty(note) && isnan(m), q.Note = 'too little live tracker data'; else, q.Note = note; end
                R{ph, s} = [R{ph, s}; q];
            end
        end
    end
end

% ---- Excel: six by_trial sheets + by_angleclass ----
xlsFile = fullfile(outDir, sprintf('yaw_average_three_phases_%s.xlsx', pid));
BA = [];
for ph = 1:3
    for s = 1:2
        T = struct2table(R{ph, s});
        T = sortrows(T, {'Position', 'Block', 'TrialNum', 'Attempt'});
        writetable(T, xlsFile, 'Sheet', sprintf('by_trial_%s_%s', phases{ph, 1}, segs{s, 1}), 'WriteMode', 'overwritesheet');
        for p = 1:9
            kp = strcmp(T.Position, positions{p});
            v  = T.MeanYaw_deg(kp); v = v(~isnan(v));
            [mm, sdA] = circ_stats(v);
            BA = [BA; struct('Phase', phases{ph, 1}, 'Segment', segs{s, 1}, 'Position', positions{p}, ...
                'Angle', -75 + 15 * p, 'nTrials', nnz(kp), 'nWithYaw', numel(v), 'MeanYaw_deg', mm, ...
                'MeanYawSigned_deg', mod(mm + 180, 360) - 180, 'AcrossTrialSD_deg', sdA)]; %#ok<AGROW>
        end
    end
end
writetable(struct2table(BA), xlsFile, 'Sheet', 'by_angleclass', 'WriteMode', 'overwritesheet');
fprintf('Saved %s\n  sheets: by_trial_{navigation,physicallywalk,imagine_walk}_{head,torso}, by_angleclass\n', xlsFile);

% ---------------------------------------------------------------------------------------------------

function [m, sd] = circ_stats(a)
% circular mean (0-360) and circular SD (deg) of angles in deg
m = NaN; sd = NaN;
a = a(~isnan(a));
if isempty(a), return; end
S = mean(sind(a)); C = mean(cosd(a));
m = mod(atan2d(S, C), 360);
sd = rad2deg(sqrt(-2 * log(max(hypot(S, C), 1e-12))));
end

function [m, sd, live, frz] = mean_yaw(tr, tA, tB, P)
% Circular-mean yaw (deg, 0-360) between tA and tB (trace clock) on a P.fs grid, live frames only:
% runs of identical frames (x, z and yaw unchanged) lasting >= P.hold s are left out (same as the epoching script).
% live = s of live samples used; frz = fraction of the window that was frozen.
m = NaN; sd = NaN; live = 0; frz = NaN;
if isnan(tA) || isnan(tB) || isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || numel(tr.time) < 2, return; end
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
yq  = interp1(t, rad2deg(unwrap(deg2rad(y))), tq, 'linear');
win = tq >= tA & tq <= tB;
k   = win & ~gap;
live = nnz(k) / P.fs;
frz  = nnz(win & gap) / max(nnz(win), 1);
if nnz(k) < P.minLive * P.fs, return; end
[m, sd] = circ_stats(yq(k));
end

function [tA, tB] = walk_period(tr, label, P)
% epoching-script walking period on the torso trace (trace clock); NaN if the walk fails the criteria
tA = NaN; tB = NaN;
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 3, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z);
[t, iu] = unique(t(ok)); x = x(ok); z = z(ok); x = x(iu); z = z(iu);
if numel(t) < 3, return; end
fs = P.fs;
tu = (t(1):1 / fs:t(end))';
xs = movmean(interp1(t, x, tu), round(P.smoothWin * fs));
zs = movmean(interp1(t, z, tu), round(P.smoothWin * fs));
vx = gradient(xs, 1 / fs); vz = gradient(zs, 1 / fs);
spd = hypot(vx, vz);
wd = round(P.dirWin * fs);
dirErr = mod(atan2d(movmean(vx, wd), -movmean(vz, wd)) - label + 180, 360) - 180;
steady = spd > P.speedThr & abs(dirErr) <= P.dirTol;
steady = bridge_gaps(steady, round(P.bridge * fs));
[len, i1, i2] = longest_run(steady);
if len == 0 || (i2 - i1) / fs - 2 * P.trim < P.chunk, return; end
if abs(mod(atan2d(x(end), -z(end)) - label + 180, 360) - 180) > P.endTol, return; end
thr = P.plateauFrac * median(spd(i1:i2));
a = i1; while a > 1 && spd(a - 1) > thr, a = a - 1; end
c = i2; while c < numel(spd) && spd(c + 1) > thr, c = c + 1; end
tA = tu(a); tB = tu(c);
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
