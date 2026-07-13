function P = init_load_internals(loadType, varargin)
%SB_GRID_SIM.INIT_LOAD_INTERNALS  Bridge-free load-internal baseline for the
% hand-authored T1/T2 models. Wire this as the model PreLoadFcn.
%
%   sb_grid_sim.init_load_internals('T2')            % full CMLD (== 'full_cmld')
%   sb_grid_sim.init_load_internals('T1')            % static     (== 'static')
%   P = sb_grid_sim.init_load_internals('T2','P',P_W,'Q',Q_var,'busKV',kV)
%
% Replaces the old init_testbench_params(...) PreLoadFcn (which lived on the H:
% Google-Drive bridge and pulled the AU14 data tree). Sets ONLY the LOAD-INTERNAL
% base-workspace variables the models resolve that the engine's apply_params does
% NOT own -- i.e. the motor equivalent circuits (incl. Stator/Lm, which apply_params
% never sets), the composition loads, and the shunt cap CapC. The grid Thevenin,
% disturbance and solver variables remain owned by sb_grid_sim.apply_params and are
% deliberately NOT set here; apply_params runs after load and overrides P_W/Q_var
% and the study-swept motor vars (via model_vars). So this only provides the
% self-contained BASELINE that lets a model open/compile with no bridge.
%
% Values come from sb_grid_sim.cmld_params_for (the vendored authoritative recipe)
% at the bus-313 baseline P=2405 MW / Q=240 MVAr / 220 kV by default.

ip = inputParser;
ip.addParameter('P', 2405e6); ip.addParameter('Q', 240e6); ip.addParameter('busKV', 220);
ip.parse(varargin{:}); o = ip.Results;

lt = upper(string(loadType));
% baseline nominal load so a model opens standalone; apply_params overrides these.
assignin('base','P_W',   o.P);
assignin('base','Q_var', o.Q);

if lt=="T1" || lt=="STATIC"
    % static model's load block reads P_W / Q_var directly -- nothing else needed.
    P = struct('P_W',o.P,'Q_var',o.Q);
    return;
end

% --- T2 / full_cmld: motor + composition + cap internals from the recipe -----
C = sb_grid_sim.cmld_params_for(o.P, o.Q, o.busKV);
Vmot = 11e3;                                    % motors sit behind the substation xfmr
for X = ['A' 'B' 'C']
    m = C.(X);
    assignin('base', ['Motor' X '_Nom'],    [m.Nom(1) Vmot 50]);
    assignin('base', ['Motor' X '_Stator'], m.Stator);
    assignin('base', ['Motor' X '_Rotor'],  m.Rotor);
    assignin('base', ['Motor' X '_Lm'],     m.Lm);
    assignin('base', ['Motor' X '_Mech'],   m.Mech);
    assignin('base', ['Motor' X '_IC'],     m.IC);
    assignin('base', ['Motor' X '_Pmec'],   m.Pmec);
    assignin('base', ['Motor' X '_Tm'],     m.Tm);
end
assignin('base','CMLD_ElecP', C.ElecP);
assignin('base','P0',         C.StaticP);
assignin('base','Q0',         C.StaticQ);
assignin('base','Pfrq',       1.0);
assignin('base','CapC',       C.CapC);          % now WIRED into the shunt caps
P = C;
end
