%% step4_amm_psd.m
% Section 9: AMM (adaptive multipole models) denoising — used INSTEAD of HFC.
% Runs after notch + bandpass filtering (step3), before epoching.
% FIXED: the denoised result is assigned BACK INTO fD (the old version put it
% in aD, so the next steps silently used the un-denoised data).

corrLim = 0.96;   % correlation limit (SPM default 1). Lower toward 0.95-0.98 only
                  % if movement-related low-frequency structure survives AMM.

S = [];
S.D       = fD;
S.li      = cfg.amm_li;       % internal harmonic order (config: 9)
S.le      = cfg.amm_le;       % external harmonic order (config: 2)
S.window  = cfg.amm_window;   % temporal window, s (config: 10)
S.corrLim = corrLim;
fD = spm_opm_amm(S);

fprintf('AMM applied (li = %d, le = %d, window = %g s, corrLim = %g).\n', ...
    cfg.amm_li, cfg.amm_le, cfg.amm_window, corrLim);

%% Section 10: PSD AFTER filtering + AMM
S = [];
S.D = fD;
S.triallength = 3000;
S.plot = 1;
S.channels = 'MEG';
spm_opm_psd(S);
title(sprintf('%s block %d - after AMM', subj, blockNum));
% >>> STOP HERE. Look at the physically-moving phases (Physical Walk /
% Response Rotation): if low-frequency, movement-related structure is still
% clearly visible, consider lowering corrLim (0.95-0.98).