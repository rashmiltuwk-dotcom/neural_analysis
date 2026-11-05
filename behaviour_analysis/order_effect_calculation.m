clearvars; clc; close all;

% participants and file paths: add or remove rows; set the last column to false to leave one out
participants = {
    'p001', 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab', true
    'p000', 'C:\Users\rashm\Documents\opm_pi\human_pilot\behavioural_mat_filled',                      true
    };
outDir = 'C:\Users\rashm\Documents\opm_pi\results_encoding_rotation';

cfg = config();   % config.m must be on the MATLAB path

if ~exist(outDir, 'dir'), mkdir(outDir); end

encPhases  = {'EncodingRotate%sTrace', 'PausedEncodingRotate%sTrace', 'PassiveEncode%sTrace', 'Stationary%sTraceTwo'};
respPhases = {'ResponseRotation%sTrace', 'PausedResponseRotation%sTrace', 'PassiveProd%sTrace', 'Stationary%sTraceThree'};
wrap = @(a) mod(a + 180, 360) - 180;

namePattern = '^[Pp](?:articipant)?[_\- ]?(\d+)[_\- ](\d+)(?:[_\- ]|$)';
for p = find([participants{:, 3}])
    pid     = participants{p, 1};
    dataDir = participants{p, 2};
    files = dir(fullfile(dataDir, cfg.master_data_pattern));
    if isempty(files)
        fprintf('%s: no MasterData files in %s\n\n', pid, dataDir);
        continue
    end
    tok   = arrayfun(@(d) regexp(d.name, namePattern, 'tokens', 'once'), files, 'UniformOutput', false);
    files = files(~cellfun(@isempty, tok));  tok = tok(~cellfun(@isempty, tok));
    [blocks, ord] = sort(cellfun(@(t) str2double(t{2}), tok));
    files = files(ord);

    Block = []; Trial = []; Condition = []; AbsError = [];
    for b = 1:numel(files)
        S  = load(fullfile(files(b).folder, files(b).name));
        MD = S.MasterData;
        for i = 1:numel(MD)
            if ~strcmp(char(MD(i).Status), 'Accepted') || ~strcmp(char(MD(i).TaskType), 'P'), continue; end
            T  = MD(i).Traces;
            E  = yaw_change(T, encPhases, 'ResponseRotation%sTrace');
            Rm = yaw_change(T, respPhases, 'ImagineWalking%sTrace');
            Block(end + 1, 1)     = blocks(b);                          %#ok<SAGROW>
            Trial(end + 1, 1)     = double(MD(i).TrialNum);             %#ok<SAGROW>
            Condition(end + 1, 1) = double(MD(i).TargetDeg);            %#ok<SAGROW>
            AbsError(end + 1, 1)  = abs(wrap(E + Rm - 180));            %#ok<SAGROW>
        end
    end
    tbl = table(Block, Trial, Condition, AbsError);
    tbl = sortrows(tbl, 'Trial');

    tbl.Condition = categorical(tbl.Condition);
    condMean      = groupsummary(tbl, 'Condition', 'mean', 'AbsError');
    tbl.CondMean  = condMean.mean_AbsError(double(tbl.Condition));
    tbl.D         = tbl.AbsError - tbl.CondMean;

    lm = fitlm(tbl, 'D ~ Trial');
    c  = lm.Coefficients.Estimate(1);
    m  = lm.Coefficients.Estimate(2);
    r  = sign(m) * sqrt(lm.Rsquared.Ordinary);

    tbl.Predicted = predict(lm, tbl);
    tbl.Epsilon   = lm.Residuals.Raw;
    writetable(tbl, fullfile(outDir, sprintf('order_effect_%s.csv', pid)));

    fprintf('%s: |Error| = CondMean %+.4f * Trial %+.2f + epsilon\n', pid, m, c);
    fprintf('n = %d, r = %.2f, change over session %+.1f deg, epsilon SD %.1f deg\n\n', height(tbl), r, ...
        m * (max(tbl.Trial) - min(tbl.Trial)), std(tbl.Epsilon));
    fprintf('%5s %5s %9s %9s %9s %9s %9s %9s\n', 'Block', 'Trial', 'Condition', '|Error|', 'CondMean', 'D', 'm*T+c', 'epsilon');
    for i = 1:height(tbl)
        fprintf('%5d %5d %9s %9.2f %9.2f %+9.2f %+9.2f %+9.2f\n', tbl.Block(i), tbl.Trial(i), char(tbl.Condition(i)), ...
            tbl.AbsError(i), tbl.CondMean(i), tbl.D(i), tbl.Predicted(i), tbl.Epsilon(i));
    end

    fig = figure('Color', 'w', 'Position', [100 100 700 480]);
    ax  = axes(fig); hold(ax, 'on');
    plot(ax, [tbl.Trial tbl.Trial]', [tbl.Predicted tbl.D]', '-', 'Color', [0.6 0.6 0.6]);
    scatter(ax, tbl.Trial, tbl.D, 16, 'k', 'filled');
    plot(ax, tbl.Trial, tbl.Predicted, 'k-', 'LineWidth', 1.5);
    yline(ax, 0, 'k-');
    xlabel(ax, 'Trial');
    ylabel(ax, sprintf('|Error| - CondMean (%s)', char(176)));
    title(ax, sprintf('%s: |Error| = CondMean %+.3f %s Trial %+.2f', pid, m, char(183), c));
    set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 11);
    exportgraphics(fig, fullfile(outDir, sprintf('order_effect_%s.png', pid)), 'Resolution', 300);
    fprintf('\n');
end

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
