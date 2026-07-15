function [mv, info] = compose_heterogeneous(H_vec, frac_vec, varargin)
%COMPOSE_HETEROGENEOUS  model_vars for a CMLD with INDEPENDENT per-motor H and fractions.
%
%   [mv, info] = compose_heterogeneous(H_vec, frac_vec)
%   [mv, info] = compose_heterogeneous(H_vec, frac_vec, 'Name',Value, ...)
%
% Generalises reduce_cmld's compose_full (which hard-wires a COMMON motor inertia
% and the fixed NSW fractions renormalised to a single penetration phi) to the
% heterogeneous case this study needs: each of motors A/B/C gets its OWN inertia
% constant H_i and its OWN absolute bus load fraction F_mi. Pure function --
% assigns nothing, opens nothing, runs nothing. Produces the model-owned base-
% workspace variables the hand-authored cmld_3m.slx reads (via params.model_vars
% on the apply_params contract); the .slx is never touched.
%
% INPUTS
%   H_vec    [H_A H_B H_C]   per-motor inertia constants (s), on each motor's own base
%   frac_vec [F_mA F_mB F_mC] ABSOLUTE bus load fractions (of P_total). Motor
%                            penetration phi = sum(frac_vec); non-motor load fills
%                            (1 - phi), split in the AEMO elec:stat ratio.
%
% OPTIONS (Name-Value; defaults = AEMO NEM baseline, matching reduce_cmld)
%   'LF'       0.75      common loading factor (sets the inertia base S_Bi = F_mi*Pw/LF)
%   'LFm'      []        motor load-factor knob for the P_W power-pin (default = LF).
%                        Moves steady-state draw (slip/Tm) ONLY; the rating Pn (hence
%                        the inertial energy H_i*S_Bi) is FIXED on the nominal LF.
%   'Rrscale'  0.5       rotor-resistance scale (reducing_cmld best-config)
%   'Pw'       2405e6    total bus demand P_total (W)
%   'Stator'   {A,B,C}   per-motor [Rs Lls] (pu on motor base)
%   'Rotor'    {A,B,C}   per-motor [Rr Llr] (pu); Rr is scaled by Rrscale
%   'Lm'       [A B C]   per-motor magnetising inductance (pu)
%   'TrqExp'   [0 2 2]   torque law per motor (0=const, 2=~w^2); AEMO: A const, B/C var
%   'ElecStat' [.337 .216] elec / static non-motor split weights (relative)
%
% OUTPUTS
%   mv    struct of model_vars: MotorA/B/C_{Nom,Stator,Rotor,Lm,Mech,Pmec,Tm,TrqExp,IC},
%         CMLD_ElecP, P0, Q0, CapC  (same var set as reduce_cmld.compose_full)
%   info  derived quantities for T1 / the estimators, WITHOUT re-parsing mv:
%         .H .F_m .LF .Pw            the inputs echoed
%         .S_B    [S_BA S_BB S_BC]   per-motor inertia base = rating Pn_i = F_mi*Pw/LF (W)
%         .s0     [sA sB sC]         initial operating slip per motor
%         .E_k_load  = sum(H_i * S_Bi)      stored kinetic energy (W*s)  (eq:KE_load)
%         .H_load    = E_k_load / Pw = sum((F_mi/LF)*H_i)   closed form (s)  (eq:hload)
%
% The closed form under test (source_docs/paper/main.tex eq:hload):
%   H_load = sum_i (F_mi / LF) * H_i          [s, on P_total base]
% is reproduced EXACTLY by info.H_load because Pn_i is set to F_mi*Pw/LF -- which is
% precisely what T1 (Phase 4) checks the initialised model against.

% ---- options ----------------------------------------------------------------
ip = inputParser;
ip.addParameter('LF', 0.75);
ip.addParameter('LFm', []);
ip.addParameter('Rrscale', 0.5);
ip.addParameter('Pw', 2405e6);
ip.addParameter('Stator', {[0.02 0.072], [0.03 0.114], [0.03 0.114]});
ip.addParameter('Rotor',  {[0.05955 0.04937], [0.02810 0.07959], [0.02810 0.07959]});
ip.addParameter('Lm',     [1.728 1.686 1.686]);
ip.addParameter('TrqExp', [0 2 2]);
ip.addParameter('ElecStat', [0.337 0.216]);
ip.parse(varargin{:}); o = ip.Results;

H_vec    = H_vec(:).';    frac_vec = frac_vec(:).';
assert(numel(H_vec)==3 && numel(frac_vec)==3, ...
    'compose_heterogeneous:shape', 'H_vec and frac_vec must each have 3 elements [A B C]');
assert(all(frac_vec >= 0) && sum(frac_vec) < 1, ...
    'compose_heterogeneous:frac', ...
    'motor fractions must be >=0 and sum to <1 (leaving room for non-motor load); got sum=%.3f', ...
    sum(frac_vec));

LF  = o.LF;
LFm = o.LFm; if isempty(LFm), LFm = LF; end
Pw  = o.Pw;
L   = 'ABC';

% ---- per-motor variables ----------------------------------------------------
mv  = struct();
S_B = zeros(1,3);  s0 = zeros(1,3);
for i = 1:3
    X    = L(i);
    Pmec = frac_vec(i) * Pw;          % mechanical draw = bus fraction * total demand
    Pn   = Pmec / LF;                 % RATING = inertia base S_Bi; FIXED on nominal LF
    Rr   = o.Rotor{i}(1) * o.Rrscale; Llr = o.Rotor{i}(2);
    s    = deal_slip(Rr, LFm);        % operating slip at the tuned load factor

    mv.(['Motor' X '_Nom'])    = [Pn 11000 50];
    mv.(['Motor' X '_Stator']) = o.Stator{i};
    mv.(['Motor' X '_Rotor'])  = [Rr Llr];
    mv.(['Motor' X '_Lm'])     = o.Lm(i);
    mv.(['Motor' X '_Mech'])   = [H_vec(i) 0 2];   % element 1 = inertia constant H_i
    mv.(['Motor' X '_Pmec'])   = LFm * Pn;         % actual mech load, scales with LFm
    mv.(['Motor' X '_Tm'])     = LFm / (1 - s);
    mv.(['Motor' X '_TrqExp']) = o.TrqExp(i);
    mv.(['Motor' X '_IC'])     = [s 0 0 0 0 0 -120 120];

    S_B(i) = Pn;  s0(i) = s;
end

% ---- non-motor passive load (fills 1 - phi), split elec/static --------------
phi = sum(frac_vec);
Pnm = (1 - phi) * Pw;                 % total non-motor power
e   = o.ElecStat(1) / sum(o.ElecStat);
mv.CMLD_ElecP = e * Pnm;
mv.P0         = (1 - e) * Pnm;
mv.Q0         = 0.20 * mv.P0;
mv.CapC       = 0.037092 * (Pw / 2405e6);

% ---- derived quantities (closed form under test) ----------------------------
info = struct();
info.H        = H_vec;
info.F_m      = frac_vec;
info.LF       = LF;
info.Pw       = Pw;
info.S_B      = S_B;                            % = F_mi*Pw/LF
info.s0       = s0;
info.E_k_load = sum(H_vec .* S_B);              % eq:KE_load  (W*s)
info.H_load   = info.E_k_load / Pw;             % eq:hload    (s) == sum((F_mi/LF).*H_i)
end

% =============================== helpers =====================================
function s = deal_slip(Rr, LF)
%DEAL_SLIP  Fixed-point operating slip at loading factor LF (matches reduce_cmld).
s = LF*Rr; for it = 1:8, s = (LF/(1-s))*Rr; end
end
