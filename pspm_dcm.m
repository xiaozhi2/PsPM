function dcm = pspm_dcm(model, options)
% SCR_DCM sets up a DCM for skin conductance, prepares and normalises the 
% data, passes it over to the model inversion routine, and saves both the 
% forward model and its inversion
%
% Both flexible-latency (within a response window) and fixed-latency 
% (evoked after a specified event) responses can be modelled. For fixed
% responses, delay and dispersion are assumed to be constant (either
% pre-determined or estimated from the data), while for flexible responses,
% both are estimated for each individual trial. Flexible responses can for
% example be anticipatory, decision-related, or evoked with unknown onset.
%
% FORMAT dcm = pspm_dcm(model, options)
%
% MODEL with required fields
% model.modelfile:  a file name for the model output
% model.datafile:   a file name (single session) OR
%                   a cell array of file names
% model.timing:     a file name/cell array of events (single session) OR
%                   a cell array of file names/cell arrays
%                   When specifying file names, each file must be a *.mat 
%                      file that contain a cell variable called 'events' 
%                   Each cell should contain either one column 
%                      (fixed response) or two columns (flexible response). 
%                   All matrices in the array need to have the same number 
%                    of rows, i.e. the event structure must be the same for 
%                    every trial. If this is not the case, include "dummy" 
%                    events with negative onsets
%
% and optional fields
% model.filter:     filter settings; modality specific default
% model.channel:    channel number; default: first SCR channel
% model.norm:       normalise data; default 0 (i. e. data are normalised
%                   during inversion but results transformed back into raw 
%                   data units)
%
% OPTIONS with optional fields:
% response function options
% - options.crfupdate: update CRF priors to observed SCRF, or use
%                      pre-estimated priors (default)
% - options.indrf: estimate the response function from the data (default 0)
% - options.getrf: only estimate RF, do not do trial-wise DCM
% - options.rf: call an external file to provide response function (for use
%               when this is previously estimated by pspm_get_rf)
%
% inversion options
% - options.depth: no of trials to invert at the same time (default: 2)
% - options.sfpre: sf-free window before first event (default 2 s)
% - options.sfpost: sf-free window after last event (default 5 s)
% - options.sffreq: maximum frequency of SF in ITIs (default 0.5/s)
% - options.sclpre: scl-change-free window before first event (default 2 s)
% - options.sclpost: scl-change-free window after last event (default 5 s)
% - options.aSCR_sigma_offset: minimum dispersion (standard deviation) for
%   flexible responses (default 0.1 s)
%
% display options
% - options.dispwin: display progress window (default 1)
% - options.dispsmallwin: display intermediate windows (default 0);
%
% output options
% - options.nosave: don't save dcm structure (e. g. used by pspm_get_rf)
%
% naming options
% - options.trlnames: cell array of names for individual trials, is used for
%   contrast manager only (e. g. condition descriptions)
% - options.eventnames: cell array of names for individual events, in the
%   order they are specified in the model.timing array - to be used for
%   display and export only
% 
% OUTPUT:   fn - name of the model file
%           dcm - model struct
%
% Output units: all timeunits are in seconds; eSCR and aSCR amplitude are
% in SN units such that an eSCR SN pulse with 1 unit amplitude causes an eSCR
% with 1 mcS amplitude
%
% pspm_dcm can handle NaN values in data channels. These are disregarded
% during model inversion, and trials containing NaNs are interpolated for
% averages and principal response components. It is not recommended to use
% this feature for missing data epochs with a duration of > 1-2 s
%
% REFERENCE: (1) Bach DR, Daunizeau J, Friston KJ, Dolan RJ (2010).
%            Dynamic causal modelling of anticipatory skin conductance 
%            changes. Biological Psychology, 85(1), 163-70
%            (2) Staib, M., Castegnetti, G., & Bach, D. R. (2015).
%            Optimising a model-based approach to inferring fear
%            learning from skin conductance responses. Journal of
%            Neuroscience Methods, 255, 131-138.
%
%__________________________________________________________________________
% PsPM 3.0
% (c) 2010-2015 Dominik R Bach (WTCN, UZH)

