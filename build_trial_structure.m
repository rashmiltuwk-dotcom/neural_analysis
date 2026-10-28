function [trl, conditionlabels, trial_status, trial_meta, timeRelSec, t_zero, trial_end_samples, audio_events, navigation_events] = ...
    build_trial_structure(D, lvmFile, cfg)
% BUILD_TRIAL_STRUCTURE  Aligns trigger channels with behavioral metadata
% to produce everything spm_eeg_epochs and the event-attachment step need.
%
% UPDATED: MasterData is found in cfg.behav_root (not cfg.root), and the
% subject / block numbers are read from the filename however they are
% written (P1_1_..., P001_1_..., P_001_001_..., p01-02_...,
% Participant_1_3_...) and compared as NUMBERS, so 'P1' and 'p001' both
% mean subject 1.
%
% UPDATED: trial_meta now also carries Position (taken as-is from
% MasterData).
%
% AUDIO: audio response events. MEASURED on the 21-10-2026 session:
% the audio response is T2 + T10 (+ T3) rising together, ~81-166 ms wide,
% 3 per trial (end of T6, end of T9, just before Open Eyes). T3 fires
% alongside EVERY trigger, so "nothing else fired" is checked against the
% PHASE channels only (cfg.trigger_channels minus T2/T10 = T5 T8 T6 T9 T7).
% This still excludes the sync pulse and redo/abort pulses, which fire
% every phase channel at once.
%   - Section 4A finds them and removes them from the phase events, so
%     they never affect pause detection, trial pairing or phase durations.
%   - Section 7 records each trial's start/end/status (trial_spans).
%   - Section 10A returns them as a separate list (audio_events), each
%     tagged with the trial it falls in. NOT added to trl.
%   Use the ONSET (sample) as the event time — the pulse width reflects
%   task-code timing jitter, not the sound itself.
%
% NAVIGATION: after each trial's Open Eyes, analogue A1 or A2 pulses
% (~4.2 V, ~2 s after Open Eyes). The END of that pulse (switch-off)
% marks the START of navigation, which lasts until the next Close Eyes.
% If more than one A1/A2 pulse falls in the same gap, cfg.nav_pulse_pick
% ('first' or 'last') decides which is used. Section 10B returns these as
% a separate list (navigation_events). NOT added to trl.
%
% CHANGED: Close Eyes / Open Eyes count mismatches are no longer always
% a hard error, and are no longer resolved by POSITION (e.g. "assume
% it's the last trigger") — MasterData carries its own ground truth for
% this via a Status field, which can read 'Aborted_Mid_Trial' for a
% trial attempt that was started (Close Eyes fired) but never properly
% closed out (Open Eyes never fired). CONFIRMED directly from real
% MasterData: a trial can appear TWICE (same TrialNum, different
% Attempt) — once as 'Aborted_Mid_Trial', once as 'Accepted' — and the
% aborted attempt can sit ANYWHERE in the recording, not just at the
% end (confirmed: Trial 5 Attempt 1 = Aborted_Mid_Trial, Attempt 2 =
% Accepted, followed by Trials 6/7/8 afterward).
%
% This version:
%   1. Counts how many MasterData rows have Status == 'Aborted_Mid_Trial'.
%   2. Requires the Close/Open Eyes count mismatch to EXACTLY equal that
%      number — if it doesn't, still errors loudly (something else,
%      unexplained by known aborts, is going on; do not guess).
%   3. Walks MasterData row by row IN ORDER, consuming one Close Eyes
%      (+ matching Open Eyes, unless this row is Aborted_Mid_Trial) per
%      row — using MasterData's own sequence as ground truth for which
%      close/open pairs go together, rather than assuming counts match
%      1:1 by position.
%   4. For an Aborted_Mid_Trial row: everything from that lone Close
%      Eyes up to (not including) the NEXT Close Eyes trigger is marked
%      'REJECTED' with that row's metadata — i.e. whatever partial
%      activity happened before the abort is excluded from analysis,
%      consistent with how genuine mid-trial aborts (detected via
%      abort_markers) are already handled elsewhere in this function.
%
% Outputs:
%   trl              - Nx3 matrix for spm_eeg_epochs
%   conditionlabels  - Nx1 cell array: plain condition name, or 'PAUSED'
%   trial_status     - Nx1 cell array: 'ACCEPTED' / 'REJECTED' / 'PAUSED'
%   trial_meta       - Nx1 struct array: TrialNum/TaskType/Direction/
%                       Quadrant/Distance/Position (NaN/'' for PAUSED rows)
%   timeRelSec       - Nx1 double: (onset_sample - t_zero) / fs
%   t_zero           - sample index of the sync pulse
%   trial_end_samples - Nx1 double: the REAL per-trial end sample (the
%                        actual Open Eyes trigger onset for the trial
%                        each event belongs to) — NOT a fixed nominal
%                        window boundary. NaN for events belonging to
%                        REJECTED (aborted-mid-trial) trials, which
%                        have no real end. Added specifically to
%                        support event-locking to something that
%                        happens at variable, trial-specific timing
%                        (e.g. an auditory cue at trial end) rather
%                        than assuming every trial took exactly
%                        cfg.epoch_win(2) ms.
%   audio_events     - AUDIO: 1xM struct array, one per audio response:
%                       sample      - onset sample in the continuous data
%                       timeRelSec  - (sample - t_zero) / fs
%                       width_ms    - [T2 T10] pulse widths in ms
%                       status      - 'ACCEPTED' / 'REJECTED' /
%                                     'OUTSIDE_TRIAL' (status of the
%                                     Close->Open trial it falls in)
%                       TrialNum, TaskType, Direction, Quadrant, Distance,
%                       Position    - that trial's metadata
%   navigation_events - NAVIGATION: 1xK struct array, one per navigation
%                       period:
%                       startSample  - END of the A1/A2 pulse
%                       endSample    - next Close Eyes onset (NaN after
%                                      the last trial)
%                       startRelSec, endRelSec - relative to t_zero
%                       duration_s   - (endSample - startSample) / fs
%                       channel      - 'A1' or 'A2'
%                       prevTrialNum, prevStatus - the trial it follows
%                       nextTrialNum - the trial it leads into
%   The caller must request outputs 8 and 9 (and save them) for them to
%   be kept.

