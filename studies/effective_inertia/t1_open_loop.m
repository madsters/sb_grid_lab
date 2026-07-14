function T = t1_open_loop(varargin)
%T1_OPEN_LOOP  T1 -- algebraic scaling check (open-loop, no dynamics).
%
%   T = t1_open_loop()                 % arithmetic identity table (offline; no Simulink)
%   T = t1_open_loop('Sim', true)      % + settle each point, confirm P_load ~ P_W
%
% Confirms the rig's INITIALISED motor inertia base reproduces the paper's closed
% form (plan.md T1). For each mix in sweep_points, compose_heterogeneous emits the
% model_vars; T1 checks that the initialised quantities satisfy, to machine precision:
%   S_Bi = MotorX_Nom(1) = F_mi*P_W/LF          (per-motor inertia base / rating)
%   H_i  = MotorX_Mech(1)                        (per-motor inertia constant)
%   E_k,load = sum_i H_i*S_Bi                     (eq:KE_load, stored kinetic energy)
%   H_load   = E_k,load / P_W = sum_i (F_mi/LF)*H_i   (eq:hload)
% These are how the SPS asynchronous machine defines stored KE (H on its own MVA
% base = Pn = S_Bi), so the closed form is faithful to the model's initialisation
% BY CONSTRUCTION of the composer -- this driver is the guard that keeps it so.
% The arithmetic runs on base MATLAB (no Simulink), so T1 is the cheapest gate.
%
% The ONE model-dependent fact T1 cannot get from arithmetic is that the composed
% load actually DRAWS P_total = P_W at the operating point (so P_W is the right
% denominator). 'Sim',true settles each point through the engine and confirms it
% (the single % RUN: point here); default false keeps T1 fully offline.
%
% OPTIONS
%   'Sim'      false   settle each mix (disturbance off) and check P_load ~ P_W
%   'Corner'   'stress' corner for the optional settle ('stress'|'nominal')
%   'Tol'      1e-10   arithmetic identity tolerance (relative)
%   'PTol'     0.02    P-match tolerance for the optional settle (2%)
%   'ModelPath' ''     cmld_3m.slx path (default studies/effective_inertia/models)
%
% RETURNS T : table [id, H_A..C, F_mA..C, phi, S_BA..C_MVA, Ek_GWs, H_load_s]
%             plus prints PASS/FAIL for every identity. Saved to t1_open_loop.mat.

ip = inputParser;
ip.addParameter('Sim', false);
ip.addParameter('Corner', 'stress');
ip.addParameter('Tol', 1e-10);
ip.addParameter('PTol', 0.02);
ip.addParameter('ModelPath', '');
ip.parse(varargin{:}); o = ip.Results;

sc   = fileparts(mfilename('fullpath'));           % studies/effective_inertia
repo = fileparts(fileparts(sc));
if isempty(which('sb_grid_sim.default_params'))
    run(fullfile(repo,'startup_sbgrid.m'));
end
addpath(sc);                                       % compose_heterogeneous + +eff_inertia
S   = sweep_points();
Pw  = S.Pw;  LF = S.LF;