% $Id$  
% $Rev$

% function revision
rev = '$Rev$';

% initialise & set output
% ------------------------------------------------------------------------
global settings;
if isempty(settings), pspm_init; end;
warnings = {};

dcm = [];

% check input arguments & set defaults
% -------------------------------------------------------------------------
if nargin < 1
    warning('No data to work on.'); fn = []; return;
elseif nargin < 2
    options = struct([]);
end;


if ~isfield(model, 'datafile')
    warning('ID:invalid_input', 'No input data file specified.'); return;
elseif ~isfield(model, 'modelfile')
    warning('ID:invalid_input', 'No output model file specified.'); return;
elseif ~isfield(model, 'timing')
    warning('ID:invalid_input', 'No event onsets specified.'); return;
end;

% check faulty input --
if ~ischar(model.datafile) && ~iscell(model.datafile)
    warning('ID:invalid_input', 'Input data must be a cell or string.'); return;
elseif ~ischar(model.modelfile)
    warning('ID:invalid_input', 'Output model must be a string.'); return;
elseif ~ischar(model.timing) && ~iscell(model.timing) 
    warning('ID:invalid_input', 'Event definition must be a string or cell array.'); return;
end;

% get further input or set defaults --
% check data channel --
if ~isfield(model, 'channel')
    model.channel = 'scr'; % this returns the first SCR channel 
elseif ~isnumeric(model.channel)
    warning('ID:invalid_input', 'Channel number must be numeric.'); return;
end;


% check normalisation --
if ~isfield(model, 'norm')
    model.norm = 0;
elseif ~ismember(model.norm, [0, 1])
    warning('ID:invalid_input', 'Normalisation must be specified as 0 or 1.'); return; 
end;

% check filter --
if ~isfield(model, 'filter')
    model.filter = settings.dcm{1}.filter;
elseif ~isfield(model.filter, 'down') || ~isnumeric(model.filter.down)
    warning('ID:invalid_input', 'Filter structure needs a numeric ''down'' field.'); return;
end;

% set and check options ---
try options.indrf;   catch, options(1).indrf = 0;    end;
try options.getrf;   catch, options.getrf = 0;    end;
try options.rf;      catch, options.rf = 0;       end;
try options.nosave;  catch, options.nosave = 0;   end;
try options.overwrite; catch, options.overwrite = 0; end;
try options.substhresh; catch, options.substhresh = 2; end;
if options.indrf && options.rf
    warning('RF can be provided or estimated, not both.'); return;
end;
try options.method; catch, options.method = 'dcm'; end;


% check files --
if exist(model.modelfile) && options.overwrite == 0
    overwrite=menu(sprintf('Model file (%s) already exists. Overwrite?', model.modelfile), 'yes', 'no');
    if overwrite == 2, return, end;
end;

if ischar(model.datafile)
    model.datafile = {model.datafile};
    model.timing   = {model.timing};
end;

if numel(model.datafile) ~= numel(model.timing)
    warning('ID:number_of_elements_dont_match', 'Session numbers of data files and event definitions do not match.'); return;
end;

% check, get and prepare data
% ------------------------------------------------------------------------

