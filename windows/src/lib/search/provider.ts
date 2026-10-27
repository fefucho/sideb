import {emptySearchData, type SearchData, type SearchMode, type SearchRpc} from './controller';
import type {SearchOrigin} from './recents';
import type {SearchPageDto, SearchSectionDto} from '../types';
export type ProviderSearchData = SearchData & {page:SearchPageDto|null;params:string|null;loadingMore:boolean;consumedContinuations:string[]};
export const emptyProviderSearchData=():ProviderSearchData=>({...emptySearchData(),page:null,params:null,loadingMore:false,consumedContinuations:[]});
/** The provider owns ranking, categories and continuation; revisions protect account/navigation changes. */
export class ProviderSearchController {
 private data=emptyProviderSearchData(); private revision=0;
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
