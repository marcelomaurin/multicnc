import http from 'node:http';
import net from 'node:net';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
export function validate(input) {
  const {name, type, transport, host = '', port = 23} = input;
  if (typeof name !== 'string' || !name.trim() || name.length > 80) throw Error('Informe um nome de até 80 caracteres.');
  if (!['laser', 'router', 'printer'].includes(type)) throw Error('Tipo de máquina inválido.');
  if (!['simulator', 'tcp'].includes(transport)) throw Error('Conexão inválida.');
  if (transport === 'tcp' && (typeof host !== 'string' || !/^[a-zA-Z0-9.:-]{1,253}$/.test(host) || !Number.isInteger(Number(port)) || Number(port) < 1 || Number(port) > 65535)) throw Error('Endereço ou porta inválidos.');
  return {name: name.trim(), type, transport, host, port: Number(port)};
}
export function parseJob(code) {
  if (typeof code !== 'string' || Buffer.byteLength(code) > 1024 * 1024) throw Error('Limite: 1 MB de G-code.');
  const lines = code.split(/\r?\n/).map(x => x.replace(/\([^)]*\)/g, '').split(';')[0].trim()).filter(Boolean);
  if (!lines.length) throw Error('O arquivo não contém comandos.');
  return lines;
}
export async function createApp(dataDir = path.join(root, 'data')) {
  await mkdir(dataDir, {recursive:true});
  const db = path.join(dataDir, 'machines.json');
  let configs;
  try { configs = JSON.parse(await readFile(db, 'utf8')); }
  catch (e) { if (e.code !== 'ENOENT') throw e; configs = ['laser','router','printer'].map((type,i) => ({id:randomUUID(), name:['Laser de demonstração','Router de demonstração','Impressora 3D de demonstração'][i],type,transport:'simulator',host:'',port:23})); }
  const machines = new Map(configs.map(c => [c.id,{...validate(c),id:c.id,status:'disconnected',logs:[],job:null}]));
  const sockets = new Map();
  let saving = Promise.resolve();
  function save() {
    const snapshot = JSON.stringify([...machines.values()].map(({id,name,type,transport,host,port}) => ({id,name,type,transport,host,port})),null,2);
    saving = saving.catch(()=>{}).then(async()=>{await writeFile(db+'.tmp',snapshot);await rename(db+'.tmp',db);});
    return saving;
  }
  await save();
  const log = (m,text) => {m.logs.push({time:new Date().toISOString(),text});m.logs=m.logs.slice(-60);};
  const timer = setInterval(()=>{for(const m of machines.values()) if(m.job?.status==='running'){m.job.completed++; if(m.job.completed>=m.job.total){m.job.status='completed';log(m,'Simulação concluída.');}}},250);
  const server = http.createServer(async(req,res)=>{
    const send = (status,value) => {res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(JSON.stringify(value));};
    try {
      const expected = `http://${req.headers.host}`;
      if (req.headers.origin && req.headers.origin !== expected) return send(403,{error:'Origem não permitida.'});
      if (!/^127\.0\.0\.1:\d+$/.test(req.headers.host || '')) return send(403,{error:'Use o endereço local 127.0.0.1.'});
      const url = new URL(req.url,expected);
      if(req.method==='GET' && url.pathname==='/'){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Content-Security-Policy':"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'",'X-Content-Type-Options':'nosniff'});return res.end(await readFile(path.join(root,'index.html')));}
      if(req.method==='GET' && url.pathname==='/api/machines') return send(200,[...machines.values()]);
      if(req.method!=='POST') return send(404,{error:'Rota não encontrada.'});
      if(!req.headers['content-type']?.startsWith('application/json')) return send(415,{error:'Envie JSON.'});
      let body='';for await (const chunk of req){body+=chunk; if(Buffer.byteLength(body)>1100000) return send(413,{error:'Arquivo muito grande.'});}
      const input=JSON.parse(body || '{}');
      if(url.pathname==='/api/machines'){const m={...validate(input),id:randomUUID(),status:'disconnected',logs:[],job:null};machines.set(m.id,m);try{await save();}catch(e){machines.delete(m.id);throw e;}return send(201,m);}
      const match=url.pathname.match(/^\/api\/machines\/([^/]+)\/(connect|disconnect|job|pause|resume|cancel)$/);
      if(!match || !machines.has(match[1])) return send(404,{error:'Máquina não encontrada.'});
      const m=machines.get(match[1]), action=match[2];
      if(action==='connect'){
        if(m.status!=='disconnected' && m.status!=='error') throw Error('Já está conectada ou conectando.');
        if(m.transport==='simulator'){m.status='connected';log(m,'Simulador conectado. Nenhuma máquina física é controlada.');}
        else {
          m.status='connecting';log(m,'Abrindo TCP em modo de recepção; nenhum comando será enviado.');
          const socket=net.createConnection({host:m.host,port:m.port});sockets.set(m.id,socket);
          const deadline=setTimeout(()=>socket.destroy(Error('Tempo de conexão esgotado.')),5000);
          socket.on('connect',()=>{clearTimeout(deadline);m.status='connected';log(m,'TCP conectado. Compatibilidade do protocolo ainda não verificada.');});
          socket.on('data',chunk=>log(m,chunk.toString('utf8').slice(0,2000)));
          socket.on('error',e=>{m.status='error';log(m,e.message);});
          socket.on('close',()=>{clearTimeout(deadline);if(m.status!=='error')m.status='disconnected';sockets.delete(m.id);});
        }
      } else if(action==='disconnect'){
        sockets.get(m.id)?.destroy();m.status='disconnected';if(m.job && ['running','paused'].includes(m.job.status))m.job.status='cancelled';log(m,'Conexão encerrada.');
      } else {
        if(m.transport!=='simulator') throw Error('Controle físico indisponível nesta versão. TCP permite apenas receber dados.');
        if(m.status!=='connected') throw Error('Conecte o simulador primeiro.');
        if(action==='job'){
          if(m.job && ['running','paused'].includes(m.job.status)) throw Error('Já existe uma simulação em andamento.');
          const lines=parseJob(input.code);m.job={name:String(input.name || 'Trabalho').slice(0,120),total:lines.length,completed:0,status:'running'};log(m,'Simulação iniciada: contagem de linhas, sem interpretar movimentos.');
        } else {
          const required={pause:['running'],resume:['paused'],cancel:['running','paused']};
          if(!m.job || !required[action].includes(m.job.status)) throw Error('Ação inválida para o estado do trabalho.');
          m.job.status={pause:'paused',resume:'running',cancel:'cancelled'}[action];
        }
      }
      send(200,m);
    } catch(e){send(400,{error:e.message});}
  });
  server.on('close',()=>{clearInterval(timer);for(const s of sockets.values())s.destroy();});
  return server;
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const app=await createApp();app.listen( Number(process.env.PORT || 3210),'127.0.0.1',()=>console.log(`MultiCNC: http://127.0.0.1:${app.address().port}`));
}
