function [] = testLSTM(modelFiles, beamSize, stackSize, batchSize, outputFile,varargin)
%%%
%
% Test a trained LSTM model by generating translations for the test data
% (stored under the params structure in the model file)
%   stackSize: the maximum number of translations we want to get.
%
% Thang Luong @ 2015, <lmthang@stanford.edu>
% Hieu Pham @ 2015, <hyhieu@cs.stanford.edu>
%
%%%
  addpath(genpath(sprintf('%s/../../matlab', pwd)));
  addpath(genpath(sprintf('%s/..', pwd)));

  %% Argument Parser
  p = inputParser;
  % required
  addRequired(p,'modelFiles',@ischar);
  addRequired(p,'beamSize',@isnumeric);
  addRequired(p,'stackSize',@isnumeric);
  addRequired(p,'batchSize',@isnumeric);
  addRequired(p,'outputFile',@ischar);

  % optional
  addOptional(p,'gpuDevice', 1, @isnumeric); % choose the gpuDevice to use. 
  addOptional(p,'align', 0, @isnumeric); % 1 -- output aignment from attention model
  addOptional(p,'assert', 0, @isnumeric); % 1 -- assert
  addOptional(p,'debug', 0, @isnumeric); % 1 -- debug
  addOptional(p,'minLenRatio', 0.5, @isnumeric); % decodeLen >= minLenRatio * srcMaxLen
  addOptional(p,'maxLenRatio', 1.5, @isnumeric); % decodeLen <= maxLenRatio * srcMaxLen
  addOptional(p,'testPrefix', '', @ischar); % to specify a different file for decoding

  p.KeepUnmatched = true;
  parse(p,modelFiles,beamSize,stackSize,batchSize,outputFile,varargin{:})
  decodeParams = p.Results;
  if decodeParams.batchSize==-1 % decode sents one by one
    decodeParams.batchSize = 1;
  end
  
  % GPU settings
  decodeParams.isGPU = 0;
  if ismac==0
    n = gpuDeviceCount;  
    if n>0 % GPU exists
      fprintf(2, '# %d GPUs exist. So, we will use GPUs.\n', n);
      decodeParams.isGPU = 1;
      gpuDevice(decodeParams.gpuDevice)
      decodeParams.dataType = 'single';
    else
      decodeParams.dataType = 'double';
    end
  else
    decodeParams.dataType = 'double';
  end
  printParams(2, decodeParams);
  
  %% load multiple models
  tokens = strsplit(decodeParams.modelFiles, ',');
  numModels = length(tokens);
  models = cell(numModels, 1);
  for mm=1:numModels
    modelFile = tokens{mm};
    [savedData] = load(modelFile);
    models{mm} = savedData.model;
    models{mm}.params = savedData.params;  
    
    % for backward compatibility  
    fieldNames = {'attnGlobal', 'attnOpt', 'predictPos', 'tieEmb', 'sameLength', 'softmaxFeedInput'};
    for ii=1:length(fieldNames)
      field = fieldNames{ii};
      if ~isfield(models{mm}.params, field)
        models{mm}.params.(field) = 0;
      end
    end
    if models{mm}.params.attnFunc==1
      models{mm}.params.attnGlobal = 1;
    end
    if ~isfield(models{mm}, 'W_emb_src')
      models{mm}.W_emb_src = models{mm}.W_emb(:, models{mm}.params.tgtVocabSize+1:end);
      models{mm}.W_emb_tgt = models{mm}.W_emb(:, 1:models{mm}.params.tgtVocabSize);
    end
    if ~isfield(models{mm}, 'W_h')
      models{mm}.W_h = models{mm}.W_ah;
    end

    % convert absolute paths to local paths
