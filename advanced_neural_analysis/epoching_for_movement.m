clearvars; clc; close all;

% file paths: change these to run on another computer or participant
behDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\Behavioural_Data_001_01\Matlab';
megDir  = 'C:\Users\rashm\Documents\opm_pi\participant_001\preprocessed';
megFile = 'prep_p001_block%02d.mat';
outDir  = fullfile(behDir, '..', 'results', 'p001');

cfg = config();   % config.m must be on the MATLAB path

askBeforeEpoching = true;
epochMode = '';   % '' = ask at the start of each run; or 'first3' / 'full' / 'stableyaw' to skip the question
includeRejected   = true;
roomLim   = [-2 2];
reclassifyInteractive = true;
reclassFile = fullfile(outDir, 'reclassified_attempts_p001.csv');   % saved reclassifications / exclusions (navigation)
reclassFilePW = fullfile(outDir, 'reclassified_attempts_pw_p001.csv');   % PhysicallyWalk-only reclassifications / exclusions
navOnlyRC = [6 46 1];   % Block TrialNum Attempt: navigation reclassifications that do NOT carry over to PhysicallyWalk
manualExclude = [];

P.fs = 50; P.smoothWin = 0.5; P.dirWin = 1.5; P.speedThr = 0.2;
P.dirTol = 35;
P.bridge = 0.3; P.trim = 0.5; P.chunk = 1.0; P.endTol = 45;
P.plateauFrac = 0.5;
P.hold = 0.25;     % yaw: runs of identical tracker frames lasting >= this (s) count as frozen and are left out
P.minLive = 0.5;   % yaw: at least this many seconds of live frames inside the walking period, else NaN
P.epochLen  = 3;     % 'first3': epoch length (s) from the start of the walking period
P.yawBand   = 15;    % 'stableyaw': longest stretch of the walking period where torso yaw stays within this many deg
P.yawSmooth = 0.5;   % 'stableyaw': s, moving mean on torso yaw before finding that stretch
% PhysicallyWalk = the walk from the start position back to the centre. Same walking-period rules as navigation,
% with these differences: body position from the head tracker (the torso tracker is often stale here), walking
% direction = start angle + 180, a lower speed threshold (slower walk), and the START (not the end) must be at the
% start position. For 'stableyaw', PhysicallyWalk uses head yaw.
P.pwSpeedThr = 0.1;              % m/s
P.headOff = 0.41; P.headAng = 10; % body = head - headOff m along (yaw - headAng)
P.startTol = 45;                 % deg: walk must start within this of the start position's angle
P.jumpThr = 0.05; P.yawJump = 20; P.jumpWin = 3;   % stale frames at the start of the PhysicallyWalk traces

if ~exist(outDir, 'dir'), mkdir(outDir); end

% ---- how the walks are epoched: decides every behavioural figure and summary below ----
modes = {'first3', 'full', 'stableyaw'};
modeTxt = {sprintf('Velocity: first %g s of the walking period (same length for every walk)', P.epochLen), ...
    'Velocity: the full walking period (length differs between walks)', ...
    sprintf('Stable yaw: the part of the walking period where torso yaw stays within %g%s', P.yawBand, char(176))};
if isempty(epochMode)
    sel = listdlg('PromptString', {'How should the walks be epoched?', ''}, 'SelectionMode', 'single', ...
        'ListString', modeTxt, 'ListSize', [520 90], 'InitialValue', 2, 'Name', 'Epoching');
    if isempty(sel), fprintf('No epoching option chosen; stopped.\n'); return; end
    epochMode = modes{sel};
end
if ~ismember(epochMode, modes), error('epochMode must be one of: %s', strjoin(modes, ', ')); end
modeLabel = modeTxt{strcmp(modes, epochMode)};
fprintf('Epoching: %s\n', modeLabel);

files  = dir(fullfile(behDir, cfg.master_data_pattern));
namePattern = '^[Pp](?:articipant)?[_\- ]?(\d+)[_\- ](\d+)(?:[_\- ]|$)';
tok    = arrayfun(@(d) regexp(d.name, namePattern, 'tokens', 'once'), files, 'UniformOutput', false);
files  = files(~cellfun(@isempty, tok));  tok = tok(~cellfun(@isempty, tok));
blocks = cellfun(@(t) str2double(t{2}), tok);
[blocks, ord] = sort(blocks);
files  = files(ord);

