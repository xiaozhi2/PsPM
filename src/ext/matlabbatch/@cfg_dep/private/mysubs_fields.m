function fnames = mysubs_fields(dep)

% function fnames = mysubs_fields(dep)
% This function returns a cell string of names containing the fields
% implemented by the cfg_dep class. It is called from @cfg_dep/subsasgn
% and @cfg_item/subsref to allow references to valid fields for this class.
%
% This code is part of a batch job configuration system for MATLAB. See 
%      help matlabbatch
% for a general overview.
%_______________________________________________________________________
% Copyright (C) 2007 Freiburg Brain Imaging

% Volkmar Glauche
% $Id: mysubs_fields.m 380 2016-11-08 07:47:23Z tmoser $

rev = '$Rev: 380 $'; %#ok

fnames = {'tname','tgt_exbranch','tgt_input','tgt_spec','jtsubs','sname','src_exbranch','src_output'};