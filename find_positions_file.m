function positionsFile = find_positions_file(subj, blockNum, cfg)
% FIND_POSITIONS_FILE  Finds the sensor positions .tsv for this subject.
%
% Inputs:
%   subj     - subject identifier string, e.g. 'p001'
%   blockNum - numeric block number
%   cfg      - struct from config()
%
% Output:
%   positionsFile - full path to the matched positions .tsv file
%
% UPDATED 23-10-2026: searches cfg.root AND its subfolders (positions
% files made by info2pos_neuro1 land in the Halo_* folder). A file with
% no block number in its name (e.g. P001_positions.tsv) is treated as
% covering the whole session. Files with 'backup' in the name are ignored.

posFiles = dir(fullfile(cfg.root, '**', cfg.positions_pattern));
posFiles = posFiles(~contains({posFiles.name}, 'backup', 'IgnoreCase', true));

exactMatch = [];  sessionMatch = [];
for f = 1:length(posFiles)
    parts = strsplit(posFiles(f).name, '_');
    if numel(parts) >= 2 && strcmpi(parts{1}, subj)
        if str2double(parts{2}) == blockNum
            exactMatch(end+1) = f;   %#ok<AGROW>
        elseif isnan(str2double(parts{2}))
            sessionMatch(end+1) = f; %#ok<AGROW>   % e.g. P001_positions.tsv
        end
    end
end

if numel(exactMatch) == 1
    idx = exactMatch;
elseif numel(exactMatch) > 1
    error('find_positions_file:ambiguous', ...
        'Multiple positions files for %s block %d.', subj, blockNum);
elseif numel(sessionMatch) == 1
    idx = sessionMatch;
elseif numel(sessionMatch) > 1
    error('find_positions_file:ambiguous', ...
        'Multiple session positions files for %s: %s', ...
        subj, strjoin({posFiles(sessionMatch).name}, ', '));
else
    error('find_positions_file:noMatch', ...
        'No positions file found for %s anywhere under %s.', subj, cfg.root);
end
positionsFile = fullfile(posFiles(idx).folder, posFiles(idx).name);
end
