%% step1_import_badchannels.m
%
% Run ONE SECTION AT A TIME. Contains Section 1 (setup/search/import)
% and Section 2 (PSD before any cleaning) only — channel marking and
% the after-marking PSD live in a separate file.
%
% CHANGED: search is now RECURSIVE (dir(..., '**', '*.lvm')) — real
% .lvm files were confirmed to live in per-block subfolders under
% cfg.root (e.g. cfg.root/P_001_001_neural_<date>_<time>/P_001_001_
% neural_array1.lvm), not directly inside cfg.root itself. A flat,
% non-recursive dir() found nothing even though the files genuinely
% existed. run_batch.m has this same non-recursive search and needs
% the identical fix if you use it instead of running blocks individually.
%
% Uses parse_subject_block.m — updated separately to match the REAL
% filename convention (P_<participant>_<block>_..., confirmed against
% actual acquired filenames like 'P_001_001_neural_array1.lvm') rather
% than the originally-assumed Px_y_z / MasterData convention.


spm('defaults', 'eeg')
addpath(fullfile(spm('dir'), 'toolbox', 'MEEGtools'))
addpath(fullfile(spm('dir'), 'toolbox', 'DAiSS'))
addpath(fullfile(spm('dir'), 'external', 'fieldtrip'))
ft_defaults
cfg = config();

%% --- EDIT THESE TWO VALUES (or set externally before calling, e.g. from a driver script) ---
if ~exist('blockNum', 'var')
    blockNum = 1;   % <-- EDIT — used only if not already set externally
end
if ~exist('subj', 'var')
    subj = 'p001';
end

%% Search cfg.root RECURSIVELY for the .lvm file matching this subject + block
allLvmFiles = dir(fullfile(cfg.root, '**', '*.lvm'));
if isempty(allLvmFiles)
    error('step1:noLvmFiles', 'No .lvm files found anywhere under cfg.root: %s', cfg.root);
end

matchIdx = [];
parseErrors = {};
for f = 1:numel(allLvmFiles)
    candidate = fullfile(allLvmFiles(f).folder, allLvmFiles(f).name);
    try
        [thisSubj, thisBlock] = parse_subject_block(candidate);
        if strcmpi(thisSubj, subj) && thisBlock == blockNum
            matchIdx(end+1) = f; %#ok<AGROW>
        end
    catch ME
        parseErrors{end+1} = sprintf('%s (%s)', allLvmFiles(f).name, ME.message); %#ok<AGROW>
    end
end
if ~isempty(parseErrors)
    fprintf('Skipped %d file(s) that did not match the expected filename convention:\n', numel(parseErrors));
    for e = 1:numel(parseErrors)
        fprintf('  - %s\n', parseErrors{e});
    end
end

if isempty(matchIdx)
    error('step1:noMatch', ...
        'No .lvm file found for subject ''%s'', block %d anywhere under %s.', ...
        subj, blockNum, cfg.root);
elseif numel(matchIdx) > 1
    error('step1:ambiguousMatch', ...
        'Multiple .lvm files found for subject ''%s'', block %d — check for duplicates.', ...
        subj, blockNum);
end

lvmFile = fullfile(allLvmFiles(matchIdx).folder, allLvmFiles(matchIdx).name);

if ~isfile(lvmFile)
    error('step1:missingLVM', '.lvm file not found: %s', lvmFile);
end

%% Positions file — matched by SUBJECT and BLOCK, with fallback to any
%% block for this subject if no exact match exists (see find_positions_file.m)
positionsFile = find_positions_file(subj, blockNum, cfg);

fprintf('Using LVM file:       %s\n', lvmFile);
fprintf('Using positions file: %s\n', positionsFile);

S = [];
S.data      = lvmFile;
S.positions = positionsFile;
% CHANGED: S.lead = 0 added. CONFIRMED (via direct error): without
% this, spm_opm_create automatically tries to build a head model and
% pop up an interactive mesh-check window (spm_opm_headmodel ->
% spm_eeg_inv_mesh_ui -> spm_eeg_inv_checkmeshes), which crashes inside
% SPM's own spm_figure.m at a zoom(F,'off') call ("Expected a string
% scalar or character vector for the parameter name") — an SPM/MATLAB
% internal compatibility bug in that UI code path, not something in
% our own scripts. This is also unnecessary at import time: headmodel/
% leadfield computation already happens properly later, in
% coregister_subject.m (via spm_eeg_inv_mesh, spm_eeg_inv_datareg,
% spm_eeg_inv_forward). Matches SPM's own OPM tutorial pattern (Neuro-1
% example), which explicitly sets S.lead = 0 at import and computes
% leadfields later.
S.lead      = 0;
if exist('outDir', 'var') && ~isempty(outDir)   % set by run_preprocessing -> write to a temp folder
    S.path = outDir;
end
D = spm_opm_create(S);

fprintf('Import complete. %d total channels.\n', D.nchannels);

%% Section 2: PSD BEFORE any cleaning
S = [];
S.D = D;
S.triallength = 3000;
S.plot = 1;
S.channels = 'MEG';
spm_opm_psd(S);
title(sprintf('%s — block %d (before cleaning)', subj, blockNum), 'Interpreter', 'none');
% >>> STOP HERE. Look for:
%   - channels that look COMPLETELY DEAD (flat line, near-zero
%     everywhere) -> these are DROPPED channels
%   - channels that are noisy but clearly still recording something
%     -> these are BAD channels
% Proceed to the marking file next (contains Sections 3 and 4), then
% step2_denoise_filter_psd.m, then epoching/topoplot — all for THIS
% block. Once every block you want is checked individually this way,
% run step7_coregister_beamform.m once to merge them all.