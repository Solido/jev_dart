// Run against an installed, exact @typesafe-ai/sdk@0.7.0 package.
import { createRequire } from 'node:module';
import { writeFileSync, readFileSync } from 'node:fs';
const require = createRequire(import.meta.url);
const sdk = require(process.argv[2] || '@typesafe-ai/sdk');
if (sdk.VERSION !== '0.7.0') throw Error('Expected SDK 0.7.0');
const { TypeSafeClient, image, withAssets, noul, score, choice, box } = sdk;
const png = Uint8Array.from([137,80,78,71,13,10,26,10,1,2,3]);
const response = { model: 'fixture-model', answers: {
  yes: {type:'noul', noul:0.8},
  category:{type:'choice', choice:'a', confidence:0.9, probabilities:{a:0.9,b:0.1}},
  rating:{type:'score', score:0.7, confidence:0.8, legend:{'0':'low','1':'high'}, probabilities:{'0':0.3,'1':0.7}},
  target:{type:'box', box:{top:0.1,bottom:0.8,left:0.2,right:0.7}, confidence:null}
}, usage:{input_tokens:null,output_tokens:null}};
function normalize(value) {
  const refs = new Map();
  return JSON.parse(JSON.stringify(value).replace(/<image:[0-9a-f]{32}>/g, ref => {
    if (!refs.has(ref)) refs.set(ref, `<image:auto${refs.size}>`);
    return refs.get(ref);
  }));
}
const captured = {};
let current;
const client = new TypeSafeClient({apiKey:'fixture-key', compression:false,
  fetch:async (url, init) => {
    const headers = new Headers(init.headers);
    let payload, parts=[];
    if (headers.get('content-type').startsWith('multipart/')) {
      const form = await new Response(init.body, {headers}).formData();
      const request = form.get('request');
      payload = JSON.parse(typeof request === 'string' ? request : await request.text());
      for (const [name,file] of form) {
        if (name !== 'request') parts.push({name, content_type:file.type, data_base64:Buffer.from(await file.arrayBuffer()).toString('base64')});
      }
    } else payload = JSON.parse(init.body);
    captured[current] = normalize({payload,parts});
    return new Response(JSON.stringify(response),{headers:{'content-type':'application/json','x-typesafe-request-id':'fixture-id'}});
  }});
current='core';
await client.systemOne({state:{document:'ticket'}, questions:{yes:noul('yes?'),category:choice('which?',{a:null,b:null}),rating:score('rate',['low','high'])}});
current='named_image';
let photo=image(png);
await client.systemOne({state:{photo},assets:{'<photo>':photo},questions:{target:box('target in <photo>')},model:'jev-preview'});
current='inline_image';
photo=image(png);
await client.systemOne({state:{photos:[photo]},questions:{yes:noul(withAssets`Does ${photo} show a dog?`)}});
current='joined_images';
photo=image(png); const other=image(png);
await client.systemOne({state:withAssets`Compare ${withAssets.join([photo,other], ' / ')}.`,questions:{yes:noul('same?')}});
const fixture={upstream_version:'0.7.0',requests:captured,response};
const output = process.argv[3];
if (process.argv.includes('--check')) {
  const expected=JSON.parse(readFileSync(output,'utf8'));
  if (JSON.stringify(expected)!==JSON.stringify(fixture)) throw Error('JS contract fixture drift');
  console.log('JS 0.7.0 contract matches committed fixtures');
} else writeFileSync(output,JSON.stringify(fixture,null,2)+'\n');
