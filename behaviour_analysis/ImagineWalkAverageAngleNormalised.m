clearvars; clc; close all;


% file paths: MasterData folder, where the results go, and the reclassification file ('' to skip)
pid     = 'p001';
dataDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
outDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\results\p001';
rcFile  = fullfile(outDir, sprintf('reclassified_attempts_%s.csv', pid));

taskTypes = {'P', 'I'};   % both: P as measured, I with the required rotation added
P.fs     = 50;
P.hold   = 0.25;   % runs of identical tracker frames lasting >= this (s) count as frozen
P.dropFrozen = false;   % false: keep frozen frames (the head is still, so they hold the last real pose); true: leave them out
P.minLive    = 0.5;     % with dropFrozen: at least this many seconds of live frames, else NaN

encPhases  = {'EncodingRotate%sTrace', 'PausedEncodingRotate%sTrace', 'PassiveEncode%sTrace', 'Stationary%sTraceTwo'};
respPhases = {'ResponseRotation%sTrace', 'PausedResponseRotation%sTrace', 'PassiveProd%sTrace', 'Stationary%sTraceThree'};
wrap = @(a) mod(a + 180, 360) - 180;

segs = {'Head', 'ImagineWalkingHeadTrace', [0.70 0.09 0.17]; 'Torso', 'ImagineWalkingTorsoTrace', [0.12 0.31 0.61]};
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
        if ~ismember(char(MD(i).TaskType), taskTypes), continue; end
        r = struct();
        r.Block     = blocks(b);
        r.TrialNum  = double(MD(i).TrialNum);
        r.Attempt   = double(MD(i).Attempt);
        r.Status    = char(MD(i).Status);
        r.TaskType  = char(MD(i).TaskType);
        r.Position  = char(MD(i).Position);
        r.Angle     = double(MD(i).StartAngleDeg);
        r.TargetDeg = double(MD(i).TargetDeg);
        r.Direction = char(MD(i).Direction);
        r.Q         = char(MD(i).Q);
        r.DistCode  = char(MD(i).DistCode);
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
            H{s} = yaw_series(tr, P);
        end
        if isempty(H{1}.t) || isempty(H{2}.t), continue; end   % no imagined-walking recording (e.g. aborted attempt)

        r.ImagDur = H{1}.t(end) - H{1}.t(1);
        T = MD(i).Traces;
        r.EncodingActual = yaw_change(T, encPhases, 'ResponseRotation%sTrace');   % deg, same as the accuracy script
        r.ResponseMade   = yaw_change(T, respPhases, 'ImagineWalking%sTrace');
        r.Required       = wrap(180 - r.EncodingActual);
        for s = 1:2
            k = true(size(H{s}.t));
            if P.dropFrozen, k = ~H{s}.gap; end
            r.([segs{s, 1} 'ImagYaw']) = NaN;
            if ~P.dropFrozen || nnz(k) >= P.minLive * P.fs
                r.([segs{s, 1} 'ImagYaw']) = mod(circ_mean_deg(H{s}.yaw(k)), 360);
            end
            r.([segs{s, 1} 'FrozenFrac']) = mean(H{s}.gap);
            r.([segs{s, 1} 'IdealYaw'])   = mod(r.([segs{s, 1} 'ImagYaw']) + r.Required - r.ResponseMade, 360);
            if strcmp(r.TaskType, 'P'), r.([segs{s, 1} 'CombinedYaw']) = r.([segs{s, 1} 'ImagYaw']);
            else, r.([segs{s, 1} 'CombinedYaw']) = r.([segs{s, 1} 'IdealYaw']); end
        end
        Y = [Y; r]; %#ok<AGROW>
    end
end
TY = struct2table(Y);
for v = {'Status', 'TaskType', 'Position', 'Direction', 'Q', 'DistCode'}, TY.(v{1}) = cellstr(TY.(v{1})); end
writetable(TY, fullfile(outDir, sprintf('imagine_walk_yaw_combined_%s.csv', pid)));

% Excel workbook: one sheet per trial, one sheet of the combined averages per angle class (position)
xlsFile = fullfile(outDir, sprintf('imagine_walk_yaw_%s.xlsx', pid));
byTrial = TY(:, {'Block', 'TrialNum', 'Attempt', 'Status', 'TaskType', 'Position', 'Angle', 'TargetDeg', 'Direction', ...
    'Q', 'DistCode', 'ImagDur', 'EncodingActual', 'Required', 'ResponseMade', ...
    'HeadImagYaw', 'HeadIdealYaw', 'HeadCombinedYaw', 'TorsoImagYaw', 'TorsoIdealYaw', 'TorsoCombinedYaw', ...
    'HeadFrozenFrac', 'TorsoFrozenFrac'});