% split into subsessions
% colnames: iSn start stop enabled (if contains events)
subsessions = [];
for iSn = 1:numel(model.datafile)
    % check & load data
    [sts, infos, data] = pspm_load_data(model.datafile{iSn}, model.channel);
    if sts == -1 || isempty(data)
        warning('No SCR data contained in file %s', model.datafile{iSn});
        return;
    end;
    model.filter.sr = data{1}.header.sr;
    missing = isnan(data{1}.data);
    
    d_miss = diff(missing)';
    miss_start = find(d_miss == 1);
    miss_stop = find(d_miss == -1);
    
    
    if numel(miss_start) > 0 || numel(miss_stop) > 0
        % check for blunt ends and fix
        if isempty(miss_start)
            miss_start = 1;
        elseif isempty(miss_stop)
            miss_stop = numel(d_miss);
        end;
        
        if miss_start(1) > miss_stop(1)
            miss_start = [1, miss_start];
        end;
        if miss_start(end) > miss_stop(end)
            miss_stop(end + 1) = numel(d_miss);
        end;
    end;
     
    % put missing epochs together
    miss_epochs = [miss_start', miss_stop'];
    % look for big epochs
    big_epochs = diff(miss_epochs, 1, 2)/data{1}.header.sr > options.substhresh;
    
    if any(big_epochs)
        b_e = find(big_epochs);
        
        se_start = [1; miss_epochs(b_e(1:end), 2) + 1];
        se_stop = [miss_epochs(b_e(1:end), 1)-1; numel(d_miss)];
        
        if se_stop(1) == 1
            se_start = se_start(2:end);
            se_stop = se_stop(2:end);
        end;
        
        if se_start(end) > length(d_miss)
            se_start = se_start(1:end-1);
            se_stop = se_stop(1:end-1);
        end;
        
        n_sbs = numel(se_start);
        subsessions(end+(1:n_sbs), 1:4) = [ones(n_sbs,1), [se_start, se_stop]/data{1}.header.sr, zeros(n_sbs,1)];
        n_miss = size(miss_epochs,1);
        subsessions(end+(1:n_miss), 1:4) = [ones(n_miss,1), miss_epochs/data{1}.header.sr, ones(n_miss,1)];
    else
        subsessions(end+1,1:4) = [iSn, [1, numel(data{1}.data)]/data{1}.header.sr, 0];
    end;
end;

% sort subsessions by start
subsessions = sortrows(subsessions);

% find missing values, interpolate and normalise ---
valid_subsessions = find(subsessions(:,4) == 0);
foo = {};
for vs = 1:numel(valid_subsessions)
    isbSn = valid_subsessions(vs);
    sbSn = subsessions(isbSn, :);
    flanks = round(sbSn(2:3)*data{1}.header.sr);
    sbSn_data = data{1}.data(flanks(1):flanks(2));
    sbs_missing{isbSn, 1} = isnan(sbSn_data);
    
    if any(sbs_missing{isbSn, 1})
        interpolateoptions = struct('extrapolate', 1);
        [~, sbSn_data] = pspm_interpolate(sbSn_data, interpolateoptions);
        clear interpolateoptions
    end;
    [sts, sbs_data{isbSn, 1}, model.sr] = pspm_prepdata(sbSn_data, model.filter);
    if sts == -1, return; end;
    foo{vs, 1} = (sbs_data{isbSn}(:) - mean(sbs_data{isbSn}));
end;

foo = cell2mat(foo);
model.zfactor = std(foo(:));
for vs = 1:numel(valid_subsessions)
    isbSn = valid_subsessions(vs);
    sbs_data{isbSn} = (sbs_data{isbSn}(:) - min(sbs_data{isbSn}))/model.zfactor;
end;
clear foo