RC  = load_reclass(reclassFile);
RCP = load_reclass(reclassFilePW);
B = [];
RAW = {};
RAWH = {};
SER = struct('t', {}, 'speed', {}, 'x', {}, 'z', {}, 'ia', {}, 'ic', {});
BP = [];          % PhysicallyWalk rows
RAWP = {};        % PhysicallyWalk body trace (from the head), used for the walking period
RAWPH = {};       % PhysicallyWalk head trace
RAWPT = {};       % PhysicallyWalk torso trace
SERP = struct('t', {}, 'speed', {}, 'x', {}, 'z', {}, 'ia', {}, 'ic', {});
for b = 1:numel(files)
    S  = load(fullfile(files(b).folder, files(b).name));
    MD = S.MasterData;
    for i = 1:numel(MD)
        r = struct();
        r.Block      = blocks(b);
        r.Order      = i;
        r.TrialNum   = double(MD(i).TrialNum);
        r.Attempt    = double(MD(i).Attempt);
        r.Status     = char(MD(i).Status);
        if strcmp(r.Status, 'Aborted_Mid_Trial'), r.TrialStatus = 'REJECTED';
        else, r.TrialStatus = 'ACCEPTED'; end
        r.Position   = char(MD(i).Position);
        r.Angle      = double(MD(i).StartAngleDeg);
        r.DistCode   = char(MD(i).DistCode);
        r.TargetDist = double(MD(i).TargetDist);
        r.OrigPosition = r.Position;
        r.OrigAngle    = r.Angle;
        r.Reclassified   = false;
        r.ManualExcluded = ismember(r.TrialNum, manualExclude);
        k = find(RC.Block == r.Block & RC.TrialNum == r.TrialNum & RC.Attempt == r.Attempt, 1, 'last');
        if ~isempty(k)
            if strcmp(RC.Action{k}, 'exclude')
                r.ManualExcluded = true;
            else
                r.Position = RC.NewPosition{k}; r.Angle = RC.NewAngle(k); r.Reclassified = true;
            end
        end
        r.BasePosition = r.OrigPosition;   % label a 'restore' goes back to (navigation: the original label)
        r.BaseAngle    = r.OrigAngle;

        sp = get_trace(MD(i).Traces, 'StartPosTorsoTrace');
        ce = [last_time(get_trace(MD(i).Traces, 'CloseEyesTorsoTrace')), ...
              last_time(get_trace(MD(i).Traces, 'CloseEyesHeadTrace'))];
        r.behSetupStart = first_time(sp);
        r.behSetupEnd   = last_time(sp);
        r.behCloseEyes  = max(ce);
        cs = [first_time(get_trace(MD(i).Traces, 'CloseEyesTorsoTrace')), ...
              first_time(get_trace(MD(i).Traces, 'CloseEyesHeadTrace'))];
        r.behCloseStart = min(cs);
        oe = [first_time(get_trace(MD(i).Traces, 'OpenEyesTorsoTrace')), ...
              first_time(get_trace(MD(i).Traces, 'OpenEyesHeadTrace'))];
        r.behOpenEyes   = min(oe);

        E = walking_period(sp, r.Angle, P);
        E = apply_epoch_mode(E, sp, epochMode, P);   % behWalkStart/End below = this walk's epoch window
        RAW{numel(B) + 1} = sp;
        SER(numel(B) + 1) = struct('t', E.tRel, 'speed', E.speed, 'x', E.x, 'z', E.z, ...
            'ia', E.ia, 'ic', E.ic);
        r.StartsAtTraceStart = E.startsAtTraceStart;
        r.behWalkStart = E.walkStart;
        r.behWalkEnd   = E.walkEnd;
        r.WalkDur      = E.walkEnd - E.walkStart;
        r.FullWalkStart = E.fullStart;   % the whole speed-based walking period, for reference
        r.FullWalkEnd   = E.fullEnd;
        r.FullWalkDur   = E.fullEnd - E.fullStart;
        r.SteadyDur    = E.steadyEnd - E.steadyStart;
        hd = get_trace(MD(i).Traces, 'StartPosHeadTrace');
        RAWH{numel(B) + 1} = hd;
        r.HeadMeanYaw  = mean_yaw(hd, E.walkStart, E.walkEnd, P);   % over this walk's walking period only
        r.TorsoMeanYaw = mean_yaw(sp, E.walkStart, E.walkEnd, P);
        r.Excluded = E.excluded;
        if r.ManualExcluded, r.Excluded = 'manually excluded'; end
        B = [B; r];

        % ---- PhysicallyWalk: same classification as navigation ----
        rp = struct();
        rp.Block = r.Block; rp.Order = r.Order; rp.TrialNum = r.TrialNum; rp.Attempt = r.Attempt;
        rp.Status = r.Status; rp.TrialStatus = r.TrialStatus;
        rp.Position = r.OrigPosition; rp.Angle = r.OrigAngle;
        if r.Reclassified && ~ismember([r.Block r.TrialNum r.Attempt], navOnlyRC, 'rows')
            rp.Position = r.Position; rp.Angle = r.Angle;          % navigation reclassification carries over
        end
        rp.DistCode = r.DistCode; rp.TargetDist = r.TargetDist;
        rp.OrigPosition = r.OrigPosition; rp.OrigAngle = r.OrigAngle;
        rp.BasePosition = rp.Position; rp.BaseAngle = rp.Angle;    % label before any PhysicallyWalk-only change
        rp.ManualExcluded = ismember(rp.TrialNum, manualExclude);   % (navigation exclusions do not carry over)
        k = find(RCP.Block == rp.Block & RCP.TrialNum == rp.TrialNum & RCP.Attempt == rp.Attempt, 1, 'last');
        if ~isempty(k)
            if strcmp(RCP.Action{k}, 'exclude'), rp.ManualExcluded = true;
            else, rp.Position = RCP.NewPosition{k}; rp.Angle = RCP.NewAngle(k); end
        end
        rp.Reclassified = ~strcmp(rp.Position, rp.OrigPosition);
        hdP = trim_stale(get_trace(MD(i).Traces, 'PhysicallyWalkHeadTrace'), P);
        toP = trim_stale(get_trace(MD(i).Traces, 'PhysicallyWalkTorsoTrace'), P);
        bdP = body_from_head(hdP, P);
        rp.behSetupStart = first_time(bdP);     % behStart_s / behEnd_s of PhysicallyWalk epochs count from here
        E = pw_period(bdP, rp.Angle, P, epochMode);
        n = numel(BP) + 1;
        RAWP{n} = bdP; RAWPH{n} = hdP; RAWPT{n} = toP;
        SERP(n) = struct('t', E.tRel, 'speed', E.speed, 'x', E.x, 'z', E.z, 'ia', E.ia, 'ic', E.ic);
        rp.StartsAtTraceStart = E.startsAtTraceStart;
        rp.behWalkStart  = E.walkStart;  rp.behWalkEnd  = E.walkEnd;  rp.WalkDur     = E.walkEnd - E.walkStart;
        rp.FullWalkStart = E.fullStart;  rp.FullWalkEnd = E.fullEnd;  rp.FullWalkDur = E.fullEnd - E.fullStart;
        rp.SteadyDur     = E.steadyEnd - E.steadyStart;
        rp.HeadMeanYaw   = mean_yaw(hdP, E.walkStart, E.walkEnd, P);
        rp.TorsoMeanYaw  = mean_yaw(toP, E.walkStart, E.walkEnd, P);
        rp.Excluded = E.excluded;
        if rp.ManualExcluded, rp.Excluded = 'manually excluded'; end
        BP = [BP; rp];
    end
end
TB = struct2table(B);
TB = derive_columns(TB, includeRejected);
TP = struct2table(BP);
TP = derive_columns(TP, includeRejected);
isRej = strcmp(TB.TrialStatus, 'REJECTED');

pos9     = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
angleOf  = arrayfun(@(k) TB.OrigAngle(find(strcmp(TB.OrigPosition, pos9{k}), 1)), 1:9);

% ---- navigation: walk patterns, reclassify / exclude, summary, final figure ----
navFcn = @(r, a) nav_period(RAW{r}, a, P, epochMode);
navYaw = @(r, E) deal(mean_yaw(RAWH{r}, E.walkStart, E.walkEnd, P), mean_yaw(RAW{r}, E.walkStart, E.walkEnd, P));
fW  = figure('Color', 'w', 'Position', [40 40 1300 1300], 'Name', 'Navigation walks');
axW = draw_walk_patterns(fW, TB, SER, P, roomLim, 'Navigation (StartPos trace)');
drawnow;
if reclassifyInteractive
    [TB, SER, RC] = reclassify_walks(fW, axW, TB, SER, RC, reclassFile, navFcn, navYaw, ...
        'Navigation (StartPos trace)', manualExclude, includeRejected, P, roomLim);
end
print_summary(TB, modeLabel, 'NAVIGATION');
print_steady(TB);
fF = draw_final_figure(TB, SER, P, false);
safe_write(fullfile(outDir, sprintf('walks_final_%s_p001.png', epochMode)), @(f) exportgraphics(fF, f, 'Resolution', 300));
safe_write(fullfile(outDir, sprintf('walks_final_%s_p001.pdf', epochMode)), @(f) exportgraphics(fF, f, 'ContentType', 'vector'));

