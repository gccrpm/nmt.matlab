function printTrainBatch(data, params)
  if params.isBi
    printSent(2, data.input(1, 1:data.srcMaxLen-1), params.srcVocab, '  src input 1: ');
    fprintf(2, '  src mask: %s\n', num2str(data.srcMask(1, :)));
  end
  
  printSent(2, data.input(1, data.srcMaxLen:end), params.tgtVocab, '  tgt input 1: ');
  printSent(2, data.tgtOutput(1, :), params.tgtVocab, '  tgt output 1: ');
  if params.predictPos %==1 % raw positions 
    fprintf(2, '  srcPos 1:');
    for ii=1:length(data.posOutput(1, :))
      fprintf(2, ' %d', data.posOutput(1, ii));
    end
    fprintf(2, '\n');
%   elseif params.predictPos==2 % position vocab
%     printSent(2, data.posOutput(1, :), params.tgtVocab, '  srcPos 1:');
  end
  
  fprintf(2, '  tgt mask: %s\n', num2str(data.tgtMask(1, :)));
end

%printSent(2, data.srcInput(1, :), params.srcVocab, '  src input 1:');
%printSent(2, data.tgtInput(1, :), params.tgtVocab, '  tgt input 1:');

%   if params.separateEmb==1    
%   else
%     if params.isBi
%       printSent(2, data.srcInput(1, :), params.vocab, '  src input 1:');
%     end
%     printSent(2, data.tgtInput(1, :), params.vocab, '  tgt input 1:');
%     printSent(2, data.tgtOutput(1, :), params.vocab, '  tgt output 1:');
%     if params.posModel>0
%       printSent(2, data.posOutput(1, :), params.vocab, '  srcPos 1:');
%     end
%   end