fs = D.fsample;

%% 1. Determine subject AND block number from the .lvm filename
[subj, blockNum] = parse_subject_block(lvmFile);

%% 2. Locate and load the MasterData file for this SUBJECT and BLOCK
%% UPDATED: looks in cfg.behav_root, and reads subject + block NUMBERS
%% from the start of the filename however they are written, then
%% compares them as numbers.
masterDataFiles = dir(fullfile(cfg.behav_root, cfg.master_data_pattern));
subjNum = str2double(regexp(subj, '\d+', 'match', 'once'));   % 'p001' -> 1

namePattern = '^[Pp](?:articipant)?[_\- ]?(\d+)[_\- ](\d+)(?:[_\- ]|$)';
matchIdx = [];
for f = 1:length(masterDataFiles)
    tok = regexp(masterDataFiles(f).name, namePattern, 'tokens', 'once');
    if isempty(tok), continue, end                % filename not in a P<subj>_<block> form
    fileSubj  = str2double(tok{1});
    fileBlock = str2double(tok{2});
    if fileSubj == subjNum && fileBlock == blockNum
        matchIdx(end+1) = f; %#ok<AGROW>
    end
end

if isempty(matchIdx)
    error('build_trial_structure:noMasterData', ...
        'No MasterData file found for subject ''%s'', block %d in %s.', subj, blockNum, cfg.behav_root);
elseif numel(matchIdx) > 1
    error('build_trial_structure:ambiguousMasterData', ...
        'Multiple MasterData files found for block %d: %s', blockNum, ...
        strjoin({masterDataFiles(matchIdx).name}, ', '));
end

masterDataFile = fullfile(cfg.behav_root, masterDataFiles(matchIdx).name);
loaded = load(masterDataFile);
MasterData = loaded.MasterData;
n_trials_meta = numel(MasterData);

%% 2A. NEW: identify aborted-mid-trial attempts from MasterData's own
%% Status field — these are EXPECTED to have no matching Open Eyes.
isAborted = arrayfun(@(m) strcmpi(m.Status, 'Aborted_Mid_Trial'), MasterData);
n_aborted_meta = sum(isAborted);

if n_aborted_meta > 0
    fprintf(['MasterData reports %d aborted-mid-trial attempt(s) ' ...
        '(TrialNum: %s) — these are expected to have a Close Eyes ' ...
        'trigger with no matching Open Eyes.\n'], ...
        n_aborted_meta, mat2str([MasterData(isAborted).TrialNum]));
end

%% 3. Establish t_zero AND genuine abort/redo markers
chan_idx_sync = D.indchannel(cfg.sync_trigger_channels);
trig_data_sync = D(chan_idx_sync, :, 1);

