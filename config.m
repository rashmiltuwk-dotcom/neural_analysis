function cfg = config()
%% ---- Paths ----
% UPDATED: laptop paths (were C:/Users/spaceandmem/rashmil_opm/...)
cfg.root       = 'C:/Users/rashm/Documents/opm_pi/participant_001/Neural_Data_001_001/';
cfg.spm_path   = 'C:/Users/rashm/Documents/spm/';
% UPDATED: behavioural MasterData lives in its own folder, not in cfg.root
cfg.behav_root = 'C:/Users/rashm/Documents/opm_pi/participant_001/Behavioural_Data_001_01/Matlab/';
cfg.master_data_pattern = '*_MasterData.mat';

%% ---- Expected block count (per participant) ----
cfg.expected_block_count = 9;   % UPDATED: was 8 — 21-10-2026 session has 9 runs

%% ---- Trigger / sync definitions ----
cfg.sync_thresh = 0.05;
cfg.sync_trigger_channels = {'T5','T8','T6','T9','T2','T10','T7','T3'};
cfg.trigger_channels = {'T5','T8','T6','T9','T2','T10','T7'};
% TODO: confirm T2 / T10 labels. This list maps T2 -> 'Response Rot' and
% T10 -> 'Imagine Walk', but the trigger viewer labels T2 = Imagine Walk
% and T10 = Response Rot. One of them is wrong.
cfg.cond_labels = {'Close Eyes','Stationary','Physical Walk', ...
    'Encoding Rot','Response Rot','Imagine Walk','Open Eyes'};
cfg.simultaneous_tol = 10;

%% ---- Audio response (T2 + T10 (+ T3) together, no phase channel) ----
% Measured 21-10-2026: T2+T3+T10, 81-166 ms (mean ~111), 3 per trial:
% end of T6, end of T9, and just before Open Eyes. T3 fires with EVERY
% trigger, so it is ignored when deciding "nothing else fired".
cfg.audio_channels     = {'T2','T10'};
cfg.audio_pulse_ms     = 115;   % typical width
cfg.audio_pulse_tol_ms = 55;    % warn if outside 60-170 ms

%% ---- Navigation (A1 / A2 analogue, after Open Eyes) ----
% Measured: one A1 (or A2) pulse ~2 s after Open Eyes, ~4.2 V.
cfg.nav_channels   = {'A1','A2'};
cfg.nav_thresh     = 2;         % V
cfg.nav_pulse_pick = 'last';    % if >1 A1/A2 pulse in a gap: 'first' or 'last'

%% ---- Epoching ----
cfg.epoch_win = [-200 3000];

%% ---- Bad channels ----
cfg.subject_dropped_channels = struct();
cfg.subject_bad_channels     = struct();

%% ---- Resampling ----
% REMOVED. Previously resampled to 1000 Hz following Spedden et al.
% (2025) — removed per decision to keep data at native acquisition
% rate. build_trial_structure.m's trl is now used directly at the
% ORIGINAL sample rate throughout preprocess_subject.m / step3_amm_psd.m
% — no rescaling step exists anymore, since none is needed.

%% ---- Signal processing: denoising (AMM, replacing HFC) ----
cfg.amm_li      = 9;
cfg.amm_le      = 2;
cfg.amm_window  = 10;   % seconds
% amm_corrLim REMOVED from here — now set directly in step4_amm_psd.m
% (and preprocess_subject.m), local to where AMM actually runs, rather
% than buried in this shared config file.

cfg.hfc_order = 1;

%% ---- Signal processing: notch filter ----
cfg.notch_freqs = [49 51];

%% ---- Signal processing: bandpass ----
cfg.hp_freq   = 2;
cfg.lp_freq   = 40;

%% ---- Sensor positions ----
% TODO: find_positions_file.m only looks DIRECTLY in cfg.root, but
% P001_positions.tsv is in the Halo_21-10-2026_10-08-54 subfolder —
% it will not be found until the file is moved or the search changed.
cfg.positions_pattern = '*positions.tsv';

%% ---- Coregistration ----
% CHANGED: using SPM's generic canonical template (avg152T1.nii)
% instead of an individual per-subject MRI — decided given this is a
% single-participant neural pilot (see methods write-up: acquiring an
% individual structural scan is not cost-effective before confirming
% the paradigm itself works). cfg.mri_pattern (per-subject '%s_T1.nii')
% REMOVED — no per-subject MRI file is expected to exist.
% CHANGED: now using the REAL individual MRI (received 17/08/2026),
% not the generic avg152T1 template — genuine subject-specific
% anatomy, finally available. cfg.template_mri name kept for now to
% avoid renaming everywhere it's referenced in coregister_subject.m.
% TODO: p001_struc.nii is not in the new folders. The only MRI found is
% scannercast/sub-002_mri.nii — confirm it belongs to p001 before using.
cfg.template_mri = fullfile(cfg.root, 'p001_struc.nii');

% p001's sensor positions (p001_1_positions.tsv, from
% table_of_info_P001_cast.csv) are ALREADY in this MRI's native
% coordinate space — built by ICP-fitting the physical scannercast's
% scalp STL directly onto p001_struc.nii's own MRI-derived scalp mesh.
% This tells coregister_subject.m to skip the (redundant, and here
% inapplicable) fiducial-based registration step and use an identity
% transform instead, since no additional rotation/translation is
% needed.
cfg.subject_sensors_prealigned.p001 = true;

% CHANGED: real fiducial coordinates, manually marked directly on the
% subject's actual individual MRI (p001_struc.nii) using spm_image,
% replacing the earlier unverified/placeholder values. Marked
% 17/08/2026 — nasion refined for midline (x~0) and correct notch
% depth; LPA/RPA confirmed roughly symmetric (similar y/z, ~4mm x
% difference, both physiologically plausible for preauricular points).

%% ---- Beamforming ----
cfg.beamform_grid_res = 5;
cfg.beamform_foi      = [4 7];
cfg.beamform_woi       = [-Inf Inf];
cfg.beamform_power_trim = 0.17;


end