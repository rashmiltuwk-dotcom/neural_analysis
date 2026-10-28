%% run_preprocessing.m
% Runs the preprocessing scripts in order, one block at a time:
%   step1_import_badchannels -> step2_psdcheck -> step3_filter_psd -> step4_amm_psd
% pausing after each step so you can check the PSD.
% Intermediate files are NOT saved: the scripts write SPM's working files
% into a temporary folder (outDir), files from finished steps are deleted
% as it goes, and the temp folder is always deleted at the end of each block.
% Only the FINAL preprocessed file (after AMM) is saved to finalDir
% (set saveFinal = false to save nothing at all).
% Results (channels, trial structure, audio + navigation events) are kept
% in the workspace variable "prep".
%
% Needs the outDir lines in step1_import_badchannels.m (right after S.lead = 0;).

%% ===================== SETTINGS =====================
subj              = 'p001';
runBlocks         = 1:9;          % e.g. 1:9
pauseBetweenSteps = true;       % wait for Enter after each step's PSD
saveFinal         = false;       % true = save ONLY the final preprocessed file; false = save nothing
finalDir          = 'C:/Users/rashm/Documents/opm_pi/participant_001/preprocessed';

%% ===================== SET-UP =====================
addpath('C:/Users/rashm/Documents/spm/')
addpath('C:/Users/rashm/Documents/neural_analysis')

% safety: make sure step1 can write to the temp folder BEFORE anything runs,
% otherwise it would overwrite the conversion next to your .lvm
assert(contains(fileread(which('step1_import_badchannels')), 'outDir'), ...
    ['step1_import_badchannels.m does not use outDir yet - add the 3 outDir lines ' ...
     'right after "S.lead = 0;" first, so nothing is written next to your data.']);

prep = [];

for blockIdx = 1:numel(runBlocks)
    blockNum = runBlocks(blockIdx);
    fprintf('\n==================== %s  block %d ====================\n', subj, blockNum);

    outDir = fullfile(tempdir, sprintf('opm_prep_%s_b%02d_%s', subj, blockNum, datestr(now, 'yyyymmdd_HHMMSS')));
    mkdir(outDir);

    %% ---------- STEP 1 ----------
    fprintf('\n---------- STEP 1: import + PSD before cleaning ----------\n');
    step1_import_badchannels
    assert(strcmpi(normPath(D.path), normPath(outDir)), ...
        'step1 wrote to %s instead of the temp folder - stopping.', D.path);
    pauseStep(pauseBetweenSteps, 'STEP 2 (drop bad channels)');

    %% ---------- STEP 2 ----------
    fprintf('\n---------- STEP 2: drop bad channels ----------\n');
    step2_psdcheck
    cleanTemp(outDir, {D});                    % keep only the current dataset
    pauseStep(pauseBetweenSteps, 'STEP 3 (trial structure + filtering)');

    %% ---------- STEP 3 ----------
    fprintf('\n---------- STEP 3: trial structure + notch + bandpass ----------\n');
    step3_filter_psd
    cleanTemp(outDir, {fD});
    pauseStep(pauseBetweenSteps, 'STEP 4 (AMM)');

    %% ---------- STEP 4 ----------
    fprintf('\n---------- STEP 4: AMM ----------\n');
    step4_amm_psd
    cleanTemp(outDir, {fD});

    %% ---------- keep the results ----------
    res = struct();
    res.subj              = subj;
    res.block             = blockNum;
    res.lvmFile           = lvmFile;
    res.positionsFile     = positionsFile;
    res.droppedChans      = droppedChans;
    res.nMEG              = numel(indchantype(fD, 'MEG'));
    res.fsample           = fD.fsample;
    res.trl               = trl;
    res.conditionlabels   = conditionlabels;
    res.trial_status      = trial_status;
    res.trial_meta        = trial_meta;
    res.timeRelSec        = timeRelSec;
    res.t_zero            = t_zero;
    res.trial_end_samples = trial_end_samples;
    res.audio_events      = audio_events;
    res.navigation_events = navigation_events;

    %% ---------- save ONLY the final file, delete the temp folder ----------
    if saveFinal
        if ~isfolder(finalDir), mkdir(finalDir); end
        finalName = sprintf('prep_%s_block%02d.mat', subj, blockNum);
        Dfinal = copy(fD, fullfile(finalDir, finalName));        % writes .mat + .dat to finalDir
        res.finalFile = fullfile(Dfinal.path, Dfinal.fname);
        fprintf('\nFinal preprocessed file saved: %s\n', res.finalFile);
        clear Dfinal
    else
        res.finalFile = '';
    end
    clear D fD
    rmdir(outDir, 's');                                         % temp folder ALWAYS deleted
    fprintf('Temporary files deleted.\n');

    if isempty(prep), prep = res; else, prep(end+1) = res; end %#ok<SAGROW>

    if blockIdx < numel(runBlocks)
        pauseStep(pauseBetweenSteps, sprintf('the NEXT BLOCK (%d)', runBlocks(blockIdx + 1)));
    end
end

%% ===================== SUMMARY =====================
fprintf('\n===================== SUMMARY =====================\n');
for k = 1:numel(prep)
    fprintf('block %d: %d MEG channels (dropped %d) | %d phase events | %d audio | %d navigation\n', ...
        prep(k).block, prep(k).nMEG, numel(prep(k).droppedChans), size(prep(k).trl, 1), ...
        numel(prep(k).audio_events), numel(prep(k).navigation_events));
    if ~isempty(prep(k).finalFile), fprintf('         saved: %s\n', prep(k).finalFile); end
end
fprintf('\nResults are in the variable "prep" (NOT saved). To keep them:\n  save(''prep_%s.mat'', ''prep'')\n', subj);


%% ===================== LOCAL FUNCTIONS =====================
function pauseStep(doPause, nextWhat)
if doPause
    input(sprintf('\n>>> Check the plot. Press Enter to continue to %s (Ctrl+C to stop) ', nextWhat), 's');
end
end

function cleanTemp(outDir, keepObjs)
% delete every SPM dataset in the temp folder except the ones still needed
keepNames = cellfun(@(o) o.fname, keepObjs, 'UniformOutput', false);
m = dir(fullfile(outDir, '*.mat'));
for k = 1:numel(m)
    if ~any(strcmpi(m(k).name, keepNames))
        [~, n] = fileparts(m(k).name);
        delete(fullfile(outDir, m(k).name));
        if isfile(fullfile(outDir, [n '.dat'])), delete(fullfile(outDir, [n '.dat'])); end
    end
end
end

function p = normPath(p)
% compare folders regardless of slash direction / trailing slash
p = lower(strrep(char(p), '/', '\'));
if endsWith(p, '\'), p = p(1:end-1); end
end