[t_zero, real_abort_markers] = detectAllTriggersSync(trig_data_sync, cfg.sync_thresh, cfg.simultaneous_tol);

if isempty(t_zero)
    error('build_trial_structure:noSyncPulse', ...
        'No all-triggers sync pulse detected. Recording system may not have been running.');
end

%% 4. Detect individual condition-trigger events (7-channel list)
chan_idx_cond = D.indchannel(cfg.trigger_channels);
trig_data_cond = D(chan_idx_cond, :, 1);

all_events = [];
for c = 1:length(cfg.trigger_channels)
    is_high = trig_data_cond(c, :) > cfg.sync_thresh;
    onsets = find(diff(is_high) == 1) + 1;
    for k = 1:length(onsets)
        all_events = [all_events; onsets(k), c]; %#ok<AGROW>
    end
end
[~, sort_idx] = sort(all_events(:, 1));
all_events = all_events(sort_idx, :);

%% 4A. AUDIO: audio response = T2 + T10 rising together, with NO other
%% PHASE channel (T5 T8 T6 T9 T7) rising at the same moment. T3 is NOT
%% checked — it fires with every trigger. The sync pulse and redo/abort
%% pulses fire every phase channel at once, so they are still excluded.
%% Removed from the phase events here; returned separately in 10A.

% T2 / T10 on-off, and their switch-on / switch-off samples
hiA = D(D.indchannel(cfg.audio_channels{1}), :, 1) > cfg.sync_thresh;   % T2
hiB = D(D.indchannel(cfg.audio_channels{2}), :, 1) > cfg.sync_thresh;   % T10
onA = find(diff(hiA) == 1) + 1;   offA = find(diff(hiA) == -1) + 1;
onB = find(diff(hiB) == 1) + 1;   offB = find(diff(hiB) == -1) + 1;

% switch-on samples of every other PHASE channel (UPDATED: was the sync
% list, which includes T3 and so rejected every audio pulse)
otherChans = setdiff(cfg.trigger_channels, cfg.audio_channels);   % T5 T8 T6 T9 T7
otherOn = [];
for c = 1:numel(otherChans)
    hiO = D(D.indchannel(otherChans{c}), :, 1) > cfg.sync_thresh;
    otherOn = [otherOn, find(diff(hiO) == 1) + 1]; %#ok<AGROW>
end

% positions of T2 / T10 in all_events(:,2)
chanA = find(strcmp(cfg.trigger_channels, cfg.audio_channels{1}));
chanB = find(strcmp(cfg.trigger_channels, cfg.audio_channels{2}));

audio_samples  = [];
audio_width_ms = [];
audio_drop     = [];
for i = 1:numel(onA)
    % check 1: T10 switched on at the same moment? (no -> phase trigger, keep)
    j = find(abs(onB - onA(i)) <= cfg.simultaneous_tol, 1);
    if isempty(j), continue, end
    % check 2: any other PHASE channel switched on too? (yes -> sync/redo, keep)
    if any(abs(otherOn - onA(i)) <= cfg.simultaneous_tol), continue, end
    % check 3: both switch off again? (no -> still high at end of recording, skip)
    fA = offA(find(offA > onA(i), 1));
    fB = offB(find(offB > onB(j), 1));
    if isempty(fA) || isempty(fB), continue, end

    % passed all three -> audio response
    audio_samples(end+1, 1)  = min(onA(i), onB(j));                        %#ok<AGROW>
    audio_width_ms(end+1, :) = [(fA - onA(i)) (fB - onB(j))] / fs * 1000;  %#ok<AGROW>

    % mark BOTH onsets for removal from the phase-event list
    audio_drop = [audio_drop; ...
        find(all_events(:,2) == chanA & abs(all_events(:,1) - onA(i)) <= cfg.simultaneous_tol); ...
        find(all_events(:,2) == chanB & abs(all_events(:,1) - onB(j)) <= cfg.simultaneous_tol)]; %#ok<AGROW>
end
all_events(unique(audio_drop), :) = [];

if ~isempty(audio_width_ms)
    badW = any(abs(audio_width_ms - cfg.audio_pulse_ms) > cfg.audio_pulse_tol_ms, 2);
    if any(badW)
        warning('build_trial_structure:audioPulseWidth', ...
            '%d of %d audio pulses are outside %d +/- %d ms (widths [T2 T10] ms: %s).', ...
            sum(badW), numel(badW), cfg.audio_pulse_ms, cfg.audio_pulse_tol_ms, ...
            mat2str(round(audio_width_ms(badW, :))));
    end
