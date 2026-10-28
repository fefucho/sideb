import assert from 'node:assert/strict';
import {test} from 'node:test';
import {existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const browser=process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
test('real PlayerBar geometry, clipping, title cycle, input and overlay in Edge with synthetic metadata',{
 skip:!existsSync(browser)?'Requires an installed Edge or SIDEB_BROWSER; no account is used':false,
 timeout:180000
},()=>{
 const result=spawnSync(process.execPath,[fileURLToPath(new URL('./player-bar-browser.mjs',import.meta.url))],{encoding:'utf8',timeout:175000,windowsHide:true});
 assert.equal(result.status,0,result.stdout+result.stderr);const evidence=JSON.parse(result.stdout.trim());assert.equal(evidence.ok,true);assert.equal(evidence.layoutCases,16);assert.deepEqual(evidence.errors,[]);
});
