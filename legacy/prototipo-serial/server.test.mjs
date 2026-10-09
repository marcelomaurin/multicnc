import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createApp,validate,parseJob} from './server.mjs';
test('validação de configuração e G-code',()=>{
  assert.throws(()=>validate({name:'x',type:'laser',transport:'tcp',host:'localhost',port:70000}));
  assert.throws(()=>parseJob('; vazio'));
  assert.deepEqual(parseJob(';comment\nG0 X1 (move)\nG1 Y2 ; line'),['G0 X1','G1 Y2']);
});
test('ciclo de simulação, persistência e bloqueio de controle físico',async()=>{
  const dir=await mkdtemp(path.join(os.tmpdir(),'multicnc-'));let app;
  try{
    app=await createApp(dir);await new Promise(r=>app.listen(0,'127.0.0.1',r));
    const base='http://127.0.0.1:'+app.address().port;
    const post=async(url,body={})=>{const r=await fetch(base+url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,value:await r.json()};};
    const machines=await (await fetch(base+'/api/machines')).json();assert.equal(machines.length,3);
    const url='/api/machines/'+machines[0].id;
    assert.equal((await post(url+'/job',{code:'G0 X1'})).status,400);
    assert.equal((await post(url+'/connect')).value.status,'connected');
    assert.equal((await post(url+'/job',{code:'G0 X1\nG1 X2'})).value.job.total,2);
    assert.equal((await post(url+'/pause')).value.job.status,'paused');
    assert.equal((await post(url+'/resume')).value.job.status,'running');
    assert.equal((await post(url+'/cancel')).value.job.status,'cancelled');
    const tcp=(await post('/api/machines',{name:'TCP',type:'router',transport:'tcp',host:'127.0.0.1',port:9999})).value;
    assert.equal((await post('/api/machines/'+tcp.id+'/job',{code:'G0 X1'})).status,400);
    const denied=await fetch(base+'/api/machines',{method:'POST',headers:{Origin:'https://example.com','Content-Type':'application/json'},body:'{}'});assert.equal(denied.status,403);
    await new Promise(r=>app.close(r));app=await createApp(dir);await new Promise(r=>app.listen(0,'127.0.0.1',r));
    assert.equal((await (await fetch('http://127.0.0.1:'+app.address().port+'/api/machines')).json()).length,4);
  }finally{if(app?.listening)await new Promise(r=>app.close(r));await rm(dir,{recursive:true,force:true});}
});