end
fprintf('Audio responses detected: %d\n', numel(audio_samples));

%% 5. Remove artifact duplicates caused by GENUINE abort/redo pulses only
filtered_events = [];
for i = 1:size(all_events, 1)
    sample = all_events(i, 1);
    is_artifact = any(abs(real_abort_markers - sample) <= cfg.simultaneous_tol);
    if ~is_artifact
        filtered_events = [filtered_events; all_events(i, :)]; %#ok<AGROW>
    end
end
valid_events = filtered_events;
abort_markers = real_abort_markers;

%% 6. Find Close/Open Eyes coincidences (simultaneous firing — PAUSE
%% markers) — cross-matched, not sequential. Counts are NOT required to
%% be equal up front any more — see Section 6A.
CLOSE_EYES_ID = find(strcmp(cfg.cond_labels, 'Close Eyes'));
OPEN_EYES_ID  = find(strcmp(cfg.cond_labels, 'Open Eyes'));

close_idx = find(valid_events(:, 2) == CLOSE_EYES_ID);
open_idx  = find(valid_events(:, 2) == OPEN_EYES_ID);

%% 6A. NEW: validate the count mismatch is EXACTLY explained by known
%% aborted-mid-trial attempts from MasterData — error otherwise.
countDiff = length(close_idx) - length(open_idx);
if countDiff ~= n_aborted_meta
    error('build_trial_structure:unexplainedMismatch', ...
        ['Found %d Close Eyes triggers but %d Open Eyes triggers ' ...
         '(difference of %d), but MasterData reports %d aborted-mid-' ...
         'trial attempt(s). These numbers should match exactly. ' ...
         'Cannot safely determine which trigger(s) are unpaired — ' ...
         'investigate directly rather than guessing.'], ...
        length(close_idx), length(open_idx), countDiff, n_aborted_meta);
end

close_onsets = valid_events(close_idx, 1);
open_onsets  = valid_events(open_idx, 1);

close_consumed = false(length(close_onsets), 1);
open_consumed  = false(length(open_onsets), 1);

trial_status = cell(size(valid_events, 1), 1);
trial_meta = repmat(struct('TrialNum',[],'TaskType','','Direction','','Quadrant','','Distance',[],'Position',[]), ...
                     size(valid_events, 1), 1);
trial_end_samples = nan(size(valid_events, 1), 1);

remove_rows = [];
n_pause = 0;
n_realign_dropped = 0;