%     fieldNames = fields(models{mm}.params);
%     for ii=1:length(fieldNames)
%       field = fieldNames{ii};
%       if ischar(models{mm}.params.(field))
%         if strfind(models{mm}.params.(field), '/afs/ir/users/l/m/lmthang') ==1
%           models{mm}.params.(field) = strrep(models{mm}.params.(field), '/afs/ir/users/l/m/lmthang', '~');
%         end
%         if strfind(models{mm}.params.(field), '/afs/cs.stanford.edu/u/lmthang') ==1
%           models{mm}.params.(field) = strrep(models{mm}.params.(field), '/afs/cs.stanford.edu/u/lmthang', '~');
%         end
%         if strfind(models{mm}.params.(field), '/home/lmthang') ==1
%           models{mm}.params.(field) = strrep(models{mm}.params.(field), '/home/lmthang', '~');
%         end    
%       end
%     end

    % convert local paths to absolute paths
    fieldNames = fields(models{mm}.params);
    for ii=1:length(fieldNames)
      field = fieldNames{ii};
      if ischar(models{mm}.params.(field))
        if strfind(models{mm}.params.(field), '~lmthang/') ==1
          models{mm}.params.(field) = strrep(models{mm}.params.(field), '~lmthang/', '/afs/ir/users/l/m/lmthang/');
        end
        if strfind(models{mm}.params.(field), '~lmthang/') ==1
          models{mm}.params.(field) = strrep(models{mm}.params.(field), '~lmthang/', '/afs/cs.stanford.edu/u/lmthang/');
        end
        if strfind(models{mm}.params.(field), '~lmthang/') ==1
          models{mm}.params.(field) = strrep(models{mm}.params.(field), '~lmthang/', '/home/lmthang/');
        end    
      end
    end
    
    % load vocabs
    [models{mm}.params] = prepareVocabs(models{mm}.params);
    
    % make sure all models have the same vocab, and the number of layers
    if mm>1 
      for ii=1:models{mm}.params.srcVocabSize
        assert(strcmp(models{mm}.params.srcVocab{ii}, models{1}.params.srcVocab{ii}), '! model %d, mismatch src word %d: %s vs. %s\n', mm, ii, models{mm}.params.srcVocab{ii}, models{1}.params.srcVocab{ii});
      end
      for ii=1:models{mm}.params.tgtVocabSize
        assert(strcmp(models{mm}.params.tgtVocab{ii}, models{1}.params.tgtVocab{ii}), '! model %d, mismatch tgt word %d: %s vs. %s\n', mm, ii, models{mm}.params.tgtVocab{ii}, models{1}.params.tgtVocab{ii});
      end
      models{mm}.params = rmfield(models{mm}.params, {'srcVocab', 'tgtVocab'});
    end
    
    % copy fields
    fieldNames = fields(decodeParams);
    for ii=1:length(fieldNames)
      field = fieldNames{ii};
      if strcmp(field, 'testPrefix')==1 && strcmp(decodeParams.(field), '')==1 % skip empty testPrefix
        continue;
      elseif strcmp(field, 'testPrefix')==1
        fprintf(2, '# Decode a different test file %s\n', decodeParams.(field));
      end
      models{mm}.params.(field) = decodeParams.(field);
    end
  end
  
  params = models{1}.params;
  params.fid = fopen(params.outputFile, 'w');
  params.logId = fopen([outputFile '.log'], 'w'); 
  % align
  if params.align
    params.alignId = fopen([params.outputFile '.align'], 'w');
  end
  printParams(2, params);
  
  % same-length decoder
  if params.sameLength
    assert(decodeParams.batchSize==1);
    fprintf(2, '## Same-length decoding\n');
  end
  
  % load test data
  if strfind(params.testPrefix, '~lmthang') == 1
    params.testPrefix = strrep(params.testPrefix, '~lmthang', '/afs/cs.stanford.edu/u/lmthang');
  end
  [srcSents, tgtSents, numSents]  = loadBiData(params, params.testPrefix, params.srcVocab, params.tgtVocab);
  
  %%%%%%%%%%%%
  %% decode %%
  %%%%%%%%%%%%
  numBatches = floor((numSents-1)/batchSize) + 1;
  
  fprintf(2, '# Decoding %d sents, %s\n', numSents, datestr(now));
  fprintf(params.logId, '# Decoding %d sents, %s\n', numSents, datestr(now));
  startTime = clock;
  for batchId = 1 : numBatches
    % prepare batch data
    startId = (batchId-1)*batchSize+1;
    endId = batchId*batchSize;
    
    if endId > numSents
      endId = numSents;
    end
    [decodeData] = prepareData(srcSents(startId:endId), tgtSents(startId:endId), 1, params);
    decodeData.startId = startId;
    
    % call lstmDecoder
    [candidates, candScores, alignInfo] = lstmDecoder(models, decodeData, params); 
    
    % print results
    printDecodeResults(decodeData, candidates, candScores, alignInfo, params, 1);
  end

  endTime = clock;
  timeElapsed = etime(endTime, startTime);
  fprintf(2, '# Complete decoding %d sents, time %.0fs, %s\n', numSents, timeElapsed, datestr(now));
  fprintf(params.logId, '# Complete decoding %d sents, time %.0fs, %s\n', numSents, timeElapsed, datestr(now));
  
  fclose(params.fid);
  fclose(params.logId);
end


