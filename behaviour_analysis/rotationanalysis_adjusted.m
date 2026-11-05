clearvars; clc; close all;

% file paths: MasterData folder for each participant (add or remove rows), and where results go
participants = {
    'p001', 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab_filled'
    'p000', 'C:\Users\rashm\Documents\opm_pi\human_pilot\behavioural_mat_filled'
    };
outDir = 'C:\Users\rashm\Documents\opm_pi\results_encoding_rotation';

cfg = config();   % config.m must be on the MATLAB path

sdCut = 2;

if ~exist(outDir, 'dir'), mkdir(outDir); end

encPhases  = {'EncodingRotate%sTrace', 'PausedEncodingRotate%sTrace', 'PassiveEncode%sTrace', 'Stationary%sTraceTwo'};
respPhases = {'ResponseRotation%sTrace', 'PausedResponseRotation%sTrace', 'PassiveProd%sTrace', 'Stationary%sTraceThree'};
wrap = @(a) mod(a + 180, 360) - 180;

namePattern = '^[Pp](?:articipant)?[_\- ]?(\d+)[_\- ](\d+)(?:[_\- ]|$)';
B = [];
for p = 1:size(participants, 1)
    files = dir(fullfile(participants{p, 2}, cfg.master_data_pattern));
    if isempty(files)
        fprintf('%s: no MasterData files in %s\n', participants{p, 1}, participants{p, 2});
        continue
    end
    tok   = arrayfun(@(d) regexp(d.name, namePattern, 'tokens', 'once'), files, 'UniformOutput', false);
    files = files(~cellfun(@isempty, tok));  tok = tok(~cellfun(@isempty, tok));
    [blocks, ord] = sort(cellfun(@(t) str2double(t{2}), tok));
    files = files(ord);
    for b = 1:numel(files)
        S  = load(fullfile(files(b).folder, files(b).name));
        MD = S.MasterData;
        for i = 1:numel(MD)
            if ~strcmp(char(MD(i).Status), 'Accepted') || ~strcmp(char(MD(i).TaskType), 'P'), continue; end
            T = MD(i).Traces;
            r = struct();
            r.Participant = participants{p, 1};
            r.Block       = blocks(b);
            r.TrialNum    = double(MD(i).TrialNum);
            r.Direction   = char(MD(i).Direction);
            r.TargetDeg   = double(MD(i).TargetDeg);
            r.EncodingActual = yaw_change(T, encPhases, 'ResponseRotation%sTrace');
            r.ResponseMade   = yaw_change(T, respPhases, 'ImagineWalking%sTrace');
            r.Required       = wrap(180 - r.EncodingActual);
            r.Error          = wrap(r.EncodingActual + r.ResponseMade - 180) * sign(r.Required);
            if r.TargetDeg < 180, r.RotationType = 'standard'; else, r.RotationType = 'reflex'; end
            if abs(wrap(180 - r.TargetDeg)) > 90, r.ResponseSize = 'major'; else, r.ResponseSize = 'minor'; end
            B = [B; r]; %#ok<AGROW>
        end
    end
end
TB = struct2table(B);
for v = {'Participant', 'Direction', 'RotationType', 'ResponseSize'}
    TB.(v{1}) = cellstr(TB.(v{1}));
end

TB.Outlier = false(height(TB), 1);
for pid = unique(TB.Participant)'
    k = find(strcmp(TB.Participant, pid{1}));
    TB.Outlier(k) = isoutlier(TB.Error(k), 'mean', 'ThresholdFactor', sdCut);
end
writetable(TB, fullfile(outDir, 'response_rotation_accuracy.csv'));

keep  = ~TB.Outlier;
comps = {
    'RotationType', {'standard', 'reflex'}, {'Standard', 'Reflex'}
    'ResponseSize', {'minor', 'major'},     {'Minor', 'Major'}
    };

fprintf('Response rotation error (deg), physical-rotation trials, %d removed (> %g SD)\n', sum(TB.Outlier), sdCut);
fprintf('%-10s %4s %9s %9s\n', '', 'n', 'signed', 'absolute');
for c = 1:size(comps, 1)
    for li = 1:2
        k = strcmp(TB.(comps{c, 1}), comps{c, 2}{li}) & keep;
        fprintf('%-10s %4d %+9.1f %9.1f\n', comps{c, 3}{li}, sum(k), mean(TB.Error(k)), mean(abs(TB.Error(k))));
    end
end

fig = figure('Color', 'w', 'Position', [80 80 900 760]);
tl  = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact');
rng(1);
for row = 1:2
    for c = 1:size(comps, 1)
        ax = nexttile(tl, (row - 1) * 2 + c); hold(ax, 'on');
        for li = 1:2
            k = strcmp(TB.(comps{c, 1}), comps{c, 2}{li}) & keep;
            v = TB.Error(k);
            if row == 2, v = abs(v); end
            bar(ax, li, mean(v), 0.6, 'FaceColor', [0.75 0.75 0.75], 'EdgeColor', 'none');
            scatter(ax, li + 0.4 * (rand(numel(v), 1) - 0.5), v, 14, 'k', 'filled', 'MarkerFaceAlpha', 0.5);
            errorbar(ax, li, mean(v), std(v) / sqrt(numel(v)), 'k', 'LineWidth', 1.2, 'CapSize', 8);
        end
        yline(ax, 0, 'k-');
        xticks(ax, 1:2); xticklabels(ax, comps{c, 3}); xlim(ax, [0.4 2.6]);
        set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 11);
        if c == 1 && row == 1, ylabel(ax, sprintf('Error (%s)', char(176))); end
        if c == 1 && row == 2, ylabel(ax, sprintf('|Error| (%s)', char(176))); end
    end
end
exportgraphics(fig, fullfile(outDir, 'response_rotation_accuracy.png'), 'Resolution', 300);

function d = yaw_change(T, phases, nextPhase)
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
