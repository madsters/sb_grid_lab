function l1_figure(H)
%L1_FIGURE  Answers study Q2.2: can the 3 three-phase motors (A+B+C) of the CMLD
% collapse to ONE equivalent three-phase motor, and should it be constant- or
% variable-torque? Same demand/supply layout as motivating_figure, but the lines
% are the FULL 3-motor CMLD (cmld_3m) vs the two single-motor equivalents
% (cmld_1m_ct constant torque, cmld_1m_vt variable torque ~w^2). All three are
% pinned to 1 pu pre-disturbance (LFm) and hit with the same matched-MW step.
%   l1_figure(2.5)   % use the H=2.5 traces (default)
if nargin < 1, H = 2.5; end
% this file lives in studies/reducing_cmld/L1_aggregation/, so repo is 4 levels up
repo = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
run(fullfile(repo,'startup_sbgrid.m'));
raw    = fullfile(repo,'studies','reducing_cmld','reducing_cmld_raw');
figdir = fileparts(mfilename('fullpath'));

% pick the load-rise trace nearest 1 pu for each of the three models, at H.
Pw = sb_grid_sim.default_params('static').scale.P_W;
[full, ct, vt] = deal([]); bf = inf; bc = inf; bv = inf;
f = dir(fullfile(raw,'*.mat'));
for i = 1:numel(f)
    S = load(fullfile(raw,f(i).name)); r = S.results;
    if r.params.disturbance.dist_dP_frac <= 0, continue; end        % load rise only
    td = r.meta.dist_time_abs; Ppre = mean(r.P(r.t<td & r.t>td-1)); d1 = abs(Ppre-Pw);
    [~,mb] = fileparts(r.params.model_path); mv = r.params.model_vars;
    switch mb
        case 'cmld_3m'
            if abs(mv.MotorA_Mech(1)-H)<0.05 && d1<bf, full = r; bf = d1; end
        case 'cmld_1m_ct'
            if abs(mv.Motor_Mech(1)-H)<0.05 && d1<bc, ct = r; bc = d1; end
        case 'cmld_1m_vt'
            if abs(mv.Motor_Mech(1)-H)<0.05 && d1<bv, vt = r; bv = d1; end
    end
end
assert(~isempty(full)&&~isempty(ct)&&~isempty(vt), ...
    'need cmld_3m + cmld_1m_ct + cmld_1m_vt (H=%.1f) load-rise traces (run reduce_cmld L1 H=%.1f first)', H, H);

dpfrac = full.params.disturbance.dist_dP_frac; Mg = full.params.grid.M; SCRg = full.params.grid.SCR;
dP = dpfrac*Pw; td = full.meta.dist_time_abs; t0 = td-1; f0 = 50;

% discriminating error vs the full model (P-load trace, post-disturbance window)
maxe = @(r) trace_maxe(r, full, td, 10);
ct_pe = maxe(ct); vt_pe = maxe(vt);
rerr = @(r) abs(abs(r.metrics.RoCoF)-abs(full.metrics.RoCoF))/abs(full.metrics.RoCoF)*100;
derr = @(r) abs(r.metrics.dip-full.metrics.dip)/full.metrics.dip*100;
fprintf('\n== L1 motor aggregation (H=%.1f, M=%g, SCR=%g, +%.2f pu) ==\n', H, Mg, SCRg, dpfrac);
fprintf('  variable-torque : RoCoF err %.1f%%  dip err %.1f%%  P-trace maxE %.1f%%\n', rerr(vt),derr(vt),vt_pe);
fprintf('  constant-torque : RoCoF err %.1f%%  dip err %.1f%%  P-trace maxE %.1f%%\n', rerr(ct),derr(ct),ct_pe);

% colours: full = black (reference), vt = blue, ct = red (dashed)
cF = [0 0 0]; cV = [0 .45 .74]; cC = [.85 .10 .10];
sm = @(x) movmean(movmedian(x(:),151),151);
% swing constant K calibrated on the full model at the step instant (motors give
% no instantaneous inertia, so the instant RoCoF is grid-only -- plan 5.6).
wi = full.t>=td & full.t<=td+0.1; pf = polyfit(full.t(wi),full.f(wi),1);
K  = abs(dP)*f0/abs(pf(1));
load_of = @(r) sm(r.P) + dP*(r.t(:)>=td);
gen_of  = @(r) movmean(r.P(:) + dP*(r.t(:)>=td) + K*gradient(r.f(:),r.t(:))/f0, 201);

