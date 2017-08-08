function [sts, import, sourceinfo] = pspm_get_eyelink(datafile, import)
% pspm_get_eyelink is the main function for import of SR Research Eyelink 1000
% files. 
%
% FORMAT: [sts, import, sourceinfo] = pspm_get_eyelink(datafile, import);
%__________________________________________________________________________
% PsPM 3.0
% (C) 2008-2015 Tobias Moser (University of Zurich)

% $Id$
% $Rev$

% initialise
% -------------------------------------------------------------------------
global settings;
if isempty(settings), pspm_init; end;
sourceinfo = []; sts = -1;
% add specific import path for specific import function
addpath([settings.path, 'Import', filesep, 'eyelink']);

% load data with specific function
% -------------------------------------------------------------------------
data = import_eyelink(datafile);

% iterate through data and fill up channel list as long as there is no
% marker channel. if there is any marker channel, the settings accordingly
% markerinfos, markers and marker type.
% -------------------------------------------------------------------------

% ensure sessions have the same samplerate
sr = cell2mat(cellfun(@(d) d.sampleRate, data, 'UniformOutput', false));
eyesObs = cellfun(@(d) d.eyesObserved, data, 'UniformOutput', false);
if numel(data) > 1 && (any(diff(sr)) || any(~strcmp(eyesObs,eyesObs{1})))
    warning('ID:invalid_data_structure', ['Cannot concatenate multiple sessions with different ', ... 
        'sample rate or different eye observation.']);
    % channels
    channels = data{1}.channels;
    % samplerate
    sampleRate = data{1}.sampleRate;
    % markers
    markers = data{1}.markers;
    % markerinfos
    markerinfos = data{1}.markerinfos;
    % units
    units = data{1}.units;
else
    % try to concatenate sessions according to timing
    sr = data{1}.sampleRate;
    last_time = data{1}.raw(1,1);
    
    channels = [];
    markers = [];
    
    mi_value = [];
    mi_name = {};
    
    n_cols = size(data{1}.channels, 2);
    counter = 1;
    
    for c = 1:numel(data)
        if sr ~= data{c}.sampleRate
            warning('ID:invalid_input', ['File consists of multiple ', ...
                'sessions with different sample rates: Unable to concatenate sessions.']);
            return;
        end
        
        start_time = data{c}.raw(1,1);
        end_time = data{c}.raw(end,1);
            
        n_diff = start_time - last_time;
        if n_diff > 0
            % channels and markers
            channels(counter:(counter+n_diff-1),1:n_cols) = NaN(n_diff, n_cols);
            markers(counter:(counter+n_diff-1), 1) = NaN(n_diff, 1);
            
            % markerinfos
            mi_value(counter:(counter+n_diff-1),1) = NaN(n_diff, 1);
            mi_name(counter:(counter+n_diff-1), 1) = {NaN};
            
            counter = counter + n_diff;
        end
        
        n_data = size(data{c}.channels, 1);
        
        % channels and markers
        channels(counter:(counter+n_data-1),1:n_cols) = data{c}.channels;
        markers(counter:(counter+n_data-1),1) = data{c}.markers;
        
        % markerinfos
        mi_value(counter:(counter+n_data-1),1) = data{c}.markerinfos.value;
        mi_name(counter:(counter+n_data-1),1) = data{c}.markerinfos.name;
        
        counter = counter + n_data;
        last_time = end_time;
    end
    
    markerinfos.name = mi_name;
    markerinfos.value = mi_value;
    
    % units (they should be for all channels the same)
    units = data{1}.units;
    
    % samplerate
    sampleRate = sr;
end

for k = 1:numel(import)
    if strcmpi(import{k}.type, 'marker')
        import{k}.marker = 'continuous';
        import{k}.sr     = sampleRate;
        import{k}.data   = markers;
        % marker info is read and set (in this instance) but
        % imported data cannot be read at the moment (in later instances)
        import{k}.markerinfo = markerinfos;
        
        % use ascending flank for translation from continuous to events
        import{k}.flank = 'ascending';
    else
        chan = import{k}.channel;
        if chan > size(channels, 2), warning('ID:channel_not_contained_in_file', 'Column %02.0f not contained in file %s.\n', chan, datafile); return; end;
        import{k}.sr = sampleRate;
        import{k}.data = channels(:, chan);
        import{k}.units = units{import{k}.channel};
        sourceinfo.chan{k, 1} = sprintf('Column %02.0f', chan);
    end
end

% extract record time and date / should be in all sessions the same
sourceinfo.date = data{1}.record_date;
sourceinfo.time = data{1}.record_time;
% other record settings
sourceinfo.gaze_coords = data{1}.gaze_coords;
sourceinfo.elcl_proc = data{1}.elcl_proc;
sourceinfo.eyesObserved = data{1}.eyesObserved;

% create invalid data stats
n_data = size(channels,1);

% count invalid data
n_inv_data = sum(isnan(channels(:,strcmpi(data{1}.units, 'area') | ...
    strcmpi(data{1}.units, 'diameter'))));

% count blink and saccades (combined in blink channel at the moment)
n_bns = sum(channels(:,strcmpi(data{1}.units, 'blink')) == 1);

ids = struct();
ids.invalid_data = n_inv_data ./ [n_data n_data];
ids.blinks_saccades = n_bns ./ n_inv_data;
ids.other = 1 - ids.blinks_saccades;

sourceinfo.invalid_data_stats = ids;

% remove specific import path
rmpath([settings.path, 'Import', filesep, 'eyelink']);

sts = 1;
return;