% ---- PhysicallyWalk: the same, after picking up any navigation reclassification made above ----
pwFcn = @(r, a) pw_period(RAWP{r}, a, P, epochMode);
pwYaw = @(r, E) deal(mean_yaw(RAWPH{r}, E.walkStart, E.walkEnd, P), mean_yaw(RAWPT{r}, E.walkStart, E.walkEnd, P));
[TP, SERP] = sync_pw_labels(TP, SERP, TB, RCP, navOnlyRC, pwFcn, pwYaw);
TP = derive_columns(TP, includeRejected);
fP  = figure('Color', 'w', 'Position', [60 40 1300 1300], 'Name', 'PhysicallyWalk walks');
axP = draw_walk_patterns(fP, TP, SERP, P, roomLim, 'PhysicallyWalk (body position from the head tracker)');
drawnow;
if reclassifyInteractive
    [TP, SERP, RCP] = reclassify_walks(fP, axP, TP, SERP, RCP, reclassFilePW, pwFcn, pwYaw, ...
        'PhysicallyWalk (body position from the head tracker)', manualExclude, includeRejected, P, roomLim);
end
print_summary(TP, modeLabel, 'PHYSICALLYWALK');
print_steady(TP);
fFP = draw_final_figure(TP, SERP, P, true);
safe_write(fullfile(outDir, sprintf('walks_final_pw_%s_p001.png', epochMode)), @(f) exportgraphics(fFP, f, 'Resolution', 300));
safe_write(fullfile(outDir, sprintf('walks_final_pw_%s_p001.pdf', epochMode)), @(f) exportgraphics(fFP, f, 'ContentType', 'vector'));
isRej = strcmp(TB.TrialStatus, 'REJECTED');

if askBeforeEpoching
    reply = input('\nWalk patterns shown. Continue to MEG epoching (part 2)? [y/n]: ', 's');
    if ~strcmpi(strtrim(reply), 'y')
        fprintf('Stopped after the behavioural output. Run again and answer y to make the epochs.\n');
        return
    end
end

if isempty(which('spm'))
    error('SPM is not on the MATLAB path: addpath(''<your spm folder>'') and run again.');
end
spm('defaults', 'eeg');
if isempty(which('ft_warning'))
    addpath(fullfile(spm('Dir'), 'external', 'fieldtrip'));
    ft_defaults;
end