% check & get events and group into flexible and fixed responses
% ------------------------------------------------------------------------
trials = {};
for iSn = 1:numel(model.timing)
    % initialise and get timing information -- 
    sn_newevents{1} = {}; sn_newevents{2} = {};
    [sts, events] = pspm_get_timing('events', model.timing{iSn});
    if sts ~=1, return; end;
    cEvnt = [1 1];
    % table with trial_id sbsnid
    %trials{iSn} = [ones(size(events{1},1),1),zeros(size(events{1},1),1)];
    % split up into flexible and fixed events --
    for iEvnt = 1:numel(events)
        if size(events{iEvnt}, 2) == 2 % flex
            sn_newevents{1}{iSn}(:, cEvnt(1), 1:2) = events{iEvnt};
            % assign event names
            if iSn == 1 && isfield(options, 'eventnames') && numel(options.eventnames) == numel(events)
                flexevntnames{cEvnt(1)} = options.eventnames{iEvnt};
            elseif iSn == 1
                flexevntnames{cEvnt(1)} = sprintf('Flexible response # %1.0f',cEvnt(1)); 
            end;
            % update counter
            cEvnt = cEvnt + [1 0];
        elseif size(events{iEvnt}, 2) == 1 % fix
            sn_newevents{2}{iSn}(:, cEvnt(2), 1) = events{iEvnt};
            % assign event names
            if iSn == 1 && isfield(options, 'eventnames') && numel(options.eventnames) == numel(events)
                fixevntnames{cEvnt(2)} = options.eventnames{iEvnt};
            elseif iSn == 1
                fixevntnames{cEvnt(2)} = sprintf('Fixed response # %1.0f',cEvnt(2)); 
            end;
            % update counter
            cEvnt = cEvnt + [0 1];
        end;
    end;
    cEvnt = cEvnt - [1, 1];
    % check number of events across sessions -- 
    if iSn == 1
        nEvnt = cEvnt;
    else
        if any(cEvnt ~= nEvnt)
            warning('Same number of events per trial required across all sessions.'); return;
        end;
    end;

    % find trialstart, trialstop and shortest ITI --
    sn_allevents = [reshape(sn_newevents{1}{iSn}, [size(sn_newevents{1}{iSn}, 1), size(sn_newevents{1}{iSn}, 2) * size(sn_newevents{1}{iSn}, 3)]), sn_newevents{2}{iSn}];
    sn_allevents(sn_allevents < 0) = inf;        % exclude "dummy" events with negative onsets
    sn_trlstart{iSn} = min(sn_allevents, [], 2); % first event per trial
    sn_allevents(isinf(sn_allevents)) = -inf;        % exclude "dummy" events with negative onsets
    sn_trlstop{iSn}  = max(sn_allevents, [], 2); % last event of per trial
    
    % assign trials to subsessions
    trls = num2cell([sn_trlstart{iSn}, sn_trlstop{iSn}],2);
    subs = cellfun(@(x) find(x(1) > subsessions(:, 2) & x(2) < (subsessions(:, 3)-options.substhresh) ... 
        & subsessions(:, 1) == iSn), trls, 'UniformOutput', 0);
    
    emp_subs = cellfun(@isempty, subs);
    if any(emp_subs)
        subs{emp_subs} = -1;
    end;
        
    % find enabled and disabled trials
    trlinfo = cellfun(@(x) x ~= -1 && subsessions(x, 4) == 0, subs, 'UniformOutput', 0);   
    trials{iSn} = [cell2mat(trlinfo), cell2mat(subs)];
    
    % cycle through subsessions
    sn_sbs = find(subsessions(:, 1) == iSn);
    for isn_sbs=1:numel(sn_sbs)
        sbs_id = sn_sbs(isn_sbs);
        sbs_trls = trials{iSn}(:, 1) == 1 & trials{iSn}(:,2) == sbs_id;
        if any(sbs_trls)
            sbs_trlstart{sbs_id} = sn_trlstart{iSn}(sbs_trls) - subsessions(sbs_id,2);
            sbs_trlstop{sbs_id} = sn_trlstop{iSn}(sbs_trls) - subsessions(sbs_id,2);
            sbs_iti{sbs_id} = [sbs_trlstart{sbs_id}(2:end); numel(sbs_data{sbs_id, 1})/model.sr] - sbs_trlstop{sbs_id};
            sbs_miniti(sbs_id) = min(sbs_iti{sbs_id});
            sbs_newevents{1}{sbs_id} = sn_newevents{1}{iSn}(sbs_trls,:,1:2) - subsessions(sbs_id,2);
            sbs_newevents{2}{sbs_id} = sn_newevents{2}{iSn}(sbs_trls,:,:) - subsessions(sbs_id,2);
            
            if sbs_miniti(iSn) < 0
                warning('Error in event definition. Either events are outside the file, or trials overlap.'); return;
            end;
        end;
    end;
        
end;

% find subsessions with events and define them to be processed
proc_subsessions = ~cellfun(@isempty, sbs_trlstart);
proc_miniti     =  sbs_miniti(proc_subsessions);
model.trlstart =  sbs_trlstart(proc_subsessions);
model.trlstop  =  sbs_trlstop(proc_subsessions);
model.iti      =  sbs_iti(proc_subsessions);
model.events   =  {sbs_newevents{1}(proc_subsessions), sbs_newevents{2}(proc_subsessions)};
model.scr      =  sbs_data(proc_subsessions);
options.missing  =  sbs_missing(proc_subsessions);