%% Coincidence (PAUSE marker) detection — unchanged logic, now looping
%% over close_onsets alone (length need not match open_onsets' length)
for ci = 1:length(close_onsets)
    if close_consumed(ci), continue; end
    match = find(~open_consumed & abs(open_onsets - close_onsets(ci)) <= cfg.simultaneous_tol, 1);
    if ~isempty(match)
        close_consumed(ci)   = true;
        open_consumed(match) = true;

        coincidence_sample = round((close_onsets(ci) + open_onsets(match)) / 2);
        span_lo = min(close_onsets(ci), open_onsets(match));
        span_hi = max(close_onsets(ci), open_onsets(match));
        in_span = find(valid_events(:,1) >= span_lo & valid_events(:,1) <= span_hi);

        if abs(coincidence_sample - t_zero) <= cfg.simultaneous_tol
            remove_rows = [remove_rows; in_span]; %#ok<AGROW>
            n_realign_dropped = n_realign_dropped + numel(in_span);
        else
            n_pause = n_pause + 1;
            meta = struct('TrialNum', NaN, 'TaskType', 'PAUSED', 'Direction', '', ...
                'Quadrant', '', 'Distance', NaN, 'Position', NaN);

            % FIXED: a genuine pause/redo can cause MULTIPLE trigger
            % channels to fire simultaneously (all within
            % cfg.simultaneous_tol of each other) — CONFIRMED directly:
            % a real block showed 6 separate 'PAUSED' entries all
            % sharing the exact same timestamp, which is one physical
            % pause event, not six. Now keeps only ONE representative
            % row (the first, chronologically) as the actual PAUSED
            % marker, and drops the rest of the simultaneous duplicates
            % entirely — same mechanism already used for realign
            % cleanup, applied here to prevent inflating the pause
            % count with duplicate near-identical epochs.
            keepRow = in_span(1);
            dropRows = in_span(2:end);

            trial_status{keepRow} = 'PAUSED';
            trial_meta(keepRow)   = meta;
            if ~isempty(dropRows)
                remove_rows = [remove_rows; dropRows]; %#ok<AGROW>
            end

            pre_idx = find(valid_events(:,1) < span_lo);
            if ~isempty(pre_idx)
                pre_idx  = pre_idx(end);
                pre_chan = valid_events(pre_idx, 2);
                post_idx = find(valid_events(:,1) > span_hi & valid_events(:,2) == pre_chan, 1, 'first');
                if ~isempty(post_idx)
                    remove_rows = [remove_rows; pre_idx]; %#ok<AGROW>
                end
            end
        end
    end
end

real_close_pos = find(~close_consumed);
real_open_pos  = find(~open_consumed);

if length(real_close_pos) - length(real_open_pos) ~= n_aborted_meta
    error('build_trial_structure:mispaired', ...
        ['After removing %d pause/realign coincidences, found %d remaining ' ...
         'Close Eyes but %d remaining Open Eyes — difference no longer ' ...
         'matches MasterData''s %d aborted-mid-trial attempt(s).'], ...
        n_pause + 1, length(real_close_pos), length(real_open_pos), n_aborted_meta);
end

%% 7. Walk MasterData row by row, IN ORDER — this is the ground truth
%% for which close (and, unless aborted, which open) belongs to which
%% row, rather than assuming a simple 1:1-by-position correspondence.
%%
%% NEW: also tracks a PER-TRIAL Stationary occurrence counter, so
%% Section 10 can label each Stationary event as 'Stationary1',
%% 'Stationary2', etc. — which occurrence NUMBER it is WITHIN that
%% specific trial (resets to 1 at the start of every trial), rather
%% than lumping all Stationary periods under one plain label.
STATIONARY_ID = find(strcmp(cfg.cond_labels, 'Stationary'));
stationary_occurrence = zeros(size(valid_events, 1), 1);

% AUDIO / NAVIGATION: each trial's span, used by Sections 10A and 10B:
% [start_samp (Close Eyes), end_samp (Open Eyes, or next Close Eyes if
%  aborted), MasterData row k, isRejected]
trial_spans = zeros(0, 4);

closePtr = 1;
openPtr  = 1;

for k = 1:n_trials_meta
    if isAborted(k)
        %% Aborted-mid-trial: ONE close, NO matching open.
        ci = real_close_pos(closePtr);
        closePtr = closePtr + 1;
        trial_start_samp = close_onsets(ci);

        % Bound the rejected span at the NEXT real close trigger (or end
        % of recording, if this was the last attempt overall) — this
        % captures whatever partial activity happened before the abort.
        if closePtr <= length(real_close_pos)
            next_close_samp = close_onsets(real_close_pos(closePtr));
        else
            next_close_samp = Inf;
        end

        in_trial = find(valid_events(:,1) >= trial_start_samp & valid_events(:,1) < next_close_samp);
        already_labeled = ~cellfun(@isempty, trial_status(in_trial));
        in_trial_unlabeled = in_trial(~already_labeled);

        meta = buildTrialMeta(MasterData, k);
        [trial_status{in_trial_unlabeled}] = deal('REJECTED');
        [trial_meta(in_trial_unlabeled)]   = deal(meta);

        trial_spans(end+1, :) = [trial_start_samp, next_close_samp, k, 1]; % AUDIO / NAVIGATION

        % NEW: number Stationary occurrences within this trial's span
        statInTrial = in_trial(valid_events(in_trial, 2) == STATIONARY_ID);
        stationary_occurrence(statInTrial) = 1:numel(statInTrial);

    else
        %% Normal trial: one close, one open.
        ci = real_close_pos(closePtr);
        oi = real_open_pos(openPtr);
        closePtr = closePtr + 1;
        openPtr  = openPtr + 1;

        trial_start_samp = close_onsets(ci);
        trial_end_samp   = open_onsets(oi);

        if trial_end_samp <= trial_start_samp
            error('build_trial_structure:badTrialOrder', ...
                ['Open Eyes at sample %d precedes its Close Eyes at sample ' ...
                 '%d, for MasterData row %d (TrialNum %g, Attempt %g).'], ...
                trial_end_samp, trial_start_samp, k, MasterData(k).TrialNum, MasterData(k).Attempt);
        end

        in_trial = find(valid_events(:, 1) >= trial_start_samp & valid_events(:, 1) <= trial_end_samp);
        already_labeled = ~cellfun(@isempty, trial_status(in_trial));
        in_trial_unlabeled = in_trial(~already_labeled);

        was_aborted = any(abort_markers > trial_start_samp & abort_markers < trial_end_samp);
        status_label = 'ACCEPTED';
        if was_aborted, status_label = 'REJECTED'; end
        meta = buildTrialMeta(MasterData, k);

        [trial_status{in_trial_unlabeled}] = deal(status_label);
        [trial_meta(in_trial_unlabeled)]   = deal(meta);

        trial_spans(end+1, :) = [trial_start_samp, trial_end_samp, k, double(was_aborted)]; % AUDIO / NAVIGATION

        % NEW: number Stationary occurrences within this trial's span
        statInTrial = in_trial(valid_events(in_trial, 2) == STATIONARY_ID);
        stationary_occurrence(statInTrial) = 1:numel(statInTrial);
    end
end

if closePtr - 1 ~= length(real_close_pos) || openPtr - 1 ~= length(real_open_pos)
    error('build_trial_structure:unconsumedTriggers', ...
        ['After walking all %d MasterData rows, %d of %d real Close Eyes ' ...
         'and %d of %d real Open Eyes triggers were consumed — expected ' ...
         'ALL of them to be consumed exactly once. Investigate before ' ...
         'trusting this run''s output.'], ...
        n_trials_meta, closePtr-1, length(real_close_pos), openPtr-1, length(real_open_pos));
end

%% 8. Drop realign rows AND pre-pause (interrupted) rows entirely
%
% FIXED: stationary_occurrence must be pruned ALONGSIDE valid_events/
% trial_status/trial_meta here — CONFIRMED this was a real bug: without
% this, indices shift after pruning but stationary_occurrence kept its
% OLD indexing, so Section 10 checked the wrong position entirely and
% every Stationary event silently fell through to the unnumbered label.
if ~isempty(remove_rows)
    remove_rows = unique(remove_rows);
    valid_events(remove_rows, :) = [];
    trial_status(remove_rows)    = [];
    trial_meta(remove_rows)      = [];
    stationary_occurrence(remove_rows) = [];
    trial_end_samples(remove_rows) = [];
end

if any(cellfun(@isempty, trial_status))
    n_orphan = sum(cellfun(@isempty, trial_status));
    error('build_trial_structure:orphanEvents', ...
        '%d trigger event(s) got no status assigned.', n_orphan);
end

%% 9. t_zero subtraction, per event
timeRelSec = (valid_events(:,1) - t_zero) / fs;

%% 10. Build trl and conditionlabels
%
% NEW: Stationary events are now labeled 'Stationary1', 'Stationary2',
% etc. — which occurrence WITHIN THAT TRIAL this is (resets per trial,
% via stationary_occurrence computed in Section 7) — instead of a flat
% 'Stationary' label for every occurrence regardless of position.
pre_trig_samp  = round((cfg.epoch_win(1) / 1000) * fs);
post_trig_samp = round((cfg.epoch_win(2) / 1000) * fs);

trl = [];
conditionlabels = {};

% CORRECTED: trial_end_samples (initialized earlier as all-NaN) is
% computed HERE, not per-trial-via-Open-Eyes as an earlier version
% did. cfg.cond_labels are SEQUENTIAL PHASES within one long
% Close-Eyes-to-Open-Eyes trial (confirmed: trials averaged ~37s,
% matching a whole multi-phase sequence, not one ~3s phase) — so the
% real end of a specific phase (e.g. Physical Walk) is the onset of
% the NEXT phase transition, NOT the eventual Open Eyes trigger for
% the whole trial. valid_events is chronologically sorted, so "next
% row's onset" IS "next phase's onset" directly.
for i = 1:size(valid_events, 1) - 1
    trial_end_samples(i) = valid_events(i+1, 1);
end
% Last event overall has no following event — leave as NaN (matches
% the pre-existing initialization). Not expected to affect the
% auditory "stop" analysis, since Physical Walk / Encoding Rot are
% never the final phase before Open Eyes in cfg.cond_labels.

for i = 1:size(valid_events, 1)
    onset   = valid_events(i, 1);
    cond_id = valid_events(i, 2);
    trl(end+1, :) = [onset + pre_trig_samp, onset + post_trig_samp, pre_trig_samp]; %#ok<AGROW>
    if strcmp(trial_status{i}, 'PAUSED')
        conditionlabels{end+1} = 'PAUSED'; %#ok<AGROW>
    elseif cond_id == STATIONARY_ID && stationary_occurrence(i) > 0
        conditionlabels{end+1} = sprintf('Stationary%d', stationary_occurrence(i)); %#ok<AGROW>
    else
        conditionlabels{end+1} = cfg.cond_labels{cond_id}; %#ok<AGROW>
    end
end

%% 10A. AUDIO: return audio responses as a separate list of events.
%% NOT added to trl — epoching of these is done in a separate script.
%% Each one is tagged with the Close->Open trial it falls in.
audio_events = struct('sample', {}, 'timeRelSec', {}, 'width_ms', {}, ...
    'status', {}, 'TrialNum', {}, 'TaskType', {}, 'Direction', {}, ...
    'Quadrant', {}, 'Distance', {}, 'Position', {});

for a = 1:numel(audio_samples)
    s = audio_samples(a);
    k = find(trial_spans(:,1) <= s & s <= trial_spans(:,2), 1);
    if isempty(k)
        meta  = struct('TrialNum', NaN, 'TaskType', '', 'Direction', '', ...
            'Quadrant', '', 'Distance', NaN, 'Position', NaN);
        tStat = 'OUTSIDE_TRIAL';
        warning('build_trial_structure:audioOutsideTrial', ...
            'Audio response at %.2f s is outside every Close->Open trial span.', (s - t_zero) / fs);
    else
        meta  = buildTrialMeta(MasterData, trial_spans(k, 3));
        tStat = 'ACCEPTED';
        if trial_spans(k, 4), tStat = 'REJECTED'; end
    end

    audio_events(end+1) = struct('sample', s, ...
        'timeRelSec', (s - t_zero) / fs, ...
        'width_ms',   audio_width_ms(a, :), ...
        'status',     tStat, ...
        'TrialNum',   meta.TrialNum, ...
        'TaskType',   meta.TaskType, ...
        'Direction',  meta.Direction, ...
        'Quadrant',   meta.Quadrant, ...
        'Distance',   meta.Distance, ...
        'Position',   meta.Position); %#ok<AGROW>
end

%% 10B. NAVIGATION: after each trial's Open Eyes, A1 or A2 pulses. The END
%% of that pulse (switch-off) = navigation START. Navigation lasts until the
%% next Close Eyes (= start of the next trial). Returned as a separate list,
%% NOT epoched here.

% every A1 / A2 pulse: switch-on, switch-off, which channel
navOn = []; navOff = []; navCh = {};
for c = 1:numel(cfg.nav_channels)
    hiN  = D(D.indchannel(cfg.nav_channels{c}), :, 1) > cfg.nav_thresh;
    onN  = find(diff(hiN) == 1) + 1;
    offN = find(diff(hiN) == -1) + 1;
    for p = 1:numel(onN)
        f = offN(find(offN > onN(p), 1));
        if isempty(f), continue, end                 % still high at end of recording
        navOn(end+1, 1)  = onN(p);                   %#ok<AGROW>
        navOff(end+1, 1) = f;                        %#ok<AGROW>
        navCh{end+1, 1}  = cfg.nav_channels{c};      %#ok<AGROW>
    end
end
[navOn, o] = sort(navOn);  navOff = navOff(o);  navCh = navCh(o);   % time order

navigation_events = struct('startSample', {}, 'endSample', {}, ...
    'startRelSec', {}, 'endRelSec', {}, 'duration_s', {}, 'channel', {}, ...
    'prevTrialNum', {}, 'prevStatus', {}, 'nextTrialNum', {});

nSpans = size(trial_spans, 1);
for r = 1:nSpans
    k = trial_spans(r, 3);                           % MasterData row of this trial
    if isAborted(k), continue, end                   % aborted attempt: no Open Eyes -> no navigation

    openSamp = trial_spans(r, 2);                    % this trial's Open Eyes
    if r < nSpans
        nextClose    = trial_spans(r+1, 1);          % next trial's Close Eyes
        nextTrialNum = MasterData(trial_spans(r+1, 3)).TrialNum;
    else
        nextClose    = Inf;                          % last trial: no next Close Eyes
        nextTrialNum = NaN;
    end

    % A1/A2 pulse(s) that start after this Open Eyes and before the next Close Eyes
    p = find(navOn > openSamp & navOn < nextClose);
    if isempty(p)
        warning('build_trial_structure:noNavPulse', ...
            'No A1/A2 pulse after Open Eyes of trial %g.', MasterData(k).TrialNum);
        continue
    end
    if numel(p) > 1
        % UPDATED: which one to use is set by cfg.nav_pulse_pick ('first' / 'last')
        if strcmpi(cfg.nav_pulse_pick, 'last'), pick = p(end); else, pick = p(1); end
        warning('build_trial_structure:multiNavPulse', ...
            ['%d A1/A2 pulses after Open Eyes of trial %g (at +%s s) - using the %s ' ...
             '(+%.2f s, %s).'], numel(p), MasterData(k).TrialNum, ...
            mat2str(round((navOn(p)' - openSamp) / fs, 2)), lower(cfg.nav_pulse_pick), ...
            (navOn(pick) - openSamp) / fs, navCh{pick});
        p = pick;
    end

    startS = navOff(p);                              % END of A1/A2 pulse = navigation start
    endS   = nextClose;  if isinf(endS), endS = NaN; end

    prevStatus = 'ACCEPTED';  if trial_spans(r, 4), prevStatus = 'REJECTED'; end

    navigation_events(end+1) = struct( ...
        'startSample',  startS, ...
        'endSample',    endS, ...
        'startRelSec',  (startS - t_zero) / fs, ...
        'endRelSec',    (endS   - t_zero) / fs, ...
        'duration_s',   (endS - startS) / fs, ...
        'channel',      navCh{p}, ...
        'prevTrialNum', MasterData(k).TrialNum, ...
        'prevStatus',   prevStatus, ...
        'nextTrialNum', nextTrialNum); %#ok<AGROW>
end
fprintf('Navigation periods detected: %d\n', numel(navigation_events));

end


%% ======================== Local helper functions ========================

function [t_zero, abort_markers] = detectAllTriggersSync(trig_data_all, thresh, tol)
nChan = size(trig_data_all, 1);

all_edges = [];
for c = 1:nChan
    is_high = trig_data_all(c, :) > thresh;
    onsets  = find(diff(is_high) == 1) + 1;
    all_edges = [all_edges; onsets(:), repmat(c, numel(onsets), 1)]; %#ok<AGROW>
end

if isempty(all_edges)
    t_zero = []; abort_markers = [];
    return
end

all_edges = sortrows(all_edges, 1);
rising_edges = [];
i = 1;
while i <= size(all_edges, 1)
    j = i;
    chans_seen = all_edges(i, 2);
    while j + 1 <= size(all_edges, 1) && (all_edges(j+1, 1) - all_edges(i, 1)) <= tol
        j = j + 1;
        chans_seen = union(chans_seen, all_edges(j, 2));
    end
    if numel(chans_seen) >= nChan
        rising_edges(end+1) = round(mean(all_edges(i:j, 1))); %#ok<AGROW>
    end
    i = j + 1;
end

if isempty(rising_edges)
    t_zero = []; abort_markers = [];
    return
end

t_zero = rising_edges(1);
abort_markers = rising_edges(2:end);
end


function meta = buildTrialMeta(MasterData, t)
trialNum   = MasterData(t).TrialNum;
taskType   = MasterData(t).TaskType;
direction  = MasterData(t).Direction;
targetDeg  = MasterData(t).TargetDeg;
targetDist = MasterData(t).TargetDist;
position   = MasterData(t).Position;

switch taskType
    case 'I', taskWord = 'Imagine';
    case 'P', taskWord = 'Physical';
    otherwise
        error('buildTrialMeta:badTaskType', ...
            'Unrecognized TaskType ''%s'' for trial %d.', taskType, trialNum);
end

switch direction
    case 'L', dirWord = 'Left';
    case 'R', dirWord = 'Right';
    otherwise
        error('buildTrialMeta:badDirection', ...
            'Unrecognized Direction ''%s'' for trial %d.', direction, trialNum);
end

if targetDeg >= 0 && targetDeg < 90
    quadrant = 'Q1';
elseif targetDeg >= 90 && targetDeg < 180
    quadrant = 'Q2';
elseif targetDeg >= 180 && targetDeg < 270
    quadrant = 'Q3';
elseif targetDeg >= 270 && targetDeg < 360
    quadrant = 'Q4';
else
    error('buildTrialMeta:badTargetDeg', ...
        'TargetDeg %g out of [0,360) range for trial %d.', targetDeg, trialNum);
end

meta.TrialNum  = trialNum;
meta.TaskType  = taskWord;
meta.Direction = dirWord;
meta.Quadrant  = quadrant;
meta.Distance  = targetDist;
meta.Position  = position;
end