fig = figure('Visible','off','Position',[100 100 1000 1040]);

% -- Panel 1: frequency --
ax1 = subplot(3,1,1); hold(ax1,'on'); grid(ax1,'on');
plot(ax1, full.t, full.f, 'Color',cF, 'LineWidth',2.0, 'DisplayName','full (3 motors)');
plot(ax1, vt.t,   vt.f,   'Color',cV, 'LineWidth',1.5, 'DisplayName','variable-torque (1 motor)');
plot(ax1, ct.t,   ct.f,   'Color',cC, 'LineWidth',1.5, 'LineStyle','--', 'DisplayName','constant-torque (1 motor)');
xline(ax1, td, ':', 'HandleVisibility','off');
xlim(ax1,[t0 td+10]); ylabel(ax1,'frequency (Hz)'); legend(ax1,'Location','southeast');
title(ax1, sprintf(['Motor aggregation (3\\rightarrow1): full CMLD vs single constant- / variable-torque equivalent\n' ...
    '+%.2f pu load step (M = %g s, SCR = %g)  --  variable-torque P-trace error %.1f%%, constant-torque %.1f%%'], ...
    dpfrac, Mg, SCRg, vt_pe, ct_pe));

% -- Panel 2: LOAD active power (demand) = own draw + disturbance step --
ax2 = subplot(3,1,2); hold(ax2,'on'); grid(ax2,'on');
Lf = load_of(full); Lv = load_of(vt); Lc = load_of(ct);
plot(ax2, full.t, Lf/1e6, 'Color',cF, 'LineWidth',2.0, 'DisplayName','full (3 motors)');
plot(ax2, vt.t,   Lv/1e6, 'Color',cV, 'LineWidth',1.5, 'DisplayName','variable-torque (1 motor)');
plot(ax2, ct.t,   Lc/1e6, 'Color',cC, 'LineWidth',1.5, 'LineStyle','--', 'DisplayName','constant-torque (1 motor)');
xline(ax2, td, ':', 'HandleVisibility','off');
xlim(ax2,[t0 td+10]); ylabel(ax2,'load active power (MW)');
title(ax2,'Load active power (demand)'); legend(ax2,'Location','southeast');

% -- Panel 3: GENERATION active power (supply) = swing/governor response --
ax3 = subplot(3,1,3); hold(ax3,'on'); grid(ax3,'on');
Gf = gen_of(full); Gv = gen_of(vt); Gc = gen_of(ct);
plot(ax3, full.t, Gf/1e6, 'Color',cF, 'LineWidth',2.0, 'DisplayName','full (3 motors)');
plot(ax3, vt.t,   Gv/1e6, 'Color',cV, 'LineWidth',1.5, 'DisplayName','variable-torque (1 motor)');
plot(ax3, ct.t,   Gc/1e6, 'Color',cC, 'LineWidth',1.5, 'LineStyle','--', 'DisplayName','constant-torque (1 motor)');
xline(ax3, td, ':', 'HandleVisibility','off');
xlim(ax3,[t0 td+10]); xlabel(ax3,'time (s)'); ylabel(ax3,'generation active power (MW)');
title(ax3,'Generation active power (supply)'); legend(ax3,'Location','southeast');

yl = [min([Lf;Lv;Lc;Gf;Gv;Gc]) max([Lf;Lv;Lc;Gf;Gv;Gc])]/1e6;
yl = yl + [-1 1]*0.04*max(diff(yl),eps); ylim(ax2,yl); ylim(ax3,yl);

rrscale = full.params.model_vars.MotorA_Rotor(1) / 0.05955;
out = fullfile(figdir, sprintf('l1_aggregation_Rr%.1f_dp%.2f.png', rrscale, dpfrac));
exportgraphics(fig, out, 'Resolution',150); close(fig);
fprintf('  figure -> %s\nL1_FIGURE_DONE\n', out);
end

function e = trace_maxe(red, full, td, T)
% max |P_red - P_full| / range(P_full) over [td, td+T], as a percent. P_load only
% (the disturbance step is common, so it cancels in the difference).
tt = full.t; win = tt>=td & tt<=td+T;
Pr = interp1(red.t, red.P, tt, 'linear','extrap');
e = max(abs(Pr(win)-full.P(win))) / (max(full.P(win))-min(full.P(win))) * 100;
end
