import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {createHash} from 'node:crypto';
import ts from 'typescript';
import {compile} from 'svelte/compiler';
import {Window} from 'happy-dom';

export async function mountedSvelteEnvironment(name) {
  const root=fileURLToPath(new URL('../../',import.meta.url));
  const cache=path.join(root,'.cache',name);await mkdir(cache,{recursive:true});
  const modules=new Map();
  async function moduleFor(filename, suppliedSource) {
    if(modules.has(filename))return modules.get(filename);
    const destination=path.join(cache,createHash('sha256').update(filename).digest('hex')+'.mjs');
    const url=pathToFileURL(destination).href;modules.set(filename,url);
    const source=suppliedSource??await readFile(filename,'utf8');
    let code=filename.endsWith('.json')?'export default '+source:filename.endsWith('.svelte')?compile(source,{filename,generate:'client',css:'external'}).js.code:ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
    code=code.replace(/import\s+['"][^'"]+\.css['"];?/g,'');
    for(const match of [...code.matchAll(/(?:from\s+|import\s*\()(['"])(\$lib\/[^'"]+|\.{1,2}\/[^'"]+)\1/g)]) {
      let target=match[2].startsWith('$lib/')?path.join(root,'src/lib',match[2].slice(5)):path.resolve(path.dirname(filename),match[2]);
      if(!path.extname(target)){try{await readFile(target+'.ts');target+='.ts';}catch{target=path.join(target,'index.ts');}}
      code=code.replaceAll(match[0],match[0].replace(match[2],await moduleFor(target)));
    }
    await writeFile(destination,code);return url;
  }
  const dom=new Window({url:'http://localhost',settings:{disableCSSFileLoading:true,disableIframePageLoading:true,disableJavaScriptFileLoading:true,disableJavaScriptEvaluation:true}});
  for(const name of ['window','document','navigator','Element','HTMLElement','HTMLInputElement','HTMLButtonElement','HTMLTableRowElement','HTMLMediaElement','SVGElement','Node','Text','Comment','Event','MouseEvent','KeyboardEvent','MutationObserver','ResizeObserver','getComputedStyle','requestAnimationFrame','cancelAnimationFrame'])Object.defineProperty(globalThis,name,{configurable:true,value:name==='window'?dom:name==='document'?dom.document:['getComputedStyle','requestAnimationFrame','cancelAnimationFrame'].includes(name)?dom[name].bind(dom):dom[name]});
  const svelte=await import('svelte');
  return {root,dom,moduleFor,...svelte};
}