writetable(byTrial, xlsFile, 'Sheet', 'by_trial_imagine_walk', 'WriteMode', 'overwritesheet');
byAngle = table(positions(:), (-75 + 15 * (1:9))', 'VariableNames', {'Position', 'Angle'});
fprintf('%d attempts with an imagined-walking recording: %d P (physical rotation), %d I (imagined rotation)\n', ...
    height(TY), nnz(strcmp(TY.TaskType, 'P')), nnz(strcmp(TY.TaskType, 'I')));

for s = 1:2
    % combined plot: P as measured, I as measured (no rotation), I + required rotation, and the combined mean
    col = segs{s, 3};
    vc  = TY.([segs{s, 1} 'CombinedYaw']);
    vr  = TY.([segs{s, 1} 'ImagYaw']);
    isP = strcmp(TY.TaskType, 'P');
    nP = zeros(1, 9); nI = zeros(1, 9);
    mP = nan(1, 9); mR = nan(1, 9); mI = nan(1, 9); mC = nan(1, 9);
    for p = 1:9
        kp = strcmp(TY.Position, positions{p}) & ~isnan(vc);
        k1 = kp & isP; k2 = kp & ~isP;
        nP(p) = nnz(k1); nI(p) = nnz(k2);
        if any(k1), mP(p) = mod(circ_mean_deg(vc(k1)), 360); end
        if any(k2), mI(p) = mod(circ_mean_deg(vc(k2)), 360); mR(p) = mod(circ_mean_deg(vr(k2)), 360); end
        if any(kp), mC(p) = mod(circ_mean_deg(vc(kp)), 360); end
    end

    % combined averages (P as measured + I with the required rotation added), for the by_angleclass sheet
    AV = table(positions(:), (-75 + 15 * (1:9))', nP(:) + nI(:), mC(:), 'VariableNames', ...
        {'Position', 'Angle', 'n', 'Combined'});
    byAngle.n = AV.n;
    byAngle.([segs{s, 1} 'Combined']) = mC(:);

    fig = figure('Color', 'w', 'Position', [100 100 900 600]);
    ax  = axes(fig, 'Position', [0.09 0.10 0.88 0.68]); hold(ax, 'on');   % room above for the legend
    h1 = plot(ax, 1:9, mC, '-o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 8, 'LineWidth', 2.2);
    h2 = plot(ax, 1:9, mP, ':', 'Color', [col 0.7], 'LineWidth', 1.3);
    h3 = plot(ax, 1:9, mI, '--', 'Color', [col 0.7], 'LineWidth', 1.3);
    h4 = plot(ax, 1:9, mR, '-.o', 'Color', [0.5 0.5 0.5], 'MarkerFaceColor', 'w', 'MarkerSize', 5, 'LineWidth', 1.1);
    xticks(ax, 1:9);
    xticklabels(ax, arrayfun(@(p) sprintf('%s (%+d%s)', positions{p}, -75 + 15 * p, char(176)), 1:9, 'UniformOutput', false));
    xlim(ax, [0.4 9.6]); ylim(ax, [0 360]); yticks(ax, 0:45:360);
    ylabel(ax, sprintf('%s yaw during imagined walking (%s)', segs{s, 1}, char(176)));
    set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 10, 'YGrid', 'on', 'GridColor', [0.85 0.85 0.85]);
    lg = legend(ax, [h1 h2 h3 h4], {'combined mean (P + I)', 'P: physically rotated, as measured', ...
        'I: imagined rotation + required rotation', 'I: imagined rotation, as measured'}, 'Box', 'off', 'FontSize', 9);
    lg.Units = 'normalized';
    lg.Position(1:2) = [0.01, 0.99 - lg.Position(4)];   % top-left corner of the figure
    exportgraphics(fig, fullfile(outDir, sprintf('imagine_walk_yaw_combined_%s_%s.png', lower(segs{s, 1}), pid)), ...
        'Resolution', 200);
end
writetable(byAngle, xlsFile, 'Sheet', 'by_angleclass', 'WriteMode', 'overwritesheet');
fprintf('\nSaved %s (sheets: by_trial_imagine_walk, by_angleclass)\n', xlsFile);

function d = yaw_change(T, phases, nextPhase)
% net torso yaw change over the listed phases, up to the first frame of nextPhase (from the accuracy script)
d = NaN;
y = [];
for q = 1:numel(phases)
    y = [y; trace_yaw(T, sprintf(phases{q}, 'Torso'))]; %#ok<AGROW>
end
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

function m = circ_mean_deg(a)
m = atan2d(mean(sind(a)), mean(cosd(a)));
end

function Y = yaw_series(tr, P)
% yaw on a P.fs grid (trace clock), 0-360, with frozen-tracker frames flagged (runs of identical frames >= P.hold s)
Y = struct('t', [], 'yaw', [], 'gap', []);
if isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || numel(tr.time) < 2, return; end
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
Y.t = tq; Y.gap = gap;
Y.yaw = mod(interp1(t, rad2deg(unwrap(deg2rad(y))), tq, 'linear'), 360);
end
