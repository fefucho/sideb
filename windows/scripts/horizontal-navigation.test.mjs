import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../src/lib/horizontal/scroll.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {horizontalPageTarget:page,horizontalOffset:offset}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);

test('one page retains the partially visible column instead of jumping past it',()=>{
 const common={extent:650,maximum:3000,stride:176};
 assert.equal(page({...common,position:0,direction:1}),528);
 assert.equal(page({...common,position:50,direction:1}),528);
 assert.equal(page({...common,position:528,direction:-1}),0);
 assert.equal(page({...common,position:2900,direction:1}),3000);
 assert.equal(page({...common,position:0,direction:-1}),0);
});
test('a viewport narrower than one song column still reaches its hidden portion',()=>{
 const common={extent:120,maximum:700,stride:284,direction:1};
 assert.equal(page({...common,position:0}),120);
 assert.equal(page({...common,position:120}),240);
 assert.equal(page({...common,position:240}),360);
});
test('mixed card widths page by observed boundaries and keep the boundary card',()=>{
 const starts=[0,160,400,550,900];const common={extent:450,maximum:1000,count:starts.length,startAt:i=>starts[i]};
 assert.equal(page({...common,position:0,direction:1}),400);
 assert.equal(page({...common,position:400,direction:1}),550);
 assert.equal(page({...common,position:900,direction:-1}),550);
});
test('large shelves inspect logarithmically many boundaries and normalize RTL overscroll',()=>{
 let reads=0;
 assert.equal(page({position:14000,extent:600,maximum:999999,count:5000,startAt:i=>{reads++;return i*176},direction:1}),14432);
 assert.ok(reads<30,reads);
 assert.equal(offset(-240,1000,true),240);
 assert.equal(offset(20,1000,true),0);
 assert.equal(offset(-1200,1000,true),1000);
 assert.equal(page({position:0,extent:600,maximum:0,stride:176,direction:1}),0);
});
