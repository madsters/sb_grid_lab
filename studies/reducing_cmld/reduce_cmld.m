function T = reduce_cmld(level, varargin)
%REDUCE_CMLD  Regression-tested CMLD model-reduction driver.
%
%   T = reduce_cmld('L0')                 % replication: 2x(1/2) CMLD vs 1 CMLD
%   T = reduce_cmld('L1','Corner','stress')
%   T = reduce_cmld('L1','Corner','both','Pool',4)
%
% Runs the FULL model and each REDUCED candidate under identical conditions,
% through sb_grid_testbench.run_point (dedup + SQLite + trace .mat), then calls
% equiv_report for the gate + two-part error metric + H_eff + verdict + the
% paired frequency/active-power figure. See studies/reducing_cmld/plan.md.
%
% Reduction levels (plan §3):
%   L0  full=cmld_3m_2x (2 identical CMLD, 1/2 power each)  reduced=cmld_3m       [exact]
%   L1  full=cmld_3m (motors A+B+C)     reduced=cmld_1m_ct, cmld_1m_vt           [lossy]
%   L2  full=cmld_3m (elec+static)      reduced=cmld_3m_elec (foil: cmld_3m_stat) [lossy]
%
% Design point (plan §4.1, from the sensitivity study, realistic ceiling):
%   H = 1.5 s,  Rr-scale = 0.5,  phi = 0.8.  Common H across A/B/C -> H_eq = 1.5.
%
% Options:  'Corner' 'stress'|'nominal'|'both'   'Pool' n   'Static' true
%           'DP' signed step fractions (default [.1 .25 .4] both signs)
%
% MODELS ARE HAND-AUTHORED and loaded READ-ONLY; all params (incl. the equivalent
% motor / aggregated load) are supplied as model-owned base-workspace vars via
% params.model_vars. Author the .slx listed in plan §7 into models/ (below) so
% each reads the model_vars this driver composes.

ip = inputParser;
ip.addParameter('Corner','stress');
ip.addParameter('Pool',4);                 % RAM-bound: keep <=4 on this box
ip.addParameter('Static',true);            % run a static ref for absolute H_eff
ip.addParameter('DP',[0.10 0.25 0.40]);    % magnitudes; both signs are added
ip.addParameter('ST',15);                  % settle time (s)
ip.addParameter('RT',12);                  % disturbance-run stop (s; >= TraceWin+buffer)
ip.addParameter('TraceWin',10);
ip.parse(varargin{:}); o = ip.Results;

sc     = fileparts(mfilename('fullpath'));      % studies/reducing_cmld
repo   = fileparts(fileparts(sc));              % sb_grid_lab
mdir   = fullfile(sc,'models');
db     = fullfile(sc,'reducing_cmld.db');
raw    = fullfile(sc,'reducing_cmld_raw');
figdir = fullfile(repo,'results','fig'); if ~isfolder(figdir), mkdir(figdir); end

DP  = o.DP(:)'; dpset = [DP, -DP];              % both signs
Hd = 1.5; Rrd = 0.5; phid = 0.8;                % design point (plan §4.1)

% corners (plan §4):  [M  SCR]
corners = struct('stress',[3 5], 'nominal',[5.5 8]);
switch lower(o.Corner)
    case 'both', cnames = {'stress','nominal'};
    otherwise,   cnames = {lower(o.Corner)};
end

% ----- level -> (full model, reduced candidates, composers, class) ----------
[fullmodel, reds, class] = level_spec(level);

% ----- shared persistent Simulink cache (parallel-safe, cross-launch) -------
cdir = fullfile(tempdir,'sbgrid_slcache');
try
    Simulink.fileGenControl('set','CacheFolder',cdir,'CreateDir',true);
catch
end

% ----- guard: the hand-authored models must exist --------------------------
need = [{fullmodel}, cellfun(@(r) r.model, reds, 'uni',0)];
if o.Static, need = [need, {'static'}]; end
assert_models_present(need, mdir);

if isempty(gcp('nocreate')) && o.Pool>1, parpool('local',o.Pool); end

