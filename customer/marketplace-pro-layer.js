/* ShubhMart Professional Integration Layer — internal/non-external marketplace features */
(function(){
'use strict';
const LS={recentSearch:'sm_search_v2',recent:'sm_recent_v2',compare:'sm_compare_v2',lang:'sm_lang_v1'};
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const noteSafe=m=>typeof window.note==='function'?window.note(m):alert(m);
const sbx=()=>window.sb||window.shubhSupabase;
const user=()=>window.currentUser||null;
const read=(k,d=[])=>{try{return JSON.parse(localStorage.getItem(k)||JSON.stringify(d))}catch(e){return d}};
const write=(k,v)=>localStorage.setItem(k,JSON.stringify(v));

function css(){
 if($('sm-pro-style'))return;
 const s=document.createElement('style');s.id='sm-pro-style';
 s.textContent=`
.sm-pro-bar{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:10px 0}
.sm-pro-pill{border:1px solid #dbe3f0;background:#fff;border-radius:999px;padding:7px 11px;font-size:12px;font-weight:800;cursor:pointer}
.sm-pro-panel{background:#fff;border:1px solid #e6eaf2;border-radius:16px;padding:16px;margin:12px 0;box-shadow:0 8px 24px #14213d0b}
.sm-pro-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}
.sm-pro-card{border:1px solid #e6eaf2;border-radius:14px;padding:12px;background:linear-gradient(180deg,#fff,#f8faff)}
.sm-pro-card img{width:100%;height:145px;object-fit:cover;border-radius:10px;background:#f2f4f8}
.sm-pro-muted{color:#667085;font-size:12px}
.sm-pro-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:8px}
.sm-pro-actions button{border:0;border-radius:9px;padding:8px 10px;font-weight:800;cursor:pointer}
.sm-pro-primary{background:#071638;color:#fff}.sm-pro-secondary{background:#eef2f7;color:#14213d}
.sm-pro-modal{position:fixed;inset:0;background:#071638aa;backdrop-filter:blur(4px);z-index:1500;display:grid;place-items:center;padding:16px}
.sm-pro-dialog{background:#fff;border-radius:20px;width:min(920px,100%);max-height:90vh;overflow:auto;padding:20px;box-shadow:0 25px 80px #0005}
.sm-pro-close{float:right;border:0;background:#eef2f7;border-radius:50%;width:36px;height:36px;font-size:22px;cursor:pointer}
.sm-pro-timeline{display:grid;gap:8px}.sm-pro-step{display:grid;grid-template-columns:30px 1fr;gap:9px;align-items:start}.sm-pro-dot{width:24px;height:24px;border-radius:50%;background:#e8edf5;display:grid;place-items:center;font-size:12px}.sm-pro-step.active .sm-pro-dot{background:#ffd21a}.sm-pro-step b{font-size:13px}.sm-pro-step small{display:block;color:#667085}
.sm-a11y{position:fixed;left:12px;bottom:14px;z-index:997;background:#fff;border:1px solid #dbe3f0;border-radius:999px;padding:7px 10px;box-shadow:0 8px 20px #14213d22;font-size:12px;font-weight:900;cursor:pointer}
.sm-high-contrast{filter:contrast(1.08)}
.sm-font-large{font-size:106%!important}.sm-font-large *{font-size:inherit}
@media(max-width:700px){.sm-pro-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.sm-pro-dialog{padding:14px}.sm-pro-card img{height:125px}}
@media(max-width:430px){.sm-pro-grid{grid-template-columns:1fr}.sm-a11y{bottom:70px}}
`;
 document.head.appendChild(s);
}

function recentSearches(){
 const a=read(LS.recentSearch,[]);
 if(!$('search'))return;
 let box=$('smRecentSearches');
 if(!box){box=document.createElement('div');box.id='smRecentSearches';box.className='sm-pro-bar';$('search').closest('.searchwrap')?.parentElement?.appendChild(box)}
 if(!a.length){box.innerHTML='';return}
 box.innerHTML='<span class="sm-pro-muted">Recent:</span>'+a.slice(0,6).map(x=>'<button class="sm-pro-pill" onclick="smUseRecentSearch(\''+esc(x).replace(/'/g,"\\'")+'\')">'+esc(x)+'</button>').join('');
}
function addSearch(v){v=String(v||'').trim();if(!v)return;let a=read(LS.recentSearch,[]).filter(x=>x!==v);a.unshift(v);write(LS.recentSearch,a.slice(0,10));recentSearches()}
function useSearch(v){const q=$('search');if(q){q.value=v;q.dispatchEvent(new Event('input',{bubbles:true}));}if(typeof window.loadProducts==='function')window.loadProducts();addSearch(v)}
window.smUseRecentSearch=useSearch;

async function productVariants(pid){
 const s=sbx();if(!s)return[];
 const r=await s.from('product_variants').select('id,sku,variant_name,option_value,price,mrp,stock,image_url,status').eq('product_id',pid).eq('status','Active').order('created_at',{ascending:true});
 return r.data||[];
}
async function productSeller(sellerId){
 const s=sbx();if(!s||!sellerId)return null;
 const r=await s.from('Sellers').select('id,seller_name,shop_name,status,kyc_status,gst_status,account_health_status').eq('id',sellerId).maybeSingle();
 return r.data||null;
}
async function enhanceProduct(p){
 const box=$('smProProductDetails');if(!box)return;
 const [vars,seller]=await Promise.all([productVariants(p.id),productSeller(p.seller_id)]);
 box.innerHTML='<div class="sm-pro-panel"><h3>Product details</h3>'+
 (p.brand?'<p><b>Brand:</b> '+esc(p.brand)+'</p>':'')+
 (p.product_type?'<p><b>Type:</b> '+esc(p.product_type)+'</p>':'')+
 (p.hsn_code?'<p><b>HSN:</b> '+esc(p.hsn_code)+'</p>':'')+
 (p.warranty_details?'<p><b>Warranty:</b> '+esc(p.warranty_details)+'</p>':'')+
 (p.return_eligible?'<p><b>Returns:</b> Eligible as per policy</p>':'<p><b>Returns:</b> Product-specific policy</p>')+
 (seller?'<p><b>Seller:</b> '+esc(seller.shop_name||seller.seller_name)+' · '+esc(seller.status||'Pending')+'</p>':'')+
 (vars.length?'<h4>Variants</h4><div class="sm-pro-actions">'+vars.map(v=>'<button class="sm-pro-pill" onclick="smSelectVariant(\''+v.id+'\')">'+esc(v.variant_name||'Variant')+': '+esc(v.option_value||'')+' · ₹'+Number(v.price).toFixed(0)+' · Stock '+Number(v.stock||0)+'</button>').join('')+'</div>':'')+
 '</div>';
 window.smVariantCache=vars;
}
window.smSelectVariant=id=>{const v=(window.smVariantCache||[]).find(x=>x.id===id);if(v)noteSafe('Variant selected: '+(v.variant_name||'Variant')+' — '+(v.option_value||'')+' · ₹'+Number(v.price).toFixed(0))};

async function safeReview(pid){
 const u=user(),s=sbx();if(!u||!s)return noteSafe('Review dene ke liye login kijiye.');
 const {data:orders}=await s.from('Orders').select('id,order_status,Order_items(product_id)').eq('customer_id',u.id).in('order_status',['Delivered','delivered']).limit(100);
 const order=orders?.find(o=>(o.Order_items||[]).some(i=>String(i.product_id)===String(pid)));
 if(!order)return noteSafe('Is product ke delivered order ke baad hi review de sakte hain.');
 const rating=Number(prompt('Rating 1-5:',5));if(!Number.isInteger(rating)||rating<1||rating>5)return;
 const text=String(prompt('Review likhiye:','Product achha laga.')||'').trim();if(!text)return;
 const {error}=await s.from('product_reviews').insert({product_id:pid,customer_id:u.id,order_id:order.id,rating,review_text:text,media_urls:[],status:'pending'});
 if(error)return noteSafe('Review submit nahi hua: '+error.message);
 noteSafe('Review submit ho gaya. Admin moderation ke baad show hoga.');
}
window.writeMarketplaceReview=safeReview;

async function safeReturn(orderId,type){
 const u=user(),s=sbx();if(!u||!s)return noteSafe('Login kijiye.');
 const reason=String(prompt(type==='Exchange'?'Exchange reason:':'Return reason:')||'').trim();if(!reason)return;
 const code=String(prompt('Reason code (example: damaged / wrong_item / not_as_described):','customer_request')||'customer_request').trim();
 const {data,error}=await s.rpc('request_order_return',{p_order_id:orderId,p_reason_code:code,p_reason:reason,p_return_type:type});
 if(error)return noteSafe(error.message);
 noteSafe((type==='Exchange'?'Exchange':'Return')+' request submit ho gayi.');if(typeof window.loadOrders==='function')window.loadOrders();
}
window.requestMarketplaceReturn=orderId=>safeReturn(orderId,'Return');
window.requestMarketplaceExchange=orderId=>safeReturn(orderId,'Exchange');

async function cancelOrder(orderId){
 const s=sbx();if(!user()||!s)return noteSafe('Login kijiye.');
 const reason=String(prompt('Cancellation reason (optional):','Customer request')||'Customer request');
 const {error}=await s.rpc('cancel_customer_order',{p_order_id:orderId,p_reason:reason});
 if(error)return noteSafe(error.message);
 noteSafe('Order cancel request process ho gayi.');if(typeof window.loadOrders==='function')window.loadOrders();
}
window.smCancelOrder=cancelOrder;

async function protection(orderId){
 const s=sbx();if(!user()||!s)return noteSafe('Login kijiye.');
 const reason=String(prompt('Buyer protection reason:','Item issue')||'').trim();if(!reason)return;
 const desc=String(prompt('Details:','')||'').trim();
 const {error}=await s.rpc('request_buyer_protection',{p_order_id:orderId,p_reason:reason,p_description:desc});
 if(error)return noteSafe(error.message);
 noteSafe('Buyer Protection claim submit ho gaya.');if(typeof window.loadOrders==='function')window.loadOrders();
}
window.smBuyerProtection=protection;

async function reorder(orderId){
 const s=sbx(),u=user();if(!s||!u)return noteSafe('Login kijiye.');
 const {data,error}=await s.from('Order_items').select('product_id,quantity,products(id,name,stock,status,is_live)').eq('order_id',orderId);
 if(error)return noteSafe(error.message);
 let added=0;
 for(const i of data||[]){if(i.products?.status==='Active'&&i.products?.is_live===true&&Number(i.products?.stock||0)>0){const r=await s.from('cart').upsert({customer_id:u.id,product_id:i.product_id,quantity:Math.max(1,Number(i.quantity||1))},{onConflict:'customer_id,product_id'});if(!r.error)added++}}
 noteSafe(added+' product(s) Buy Again ke liye cart mein add ho gaye.');if(typeof window.loadCart==='function')window.loadCart();if(typeof window.show==='function')window.show('cart');
}
window.smReorder=reorder;

async function orderTimeline(orderId){
 const s=sbx();if(!s)return;
 const {data:sh}=await s.from('shipments').select('id,tracking_number,shipment_status,estimated_delivery_at').eq('order_id',orderId).maybeSingle();
 let ev=[];
 if(sh){const r=await s.from('delivery_events').select('status,note,created_at').eq('shipment_id',sh.id).order('created_at',{ascending:true});ev=r.data||[]}
 const base=['Pending','Confirmed','Processing','Packed','Dispatched','Out for Delivery','Delivered'];
 const status=sh?.shipment_status||'';
 const html='<div class="sm-pro-modal" id="smProModal"><div class="sm-pro-dialog"><button class="sm-pro-close" onclick="smCloseModal()">×</button><h2>📦 Order Tracking</h2>'+
 '<p class="sm-pro-muted">Order #'+esc(orderId.slice(0,8))+'…'+(sh?.tracking_number?' · Tracking '+esc(sh.tracking_number):'')+'</p>'+
 '<div class="sm-pro-timeline">'+base.map((x,i)=>{const active=status===x||ev.some(e=>e.status===x);return '<div class="sm-pro-step '+(active?'active':'')+'"><div class="sm-pro-dot">'+(active?'✓':(i+1))+'</div><div><b>'+x+'</b></div></div>'}).join('')+
 (ev.length?'<hr>'+ev.map(e=>'<div class="sm-pro-step active"><div class="sm-pro-dot">•</div><div><b>'+esc(e.status)+'</b><small>'+esc(e.note||'')+' · '+new Date(e.created_at).toLocaleString('en-IN')+'</small></div></div>').join(''):'')+
 (sh?.estimated_delivery_at?'<p><b>ETA:</b> '+new Date(sh.estimated_delivery_at).toLocaleString('en-IN')+'</p>':'')+
 '</div></div></div>';
 document.body.insertAdjacentHTML('beforeend',html);
}
function closeModal(){document.querySelectorAll('.sm-pro-modal').forEach(x=>x.remove())}
window.smOrderTimeline=orderTimeline;window.smCloseModal=closeModal;

async function loadRecommendations(){
 const s=sbx(),root=$('smProRecommendations');if(!s||!root)return;
 const recent=read(LS.recent,[]);
 const cat=recent[0]?.category;
 let q=s .from('products').select('id,name,price,mrp,image_url,category,stock').eq('status','Active').eq('is_live',true).gt('stock',0).limit(8);
 if(cat)q=q.eq('category',cat);
 const {data,error}=await q.order('created_at',{ascending:false});if(error)return;
 root.innerHTML=(data||[]).length?'<div class="sm-pro-panel"><div class="section-head"><h2>✨ Aapke liye</h2></div><div class="sm-pro-grid">'+data.map(p=>'<div class="sm-pro-card"><img src="'+esc(p.image_url||'https://placehold.co/400x300?text=ShubhMart')+'"><b>'+esc(p.name)+'</b><div>₹'+Number(p.price||0).toFixed(0)+'</div><div class="sm-pro-actions"><button class="sm-pro-primary" onclick="openProductById(\''+p.id+'\')">View</button><button class="sm-pro-secondary" onclick="addCart(\''+p.id+'\')">Cart</button></div></div>').join('')+'</div></div>':'';
}
function patchOpenProduct(){
 if(typeof window.openProduct!=='function'||window.openProduct.__smPro)return;
 const old=window.openProduct;
 const wrap=function(p){old(p);setTimeout(()=>{let box=$('smProProductDetails');const inner=$('productModalContent');if(inner&&!box){box=document.createElement('div');box.id='smProProductDetails';inner.appendChild(box)}if(p)enhanceProduct(p)},60)};
 wrap.__smPro=true;window.openProduct=wrap;
}
function patchLoadOrders(){
 if(typeof window.loadOrders!=='function'||window.loadOrders.__smPro)return;
 const old=window.loadOrders;
 const wrap=async function(){
   await old();
   const box=$('ordersbox');if(!box)return;
   const panels=[...box.querySelectorAll('.panel')];
   for(const panel of panels){
     if(panel.dataset.smPro==='1')continue;
     const m=panel.textContent.match(/Order #([a-f0-9]{8})/i);if(!m)continue;
     const idGuess=m[1];const s=sbx(),u=user();if(!s||!u)continue;
     const r=await s.from('Orders').select('id,order_status,payment_status').eq('customer_id',u.id).order('created_at',{ascending:false}).limit(100);
     const o=(r.data||[]).find(x=>String(x.id).startsWith(idGuess));if(!o)continue;
     const row=document.createElement('div');row.className='sm-pro-actions';
     const track=document.createElement('button');track.className='sm-pro-secondary';track.textContent='📍 Track';track.onclick=()=>orderTimeline(o.id);
     const buy=document.createElement('button');buy.className='sm-pro-secondary';buy.textContent='🔁 Buy Again';buy.onclick=()=>reorder(o.id);row.append(track,buy);
     if(['Pending','Confirmed'].includes(o.order_status)){const c=document.createElement('button');c.className='sm-pro-secondary';c.textContent='✕ Cancel';c.onclick=()=>cancelOrder(o.id);row.appendChild(c)}
     if(o.order_status==='Delivered'){const rt=document.createElement('button');rt.className='sm-pro-secondary';rt.textContent='↩ Return';rt.onclick=()=>safeReturn(o.id,'Return');const ex=document.createElement('button');ex.className='sm-pro-secondary';ex.textContent='⇄ Exchange';ex.onclick=()=>safeReturn(o.id,'Exchange');row.append(rt,ex)}
     const bp=document.createElement('button');bp.className='sm-pro-secondary';bp.textContent='🛡 Buyer Protection';bp.onclick=()=>protection(o.id);row.appendChild(bp);
     panel.appendChild(row);panel.dataset.smPro='1';
   }
 };
 wrap.__smPro=true;window.loadOrders=wrap;
}
function accessibility(){
 if($('smA11y'))return;
 const b=document.createElement('button');b.id='smA11y';b.className='sm-a11y';b.textContent='Aa';b.title='Accessibility';
 b.onclick=()=>{document.body.classList.toggle('sm-font-large');document.body.classList.toggle('sm-high-contrast')};
 document.body.appendChild(b);
}
async function coins(){
 const s=sbx(),u=user();if(!s||!u)return;
 const r=await s.rpc('ensure_shubhcoins_wallet');if(r.error)return;
 const w=Array.isArray(r.data)?r.data[0]:r.data; if(!$('smCoins')){const el=document.createElement('div');el.id='smCoins';el.className='sm-pro-pill';el.textContent='🪙 '+Number(w?.balance||0)+' ShubhCoins';el.onclick=()=>noteSafe('ShubhCoins balance: '+Number(w?.balance||0));$('head-actions')?.appendChild(el)}
}
function inject(){
 css();recentSearches();accessibility();patchOpenProduct();patchLoadOrders();
 setTimeout(patchOpenProduct,500);setTimeout(patchLoadOrders,700);
 const main=$('.main')||document.body;
 if(!$('smProRecommendations')){const r=document.createElement('section');r.id='smProRecommendations';main.appendChild(r)}
 loadRecommendations().catch(()=>{});
 if(user())coins().catch(()=>{});
}
window.addEventListener('sm:search',e=>addSearch(e.detail||''));
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject);else inject();
setTimeout(inject,1500);setTimeout(inject,3500);
})();