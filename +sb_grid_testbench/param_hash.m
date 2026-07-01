function h = param_hash(params)
%SB_GRID_TESTBENCH.PARAM_HASH  Stable canonical SHA-256 hash of a params struct.
%
%   h = sb_grid_testbench.param_hash(params)
%
% Returns a lowercase hex char row (64 chars) that is the dedup identity for a
% sim run (see contract 3). The hash is CANONICAL: it is invariant to struct
% field ORDER and to trivial floating-point noise, but distinguishes any real
% difference in parameter VALUES.
%
% How:
%   1. Recursively canonicalize the struct -- sort field names, round every
%      finite float to 12 significant digits, normalize numeric class/shape.
%   2. Serialize deterministically with jsonencode of the canonical form.
%   3. SHA-256 the UTF-8 bytes via java.security.MessageDigest (always present).
%
% Identical-MEANING params hash identically; field order and float round-off
% below the 12-sig-fig precision do NOT matter.

canon = canonicalize(params);
json  = jsonencode(canon);

md = java.security.MessageDigest.getInstance('SHA-256');
digest = md.digest(uint8(unicode2native(json, 'UTF-8')));      % int8 row, [-128,127]
bytes  = typecast(int8(digest), 'uint8');                      % -> uint8 [0,255]
h = lower(reshape(dec2hex(bytes, 2).', 1, []));                % hex char row
end

% -------------------------------------------------------------------------
function c = canonicalize(v)
%CANONICALIZE  Recursively normalize a value into a JSON-stable form.
if isstruct(v)
    if numel(v) ~= 1
        % struct array: canonicalize each element in order, wrap in a cell
        c = cell(1, numel(v));
        for k = 1:numel(v)
            c{k} = canonicalize(v(k));
        end
        % tag so a 1x1 struct cannot collide with a 1-element struct array
        c = struct('x__structarray__', {c});
        return
    end
    fn = sort(fieldnames(v));
    c = struct();
    for i = 1:numel(fn)
        % field names are valid identifiers, so they survive as-is in a struct
        c.(fn{i}) = canonicalize(v.(fn{i}));
    end

elseif iscell(v)
    c = cell(size(v));
    for k = 1:numel(v)
        c{k} = canonicalize(v{k});
    end

elseif ischar(v)
    c = v;

elseif isstring(v)
    % normalize string -> char so "x" and 'x' hash identically
    if isscalar(v)
        c = char(v);
    else
        c = cellfun(@char, cellstr(v), 'UniformOutput', false);
    end

elseif islogical(v)
    c = v;

elseif isnumeric(v)
    c = round_sig(double(v), 12);

else
    % function handles, objects, etc. -- fall back to a stable text form
    c = char(string(v));
end
end

% -------------------------------------------------------------------------
function y = round_sig(x, sig)
%ROUND_SIG  Round to SIG significant digits; leave 0/Inf/NaN untouched.
y = x;
m = isfinite(x) & (x ~= 0);
if any(m(:))
    e = floor(log10(abs(x(m))));
    f = 10.^(sig - 1 - e);
    y(m) = round(x(m) .* f) ./ f;
end
% normalize negative zero to zero
y(y == 0) = 0;
end
