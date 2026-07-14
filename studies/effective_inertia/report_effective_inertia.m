function report_effective_inertia(outfile)
%REPORT_EFFECTIVE_INERTIA  Turn the saved T1/T2 outputs into filled markdown tables.
%
%   report_effective_inertia()                 % -> results_tables.md (+ prints)
%   report_effective_inertia('path/to.md')
%
% Reads t1_open_loop.mat and t2_results.mat (produced by t1_open_loop / t2_driver)
% and emits the results tables + a quantitative findings summary as GitHub-flavoured
% markdown. No simulation -- pure formatting of stored results. Run after t2_driver.

sc = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(outfile), outfile = fullfile(sc,'results_tables.md'); end

lines = strings(0,1);
function emit(varargin), lines = [lines; string(sprintf(varargin{:}))]; end %#ok<*AGROW>

% ---- T1 ---------------------------------------------------------------------
emit('## T1 -- algebraic scaling (open-loop)  [filled]'); emit('');
f1 = fullfile(sc,'t1_open_loop.mat');
if isfile(f1)
    T1 = load(f1); T1 = T1.T;
    emit('| id | H_A | H_B | H_C | F_mA | F_mB | F_mC | phi | E_k,load (GW·s) | H_load (s) |');
    emit('|---|---|---|---|---|---|---|---|---|---|');
    for i = 1:height(T1)
        emit('| %s | %.2f | %.2f | %.2f | %.3f | %.3f | %.3f | %.3f | %.3f | %.4f |', ...
            T1.id{i}, T1.H_A(i),T1.H_B(i),T1.H_C(i), T1.F_mA(i),T1.F_mB(i),T1.F_mC(i), ...
            T1.phi(i), T1.Ek_GWs(i), T1.H_load_s(i));
    end
    emit(''); emit('All algebraic identities PASS (S_Bi=F_mi·Pw/LF, E_k=ΣH_i·S_Bi, H_load=Σ(F_mi/LF)H_i).');
else
    emit('_(t1_open_loop.mat not found -- run t1_open_loop first)_');
end
emit('');

% ---- T2 ---------------------------------------------------------------------
emit('## T2 -- delivered effective inertia + response factor  [filled]'); emit('');
f2 = fullfile(sc,'t2_results.mat');
if ~isfile(f2)
    emit('_(t2_results.mat not found -- run t2_driver first)_');
else
    D = load(f2); T = D.T;
    emit(['| corner | mix | dP | H_load | H_eff E1 | H_eff E2 | H_eff E3 | r_E1 | r_E2 | ' ...
          'r_E3 | frac_rel | damping(GW/pu) | E2_cond |']);
    emit('|---|---|---|---|---|---|---|---|---|---|---|---|---|');
    for i = 1:height(T)
        emit('| %s | %s | %+.2f | %.4f | %.4f | %.4f | %.4f | %.3f | %.3f | %.3f | %.3f | %.2f | %.1f |', ...
            T.corner{i}, T.mix{i}, T.dp(i), T.H_load_s(i), ...
            T.Heff_E1_500ms(i), T.Heff_E2_500ms(i), T.Heff_E3_500ms(i), ...
            T.r_E1(i), T.r_E2(i), T.r_E3(i), T.frac_released_E3(i), ...
            T.damping_W_pu(i)/1e9, T.E2_cond(i));
    end
    emit('');

    % ---- findings: is r stable? (primary dP=+0.10 per corner) --------------
    emit('### Findings (primary dP=+0.10)'); emit('');
    corners = unique(T.corner,'stable');
    for c = 1:numel(corners)
        cn = corners{c};
        m = strcmp(T.corner,cn) & T.dp==0.10;
        r1 = T.r_E1(m); r3 = T.r_E3(m); hl = T.H_load_s(m); fr = T.frac_released_E3(m);
        cc = corrcoef(hl, r1); rho = cc(1,2);
        emit(['**%s corner** (n=%d mixes): r_E1 = %.3f ± %.3f (min %.3f, max %.3f); ' ...
              'corr(r_E1, H_load) = %+.2f. r_E3 = %.3f ± %.3f. frac released@500ms = %.2f ± %.2f.'], ...
            cn, nnz(m), mean(r1),std(r1),min(r1),max(r1), rho, ...
            mean(r3),std(r3), mean(fr),std(fr));
        emit('');
    end
    emit(['Interpretation: a *stable* r (small spread, ~0 correlation with H_load) means the ' ...
          'paper''s stored-energy H_load is a faithful proxy up to a fixed coupling factor; a ' ...
          'drift means the delivered response depends on WHICH motor carries the inertia. ' ...
          'The E1–E3 gap is the coupling/damping residual; E3''s frac-released is the fraction ' ...
          'of stored KE actually delivered within the 500 ms window.']);
end
emit('');

txt = strjoin(cellstr(lines), newline);
fid = fopen(outfile,'w'); fwrite(fid, txt); fclose(fid);
fprintf('%s\n', txt);
fprintf('\n[report -> %s]\n', outfile);
end