% ----- run every corner x disturbance x candidate ---------------------------
rows = {};
for ci = 1:numel(cnames)
    cn = cnames{ci}; M = corners.(cn)(1); SCR = corners.(cn)(2);
    fprintf('\n==== %s corner %s: M=%g SCR=%g  (H=%.2f Rr=%.2f phi=%.2f) ====\n', ...
            upper(level), cn, M, SCR, Hd, Rrd, phid);

    for dp = dpset
        tag = sprintf('%s_%s_dp%+.2f', level, cn, dp);

        % FULL reference
        pf = mkparams('full_cmld', fullfile(mdir,[fullmodel '.slx']), M,SCR,dp,o);
        pf.model_vars = compose_full_or_2x(fullmodel, phid, Hd, Rrd);
        rf = sb_grid_testbench.run_point(pf,'DBFile',db,'RawDir',raw);
        full = load_trace(rf.trace_path, dp*pf.scale.P_W);
        full.label = 'full';

        % STATIC reference (for absolute H_eff), optional/guarded
        stat = [];
        if o.Static
            ps = mkparams('static', fullfile(mdir,'static.slx'), M,SCR,dp,o);
            try
                rs = sb_grid_testbench.run_point(ps,'DBFile',db,'RawDir',raw);
                stat = load_trace(rs.trace_path, dp*ps.scale.P_W);
            catch ME
                warning('reduce_cmld:static','static ref skipped (%s)',ME.message);
            end
        end

        % each REDUCED candidate
        for k = 1:numel(reds)
            pr = mkparams('full_cmld', fullfile(mdir,[reds{k}.model '.slx']), M,SCR,dp,o);
            pr.model_vars = reds{k}.compose(phid, Hd, Rrd);
            rr = sb_grid_testbench.run_point(pr,'DBFile',db,'RawDir',raw);
            red = load_trace(rr.trace_path, dp*pr.scale.P_W);
            red.label = reds{k}.name;

            fig = fullfile(figdir, sprintf('reduce_%s_%s.png', tag, reds{k}.name));
            R = equiv_report(full, red, 'Static',stat, 'M_g1',M, ...
                    'Class',class, 'TraceWin',o.TraceWin, 'FigFile',fig, ...
                    'Title',sprintf('%s  %s  dP=%+.2f pu  %s vs full', upper(level),cn,dp,reds{k}.name));

            rows(end+1,:) = {level, cn, M, SCR, dp, reds{k}.name, ...
                100*R.rocof_oper_err, 100*R.dip_err, R.f_maxe, R.P_maxe, ...
                R.gate.pass, R.verdict}; %#ok<AGROW>
        end
    end
end

T = cell2table(rows, 'VariableNames', ...
    {'level','corner','M','SCR','dp','candidate', ...
     'rocof500_err_pct','dip_err_pct','f_maxe_pct','P_maxe_pct','gate_pass','verdict'});
save(fullfile(sc, sprintf('reduce_%s.mat',level)), 'T');
fprintf('\n===== %s summary =====\n', upper(level)); disp(T);
fprintf('figures -> %s\nREDUCE_%s_OK\n', figdir, upper(level));
end

% =========================== level specification ============================
function [fullmodel, reds, class] = level_spec(level)
switch upper(level)
    case 'L0'
        fullmodel = 'cmld_3m_2x'; class = 'exact';
        reds = {struct('name','1cmld','model','cmld_3m', ...
                       'compose',@(phi,H,Rr) compose_full(phi,H,Rr))};
    case 'L1'
        fullmodel = 'cmld_3m'; class = 'lossy';
        reds = {struct('name','ct','model','cmld_1m_ct', ...
                       'compose',@(phi,H,Rr) compose_1mot(phi,H,Rr,0)), ...   % constant torque
                struct('name','vt','model','cmld_1m_vt', ...
                       'compose',@(phi,H,Rr) compose_1mot(phi,H,Rr,2))};      % variable torque
    case 'L2'
        fullmodel = 'cmld_3m'; class = 'lossy';
        reds = {struct('name','elec','model','cmld_3m_elec', ...
                       'compose',@(phi,H,Rr) compose_passive(phi,H,Rr,'elec')), ...  % chosen
                struct('name','stat','model','cmld_3m_stat', ...
                       'compose',@(phi,H,Rr) compose_passive(phi,H,Rr,'stat'))};     % foil
    otherwise
        error('reduce_cmld:level','unknown level "%s" (L0..L2)', level);
