/* ShubhMart Seller Professional Layer — internal tools */
(function(){
'use strict';
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const s=()=>window.sb||window.shubhSupabase;
function note2(m,b){if(typeof window.note==='function')window.note(m,b);else alert(m)}
function style(){
 if(document.getElementById('smSellerProStyle'))return;
 const st=document.createElement('style');st.id='smSellerProStyle';st.textContent=`
.sm-seller-pro{margin-top:18px;background:linear-gradient(135deg,#071638,#123b7b);color:#fff;border-radius:18px;padding:18px;box-shadow:0 14px 34px #07163830}
.sm-seller-pro h2{margin:0 0 5px}.sm-seller-pro p{color:#dbe6ff;font-size:12px}.sm-seller-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.sm-seller-tool{background:#ffffff12;border:1px solid #ffffff24;border-radius:13px;padding:12px}.sm-seller-tool b{display:block;margin-bottom:6px}.sm-seller-tool button{border:0;border-radius:9px;padding:8px 10px;font-weight:800;cursor:pointer;background:#ffd21a;color:#111;margin-top:6px}.sm-seller-tool input{background:#fff;color:#111}.sm-seller-light{margin-top:12px;background:#fff;color:#14213d;border-radius:14px;padding:13px}.sm-seller-list{display:grid;gap:7px;font-size:12px}.sm-seller-chip{display:inline-block;background:#eef2f7;padding:5px 8px;border-radius:999px;margin:2px;font-weight:800}@media(max-width:800px){.sm-seller-grid{grid-template-columns:1fr 1fr}}@media(max-width:480px){.sm-seller-grid{grid-template-columns:1fr}}
`;document.head.appendChild(st)
}
async function sellerStats(){
 const db=s(),sid=window.seller?.id;if(!db||!sid)return null;
 const [p,o,r]=await Promise.all([
  db.from('products').select('id,name,price,mrp,stock,description,image_url,brand,category,hsn_code,gtin,manufacturer_name,packer_name,package_contents,status').eq('seller_id',sid).limit(500),
  db.from('Orders').select('id,total_amount,order_status,created_at').eq('seller_id',sid).limit(500),
  db.from('product_reviews').select('rating,status,product_id').limit(500)
 ]);
 return {products:p.data||[],orders:o.data||[],reviews:r.data||[]}
}
function quality(p){
 let score=0; if(p.name)score+=15;if(p.description&&p.description.length>40)score+=15;if(p.image_url)score+=15;if(p.category)score+=10;if(p.brand)score+=8;if(p.hsn_code)score+=8;if(p.gtin)score+=7;if(p.manufacturer_name)score+=7;if(p.packer_name)score+=5;if(p.package_contents)score+=5;if(Number(p.mrp)>0&&Number(p.price)>0)score+=5;return Math.min(100,score)
}
function download(name,text,type='text/csv'){
 const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([text],{type}));a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)
}
function csv(rows){if(!rows.length)return '';const keys=Object.keys(rows[0]);return [keys.join(','),...rows.map(x=>keys.map(k=>{const v=String(x[k]??'');return '"'+v.replace(/"/g,'""')+'"'}).join(','))].join('\n')}
async function exportProducts(){
 const z=await sellerStats();if(!z)return;
 download('shubhmart-seller-products.csv',csv(z.products.map(p=>({id:p.id,name:p.name,category:p.category,price:p.price,mrp:p.mrp,stock:p.stock,image_url:p.image_url,brand:p.brand,hsn_code:p.hsn_code,gtin:p.gtin,status:p.status,quality_score:quality(p)}))));
 note2('Product CSV export ready.')
}
function parseCSV(t){
 const lines=t.split(/\r?\n/).filter(Boolean);if(!lines.length)return[];const head=lines[0].split(',').map(x=>x.trim().replace(/^"|"$/g,''));return lines.slice(1).map(line=>{const cells=[];let cur='',q=false;for(let i=0;i<line.length;i++){const ch=line[i];if(ch==='"'&&line[i+1]==='"'){cur+='"';i++;continue}if(ch==='"'){q=!q;continue}if(ch===','&&!q){cells.push(cur);cur='';}else cur+=ch}cells.push(cur);const o={};head.forEach((h,i)=>o[h]=cells[i]??'');return o})}
async function importProducts(input){
 const db=s(),sid=window.seller?.id;if(!db||!sid)return;
 const file=input.files?.[0];if(!file)return;
 const rows=parseCSV(await file.text()).slice(0,50);if(!rows.length)return note2('CSV mein rows nahi mili.',true);
 const clean=rows.filter(x=>x.name&&x.category&&Number(x.price)>0).map(x=>({seller_id:sid,name:String(x.name).slice(0,180),category:String(x.category).slice(0,100),price:Number(x.price),mrp:Number(x.mrp||x.price),stock:Math.max(0,Math.floor(Number(x.stock||0))),image_url:x.image_url||null,description:x.description||null,brand:x.brand||null,seller_sku:x.seller_sku||null,status:'Pending',is_live:false}));
 if(!clean.length)return note2('Valid product rows nahi mili.',true);
 const r=await db.from('products').insert(clean);if(r.error)return note2('Bulk import error: '+r.error.message,true);
 note2(clean.length+' products Pending review ke liye submit ho gaye.');if(typeof window.loadMyProducts==='function')window.loadMyProducts();input.value=''
}
async function render(){
 style();const dash=document.getElementById('dashboard');if(!dash||document.getElementById('smSellerPro'))return;
 const sec=document.createElement('section');sec.id='smSellerPro';sec.className='sm-seller-pro';sec.innerHTML='<h2>🚀 Seller Growth Center</h2><p>Listing quality, inventory, performance, CSV tools aur storefront — ek professional workspace.</p><div class="sm-seller-grid"><div class="sm-seller-tool"><b>📥 Bulk Listing</b><span>CSV se up to 50 products import</span><br><input id="smSellerCsv" type="file" accept=".csv"><button onclick="smSellerImport()">Import</button></div><div class="sm-seller-tool"><b>📤 Product Export</b><span>Products + quality score CSV</span><br><button onclick="smSellerExport()">Export CSV</button></div><div class="sm-seller-tool"><b>📊 Performance</b><span>Orders, ratings, fulfilment snapshot</span><br><button onclick="smSellerPerformance()">Open</button></div><div class="sm-seller-tool"><b>🏪 Storefront</b><span>Public seller page shortcut</span><br><button onclick="smSellerStorefront()">Open Store</button></div></div><div id="smSellerProBody" class="sm-seller-light"></div>';
 dash.appendChild(sec)
}
async function performance(){
 const z=await sellerStats();if(!z)return;
 const delivered=z.orders.filter(o=>o.order_status==='Delivered').length, cancelled=z.orders.filter(o=>o.order_status==='Cancelled').length;
 const avg=z.reviews.filter(r=>r.status==='Published').reduce((a,r)=>a+Number(r.rating||0),0)/(z.reviews.filter(r=>r.status==='Published').length||1);
 const weak=z.products.map(p=>({...p,q:quality(p)})).sort((a,b)=>a.q-b.q).slice(0,5);
 document.getElementById('smSellerProBody').innerHTML='<h3>Seller Performance</h3><div class="sm-seller-list"><div><span class="sm-seller-chip">Products '+z.products.length+'</span><span class="sm-seller-chip">Orders '+z.orders.length+'</span><span class="sm-seller-chip">Delivered '+delivered+'</span><span class="sm-seller-chip">Cancelled '+cancelled+'</span><span class="sm-seller-chip">Rating '+avg.toFixed(1)+'/5</span></div><h4>Listing Quality Improvement</h4>'+weak.map(p=>'<div><b>'+esc(p.name)+'</b> — '+p.q+'/100 '+(p.q<70?'⚠️ Improve':'✅ Good')+'</div>').join('')+'</div>'
}
function storefront(){
 const sid=window.seller?.id;if(!sid)return note2('Seller profile load nahi hua.',true);
 const u=new URL('index.html',location.href);u.searchParams.set('seller',sid);window.open(u.toString(),'_blank','noopener')
}
window.smSellerImport=()=>{const x=document.getElementById('smSellerCsv');if(x)importProducts(x)};
window.smSellerExport=exportProducts;window.smSellerPerformance=performance;window.smSellerStorefront=storefront;
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(render,1200));else setTimeout(render,1200);
setTimeout(render,3000);
})();