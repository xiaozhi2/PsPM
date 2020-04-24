function [sts, import, sourceinfo] = pspm_get_txt(datafile, import)
% pspm_get_txt is the main function for import of text files
%
% FORMAT: [sts, import, sourceinfo] = pspm_get_txt(datafile, import);
%       datafile: a .txt-file containing numerical data (with any
%                 delimiter) and optionally the channel names in the first
%                 line.
%__________________________________________________________________________
% PsPM 3.0
% (C) 2008-2015 Dominik R Bach (Wellcome Trust Centre for Neuroimaging)

% $Id$
% $Rev$

% v005 lr  23.09.2013 added support for channel names
% v004 lr  09.09.2013 removed bugs
% v003 drb 31.07.2013 changed for 3.0 architecture
% v002 drb 11.02.2011 comply with new pspm_import requirements
% v001 drb 16.9.2009


% initialise
% -------------------------------------------------------------------------
global settings;
if isempty(settings), pspm_init; end;
sourceinfo = []; sts = -1;

% load & check data
% -------------------------------------------------------------------------
header_lines_counter = 0;
% Check whether column seperator is specified
fid = fopen(datafile);
line = textscan(fgetl(fid), '%s');
delimiter = regexpi(line{:},'.*(sep=)([^\"]?).*','tokens');
if ~isempty(delimiter)
    % A delimiter is specified. 
    % increment the header line counter
    header_lines_counter = header_lines_counter+1;
    if length(delimiter{1}{1})==1
        % If second element is missing, assume TAB as delimiter
        delimiter = '\t';  
    else
        % else, second element is delimiter
        delimiter = delimiter{1}{1}{2};
    end
    % Load next line for checking channel names
    channel_names = textscan(fgetl(fid), '%s','Delimiter',delimiter);
else
    % No delimiter is specified; use Matlab default delimiters
    delimiter = {' ','\b','\t'};
    % Current line might be channel_names. assigne to corresponding
    % variable
    channel_names = line;
end

% Check next line for channel names
channel_names = channel_names{1};

fline = str2double(channel_names);
if ~any(isnan(fline)) %no headerline
    % close previously openend fil. this is done here so further header
    % lines can be detected below
    fclose(fid);
    % read data from all channels
    data = dlmread(datafile);
elseif all(isnan(fline)) %headerline
    % check for more potential header lines
    while all(isnan(fline))
        % increment the header line counter
        header_lines_counter = header_lines_counter+1;
        line = textscan(fgetl(fid), '%s','Delimiter',delimiter);
        fline = str2double(line{1});
    end
    % close and reopen file
    fclose(fid);
    fid = fopen(datafile);
    formatSpec = '';
    for i=1:numel(channel_names)
        formatSpec = [formatSpec '%f'];
    end
    data = textscan(fid, formatSpec, 'Delimiter',delimiter,'HeaderLines', 3);
    data = cell2mat(data);
    fclose(fid);
else
    warning('The format of %s is not supported', datafile); return;
end

if isempty(data), warning('An error occured while reading a textfile.\n'); return; end;
    

% select desired channels
% -------------------------------------------------------------------------
for k = 1:numel(import)
    % define channel number
    if import{k}.channel > 0
        chan = import{k}.channel;
    else
        chan = pspm_find_channel(channel_names, import{k}.type);
        if chan < 1, return; end;
    end;
    
    if chan > size(data, 2), warning('ID:channel_not_contained_in_file', 'Channel %02.0f not contained in file %s.\n', chan, datafile); return; end;
    
    import{k}.data = data(:, chan);
    
    if strcmpi(settings.chantypes(import{k}.typeno).data, 'events')
        import{k}.marker = 'continuous';
    end;
    
    sourceinfo.chan{k} = sprintf('Data column %02.0', chan);
end;

sts = 1;
return;
