clearvars; clc; close all;

% file paths: change these to run on another computer or participant
behDir = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab_filled';
outDir = fullfile(behDir, '..', 'results', 'p001');

cfg = config();   % config.m must be on the MATLAB path

imaginedRotationOnly = true;

if ~exist(outDir, 'dir'), mkdir(outDir); end

files = dir(fullfile(behDir, cfg.master_data_pattern));
namePattern = '^[Pp](?:articipant)?[_\- ]?(\d+)[_\- ](\d+)(?:[_\- ]|$)';
tok   = arrayfun(@(d) regexp(d.name, namePattern, 'tokens', 'once'), files, 'UniformOutput', false);
files = files(~cellfun(@isempty, tok));  tok = tok(~cellfun(@isempty, tok));
[blocks, ord] = sort(cellfun(@(t) str2double(t{2}), tok));
files = files(ord);

B = [];
for b = 1:numel(files)
    S  = load(fullfile(files(b).folder, files(b).name));
    MD = S.MasterData;
    for i = 1:numel(MD)
        if ~strcmp(char(MD(i).Status), 'Accepted'), continue; end
        T  = MD(i).Traces;
        p0 = position(get_trace(T, 'CloseEyesTorsoTrace'), 'first');
        pR = position(get_trace(T, 'RealignTorsoTrace'), 'last');
        pI = position(get_trace(T, 'ImagineWalkingTorsoTrace'), 'first');
        r = struct();
        r.Block      = blocks(b);
        r.TrialNum   = double(MD(i).TrialNum);
        r.TaskType   = char(MD(i).TaskType);
        r.PhysDist   = hypot(pR(1) - p0(1), pR(2) - p0(2));
        r.ImagDist   = hypot(pI(1) - p0(1), pI(2) - p0(2));
        r.PhysWalkDur    = phase_dur(T, 'PhysicallyWalk');
        r.ImagineWalkDur = phase_dur(T, 'ImagineWalking');
        B = [B; r]; %#ok<AGROW>
    end
end
TB = struct2table(B);
writetable(TB, fullfile(outDir, 'imagined_start_distance_p001.csv'));

useI = ~imaginedRotationOnly | strcmp(cellstr(TB.TaskType), 'I');
red  = [0.80 0.10 0.10];
blue = [0.10 0.30 0.80];
fig = figure('Color', 'w', 'Position', [60 60 1500 460]);
tl  = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact');

ax = nexttile(tl);
lab = scatter_fit(ax, TB.PhysDist, TB.PhysWalkDur, red, 'physical', 'duration vs distance');
legend(ax, lab, 'Location', 'northwest', 'Box', 'off');
xlabel(ax, 'Distance from start point to end of realignment (m)');
ylabel(ax, 'Physical walk duration (s)');
title(ax, 'Physical walk');

ax = nexttile(tl);
lab = scatter_fit(ax, TB.ImagDist(useI), TB.ImagineWalkDur(useI), blue, 'imagined', 'duration vs distance');
legend(ax, lab, 'Location', 'northwest', 'Box', 'off');
xlabel(ax, 'Distance from start point at start of imagined walk (m)');
ylabel(ax, 'Imagined walk duration (s)');
if imaginedRotationOnly, title(ax, 'Imagined walk (imagined-rotation trials)'); else, title(ax, 'Imagined walk'); end

ax = nexttile(tl);
labP = scatter_fit(ax, TB.PhysDist, TB.PhysWalkDur, red, 'physical', 'duration vs distance');
labI = scatter_fit(ax, TB.ImagDist(useI), TB.ImagineWalkDur(useI), blue, 'imagined', 'duration vs distance');
legend(ax, [labI labP], 'Location', 'northwest', 'Box', 'off');
xlabel(ax, 'Distance from start point (m)');
ylabel(ax, 'Walk duration (s)');
title(ax, 'Physical and imagined');

exportgraphics(fig, fullfile(outDir, 'imagined_start_distance_p001.png'), 'Resolution', 300);

fig2 = figure('Color', 'w', 'Position', [120 120 680 480]);
ax   = axes(fig2);
labI = scatter_fit(ax, TB.ImagDist, TB.ImagineWalkDur, blue, 'imagined walk', 'duration vs distance');
labP = scatter_fit(ax, TB.PhysDist, TB.PhysWalkDur, red, 'physical walk', 'duration vs distance');
legend(ax, [labI labP], 'Location', 'northwest', 'Box', 'off');
xlabel(ax, 'Distance (m)');
ylabel(ax, 'Walk duration (s)');
exportgraphics(fig2, fullfile(outDir, 'imagined_physical_walk_p001.png'), 'Resolution', 300);

fprintf('\nDistance from start point: physical (to end of realignment) median %.2f m, ', median(TB.PhysDist));
fprintf('imagined (at start of imagined walk) median %.2f m\n', median(TB.ImagDist(useI)));

function h = scatter_fit(ax, x, y, c, name, what, dropOutliers)
if nargin < 7, dropOutliers = true; end
hold(ax, 'on');
out = isnan(x) | isnan(y);
if dropOutliers, out = out | isoutlier(x) | isoutlier(y); end
k   = ~out;
R   = corrcoef(x(k), y(k)); r = R(1, 2);
pf  = polyfit(x(k), y(k), 1);
h   = scatter(ax, x(k), y(k), 40, c, 'filled', 'MarkerFaceAlpha', 0.75, ...
    'DisplayName', name);
scatter(ax, x(out), y(out), 40, c, 'LineWidth', 1.2, 'HandleVisibility', 'off');
xx  = linspace(min(x(k)), max(x(k)), 50);
plot(ax, xx, polyval(pf, xx), '-', 'Color', c, 'LineWidth', 2, 'HandleVisibility', 'off');
set(ax, 'Box', 'off', 'TickDir', 'out', 'FontSize', 11);
fprintf('%-9s %-21s r = %.2f, r^2 = %.2f, slope %.3f, n = %d, outliers excluded: %d\n', name, ...
    what, r, r ^ 2, pf(1), sum(k), sum(out & ~isnan(x) & ~isnan(y)));
end

function tr = get_trace(T, name)
tr = [];
if isfield(T, name), tr = T.(name); end
end

function p = position(tr, which)
p = [NaN NaN];
if isempty(tr) || ~isfield(tr, 'x'), return; end
x = double(tr.x(:)); z = double(tr.z(:));
ok = find(~isnan(x) & ~isnan(z));
if isempty(ok), return; end
if strcmp(which, 'first'), k = ok(1); else, k = ok(end); end
p = [x(k) z(k)];
end

function d = phase_dur(T, phase)
t0 = NaN; t1 = NaN;
for part = {'Head', 'Torso'}
    tr = get_trace(T, [phase part{1} 'Trace']);
    if isempty(tr) || ~isfield(tr, 'time'), continue; end
    t = double(tr.time(:)); t = t(~isnan(t));
    if numel(t) < 2, continue; end
    t0 = min(t0, min(t)); t1 = max(t1, max(t));
end
d = t1 - t0;
end