TB.megClose = nan(height(TB), 1);
M = struct('block', {}, 'file', {}, 'fs', {}, 'tZero', {});
for b = 1:numel(blocks)
    f = fullfile(megDir, sprintf(megFile, blocks(b)));
    D = spm_eeg_load(f);
    fs = D.fsample;

    syncData = D(D.indchannel(cfg.sync_trigger_channels), :, 1);
    [tZero, abortMarks] = detect_sync(syncData, cfg.sync_thresh, cfg.simultaneous_tol);
    if isempty(tZero), error('Block %d: no sync pulse found on the trigger channels.', blocks(b)); end

    condData = D(D.indchannel(cfg.trigger_channels), :, 1);
    on = cell(1, numel(cfg.trigger_channels));
    for c = 1:numel(cfg.trigger_channels)
        e = find(diff(condData(c, :) > cfg.sync_thresh) == 1) + 1;
        e = e(~any(abs(e(:) - abortMarks(:)') <= cfg.simultaneous_tol, 2));
        on{c} = e(:);
    end
    closeOn = on{strcmp(cfg.cond_labels, 'Close Eyes')};
    openOn  = on{strcmp(cfg.cond_labels, 'Open Eyes')};

    isPause = false(size(closeOn)); usedOpen = false(size(openOn));
    for k = 1:numel(closeOn)
        m = find(~usedOpen & abs(openOn - closeOn(k)) <= cfg.simultaneous_tol, 1);
        if ~isempty(m), isPause(k) = true; usedOpen(m) = true; end
    end
    closeOn = closeOn(~isPause); openOn = openOn(~usedOpen);

    rows = find(TB.Block == blocks(b));
    isAb = strcmp(TB.Status(rows), 'Aborted_Mid_Trial');
    if numel(closeOn) ~= numel(rows) || numel(openOn) ~= sum(~isAb)
        error(['Block %d: trigger counts do not match the behavioural attempts ', ...
            '(expected %d Close Eyes and %d Open Eyes).'], blocks(b), numel(rows), sum(~isAb));
    end
    TB.megClose(rows) = closeOn;
    M(end + 1) = struct('block', blocks(b), 'file', f, 'fs', fs, 'tZero', tZero);
end

dCE = TB.behCloseEyes - TB.behCloseStart;
closeOffset_s = median(dCE(dCE <= min(dCE) + 0.1), 'omitnan');
behCloseTrig = TB.behCloseEyes - closeOffset_s;
fit = struct('block', {}, 'a', {}, 'b', {});
for mm = 1:numel(M)
    all_ = find(TB.Block == M(mm).block);
    ok   = ~isnan(behCloseTrig(all_));
    coef = [ones(sum(ok), 1), behCloseTrig(all_(ok))] \ TB.megClose(all_(ok));
    fit(mm) = struct('block', M(mm).block, 'a', coef(1), 'b', coef(2));
end

% one epoch per walk (navigation and PhysicallyWalk), already the window for the chosen epochMode;
% both phases use the same block clock mapping (Close Eyes triggers)
rowsL = make_epoch_rows(TB, M, fit, P, epochMode);
rowsP = make_epoch_rows(TP, M, fit, P, epochMode);

EP = struct();
EP.mode = epochMode;
EP.full = struct2table(rowsL);   % navigation epochs (kept under this name for the scripts that read it)
EP.pw   = table();               % PhysicallyWalk epochs, same columns
if ~isempty(rowsP), EP.pw = struct2table(rowsP); end
EP.note = [modeLabel, '; one epoch per walk; EP.full = navigation (StartPos trace), EP.pw = PhysicallyWalk; ', ...
    'WalkDur = epoch window, FullWalkDur / fullWalkStart_s / fullWalkEnd_s = ', ...
    'the whole speed-based walking period for reference; ', ...
    'behStart_s / behEnd_s are seconds from the start of the StartPos trace (EP.full) or of the PhysicallyWalk ', ...
    'trace after its stale start frames (EP.pw); ', ...
    'begsample / endsample index the continuous file in File; ', ...
    'timeRelSyncStart_s is the epoch start relative to the sync pulse (t_zero), as timeRelSec; ', ...
    'HeadMeanYaw / TorsoMeanYaw are circular-mean yaw (deg, 0-360) over the epoch window, live tracker frames only ', ...
    '(frozen runs >= P.hold s left out; NaN if < P.minLive s of live frames). ', ...
    'PhysicallyWalk walking period: body position from the head tracker, direction = start angle + 180, ', ...
    sprintf('speed > %g m/s, walk must start within %g deg of the start position.', P.pwSpeedThr, P.startTol)];
outName = sprintf('walk_epochs_%s_p001', epochMode);   % walk_epochs_first3_p001 / _full_ / _stableyaw_
fM = safe_write(fullfile(outDir, [outName '.mat']), @(f) save_ep(f, EP));
fC = safe_write(fullfile(outDir, [outName '.csv']), @(f) writetable(struct2table(rowsL), f));
len = [rowsL.EpochLen];
fprintf('\nEpoching file saved (%s): %d navigation epochs, one per walk, %.2f-%.2f s long (mean %.2f, median %.2f s)\n   %s\n   %s\n', ...
    epochMode, numel(rowsL), min(len), max(len), mean(len), median(len), fM, fC);
if ~isempty(rowsP)
    fCP = safe_write(fullfile(outDir, sprintf('walk_epochs_%s_pw_p001.csv', epochMode)), @(f) writetable(EP.pw, f));
    len = [rowsP.EpochLen];
    fprintf('   + %d PhysicallyWalk epochs (EP.pw), %.2f-%.2f s long (mean %.2f, median %.2f s)\n   %s\n', ...
        numel(rowsP), min(len), max(len), mean(len), median(len), fCP);
end

function [T, SER, RC] = reclassify_walks(fW, axW, T, SER, RC, rcFile, periodFcn, yawFcn, ttl, manualExclude, includeRejected, P, roomLim)
% Click walks in the walk-pattern figure to move them to another angle or exclude them; changes go to rcFile.
% periodFcn(r, angle) -> walking period E for row r at that angle; yawFcn(r, E) -> [head, torso] mean yaw.
% A row is written to rcFile when the walk's label differs from T.BasePosition (navigation: the original label;
% PhysicallyWalk: the label carried over from navigation).
pos9    = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
angleOf = arrayfun(@(k) T.OrigAngle(find(strcmp(T.OrigPosition, pos9{k}), 1)), 1:9);
answer = questdlg({sprintf('%s:', ttl), 'Do you want to move any walk to a different angle,', ...
    'or leave a walk out of the analysis?', '', ...
    'Yes: click walks in the figure.  No: continue as shown.'}, ...
    'Reclassify or exclude walks', 'Yes', 'No', 'No');
while strcmp(answer, 'Yes')
    figure(fW);
    fprintf(['\n%s: click the walk you want to change in the figure.\n', ...
        'When you are done, press Enter with the figure window selected.\n'], ttl);
    [xc, yc] = ginput(1);
    if isempty(xc), break; end
    p = find(axW == gca, 1);
    if isempty(p), continue; end
    cand = find(strcmp(T.Position, pos9{p}));
    dmin = inf(size(cand));
    for q = 1:numel(cand)
        S = SER(cand(q));
        if ~isempty(S.x), dmin(q) = min(hypot(S.x - xc, S.z - yc)); end
    end
    [dBest, q] = min(dmin);
    if isempty(cand) || dBest > 0.25
        fprintf('  No walk within 0.25 m of that click in %s.\n', pos9{p});
        continue
    end
    r = cand(q);
    hSel = plot(axW(p), SER(r).x, SER(r).z, 'k-', 'LineWidth', 4); drawnow;

    if T.ManualExcluded(r), stateTxt = 'excluded by hand';
    elseif isempty(T.Excluded{r}), stateTxt = 'kept';
    else, stateTxt = ['excluded: ' T.Excluded{r}]; end
    opts = [arrayfun(@(k) sprintf('%s (%g deg)', pos9{k}, angleOf(k)), 1:9, 'UniformOutput', false), ...
        {'EXCLUDE ENTIRELY', sprintf('restore %s (no manual changes)', T.BasePosition{r}), 'cancel'}];
    sel = listdlg('PromptString', {trial_label(T, r), sprintf('labelled %s, shown under %s, %s.', T.OrigPosition{r}, T.Position{r}, ...
        stateTxt), 'New angle, or exclude:'}, 'SelectionMode', 'single', 'ListString', opts, ...
        'ListSize', [320 250]);
    delete(hSel);
    if isempty(sel) || sel == numel(opts), continue; end
    RC = RC(~(RC.Block == T.Block(r) & RC.TrialNum == T.TrialNum(r) & RC.Attempt == T.Attempt(r)), :);
    if sel == 10
        T.ManualExcluded(r) = true;
        T.Excluded{r} = 'manually excluded';
        T = derive_columns(T, includeRejected);
        fprintf('  %s: excluded entirely\n', trial_label(T, r));
        RC = [RC; cell2table({T.Block(r), T.TrialNum(r), T.Attempt(r), T.OrigPosition{r}, ...
            T.OrigAngle(r), T.Position{r}, T.Angle(r), 'exclude', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'))}, ...
            'VariableNames', RC.Properties.VariableNames)];
        save_reclass(RC, rcFile);
        axW = draw_walk_patterns(fW, T, SER, P, roomLim, ttl);
        drawnow;
        continue
    end
    if sel == 11, newPos = T.BasePosition{r}; newAng = T.BaseAngle(r);
    else, newPos = pos9{sel}; newAng = angleOf(sel); end
    T.ManualExcluded(r) = ismember(T.TrialNum(r), manualExclude);
    T.Position{r} = newPos;  T.Angle(r) = newAng;
    T.Reclassified(r) = ~strcmp(newPos, T.OrigPosition{r});
    E = periodFcn(r, newAng);
    [hy, ty] = yawFcn(r, E);                  % new walking period -> recompute yaw
    [T, SER] = set_walk(T, SER, r, E, hy, ty);
    T = derive_columns(T, includeRejected);
    if isempty(E.excluded)
        fprintf('  %s -> %s: walk kept, walking period %.2f s (one epoch)\n', trial_label(T, r), ...
            newPos, T.WalkDur(r));
    else
        fprintf('  %s -> %s: still excluded (%s)\n', trial_label(T, r), newPos, E.excluded);
    end
    if ~strcmp(newPos, T.BasePosition{r})
        RC = [RC; cell2table({T.Block(r), T.TrialNum(r), T.Attempt(r), T.OrigPosition{r}, ...
            T.OrigAngle(r), newPos, newAng, 'reclassify', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'))}, ...
            'VariableNames', RC.Properties.VariableNames)];
    end
    save_reclass(RC, rcFile);
    axW = draw_walk_patterns(fW, T, SER, P, roomLim, ttl);
    drawnow;
end
end

function [T, SER] = set_walk(T, SER, r, E, hy, ty)
% write a new walking period (and its mean yaw) into row r
T.FullWalkStart(r) = E.fullStart;  T.FullWalkEnd(r) = E.fullEnd;
T.FullWalkDur(r) = E.fullEnd - E.fullStart;
T.StartsAtTraceStart(r) = E.startsAtTraceStart;
T.behWalkStart(r) = E.walkStart;  T.behWalkEnd(r) = E.walkEnd;
T.WalkDur(r) = E.walkEnd - E.walkStart;
T.SteadyDur(r) = E.steadyEnd - E.steadyStart;
T.HeadMeanYaw(r) = hy;  T.TorsoMeanYaw(r) = ty;
T.Excluded{r} = E.excluded;
if T.ManualExcluded(r), T.Excluded{r} = 'manually excluded'; end
SER(r).ia = E.ia;  SER(r).ic = E.ic;
end

function [TP, SERP] = sync_pw_labels(TP, SERP, TB, RCP, navOnlyRC, pwFcn, pwYaw)
% Navigation reclassifications made in this run carry over to PhysicallyWalk (except navOnlyRC and walks that
% have their own PhysicallyWalk entry in RCP).
for r = 1:height(TP)
    n = find(TB.Block == TP.Block(r) & TB.TrialNum == TP.TrialNum(r) & TB.Attempt == TP.Attempt(r), 1);
    if isempty(n), continue; end
    if TB.Reclassified(n) && ~ismember([TP.Block(r) TP.TrialNum(r) TP.Attempt(r)], navOnlyRC, 'rows')
        nb = TB.Position{n}; na = TB.Angle(n);
    else
        nb = TP.OrigPosition{r}; na = TP.OrigAngle(r);
    end
    if strcmp(nb, TP.BasePosition{r}), continue; end
    TP.BasePosition{r} = nb; TP.BaseAngle(r) = na;
    if any(RCP.Block == TP.Block(r) & RCP.TrialNum == TP.TrialNum(r) & RCP.Attempt == TP.Attempt(r)), continue; end
    TP.Position{r} = nb; TP.Angle(r) = na;
    TP.Reclassified(r) = ~strcmp(nb, TP.OrigPosition{r});
    E = pwFcn(r, na);
    [hy, ty] = pwYaw(r, E);
    [TP, SERP] = set_walk(TP, SERP, r, E, hy, ty);
    fprintf('  PhysicallyWalk %s: label from navigation -> %s\n', trial_label(TP, r), nb);
end
end

function E = nav_period(sp, ang, P, mode)
% navigation walking period (StartPos torso trace) turned into this run's epoch window
E = walking_period(sp, ang, P);
E = apply_epoch_mode(E, sp, mode, P);
end

function E = pw_period(bd, ang, P, mode)
% PhysicallyWalk walking period: body trace (from the head), walking back to the centre (direction = angle + 180),
% lower speed threshold, and the walk must START at the start position
Q = P; Q.speedThr = P.pwSpeedThr;
E = walking_period(bd, mod(ang + 360, 360) - 180, Q, ang);
E = apply_epoch_mode(E, bd, mode, P);
end

function tr = body_from_head(tr, P)
% body position from the head tracker: the head point sits P.headOff m in front of the body along (yaw - P.headAng).
% Yaw is left as head yaw; frozen head frames stay identical, so they are still found as frozen.
if isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || ~isfield(tr, 'x') || ~isfield(tr, 'z'), return; end
y = double(tr.yaw(:));
tr.x = double(tr.x(:)) - P.headOff * sind(y - P.headAng);
tr.z = double(tr.z(:)) - P.headOff * cosd(y - P.headAng);
end

function tr = trim_stale(tr, P)
% start the trace after the last single-frame jump (> P.jumpThr m or > P.yawJump deg) in its first P.jumpWin s
% (the tracker holding an old pose at the start of the trace)
if isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || numel(tr.time) < 3, return; end
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

function print_steady(T)
pos9    = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
angleOf = arrayfun(@(k) T.OrigAngle(find(strcmp(T.OrigPosition, pos9{k}), 1)), 1:9);
fprintf('\nAngle-specific (steady) part vs full walking period, kept walks:\n');
fprintf('   %-4s %6s | %5s %10s %12s %10s %8s\n', 'Pos', 'angle', 'walks', 'full (s)', 'steady (s)', 'cut (s)', 'kept %');
for p = 1:9
    k = T.Use & strcmp(T.Position, pos9{p});
    if ~any(k), continue; end
    f = T.FullWalkDur(k); s = T.SteadyDur(k);
    fprintf('   %-4s %+5g%s | %5d %10.2f %12.2f %10.2f %7.0f%%\n', pos9{p}, angleOf(p), char(176), nnz(k), ...
        median(f), median(s), median(f - s), 100 * median(s ./ f));
end
f = T.FullWalkDur(T.Use); s = T.SteadyDur(T.Use);
fprintf('   All: full %.2f s, steady %.2f s, cut %.2f s (medians), %.0f%% kept\n', ...
    median(f), median(s), median(f - s), 100 * median(s ./ f));
end

function rowsL = make_epoch_rows(T, M, fit, P, epochMode)
% one epoch per walk: behWalkStart-behWalkEnd, which is already the window for the chosen epochMode
keep = find(T.Use & T.nEpochs > 0);
rowsL = [];
for r = keep'
    mm  = find([M.block] == T.Block(r));
    fs  = M(mm).fs;
    map = @(t) fit(mm).a + fit(mm).b * t;
    beg = round(map(T.behWalkStart(r)));
    fin = round(map(T.behWalkEnd(r)));
    if strcmp(epochMode, 'first3'), fin = beg + round(P.epochLen * fs) - 1; end   % exactly the same length for every walk
    x = struct('EpochMode', epochMode, 'EpochLen', (fin - beg + 1) / fs, 'WalkDur', T.WalkDur(r), ...
        'FullWalkDur', T.FullWalkDur(r), 'Block', T.Block(r), 'File', M(mm).file, ...
        'TrialNum', T.TrialNum(r), 'Attempt', T.Attempt(r), 'TrialStatus', T.TrialStatus{r}, ...
        'Position', T.Position{r}, 'Angle', T.Angle(r), ...
        'HeadMeanYaw', T.HeadMeanYaw(r), 'TorsoMeanYaw', T.TorsoMeanYaw(r), ...
        'OrigPosition', T.OrigPosition{r}, 'Reclassified', T.Reclassified(r), ...
        'DistCode', T.DistCode{r}, 'Epoch', 1, 'nEpochsInWalk', 1, ...
        'behStart_s', T.behWalkStart(r) - T.behSetupStart(r), 'behEnd_s', T.behWalkEnd(r) - T.behSetupStart(r), ...
        'fullWalkStart_s', T.FullWalkStart(r) - T.behSetupStart(r), 'fullWalkEnd_s', T.FullWalkEnd(r) - T.behSetupStart(r), ...
        'begsample', beg, 'endsample', fin, 'nSamples', fin - beg + 1, ...
        'timeRelSyncStart_s', (beg - M(mm).tZero) / fs);
    rowsL = [rowsL; x]; %#ok<AGROW>
end
end

function fF = draw_final_figure(TB, SER, P, labelAtStart)
% labelAtStart: put the angle labels at the walk start (PhysicallyWalk ends at the centre) instead of the end
if nargin < 4, labelAtStart = false; end
pos9 = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
cols = [0.031 0.188 0.420; 0.129 0.400 0.675; 0.263 0.576 0.765; 0.553 0.722 0.847; 0.302 0.302 0.302; ...
        0.910 0.627 0.498; 0.839 0.376 0.302; 0.698 0.094 0.169; 0.404 0.000 0.122];
fF = figure('Color', 'w', 'Position', [100 100 700 600]);
ax = axes(fF); hold(ax, 'on');
for k = 1:9
    kp = find(TB.Use & strcmp(TB.Position, pos9{k}));
    ends = nan(numel(kp), 2);
    for n = 1:numel(kp)
        S = SER(kp(n));
        w = S.ia:S.ic;
        plot(ax, S.x(w), S.z(w), '-', 'Color', [cols(k, :) 0.9], 'LineWidth', 2.2);   % whole walking period = the epoch
        if labelAtStart, ends(n, :) = [S.x(S.ia), S.z(S.ia)]; else, ends(n, :) = [S.x(S.ic), S.z(S.ic)]; end
    end
    if isempty(kp), continue; end
    e = median(ends, 1); e = e / norm(e) * (norm(e) + 0.22);
    a = TB.Angle(kp(1));
    if a == 0, lab = sprintf('0%s', char(176)); else, lab = sprintf('%+g%s', a, char(176)); end
    text(ax, e(1), e(2), lab, 'Color', cols(k, :) * 0.9, 'FontSize', 11, 'HorizontalAlignment', 'center');
end
plot(ax, 0, 0, 'p', 'MarkerSize', 15, 'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');
set(ax, 'XDir', 'reverse', 'Box', 'off', 'TickDir', 'out', 'FontSize', 11);
axis(ax, 'equal'); xlim(ax, [-1.9 1.9]); ylim(ax, [-2.05 0.45]);
xlabel(ax, 'x (m)'); ylabel(ax, 'z (m)');
end

function E = apply_epoch_mode(E, tr, mode, P)
% Turn the speed-based walking period into the epoch window for the chosen mode.
% E.walkStart/E.walkEnd (and E.ia/E.ic, used by the figures) become the epoch window;
% E.fullStart/E.fullEnd keep the whole walking period.
E.fullStart = E.walkStart; E.fullEnd = E.walkEnd;
if ~isempty(E.excluded), return; end
switch mode
    case 'first3'
        if E.walkEnd - E.walkStart < P.epochLen
            E.excluded = sprintf('walking period < %g s', P.epochLen); return
        end
        E.walkEnd = E.walkStart + P.epochLen;
    case 'stableyaw'
        [fa, fb] = flat_window(tr, E.walkStart, E.walkEnd, P);
        if isnan(fa), E.excluded = 'no stable-yaw stretch'; return; end
        E.walkStart = fa; E.walkEnd = fb;
end
ta = E.tRel + E.t0;
ia = find(ta >= E.walkStart - 1e-9, 1); ic = find(ta <= E.walkEnd + 1e-9, 1, 'last');
if ~isempty(ia) && ~isempty(ic), E.ia = ia; E.ic = ic; end
E.startsAtTraceStart = (E.ia == 1);
end

function [fa, fb] = flat_window(tr, a, b, P)
% Longest stretch inside a-b (trace clock) where torso yaw, unwrapped and smoothed over P.yawSmooth s,
% stays within P.yawBand deg (max - min). Same rule as setup_walk_yaw.m.
fa = NaN; fb = NaN;
if isnan(a) || isnan(b) || isempty(tr) || ~isfield(tr, 'time') || ~isfield(tr, 'yaw') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:)); y = double(tr.yaw(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z) & ~isnan(y);
t = t(ok); y = y(ok);
[t, iu] = unique(t); y = y(iu);
if numel(t) < 2, return; end
tq = (t(1):1 / P.fs:t(end))';
ys = movmean(interp1(t, rad2deg(unwrap(deg2rad(y))), tq, 'linear'), round(P.yawSmooth * P.fs));
idx = find(tq >= a & tq <= b);
if numel(idx) < 2, return; end
v = ys(idx); n = numel(v); best = -1;
for i = 1:n
    lo = v(i); hi = v(i); j = i;
    while j < n && max(hi, v(j + 1)) - min(lo, v(j + 1)) <= P.yawBand
        j = j + 1; lo = min(lo, v(j)); hi = max(hi, v(j));
    end
    if j - i > best, best = j - i; fa = tq(idx(i)); fb = tq(idx(j)); end
end
end

function f = safe_write(f, writer)
% Write with writer(f). If the file is locked (e.g. open in Excel or a PDF viewer),
% save a timestamped copy next to it instead of stopping, and say so.
try
    writer(f);
catch err
    locked = contains(lower(err.message), {'permission', 'denied', 'unable to open', 'cannot open', ...
        'could not open', 'cannot create', 'being used', 'in use'});
    if ~locked, rethrow(err); end   % a real error, not a locked file: stop and show it
    [d, n, e] = fileparts(f);
    f2 = fullfile(d, sprintf('%s_%s%s', n, char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')), e));
    writer(f2);
    warning('Could not write %s (%s)\n  -> saved as %s instead. Close the file in the other program to overwrite it next time.', ...
        f, err.message, f2);
    f = f2;
end
end

function save_ep(f, EP) %#ok<INUSD> EP is saved by name
save(f, 'EP');
end

function save_reclass(RC, f)
% The reclassification file is read back on the next run, so it must keep its name:
% if it is locked, ask for it to be closed and try again rather than saving a copy.
while true
    try
        writetable(RC, f);
        return
    catch err
        fprintf(2, '\nCould not save %s:\n  %s\n', f, err.message);
        reply = input('Close it in the other program (e.g. Excel), then press Enter to retry, or type s to skip: ', 's');
        if strcmpi(strtrim(reply), 's')
            warning('Reclassification NOT saved this time; your changes will be lost when the script ends.');
            return
        end
    end
end
end

function txt = trial_label(TB, r)
if sum(TB.TrialNum == TB.TrialNum(r)) > 1
    txt = sprintf('Trial %d (attempt %d)', TB.TrialNum(r), TB.Attempt(r));
else
    txt = sprintf('Trial %d', TB.TrialNum(r));
end
end

function RC = load_reclass(f)
vars = {'Block', 'TrialNum', 'Attempt', 'OrigPosition', 'OrigAngle', 'NewPosition', 'NewAngle', 'Action', 'Saved'};
if exist(f, 'file')
    RC = readtable(f, 'TextType', 'char', 'Delimiter', ',');
    if ~ismember('Action', RC.Properties.VariableNames)
        RC.Action = repmat({'reclassify'}, height(RC), 1);
    end
    for v = {'OrigPosition', 'NewPosition', 'Action', 'Saved'}
        if ~iscell(RC.(v{1})), RC.(v{1}) = cellstr(string(RC.(v{1}))); end
    end
    RC = RC(:, vars);
else
    RC = cell2table(cell(0, numel(vars)), 'VariableNames', vars);
    RC.Block = zeros(0, 1); RC.TrialNum = zeros(0, 1); RC.Attempt = zeros(0, 1);
    RC.OrigAngle = zeros(0, 1); RC.NewAngle = zeros(0, 1);
end
end

function TB = derive_columns(TB, includeRejected)
isRej  = strcmp(TB.TrialStatus, 'REJECTED');
walkOK = cellfun(@isempty, TB.Excluded);
TB.Use = walkOK & (~isRej | includeRejected);
TB.nEpochs = double(walkOK & isfinite(TB.WalkDur) & TB.WalkDur > 0);   % one epoch per walk: the whole walking period
end

function print_summary(TB, modeLabel, phaseName)
if nargin > 2, fprintf('\n==================== %s ====================\n', phaseName); end
pos9   = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
dcList = {'D1', 'D2', 'D3'};
deg    = @(a) strrep(sprintf('%+g%s', a, char(176)), '+0', '0');
rc = find(TB.Reclassified & cellfun(@isempty, TB.Excluded));
fprintf('\nReclassified walks (new angle):\n');
if isempty(rc), fprintf('   none\n'); end
for r = rc'
    fprintf('   %-24s %s (%s) -> %s (%s)\n', trial_label(TB, r), TB.OrigPosition{r}, ...
        deg(TB.OrigAngle(r)), TB.Position{r}, deg(TB.Angle(r)));
end
kept = find(TB.Use);
fprintf('\nEpochs available, one per walk (%s):\n', modeLabel);
fprintf('   %-4s %6s %-3s | %5s %10s %15s %9s\n', 'Pos', 'angle', 'D', 'walks', 'median (s)', 'range (s)', 'total (s)');
for p = 1:9
    for d = 1:3
        k = kept(strcmp(TB.Position(kept), pos9{p}) & strcmp(TB.DistCode(kept), dcList{d}));
        if isempty(k), continue; end
        fprintf('   %-4s %6s %-3s | %5d %10.2f %6.2f - %6.2f %9.1f\n', pos9{p}, deg(TB.Angle(k(1))), dcList{d}, ...
            numel(k), median(TB.WalkDur(k)), min(TB.WalkDur(k)), max(TB.WalkDur(k)), sum(TB.WalkDur(k)));
    end
end
fprintf('   Total: %d walks = %d epochs, %.1f s of walking (median %.2f s, range %.2f - %.2f s)\n', numel(kept), ...
    sum(TB.nEpochs(kept)), sum(TB.WalkDur(kept)), median(TB.WalkDur(kept)), min(TB.WalkDur(kept)), max(TB.WalkDur(kept)));
fprintf('   (whole walking periods of the same walks: median %.2f s, %.1f s in total)\n', median(TB.FullWalkDur(kept)), ...
    sum(TB.FullWalkDur(kept)));
end

function m = mean_yaw(tr, tA, tB, P)
% Circular-mean yaw (deg, 0-360) between tA and tB (trace clock), from live frames only.
% Runs of identical frames (x, z and yaw unchanged) lasting >= P.hold s are the tracker freezing and are left out.
% NaN if the walk was excluded or there are < P.minLive s of live frames in the window.
m = NaN;
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
yq = interp1(t, rad2deg(unwrap(deg2rad(y))), tq, 'linear');
k = tq >= tA & tq <= tB & ~gap;
if nnz(k) < P.minLive * P.fs, return; end
m = mod(atan2d(mean(sind(yq(k))), mean(cosd(yq(k)))), 360);
end

function axW = draw_walk_patterns(fW, TB, SER, P, roomLim, ttl)
clf(fW);
pos9   = arrayfun(@(k) sprintf('A%d', k), 1:9, 'UniformOutput', false);
dcList = {'D1', 'D2', 'D3'};
dCol   = [0.11 0.62 0.47; 0.85 0.37 0.01; 0.46 0.44 0.70];
red    = [0.85 0 0];  mag = [0.80 0 0.80];
isRej  = strcmp(TB.TrialStatus, 'REJECTED');
walkOK = cellfun(@isempty, TB.Excluded);
kept   = find(TB.Use);
tlW = tiledlayout(fW, 3, 3, 'TileSpacing', 'compact');
if nargin > 5, title(tlW, ttl, 'FontWeight', 'bold'); end
axW = gobjects(1, 9);
for p = 1:9
    axW(p) = nexttile(tlW); hold on; box on; axis equal;
    kp = kept(strcmp(TB.Position(kept), pos9{p}));
    for r = kp'
        c = dCol(strcmp(dcList, TB.DistCode{r}), :);
        ls = '-'; if isRej(r), ls = '--'; end
        S = SER(r); X = S.x; Y = S.z;
        if TB.Reclassified(r), plot(X, Y, '-', 'Color', mag, 'LineWidth', 1.5);
        else, plot(X, Y, '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 1); end
        plot(X(S.ia:S.ic), Y(S.ia:S.ic), ls, 'Color', c, 'LineWidth', 3.5);       % whole walking period = the epoch
        plot(X(S.ia), Y(S.ia), 'o', 'MarkerFaceColor', c, 'MarkerEdgeColor', 'k', 'MarkerSize', 6);
        plot(X(S.ic), Y(S.ic), 's', 'MarkerFaceColor', 'w', 'MarkerEdgeColor', c, 'MarkerSize', 6, 'LineWidth', 1.5);
    end
    km = find(TB.ManualExcluded & strcmp(TB.Position, pos9{p}));
    labsM = {};
    for r = km'
        S = SER(r);
        labsM{end + 1} = ['excluded by hand: ' trial_label(TB, r)];
        if isempty(S.x), continue; end
        plot(S.x, S.z, ':', 'Color', [0 0 0], 'LineWidth', 2);
        plot(S.x(end), S.z(end), 'x', 'Color', [0 0 0], 'MarkerSize', 9, 'LineWidth', 2);
    end
    if ~isempty(labsM)
        text(0.98, 0.97, strjoin(labsM, newline), 'Units', 'normalized', 'Color', [0 0 0], 'FontSize', 8, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
    end
    kx = find(~walkOK & ~TB.ManualExcluded & strcmp(TB.Position, pos9{p}));
    labs = {};
    for r = kx'
        S = SER(r);
        labs{end + 1} = ['excluded: ' trial_label(TB, r)];
        if isempty(S.x), continue; end
        plot(S.x, S.z, '-', 'Color', red, 'LineWidth', 2);
        plot(S.x(end), S.z(end), 'x', 'Color', red, 'MarkerSize', 9, 'LineWidth', 2);
    end
    kr = find(TB.Reclassified & walkOK & strcmp(TB.Position, pos9{p}));
    labsR = arrayfun(@(r) sprintf('reclassified: %s (from %s)', trial_label(TB, r), TB.OrigPosition{r}), ...
        kr, 'UniformOutput', false);
    if ~isempty(labs)
        text(0.98, 0.03, strjoin(labs, newline), 'Units', 'normalized', 'Color', red, 'FontSize', 8, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
    end
    if ~isempty(labsR)
        text(0.02, 0.03, strjoin(labsR, newline), 'Units', 'normalized', 'Color', mag, 'FontSize', 8, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom');
    end
    plot(0, 0, 'k*', 'MarkerSize', 14, 'LineWidth', 1.5);
    set(gca, 'XDir', 'reverse'); grid on; xlim(roomLim); ylim(roomLim);
    angP = TB.OrigAngle(find(strcmp(TB.OrigPosition, pos9{p}), 1));
    title(sprintf('%s (%g%s): %d walks (%d rej.), median %.1f s, %d excluded', pos9{p}, angP, char(176), ...
        numel(kp), sum(isRej(kp)), median(TB.WalkDur(kp)), numel(kx) + numel(km)));
    if mod(p - 1, 3) == 0, ylabel('Room Z Position (Meters)'); end
    if p > 6, xlabel('Room X Position (Meters)'); end
end
hL = gobjects(1, 11);
for d = 1:3, hL(d) = plot(axW(1), NaN, NaN, '-', 'Color', dCol(d, :), 'LineWidth', 3.5); end
hL(4)  = plot(axW(1), NaN, NaN, '-', 'Color', [0.4 0.4 0.4], 'LineWidth', 3.5);
hL(5)  = plot(axW(1), NaN, NaN, 'o', 'MarkerFaceColor', [0.4 0.4 0.4], 'MarkerEdgeColor', 'k', 'MarkerSize', 6);
hL(6)  = plot(axW(1), NaN, NaN, '-', 'Color', [0.82 0.82 0.82], 'LineWidth', 1);
hL(7)  = plot(axW(1), NaN, NaN, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 2);
hL(8)  = plot(axW(1), NaN, NaN, '-', 'Color', red, 'LineWidth', 2);
hL(9)  = plot(axW(1), NaN, NaN, ':', 'Color', [0 0 0], 'LineWidth', 2);
hL(10) = plot(axW(1), NaN, NaN, '-', 'Color', mag, 'LineWidth', 1.5);
hL(11) = plot(axW(1), NaN, NaN, 'k*', 'MarkerSize', 10, 'LineWidth', 1.5);
lg = legend(axW(1), hL, {'D1 (1.00 m)', 'D2 (1.25 m)', 'D3 (1.50 m)', 'epoch window', ...
    'walk start (square = end)', 'whole trace', 'rejected attempt', 'excluded (walk criteria)', ...
    'excluded by hand', 'reclassified', 'room centre'}, ...
    'Orientation', 'horizontal', 'NumColumns', 6, 'FontSize', 9);
lg.Layout.Tile = 'south';
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

function E = walking_period(tr, label, P, startAngle)
% startAngle given (PhysicallyWalk): the walk must START within P.startTol of that angle; otherwise (navigation)
% it must END within P.endTol of label
if nargin < 4, startAngle = []; end
E = struct('walkStart', NaN, 'walkEnd', NaN, 'steadyStart', NaN, 'steadyEnd', NaN, 'excluded', 'no walk recording', ...
    'tRel', [], 'speed', [], 'x', [], 'z', [], 'ia', NaN, 'ic', NaN, 'startsAtTraceStart', false, 't0', NaN);
if isempty(tr) || ~isfield(tr, 'time') || numel(tr.time) < 2, return; end
t = double(tr.time(:)); x = double(tr.x(:)); z = double(tr.z(:));
ok = ~isnan(t) & ~isnan(x) & ~isnan(z);
[t, iu] = unique(t(ok)); x = x(ok); z = z(ok); x = x(iu); z = z(iu);
if numel(t) < 2, return; end
fs = P.fs;
tu = (t(1):1/fs:t(end))';
E.t0 = tu(1);
xs = movmean(interp1(t, x, tu), round(P.smoothWin * fs));
zs = movmean(interp1(t, z, tu), round(P.smoothWin * fs));
vx = gradient(xs, 1 / fs); vz = gradient(zs, 1 / fs);
spd = hypot(vx, vz);
E.tRel = (tu - tu(1))'; E.speed = spd'; E.x = xs'; E.z = zs';
wd = round(P.dirWin * fs);
dirErr = mod(atan2d(movmean(vx, wd), -movmean(vz, wd)) - label + 180, 360) - 180;
steady = spd > P.speedThr & abs(dirErr) <= P.dirTol;
steady = bridge_gaps(steady, round(P.bridge * fs));
[len, i1, i2] = longest_run(steady);
if len == 0, E.excluded = 'no steady walk'; return; end
if (i2 - i1) / fs - 2 * P.trim < P.chunk
    E.excluded = 'steady walk < 1 s after trimming'; return
end
if isempty(startAngle)
    endAngle = atan2d(x(end), -z(end));
    if abs(mod(endAngle - label + 180, 360) - 180) > P.endTol
        E.excluded = sprintf('ends > %g deg from start position', P.endTol); return
    end
else
    begAngle = atan2d(x(1), -z(1));
    if abs(mod(begAngle - startAngle + 180, 360) - 180) > P.startTol
        E.excluded = sprintf('starts > %g deg from start position', P.startTol); return
    end
end
thr = P.plateauFrac * median(spd(i1:i2));
a = i1; while a > 1 && spd(a - 1) > thr, a = a - 1; end
c = i2; while c < numel(spd) && spd(c + 1) > thr, c = c + 1; end
E.walkStart = tu(a);
E.walkEnd   = tu(c);
E.ia = a; E.ic = c;
E.steadyStart = tu(i1); E.steadyEnd = tu(i2);
E.startsAtTraceStart = (a == 1);
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

function [tZero, abortMarks] = detect_sync(trig, thresh, tol)
edges = [];
for c = 1:size(trig, 1)
    on = find(diff(trig(c, :) > thresh) == 1) + 1;
    edges = [edges; on(:), repmat(c, numel(on), 1)];
end
tZero = []; abortMarks = [];
if isempty(edges), return; end
edges = sortrows(edges, 1);
rise = [];
i = 1;
while i <= size(edges, 1)
    j = i;
    while j < size(edges, 1) && edges(j + 1, 1) - edges(i, 1) <= tol, j = j + 1; end
    if numel(unique(edges(i:j, 2))) >= size(trig, 1), rise(end + 1) = round(mean(edges(i:j, 1))); end
    i = j + 1;
end
if isempty(rise), return; end
tZero = rise(1);
abortMarks = rise(2:end);
end