% prepare data for CRF estimation and for amplitude priors
% ------------------------------------------------------------------------
% get average event sequence per trial --
if nEvnt(1) > 0
    flexseq = cell2mat(model.events{1}') - repmat(cell2mat(model.trlstart'), [1, size(model.events{1}{1}, 2), 2]);
    flexseq(flexseq < 0) = NaN;
    flexevents = [];
    % this loop serves to avoid the function nanmean which is part of the
    % stats toolbox
    for k = 1:size(flexseq, 2)
        for m = 1:2
            foo = flexseq(:, k, m);
            flexevents(k, m) = mean(foo(~isnan(foo)));
        end;
    end;
else
    flexevents = [];
end;
if nEvnt(2) > 0
    fixseq  = cell2mat(model.events{2}') - repmat(cell2mat(model.trlstart'), 1, size(model.events{2}{1}, 2));
    fixseq(fixseq < 0) = NaN;
    fixevents = [];
    for k = 1:size(fixseq, 2)
        foo = fixseq(:, k);
        fixevents(k) = mean(foo(~isnan(foo)));
    end;
else
    fixevents = [];
end;
startevent = min([flexevents(:); fixevents(:)]);
flexevents = flexevents - startevent;
fixevents  = fixevents  - startevent;

options.flexevents = flexevents;
options.fixevents  = fixevents;

clear flexseq fixseq flexevents fixevents startevent

% check ITI --
if (options.indrf || options.getrf) && min(proc_miniti) < 5
    warnings{1} = ('Inter trial interval is too short to estimate individual CRF - at least 5 s needed. Standard CRF will be used instead.');
    fprintf('\n%s\n', warnings{1});
    options.indrf = 0;
end;