end
end

% =========================== param assembly ================================
function p = mkparams(load_type, model_path, M, SCR, dp, o)
p = sb_grid_sim.default_params(load_type);
p.grid.M = M; p.grid.SCR = SCR;
p.disturbance.dist_dP_frac = dp;              % signed: + load rise, - load drop
p.solver.SettleTime = o.ST; p.solver.StopTime = o.RT;
p.model_path = model_path;                    % study-local hand-authored .slx
end

function tr = load_trace(trace_path, Pdist_W)
% Build the trace struct equiv_report wants from a run_point trace .mat.
S = load(trace_path); r = S.results;
tr = struct('t',r.t(:), 'f',r.f(:), 'P',r.P(:), 'V',r.V(:), ...
            'td', r.meta.dist_time_abs, 'Pref', r.meta.P_ref_g1, 'Pdist', Pdist_W);
end

% ===================== composition / equivalencing math =====================
% CONTRACT: these produce the model_vars each hand-authored .slx must read
% (plan §7). Motor baselines are the AEMO PSS/E CMLD defaults (per-unit, on each
% motor's own MVA base); A = constant-torque, B/C = variable-torque.

function b = motor_baseline()
% [Rs Lls], [Rr Llr], Lm, load fraction, torque exponent (0=const, 2=~w^2)
b.frac  = [0.152 0.166 0.129];               % A B C  (NSW annual avg)
b.Stator = {[0.02 0.072], [0.03 0.114], [0.03 0.114]};
b.Rotor  = {[0.05955 0.04937], [0.02810 0.07959], [0.02810 0.07959]};
b.Lm     = [1.728 1.686 1.686];
b.etrq   = [0 2 2];
b.LF     = 0.75;                             % loading factor
b.felec  = 0.337; b.fstat = 0.216;           % non-motor split
end

function mv = compose_full(phi, H, Rrscale, Pw)
% Full 3-motor CMLD at the design point.  mv holds MotorA/B/C_* + passive + CapC.
if nargin < 4, Pw = 2405e6; end
b = motor_baseline(); fm = sum(b.frac); L = 'ABC'; mv = struct();
for i = 1:3
    X = L(i);
    Pmec = phi*(b.frac(i)/fm)*Pw;  Pn = Pmec/b.LF;
    Rr = b.Rotor{i}(1)*Rrscale;  Llr = b.Rotor{i}(2);
    s  = deal_slip(Rr, b.LF);
    mv.(['Motor' X '_Nom'])    = [Pn 11000 50];
    mv.(['Motor' X '_Stator']) = b.Stator{i};
    mv.(['Motor' X '_Rotor'])  = [Rr Llr];
    mv.(['Motor' X '_Lm'])     = b.Lm(i);
    mv.(['Motor' X '_Mech'])   = [H 0 2];
    mv.(['Motor' X '_Pmec'])   = Pmec;
    mv.(['Motor' X '_Tm'])     = b.LF/(1-s);
    mv.(['Motor' X '_TrqExp']) = b.etrq(i);
    mv.(['Motor' X '_IC'])     = [s 0 0 0 0 0 -120 120];
end
mv = add_passive(mv, b, phi, Pw, 'split');   % elec + static as in the fixture
mv.CapC = 0.037092*(Pw/2405e6);
end

function mv = compose_1mot(phi, H, Rrscale, trqexp, Pw)
% L1: aggregate motors A+B+C -> ONE equivalent motor. MVA-weighted average of
% per-unit params (exact for identical motors; validated by L0). H_eq is the
% MVA-weighted H (= H here, since H is common -> so L1 tests torque/electrical
% abstraction, not inertia; plan §4.1). trqexp selects the torque law.
if nargin < 5, Pw = 2405e6; end
b = motor_baseline(); fm = sum(b.frac);
Pmec = phi*(b.frac/fm)*Pw;  S = Pmec/b.LF;  w = S/sum(S);   % MVA weights
Rs_eq  = w*cellfun(@(z)z(1), b.Stator)';   Lls_eq = w*cellfun(@(z)z(2), b.Stator)';
Rr_eq  = (w*cellfun(@(z)z(1), b.Rotor)')*Rrscale;
Llr_eq = w*cellfun(@(z)z(2), b.Rotor)';
Lm_eq  = w*b.Lm';   H_eq = H;                                % w*[H H H]' = H
Pmec_eq = sum(Pmec);  Pn_eq = Pmec_eq/b.LF;  s = deal_slip(Rr_eq, b.LF);
mv = struct();
mv.Motor_Nom    = [Pn_eq 11000 50];
mv.Motor_Stator = [Rs_eq Lls_eq];
mv.Motor_Rotor  = [Rr_eq Llr_eq];
mv.Motor_Lm     = Lm_eq;
mv.Motor_Mech   = [H_eq 0 2];
mv.Motor_Pmec   = Pmec_eq;
mv.Motor_Tm     = b.LF/(1-s);
mv.Motor_TrqExp = trqexp;                                    % 0=const, 2=variable
mv.Motor_IC     = [s 0 0 0 0 0 -120 120];
mv = add_passive(mv, b, phi, Pw, 'split');
mv.CapC = 0.037092*(Pw/2405e6);
end

function mv = compose_passive(phi, H, Rrscale, mode, Pw)
% L2: motors A+B+C unchanged (full); collapse elec+static into ONE block.
% mode 'elec' (chosen) = single electronic; 'stat' (foil) = single static ZIP.
if nargin < 5, Pw = 2405e6; end
mv = compose_full(phi, H, Rrscale, Pw);
b = motor_baseline();
% strip the split passive vars, replace with a single aggregated block
for f = {'CMLD_ElecP','P0','Q0'}, if isfield(mv,f{1}), mv = rmfield(mv,f{1}); end, end
mv = add_passive(mv, b, phi, Pw, mode);
end

function mv = add_passive(mv, b, phi, Pw, mode)
Pnm = (1-phi)*Pw;                            % total non-motor power
switch mode
    case 'split'                             % fixture: elec + static, ratio e:st
        e = b.felec/(b.felec+b.fstat);
        mv.CMLD_ElecP = e*Pnm;  mv.P0 = (1-e)*Pnm;  mv.Q0 = 0.20*mv.P0;
    case 'elec'                              % all non-motor -> one electronic
        mv.CMLD_ElecP = Pnm;    mv.P0 = 0;   mv.Q0 = 0;
    case 'stat'                              % all non-motor -> one static ZIP
        mv.CMLD_ElecP = 0;      mv.P0 = Pnm; mv.Q0 = 0.20*Pnm;
end
end

function mv = compose_full_or_2x(model, phi, H, Rr)
% cmld_3m -> one CMLD at full power. cmld_3m_2x -> TWO IDENTICAL copies of the
% same CMLD subsystem, both reading the SAME var names; we supply HALF-power
% values so each instance draws 1/2 and the pair totals full (L0 control). No
% per-instance prefixing needed -- the two copies share one model_vars set.
Pw = 2405e6;
if strcmp(model,'cmld_3m_2x')
    mv = compose_full(phi, H, Rr, 0.5*Pw);   % each of the 2 identical instances draws half
else
    mv = compose_full(phi, H, Rr, Pw);
end
end

% =============================== small utils ================================
function s = deal_slip(Rr, LF)
s = LF*Rr; for it = 1:8, s = (LF/(1-s))*Rr; end
end

function assert_models_present(names, mdir)
names = unique(names, 'stable'); missing = {};
for i = 1:numel(names)
    if ~isfile(fullfile(mdir, [names{i} '.slx'])), missing{end+1} = names{i}; end %#ok<AGROW>
end
if ~isempty(missing)
    error('reduce_cmld:missingModels', ...
        ['Author these hand-authored models into %s first (plan §7):\n  %s\n' ...
         'Each must honour docs/model-interface.md and read the model_vars this ' ...
         'driver composes.'], mdir, strjoin(strcat(missing,'.slx'), ', '));
end
end
