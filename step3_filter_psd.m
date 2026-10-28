%% Section 5: trigger detection
%
% Unaffected by the filter/AMM reorder — must always happen on raw,
% completely unprocessed D.
% UPDATED 23-10-2026: also returns audio_events and navigation_events
[trl, conditionlabels, trial_status, trial_meta, timeRelSec, t_zero, trial_end_samples, audio_events, navigation_events] = ...
    build_trial_structure(D, lvmFile, cfg);

fprintf('Trigger detection complete: %d trials found.\n', size(trl, 1));
fprintf('t_zero (sync pulse sample): %d\n', t_zero);

fprintf('Resampling skipped — data kept at native rate (%g Hz).\n', D.fsample);

%% Section 6: notch filter (49-51 Hz only, Spedden et al. 2025)
%
% CHANGED: filter now runs BEFORE AMM (was after) — swapped with the
% content that used to live in this file slot. Operates directly on D.
%
% FIXED: S.type/S.order/S.dir now set EXPLICITLY (order=4), matching
% the same fix already applied to the bandpass filters below.
% CONFIRMED: without this, spm_eeg_filter used its own default order
% (5), which repeatedly triggered "instability detected — reducing the
% 5th order filter to a 4th order filter" (~130 times in one run) —
% meaning order 4 was always the order actually being applied anyway,
% just via a silent auto-correction each time rather than being
% requested directly.
fD = D;
for n = 1:size(cfg.notch_freqs, 1)
    S = [];
    S.D    = fD;
    S.freq = cfg.notch_freqs(n, :);
    S.band = 'stop';
    S.type = 'butterworth';
    S.order = 4;
    S.dir = 'twopass';
    fD = spm_eeg_filter(S);
    fprintf('Applied notch filter: %.1f-%.1f Hz\n', cfg.notch_freqs(n,1), cfg.notch_freqs(n,2));
end

%% Section 7: bandpass filter
S = []; S.D = fD; S.type='butterworth'; S.order=5; S.dir='twopass';
S.freq = cfg.hp_freq; S.band = 'high';
fD = spm_eeg_filter(S);

S = []; S.D = fD; S.type='butterworth'; S.order=5; S.dir='twopass';
S.freq = cfg.lp_freq; S.band = 'low';
fD = spm_eeg_filter(S);

%% Section 8: PSD AFTER filtering, BEFORE AMM
S = [];
S.D = fD;
S.triallength = 3000;
S.plot = 1;
S.channels = 'MEG';
spm_opm_psd(S);
% >>> STOP HERE. Confirm the mains notch (50Hz) is visible as a clean
% dip, and the overall spectrum looks physiologically plausible.
% Proceed to step4_amm_psd.m next (AMM now runs AFTER filtering).

fprintf('Filtering complete. fD is ready for AMM (step4).\n');