% extract PCA of last fixed response (eSCR) if last event is fixed --
if (options.indrf || options.getrf) && (isempty(options.flexevents) ...
        || (max(options.fixevents > max(options.flexevents(:, 2), [], 2))))
    [foo, lastfix] = max(options.fixevents);
    % extract data
    winsize = round(sr * min([proc_miniti 10]));
    D = []; c = 1;
    for isbSn = 1:numel(model.scr)
        foo = sbs_newevents{2}{isbSn}(:, lastfix);
        foo(foo < 0) = [];
        for n = 1:size(foo, 1)
            win = ceil(sr * foo(n) + (1:winsize));
            D(c, :) = model.scr{isbSn}(win);
            c = c + 1;
        end;
    end;
    clear c k n
    
    % mean centre
    mD = D - repmat(mean(D, 2), 1, size(D, 2));
    
    % PCA
    [u s]=svd(mD', 0);
    [p,n] = size(mD);
    s = diag(s);
    comp = u .* repmat(s',n,1);
    eSCR = comp(:, 1);
    eSCR = eSCR - eSCR(1);
    foo = min([numel(eSCR), 50]);
    [mx ind] = max(abs(eSCR(1:foo)));
    if eSCR(ind) < 0, eSCR = -eSCR; end;
    eSCR = (eSCR - min(eSCR))/(max(eSCR) - min(eSCR));
    
    % check for peak (zero-crossing of the smoothed derivative) after more
    % than 3 seconds (use CRF if there is none)
    der = diff(eSCR);
    der = conv(der, ones(10, 1));
    der = der(ceil(3 * sr):end);
    if all(der > 0) || all(der < 0)
        warnings{1} = ('No peak detected in response to outcomes. Cannot individually adjust CRF. Standard CRF will be used instead.');
        fprintf('\n%s\n', warnings{1});
        options.indrf = 0;
    else
        options.eSCR = eSCR;
    end;
end;

% extract data from all trials
winsize = round(model.sr * min([proc_miniti 10]));
D = []; c = 1;
for isbSn = 1:numel(model.scr)
    for n = 1:numel(model.trlstart{isbSn})
        win = ceil(((model.sr * model.trlstart{isbSn}(n)):(model.sr * model.trlstop{isbSn}(n) + winsize)));
        % correct rounding errors
        win(win == 0) = [];
        win(win > numel(model.scr{isbSn})) = [];
        D(c, 1:numel(win)) = model.scr{isbSn}(win);
        c = c + 1;
    end;
end;
clear c n


% do PCA if required
if (options.indrf || options.getrf) && ~isempty(options.flexevents)
    % mean SOA
    meansoa = mean(cell2mat(model.trlstop') - cell2mat(model.trlstart'));
    % mean centre
    mD = D - repmat(mean(D, 2), 1, size(D, 2));
    % PCA
    [u s c]=svd(mD', 0);
    [p,n] = size(mD);
    s = diag(s);
    comp = u .* repmat(s',n,1);
    aSCR = comp(:, 1);
    aSCR = aSCR - aSCR(1);
    foo = min([numel(aSCR), (round(model.sr * meansoa) + 50)]);
    [mx ind] = max(abs(aSCR(1:foo)));
    if aSCR(ind) < 0, aSCR = -aSCR; end;
    aSCR = (aSCR - min(aSCR))/(max(aSCR) - min(aSCR));
    clear u s c p n s comp mx ind mD
    options.aSCR = aSCR;
end;

% get mean response
options.meanSCR = (mean(D))';

% invert DCM
% ------------------------------------------------------------------------
dcm = pspm_dcm_inv(model, options);


% assemble stats & names
% ------------------------------------------------------------------------
dcm.stats = [];
cTrl = 0;
proc_subs_ids = find(proc_subsessions);
for iSn = 1:numel(model.datafile)
    trls = trials{iSn};
    sn_sbs = find(subsessions(proc_subs_ids, 1) == iSn);
    
    for isbSn = 1:numel(sn_sbs)
        sbs_id = proc_subs_ids(sn_sbs(isbSn));
        sbs_trl = find(trls(:,2) == sbs_id);
        offset_trl = sbs_trl + 1 - min(sbs_trl); % start counting from 1
        dcm.stats(sbs_trl + cTrl, :) = [[dcm.sn{sn_sbs(isbSn)}.a(offset_trl).a]', ...
            [dcm.sn{sn_sbs(isbSn)}.a(offset_trl).m]', ...
            [dcm.sn{sn_sbs(isbSn)}.a(offset_trl).s]', ...
            [dcm.sn{sn_sbs(isbSn)}.e(offset_trl).a]'];
    end;
    % set disabled trials to NaN
    dcm.stats(cTrl + find(trls(:, 1) == 0), :) = NaN;
    cTrl = cTrl + size(trls, 1);
end;
dcm.names = {};
for iEvnt = 1:numel(dcm.sn{1}.a(1).a)
    dcm.names{iEvnt, 1} = sprintf('%s: amplitude', flexevntnames{iEvnt});
    dcm.names{iEvnt + numel(dcm.sn{1}.a(1).a), 1} = sprintf('%s: peak latency', flexevntnames{iEvnt});
    dcm.names{iEvnt + 2*numel(dcm.sn{1}.a(1).a), 1} = sprintf('%s: dispersion', flexevntnames{iEvnt});
end;
cMsr = 3 * iEvnt; 
if isempty(cMsr), cMsr = 0; end;
for iEvnt = 1:numel(dcm.sn{1}.e(1).a)
    dcm.names{iEvnt + cMsr, 1} = sprintf('%s: response amplitude', fixevntnames{iEvnt});
end;
    
if isfield(options, 'trlnames') && numel(options.trlnames) == size(dcm.stats, 1)
    dcm.trlnames = options.trlnames;
else
    for iTrl = 1:size(dcm.stats, 1)
        dcm.trlnames{iTrl} = sprintf('Trial #%d', iTrl);
    end;
end;

% assemble input and save
% ------------------------------------------------------------------------
dcm.dcmname = model.modelfile; % this field will be removed in the future
dcm.modelfile = model.modelfile;
dcm.input = model;
dcm.options = options;
dcm.warnings = warnings;
dcm.modeltype = 'dcm';
dcm.modality = settings.modalities.dcm;
dcm.revision = rev;

if ~options.nosave
    save(model.modelfile, 'dcm');
end;

return;
