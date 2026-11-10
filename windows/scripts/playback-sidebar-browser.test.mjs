import assert from 'node:assert/strict';
import {test} from 'node:test';
import {existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const browser=process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
test('real PlaybackDock + PlaybackSidebar geometry at 350/380/420, single interactive destination, reversal and Reduce Motion in Chromium',{
 skip:!existsSync(browser)?'Requires an installed Edge/Chrome or SIDEB_BROWSER; no account or audio is used':false,
 timeout:240000
},()=>{
 const result=spawnSync(process.execPath,[fileURLToPath(new URL('./playback-sidebar-browser.mjs',import.meta.url))],{encoding:'utf8',timeout:235000,windowsHide:true});
 assert.equal(result.status,0,result.stdout+result.stderr);const evidence=JSON.parse(result.stdout.trim().split('\n').at(-1));assert.equal(evidence.ok,true);assert.equal(evidence.cases,12);assert.deepEqual(evidence.errors,[]);
});
