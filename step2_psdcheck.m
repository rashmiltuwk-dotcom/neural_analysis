
%% Section 3: mark dropped + bad channels based on what you saw
% UPDATED 23-10-2026: cleared for the 21-10-2026 session — fill in from THIS session's step1 PSD.
droppedChans = {'X1', 'Y1', 'Z1', 'X6', 'Y6', 'Z6', 'X8', 'Z8', 'X9', 'Y9', 'Z9', ...
                'X11', 'Y11', 'X13', 'Y13', 'Z13', 'X14', 'Y14', 'Z14', 'X16', 'Y16', 'Z16', ...
                'X17', 'Y17', 'Z17', 'Z18', 'X19', 'Y19', 'Z19', 'Y20', 'Z20', 'X22', 'Y22', 'Z21',...
                'X25', 'Y25', 'Z25', 'X30', 'Y30', 'Z30', 'X31', 'Y31', 'Z31', 'Y32', 'X38', ...
                'Y42', 'X45', 'Y45', 'Z45', 'X47', 'Y47', 'Z47', 'X49', 'Y49', 'Z49', ...
                'X50', 'Y50', 'Z50', 'X52', 'Y52', 'Z52', 'X54', 'Y54', 'Z54', 'X57', 'Y57', 'Z57', ...
                'X59', 'Y59', 'Z59', 'X61', 'Y61', 'Z61', 'X62', 'Y62', 'Z62', 'X63', 'Y63', 'Z63', ...
                'X64', 'Y64', 'Z64'};   % <-- EDIT: dead/flat channels to drop, e.g. {'X30','Y30','Z30'}
badChans     = {};   % <-- EDIT: noisy-but-alive channels to mark bad
if ~isempty(droppedChans)
    keepChans = setdiff(D.chanlabels, droppedChans);
    S = []; S.D = D; S.channels = keepChans;
    D = spm_eeg_crop(S);
    fprintf('Excluded %d dropped channel(s): %s\n', numel(droppedChans), strjoin(droppedChans, ', '));
end

if ~isempty(badChans)
    D = badchannels(D, D.selectchannels(badChans), 1);
    D.save();
    fprintf('Marked %d bad channel(s): %s\n', numel(badChans), strjoin(badChans, ', '));
end

if isempty(droppedChans) && isempty(badChans)
    fprintf('No channels marked — both lists empty.\n');
end

%% Section 4: PSD AFTER marking, to confirm
S = [];
S.D = D;
S.triallength = 3000;
S.plot = 1;
S.channels = 'MEG';
spm_opm_psd(S);
% >>> STOP HERE. Confirm marked channels no longer dominate the plot.
% Proceed to step2_denoise_filter_psd.m next.

fprintf('\nOnce satisfied, add to config.m:\n');
fprintf('cfg.subject_dropped_channels.%s = {%s};\n', subj, ...
    strjoin(cellfun(@(c) ['''' c ''''], droppedChans, 'UniformOutput', false), ', '));
fprintf('cfg.subject_bad_channels.%s = {%s};\n', subj, ...
    strjoin(cellfun(@(c) ['''' c ''''], badChans, 'UniformOutput', false), ', '));