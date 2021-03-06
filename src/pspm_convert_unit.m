function [sts, converted] = pspm_convert_unit(data, from, to)
% pspm_convert_unit is a function to convert between different units
% currently only length units are possible.
%
% FORMAT:
%   [sts, converted] = pspm_convert_unit(data, from, to)
%
% ARGUMENTS:
%   data:               The data which should be converted. Must be a numeric 
%                       array of any shape.
%   from:               Unit of the input vector.
%   to:                 Unit of the output vector.
% 
% Valid units are currently mm, cm, dm, m, km, in, inches
%______________________________________________________________________________
% PsPM 4.0
% (C) 2018 Tobias Moser (University of Zurich)

% $Id: pspm_convert_au2mm.m 501 2017-11-24 08:36:53Z tmoser $
% $Rev: 501 $

% initialise
% -----------------------------------------------------------------------------
global settings;
if isempty(settings), pspm_init; end
sts = -1;
converted = [];

% define conversion settings
converter = struct('length', ...
    struct(...
        'value', {'mm', 'cm', 'dm', 'm', 'km', 'in', 'inches'}, ...
        'factor', {10^-3, 10^-2, 10^-1, 1, 10^3, 2.54e-2, 2.54e-2}...
));

% input checks
% -----------------------------------------------------------------------------
if ~isnumeric(data)
    warning('ID:invalid_input', 'Data is not numeric.'); 
    return;
elseif ~(isstr(from) && isstr(to) && all(ismember({from, to}, {converter.length.value})))
    valid_units_str = join({converter.length.value}, ', ');
    valid_units_str = valid_units_str{1};
    warning('ID:invalid_input', 'Both units must be string and must be one of %s.\n', valid_units_str);
    return;
end

[~, from_idx] = ismember(from, {converter.length.value});
[~, to_idx] = ismember(to, {converter.length.value});

from_fact = converter.length(from_idx).factor;
to_fact = converter.length(to_idx).factor;

converted = data*from_fact/to_fact;
sts = 1;
end
