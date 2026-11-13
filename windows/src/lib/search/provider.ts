import {emptySearchData, type SearchData, type SearchMode, type SearchRpc} from './controller';
import type {SearchOrigin} from './recents';
import type {SearchPageDto, SearchSectionDto} from '../types';
import {emptyCategoryInput, fetchTargets, type CategoryInput, type ChipKind} from './categories';
export type ProviderSearchData = SearchData & {page:SearchPageDto|null;params:string|null;loadingMore:boolean;consumedContinuations:string[];
 /** One chip search per category that fills the by-category sections (never part of the saved provider page). */
 categories:CategoryInput};
export const emptyProviderSearchData=():ProviderSearchData=>({...emptySearchData(),page:null,params:null,loadingMore:false,consumedContinuations:[],categories:emptyCategoryInput()});
/** The provider owns ranking, categories and continuation; revisions protect account/navigation changes. */
export class ProviderSearchController {
 private data=emptyProviderSearchData(); private revision=0; private categoriesFor=-1;
 constructor(private rpc:SearchRpc,private publish:(data:ProviderSearchData)=>void){}
 private emit(){this.publish({...this.data});}
 reset(){++this.revision;this.data=emptyProviderSearchData();this.emit();}
 invalidate(){++this.revision;this.data={...this.data,isLoading:false,loadingMore:false};this.emit();}
 restore(snapshot:SearchData){++this.revision;this.data={...emptyProviderSearchData(),...snapshot,isLoading:false,loadingMore:false};this.emit();if(snapshot.isLoading)void this.execute(snapshot.lastSearchedQuery,snapshot.mode,'navigationRestore',snapshot.ignoreSpelling,(snapshot as Partial<ProviderSearchData>).params??null);}
 setMode(mode:SearchMode){this.data.mode=mode;const chip=this.data.page?.chips.find(c=>c.id===mode);if(chip)void this.selectParams(chip.params);}
 async execute(query:string,mode:SearchMode='all',origin:SearchOrigin|boolean='submit',ignoreSpelling=false,params:string|null=null){
  query=query.trim();if(!query)return;const revision=++this.revision;
  this.data={...emptyProviderSearchData(),query,lastSearchedQuery:query,mode,params,ignoreSpelling,hasSearched:true,isLoading:true};this.emit();
  try{const page=await this.rpc<SearchPageDto>('search_page',{query,params,recordHistory:typeof origin==='boolean'?origin:origin==='submit'||origin==='recentQuery',ignoreSpelling});if(revision!==this.revision)return;this.data={...this.data,page,correction:page.correction,isLoading:false};}
  catch(error){if(revision!==this.revision)return;this.data={...this.data,isLoading:false,error:message(error)};}
  this.emit();
 }
 /** One chip request per category, at most three at a time. The results page asks for it once per provider page:
  * a filtered page (chip or «show all») is already a single category, and a newer search or account reset drops the replies. */
 loadCategories(showVideos:boolean){
  const page=this.data.page;
  if(!page||this.data.params!=null||this.categoriesFor===this.revision)return;
  this.categoriesFor=this.revision;
  const targets=fetchTargets(page,showVideos);
  if(!targets.length)return;
  const revision=this.revision;
  const query=page.correction?.applied?page.correction.query:this.data.lastSearchedQuery;
  const ignoreSpelling=this.data.ignoreSpelling;
  let categories:CategoryInput={chipPages:{},pending:targets.map(target=>target.kind)};
  const settle=(kind:ChipKind,result:SearchPageDto|null)=>{
   if(revision!==this.revision)return;
   categories={chipPages:result?{...categories.chipPages,[kind]:result}:categories.chipPages,pending:categories.pending.filter(item=>item!==kind)};
   this.data={...this.data,categories};this.emit();
  };
  this.data={...this.data,categories};this.emit();
  let next=0;
  const worker=async()=>{
   while(next<targets.length){
    const target=targets[next++];
    if(revision!==this.revision)return;
    try{settle(target.kind,await this.rpc<SearchPageDto>('search_page',{query,params:target.params,recordHistory:false,ignoreSpelling}));}
    catch{settle(target.kind,null);}
   }
  };
  void Promise.all([worker(),worker(),worker()]);
 }
 selectParams(params:string|null,query=this.data.lastSearchedQuery){return this.execute(query,'all','filter',this.data.ignoreSpelling,params);}
 retryBlock(){return this.execute(this.data.lastSearchedQuery,this.data.mode,'refresh',this.data.ignoreSpelling,this.data.params);}
 more(section:SearchSectionDto){return this.selectParams(section.moreParams,section.moreQuery||this.data.lastSearchedQuery);}
 async loadMore(){
  const token=this.data.page?.continuation;if(!token||this.data.loadingMore||this.data.consumedContinuations.includes(token))return;
  const revision=this.revision;this.data={...this.data,loadingMore:true,error:null};this.emit();
  try{const page=await this.rpc<SearchPageDto>('search_page_continuation',{continuation:token});if(revision!==this.revision)return;
   const consumedContinuations=[...this.data.consumedContinuations,token],offset=this.data.page!.sections.length;
   this.data={...this.data,consumedContinuations,page:{...this.data.page!,sections:[...this.data.page!.sections,...page.sections.map((section,index)=>({...section,id:`${offset+index}:${section.id}`}))],continuation:page.continuation&&consumedContinuations.includes(page.continuation)?null:page.continuation},loadingMore:false};
  }catch(error){if(revision!==this.revision)return;this.data={...this.data,loadingMore:false,error:message(error)};}this.emit();
 }
}
function message(error:unknown){return typeof error==='string'?error:error instanceof Error?error.message:'No se pudo consultar YouTube Music.';}
