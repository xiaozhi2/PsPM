function [sts, out] = pspm_convert_pixel2unit(fn, chan, width, height, options)
% Allows to transfer gaze data from pixel to units. This facilitates the
% use of pspm_find_valid_fixations() which needs data in unit values.
%
% Usage:
%   [sts, out] = pspm_convert_pixel2unit(fn, chan, unit, width, height, options)
%       
% Arguments:
%
%   fn:                         File to convert.
%   chan:                       On which subset of channels should the conversion
%                               be done. Supports all values which can be passed
%                               to pspm_load_data(). The will only work on
%                               gaze-channels. Other channels specified will be
%                               ignored.
%   unit:                       length unit in which height and width are given
%                               and to which the measurements should be
%                               converted
%   width:                      Width of the display window.
%   height:                     Height of the display window.
%   options:                    Options struct
%       channel_action:         'add', 'replace' new channels.
%       
% Return values:
%
%   sts:                        Status determining whether the execution was 
%                               successfull (sts == 1) or not (sts == -1)
%   out:                        Output struct
%       .channel                Id of the added channels.
%__________________________________________________________________________
% PsPM 4.0
% (C) 2016 Tobias Moser (University of Zurich)

% $Id: pspm_find_valid_fixations.m 512 2017-12-15 13:13:08Z tmoser $
% $Rev: 512 $
global settings;
if isempty(settings), pspm_init; end
sts = -1;


if nargin < 4
    warning('ID:invalid_input', 'Not enough arguments.');
    return;
end

% try to set default values
if ~exist('options', 'var')
    options = struct();
end

if ~isfield(options, 'channel_action') 
    options.channel_action = 'add';
end


% do value checks
if ~isstruct(options) 
    warning('ID:invalid_input', 'Options must be a struct.');
    return;
elseif ~isnumeric(width)
    warning('ID:invalid_input', 'Width must be numeric.');
    return;
elseif ~isnumeric(height)
    warning('ID:invalid_input', 'Height must be numeric.');
    return;
elseif ~ischar(unit)
    warning('ID:invalid_input', 'Unit must be a char.');
    return;
end

% load data to convert
[lsts, ~, data] = pspm_load_data(fn, chan);
if lsts ~= 1 
    warning('ID:invalid_input', 'Could not load input data correctly.');
    return;
end

% find gaze channels
gaze_idx = cellfun(@(x) ~isempty(...
    regexp(x.header.chantype, 'gaze_[x|y]_[r|l]', 'once')), data);

gaze_chans = data(gaze_idx);
n_chans = numel(gaze_chans);

% do conversion
for c = 1:n_chans
    chan = gaze_chans{c};
    if strcmpi(chan.header.units, 'pixel')

        % pick conversion factor according to channel type x / y coord
        if ~isempty(regexp(chan.header.chantype, 'gaze_x_', 'once'))
            fact = width;
        else
            fact = height;
        end

        % convert according to range
        chan.data = (chan.data-chan.header.range(1)) ...
            / diff(chan.header.range) * fact;

        % convert range
        chan.header.range = (chan.header.range-chan.header.range(1)) ...
            ./ diff(chan.header.range) * fact;

        chan.header.units = unit;
    else
        warning('ID:invalid_input', ['Not converting (%s) because ', ...
            'input data is not in pixel.'], chan.header.chantype);
    end

    % replace data 
    gaze_chans{c} = chan;
end

[lsts, outinfo] = pspm_write_channel(fn, gaze_chans, options.channel_action);
if lsts ~= 1
    warning('ID:invalid_input', 'Could not write converted data.');
    return;
end

sts = 1;
out = outinfo;

end