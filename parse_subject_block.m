function [subj, blockNum] = parse_subject_block(lvmFile)
% PARSE_SUBJECT_BLOCK  Parses subject ID and block number from a
% filename.
%
% CHANGED: updated to match REAL experimental .lvm filenames, confirmed
% directly against actual acquired data:
%   P_001_001_neural_array1.lvm
%   P_001_002_neural_array1.lvm
%   ...
% Format: P_<participant>_<block>_<rest>  (underscore BETWEEN 'P' and
% the participant number — different from the Px_y_z / MasterData
% convention this function originally assumed, which had no underscore
% there, e.g. 'P001_1_...'). Real filenames DO have that underscore, so
% splitting on '_' now gives participant number in segment 2 and block
% number in segment 3, not segment 1.
%
% Previous (now confirmed WRONG for real data) assumption is left below
% for reference only, not used:
%   subjRaw = parts{1}; blockNum = parts{2};  % <- was wrong
%
% Still cross-checks against the enclosing folder name, if that folder
% itself looks like a participant identifier — unchanged logic, just
% now also tries the real folder-naming pattern actually seen
% (P_001_001_neural_<date>_<time>), which does NOT match a simple
% ^[Pp]\d+$ pattern, so the cross-check is skipped for folders shaped
% like this (same "skip if it doesn't look like a participant folder"
% behaviour as before — nothing extra needed for that case).
%
% Expected format: P_<participant>_<block>_<rest of filename>
%   e.g. 'P_001_001_neural_array1.lvm' -> subj='p001', blockNum=1
%
% Inputs:
%   lvmFile - full path or filename to a .lvm (or matching .mat) file
%
% Outputs:
%   subj     - lowercase subject identifier string, e.g. 'p001'
%   blockNum - numeric block number

[fileDir, fileName, ~] = fileparts(lvmFile);
parts = strsplit(fileName, '_');

if numel(parts) < 3
    error('parse_subject_block:badFilename', ...
        ['Filename ''%s'' does not have at least three underscore-' ...
         'separated parts. Expected P_<participant>_<block>_... ' ...
         'convention (e.g. P_001_001_neural_array1). Cannot parse ' ...
         'subject/block.'], fileName);
end

if ~strcmpi(parts{1}, 'P')
    error('parse_subject_block:badPrefix', ...
        ['First filename segment ''%s'' is not ''P''. Expected ' ...
         'P_<participant>_<block>_... convention. Filename: ''%s''.'], ...
        parts{1}, fileName);
end

participantRaw = parts{2};
if isempty(regexp(participantRaw, '^\d+$', 'once'))
    error('parse_subject_block:badParticipantFormat', ...
        ['Second filename segment ''%s'' is not purely numeric — ' ...
         'expected the participant number. Filename: ''%s''.'], ...
        participantRaw, fileName);
end
subj = sprintf('p%s', participantRaw);   % e.g. '001' -> 'p001'
subj = lower(subj);

blockRaw = parts{3};
blockNum = str2double(blockRaw);
if isnan(blockNum)
    error('parse_subject_block:badBlockFormat', ...
        ['Third filename segment ''%s'' is not numeric — expected ' ...
         'the block number. Filename: ''%s''.'], blockRaw, fileName);
end

%% Cross-check against the enclosing folder name, if it looks like a
%% simple participant identifier (e.g. 'p001' or 'P001', nothing else).
%% Real folders seen so far (e.g. 'P_001_001_neural_14-08-2026_13-11-12')
%% do NOT match this simple pattern, so the check is correctly skipped
%% for them — same "only check if it looks like one" behaviour as
%% before, unchanged.
[~, folderName] = fileparts(fileDir);
if ~isempty(regexp(folderName, '^[Pp]\d+$', 'once'))
    folderSubj = lower(folderName);
    if ~strcmp(folderSubj, subj)
        error('parse_subject_block:folderFilenameMismatch', ...
            ['File ''%s'' sits inside folder ''%s'', but its filename ' ...
             'indicates subject ''%s''. Folder and filename disagree on ' ...
             'which participant this file belongs to — fix this before ' ...
             'running the pipeline; do not silently trust one source ' ...
             'over the other.'], ...
            fileName, folderName, subj);
    end
end

end