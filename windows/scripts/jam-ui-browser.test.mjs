import assert from 'node:assert/strict';
import {test} from 'node:test';
import {existsSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const browser=process.env.SIDEB_BROWSER??'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
test('real Jam UI geometry in Edge: Connections badge and flyout, fullscreen marker 10 px above the cover, sidebar marker, no layout shift',{
 skip:!existsSync(browser)?'Requires an installed Edge or SIDEB_BROWSER; fixture states only, no account and no Jam':false,
 timeout:180000
},()=>{
 const result=spawnSync(process.execPath,[fileURLToPath(new URL('./jam-ui-browser.mjs',import.meta.url))],{encoding:'utf8',timeout:175000,windowsHide:true});
 assert.equal(result.status,0,result.stdout+result.stderr);const evidence=JSON.parse(result.stdout.trim().split('\n').at(-1));assert.equal(evidence.ok,true);assert.deepEqual(evidence.errors,[]);
});
