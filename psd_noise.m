%% psd_noise.m - PSD of the noise recording, select lines to see which channels they are
clearvars; close all
addpath('C:/Users/rashm/Documents/spm/')
spm('defaults', 'eeg')
addpath(fullfile(spm('dir'), 'toolbox', 'MEEGtools'))

% load the noise recording
D = spm_eeg_load('C:/Users/rashm/Documents/opm_pi/participant_001/Neural_Data_001_001/Noise_21-10-2026_10-02-05/Noise_21-10-2026_10-02-05_array1.mat');

% PSD with interactive selection
S = [];
S.D           = D;
S.triallength = 3000;     % ms
S.plot        = 1;
S.channels    = 'MEG';
S.selectbad   = 1;        % <-- lets you click / box-select lines on the plot
[~, ~, selIdx] = spm_opm_psd(S);   % waits here until you CLOSE the figure

% which channels did you select?
selLabels = D.chanlabels(selIdx);
fprintf('\nSelected %d channel(s): %s\n', numel(selLabels), strjoin(selLabels, ' '));