nrow = numel(S.mix);
rows = cell(nrow, 11);           % 11 columns -- matches the tuple + VariableNames below
allpass = true;
fprintf('\n==== T1 open-loop algebraic scaling check (P_W = %.0f MW, LF = %.2f) ====\n', Pw/1e6, LF);
for i = 1:nrow
    mx = S.mix(i);  H = mx.H;  F = mx.F;
    [mv, info] = compose_heterogeneous(H, F, 'Pw',Pw, 'LF',LF, 'Rrscale',S.Rrscale);

    % --- identity checks (machine precision) ---------------------------------
    Nom = [mv.MotorA_Nom(1) mv.MotorB_Nom(1) mv.MotorC_Nom(1)];
    Mech= [mv.MotorA_Mech(1) mv.MotorB_Mech(1) mv.MotorC_Mech(1)];
    c1 = relok(info.S_B,   F*Pw/LF,            o.Tol);   % S_Bi = F_mi*Pw/LF
    c2 = relok(Nom,        info.S_B,           o.Tol);   % Nom(1) wired to S_Bi
    c3 = isequal(Mech,     H);                           % Mech(1) wired to H_i
    c4 = relok(info.E_k_load, sum(H.*info.S_B), o.Tol);  % E_k,load
    c5 = relok(info.H_load, sum((F/LF).*H),     o.Tol);  % H_load closed form
    c6 = relok(info.H_load, info.E_k_load/Pw,   o.Tol);  % H_load = E_k/Pw
    pass = c1 && c2 && c3 && c4 && c5 && c6;
    allpass = allpass && pass;

    fprintf('  %-4s  H=[%.2f %.2f %.2f]  F=[%.3f %.3f %.3f]  H_load=%.4f s  E_k=%.3f GW·s  [%s]\n', ...
        mx.id, H(1),H(2),H(3), F(1),F(2),F(3), info.H_load, info.E_k_load/1e9, tf(pass));

    rows(i,:) = {mx.id, H(1),H(2),H(3), F(1),F(2),F(3), sum(F), ...
                 info.S_B(1)/1e6, info.E_k_load/1e9, info.H_load};
    % (S_BB and S_BC are recoverable from F; store S_BA + aggregate to keep the table compact)
end

T = cell2table(rows, 'VariableNames', ...
    {'id','H_A','H_B','H_C','F_mA','F_mB','F_mC','phi','S_BA_MVA','Ek_GWs','H_load_s'});
fprintf('\n----- T1 identities: %s -----\n', tf(allpass));
disp(T);
assert(allpass, 't1_open_loop:identityFail', 'T1 algebraic identities did not all hold');

% --- OPTIONAL model-faithfulness settle (the one % RUN: point) ---------------
if o.Sim
    mdir = o.ModelPath; if isempty(mdir), mdir = fullfile(sc,'models','cmld_3m.slx'); end
    M = S.corners.(o.Corner)(1);  SCR = S.corners.(o.Corner)(2);
    fprintf('\n==== T1 settle P-match (%s corner, model %s) ====\n', o.Corner, mdir);
    Pmatch = nan(nrow,1);
    for i = 1:nrow
        mx = S.mix(i);
        p = sb_grid_sim.default_params('full_cmld');
        p.grid.M = M;  p.grid.SCR = SCR;  p.model_path = mdir;
        p.solver.SettleTime = 40;  p.solver.StopTime = p.disturbance.dist_time + 3;
        p.model_vars = compose_heterogeneous(mx.H, mx.F, 'Pw',Pw, 'LF',LF, 'Rrscale',S.Rrscale);
        % % RUN: settle (disturbance auto-disabled during init); read pre-step P_load
        %        expected: P_load within PTol of P_W = 2405 MW at every mix
        r  = sb_grid_sim.simulate(p);
        td = r.meta.dist_time_abs;
        P0 = mean(r.P(r.t < td & r.t > td-1));
        Pmatch(i) = P0/Pw - 1;
        fprintf('  %-4s  P_load=%.1f MW  (%+.2f%% vs P_W)  [%s]\n', ...
            mx.id, P0/1e6, 100*Pmatch(i), tf(abs(Pmatch(i)) < o.PTol));
    end
    T.Pmatch_pct = 100*Pmatch;
end

save(fullfile(sc,'t1_open_loop.mat'), 'T');
fprintf('\nT1_OPEN_LOOP_OK  (table -> t1_open_loop.mat)\n');
end

% =============================== helpers =====================================
function ok = relok(a, b, tol)
a = a(:); b = b(:);
den = max(abs(b), eps);
ok = all(abs(a-b)./den < tol);
end
function s = tf(b), if b, s = 'PASS'; else, s = 'FAIL'; end, end
