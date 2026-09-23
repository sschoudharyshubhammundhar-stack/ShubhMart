const PAYMENT_FUNCTION = "razorpay-payment";
const sb = window.shubhSupabase;

let currentUser = null;
let selectedAddress = null;
let checkoutBusy = false;


/* MESSAGE */

function note(text,danger=false){

  const e=document.getElementById("msg");

  e.className=danger ? "msg danger" : "msg";

  e.textContent=text;

  setTimeout(()=>{
    e.textContent="";
  },4000);
}


/* NAVIGATION */

function show(id){

  ["home","cart","orders","account"].forEach(x=>{
    document.getElementById(x)
      .classList.toggle("hidden",x!==id);
  });

  if(id==="cart") loadCart();

  if(id==="orders") loadOrders();

  if(id==="account") loadAccount();
}


/* ESCAPE */

function esc(s){

  return String(s??"").replace(
    /[&<>"']/g,
    c=>({
      "&":"&amp;",
      "<":"&lt;",
      ">":"&gt;",
      '"':"&quot;",
      "'":"&#39;"
    }[c])
  );
}


/* PRODUCTS */

async function loadProducts(){

  const q=
    document.getElementById("search")
      .value.trim();

  let query=
    sb.from("products")
      .select("*")
      .eq("status","Active")
      .order("created_at",{ascending:false});

  if(q){
    query=query.ilike(
      "name",
      "%"+q+"%"
    );
  }

  const {data,error}=await query;

  const el=
    document.getElementById("products");

  if(error){

    el.innerHTML=
      "<div>Products load error: "+
      esc(error.message)+
      "</div>";

    return;
  }

  if(!data?.length){

    el.innerHTML="No active products yet.";

    return;
  }

  el.innerHTML=data.map(p=>`

    <div class="card">

      <img
        src="${p.image_url ||
        "https://placehold.co/500x400?text=ShubhMart"}"
      >

      <h3>${esc(p.name)}</h3>

      <div class="price">
        ₹${Number(p.price||0).toFixed(0)}

        <span class="old">
          ₹${Number(p.mrp||0).toFixed(0)}
        </span>
      </div>

      <div class="small">
        ${esc(p.category||"")}
      </div>

      <button class="btn"
        onclick="addCart('${p.id}')">
        Add to Cart
      </button>

      <button class="btn alt"
        onclick="buy('${p.id}')">
        Buy Now
      </button>

    </div>

  `).join("");
}


/* CART BADGE */
async function updateCartBadge(){
  const badge=document.getElementById("cartBadge");
  if(!badge)return;
  if(!currentUser){ badge.textContent="0"; return; }
  const {data,error}=await sb.from("cart").select("quantity").eq("customer_id",currentUser.id);
  if(error){ badge.textContent="0"; return; }
  const count=(data||[]).reduce((n,row)=>n+Number(row.quantity||0),0);
  badge.textContent=String(count);
}

/* CART */

async function addCart(id){

  if(!currentUser){

    note(
      "Pehle login/signup kijiye",
      true
    );

    show("account");

    return;
  }

  const {error}=await sb
    .from("cart")
    .upsert(
      {
        customer_id:currentUser.id,
        product_id:id,
        quantity:1
      },
      {
        onConflict:
        "customer_id,product_id"
      }
    );

  if(error){

    note(error.message,true);

  }else{

    note("Cart mein add ho gaya ✅");
    await updateCartBadge();

  }
}


async function buy(id){

  if(!currentUser){

    note(
      "Pehle login/signup kijiye",
      true
    );

    show("account");

    return;
  }

  await addCart(id);

  show("cart");
}


async function loadCart(){

  if(!currentUser){
    document.getElementById("cartbox").innerHTML="Login kijiye.";
    return;
  }

  const {data,error}=await sb
    .from("cart")
    .select("id,quantity,product_id,products(id,name,price,mrp,image_url,category)")
    .eq("customer_id",currentUser.id);

  const box=document.getElementById("cartbox");

  if(error){
    box.textContent=error.message;
    await updateCartBadge();
    return;
  }

  await updateCartBadge();

  if(!data?.length){
    box.innerHTML="Cart empty.";
    return;
  }

  let itemTotal=0;
  let mrpTotal=0;

  const items=data.map(x=>{
    const price=Number(x.products?.price||0);
    const mrp=Number(x.products?.mrp||price);
    const qty=Number(x.quantity||0);
    const line=price*qty;
    itemTotal+=line;
    mrpTotal+=Math.max(price,mrp)*qty;
    return {x,price,mrp,qty,line};
  });

  const productDiscount=Math.max(0,mrpTotal-itemTotal);

  box.innerHTML=
    '<h3>Added Products</h3>'+
    items.map(({x,price,mrp,qty,line})=>`
      <div class="panel row">
        <img src="${x.products?.image_url || "https://placehold.co/120x90?text=ShubhMart"}"
          style="width:90px;height:70px;object-fit:cover;border-radius:10px">
        <div style="flex:1;min-width:160px">
          <b>${esc(x.products?.name||"Product")}</b>
          <div class="small">${esc(x.products?.category||"")}</div>
          <div>
            <b>₹${price.toFixed(2)}</b>
            ${mrp>price ? '<span class="old"> ₹'+mrp.toFixed(2)+'</span>' : ''}
            × ${qty}
          </div>
          <div><b>Item Total: ₹${line.toFixed(2)}</b></div>
        </div>
        <div>
          <button class="btn" onclick="changeQty('${x.id}',${qty-1})">−</button>
          <button class="btn" onclick="changeQty('${x.id}',${qty+1})">+</button>
          <button class="btn alt" onclick="removeCart('${x.id}')">Remove</button>
        </div>
      </div>
    `).join("")+
    `
      <div class="panel">
        <h3>Price Summary</h3>
        <div>Products Total <b style="float:right">₹${mrpTotal.toFixed(2)}</b></div>
        <div>Product Discount <b style="float:right">−₹${productDiscount.toFixed(2)}</b></div>
        <div>Cart Value <b style="float:right">₹${itemTotal.toFixed(2)}</b></div>
        <hr>
        <div style="font-size:20px"><b>Total</b><b style="float:right">₹${itemTotal.toFixed(2)}</b></div>
      </div>
    `;
}

async function changeQty(id,q){

  if(q<=0){

    return removeCart(id);

  }

  await sb
    .from("cart")
    .update({
      quantity:q
    })
    .eq("id",id)
    .eq(
      "customer_id",
      currentUser.id
    );

  await updateCartBadge();
  loadCart();
}


async function removeCart(id){

  await sb
    .from("cart")
    .delete()
    .eq("id",id)
    .eq(
      "customer_id",
      currentUser.id
    );

  await updateCartBadge();
  loadCart();
}


/* AUTH */

async function signup(){

  const email=document.getElementById("email").value.trim();
  const password=document.getElementById("password").value;
  const name=document.getElementById("signupName").value.trim();
  const phone=document.getElementById("signupPhone").value.trim();

  if(!email || !password || !name || !phone){
    document.getElementById("signupFields").classList.remove("hidden");
    note("Name, mobile, email aur password bhariye.",true);
    return;
  }

  if(password.length<8){
    note("Password kam se kam 8 characters ka rakhein.",true);
    return;
  }

  const {data,error}=await sb.auth.signUp({
    email,
    password,
    options:{data:{full_name:name,phone:phone,role:"customer"}}
  });

  if(error){
    note(error.message,true);
    return;
  }

  document.getElementById("signupFields").classList.add("hidden");
  note(data.session ? "Signup successful ✅" : "Account ban gaya. Email verify karke Login karein.");
}

async function resetPassword(){

  const email=document.getElementById("email").value.trim();

  if(!email){
    note("Pehle email bhariye.",true);
    return;
  }

  const redirectTo=location.origin+location.pathname;
  const {error}=await sb.auth.resetPasswordForEmail(email,{redirectTo});

  if(error){
    note(error.message,true);
    return;
  }

  note("Password reset link email par bhej diya gaya hai.");
}


async function login(){

  const email=document.getElementById("email").value.trim();
  const password=document.getElementById("password").value;

  if(!email || !password){
    note("Email aur password bhariye.",true);
    return;
  }

  const {data,error}=await sb.auth.signInWithPassword({email,password});

  if(error){
    note(error.message,true);
  }else{
    currentUser=data.user;
    note("Login successful ✅");
    loadAccount();
  }
}


async function logout(){

  await sb.auth.signOut();

  currentUser=null;

  selectedAddress=null;
  await updateCartBadge();

  note("Logout ho gaya");

  loadAccount();
}


/* ACCOUNT */

async function loadAccount(){

  const box=
    document.getElementById("userbox");

  const lb=
    document.getElementById("loginbox");

  const ab=
    document.getElementById("addressbox");
  const signupFields=document.getElementById("signupFields");

  if(!currentUser){

    box.innerHTML=
      '<div class="small">Customer login/signup karein.</div>';

    lb.classList.remove("hidden");

    ab.classList.add("hidden");
    if(signupFields) signupFields.classList.add("hidden");

    return;
  }

  lb.classList.add("hidden");

  ab.classList.remove("hidden");

  box.innerHTML=
    `Logged in:
     <b>${esc(currentUser.email)}</b>`;

  loadAddresses();
}


/* ADDRESS */

async function saveAddress(){

  if(!currentUser)return;

  const a={

    customer_id:currentUser.id,

    name:
      document.getElementById("aname").value,

    mobile:
      document.getElementById("amobile").value,

    house_shop:
      document.getElementById("ahouse").value,

    area:
      document.getElementById("aarea").value,

    city:
      document.getElementById("acity").value,

    state:
      document.getElementById("astate").value,

    pincode:
      document.getElementById("apin").value,

    is_default:true

  };

  const {error}=await sb
    .from("addresses")
    .insert(a);

  if(error){

    note(error.message,true);

  }else{

    note("Address save ho gaya ✅");

    loadAddresses();

  }
}


async function loadAddresses(){

  const {data,error}=await sb
    .from("addresses")
    .select("*")
    .eq(
      "customer_id",
      currentUser.id
    )
    .order(
      "created_at",
      {ascending:false}
    );

  const e=
    document.getElementById("addresses");

  if(error){

    e.textContent=error.message;

    return;
  }

  if(!data?.length){

    e.innerHTML="No saved address.";

    return;
  }

  e.innerHTML=data.map(a=>`

    <div class="panel">

      <b>${esc(a.name)}</b>,
      ${esc(a.mobile)}

      <br>

      ${esc(a.house_shop||"")}
      ${esc(a.area||"")}

      <br>

      ${esc(a.city)},
      ${esc(a.state)}
      -
      ${esc(a.pincode)}

      <br>

      <button class="btn"
        onclick='selectAddress(
          ${JSON.stringify(a)}
        )'>
        Use this address
      </button>

    </div>

  `).join("");
}


function selectAddress(a){

  selectedAddress=a;

  note("Address selected ✅");
}



let checkoutCouponCode="";
function deliveryChoice(){
  return document.querySelector('input[name="delivery_method"]:checked')?.value || "standard";
}
async function loadCheckoutItems(){
  const {data,error}=await sb.from("cart").select("quantity,product_id,products(id,name,price,mrp)").eq("customer_id",currentUser.id);
  if(error)return {items:[],error};
  return {items:(data||[]).map(x=>({name:x.products?.name||"Product",quantity:Number(x.quantity||0),price:Number(x.products?.price||0),mrp:Number(x.products?.mrp||x.products?.price||0)})),error:null};
}
function renderCheckoutSummary(items){
  const itemTotal=items.reduce((n,i)=>n+i.price*i.quantity,0);
  const productDiscount=items.reduce((n,i)=>n+Math.max(0,i.mrp-i.price)*i.quantity,0);
  const couponDiscount=checkoutCouponCode==="WELCOME10"?Math.min(itemTotal*0.10,200):0;
  const d=deliveryChoice();
  const delivery=d==="express"?99:d==="fast"?49:d==="scheduled"?79:(itemTotal>=499?0:40);
  const total=Math.max(0,itemTotal-couponDiscount+delivery);
  document.getElementById("checkoutItemsSummary").innerHTML=items.map(i=>"<div>"+esc(i.name)+" × "+i.quantity+" — ₹"+(i.price*i.quantity).toFixed(2)+(i.mrp>i.price?" <span class='small'>MRP ₹"+i.mrp.toFixed(2)+"</span>":"")+"</div>").join("");
  document.getElementById("summaryItemTotal").textContent="₹"+itemTotal.toFixed(2);
  document.getElementById("summaryProductDiscount").textContent="−₹"+productDiscount.toFixed(2);
  document.getElementById("summaryCouponDiscount").textContent="−₹"+couponDiscount.toFixed(2);
  document.getElementById("summaryDelivery").textContent=delivery?"₹"+delivery.toFixed(2):"FREE";
  document.getElementById("summaryTotal").textContent="₹"+total.toFixed(2);
}
async function refreshCheckoutSummary(){
  const r=await loadCheckoutItems();
  if(!r.error)renderCheckoutSummary(r.items);
}
async function applyCheckoutCoupon(){
  checkoutCouponCode=(document.getElementById("couponInput")?.value||"").trim().toUpperCase();
  if(checkoutCouponCode && checkoutCouponCode!=="WELCOME10"){
    checkoutCouponCode="";
    note("Coupon valid nahi hai. Demo coupon: WELCOME10",true);
  }else{
    note(checkoutCouponCode?"Coupon apply ho gaya ✅":"Coupon hata diya.");
  }
  await refreshCheckoutSummary();
}

/* CHECKOUT UI */

function paymentChoice(){

  return document
    .querySelector(
      'input[name="payment_method"]:checked'
    )?.value || "razorpay";
}


function setCheckoutBusy(value){

  checkoutBusy=value;

  const b=
    document.getElementById(
      "checkoutBtn"
    );

  if(b){

    b.disabled=value;

    b.textContent=
      value
      ? "Processing..."
      : "Proceed to Checkout";

  }
}


async function checkout(){

  if(checkoutBusy)return;

  if(!currentUser){

    note(
      "Pehle login kijiye",
      true
    );

    show("account");

    return;
  }

  if(!selectedAddress){
    const {data:addresses,error:ae}=await sb
      .from("addresses")
      .select("*")
      .eq("customer_id",currentUser.id)
      .order("is_default",{ascending:false})
      .order("created_at",{ascending:false});
    if(ae){
      note(ae.message,true);
      return;
    }
    if(!addresses?.length){
      note("Pehle Delivery Address save kijiye.",true);
      show("account");
      return;
    }
    selectedAddress=addresses[0];
  }

  const box=
    document.getElementById("cartbox");

  if(document.getElementById("paymentBox")){

    return;
  }

  box.insertAdjacentHTML(
    "beforeend",

    `

    <div id="paymentBox" class="paybox">

      <h3>Delivery Address</h3>
      <div class="panel">
        <b>${esc(selectedAddress.name)}</b> — ${esc(selectedAddress.mobile)}<br>
        ${esc(selectedAddress.house_shop||"")} ${esc(selectedAddress.area||"")}<br>
        ${esc(selectedAddress.city||"")}, ${esc(selectedAddress.state||"")} - ${esc(selectedAddress.pincode||"")}
        <br>
        <button class="btn alt" onclick="changeCheckoutAddress()">Change Address</button>
      </div>
      <h3>Delivery Method</h3>
      <label class="payoption"><input type="radio" name="delivery_method" value="standard" checked onchange="refreshCheckoutSummary()"> Standard Delivery — ₹40 / ₹0 above ₹499</label>
      <label class="payoption"><input type="radio" name="delivery_method" value="fast" onchange="refreshCheckoutSummary()"> Fast Delivery — ₹49</label>
      <label class="payoption"><input type="radio" name="delivery_method" value="express" onchange="refreshCheckoutSummary()"> Express Delivery — ₹99</label>
      <label class="payoption"><input type="radio" name="delivery_method" value="scheduled" onchange="refreshCheckoutSummary()"> Scheduled Delivery — ₹79</label>

      <div id="checkoutSummary" class="panel">
        <h3>Price Details</h3>
        <div id="checkoutItemsSummary"></div>
        <div>Item Total <b id="summaryItemTotal" style="float:right">₹0.00</b></div>
        <div>Product Discount <b id="summaryProductDiscount" style="float:right">−₹0.00</b></div>
        <div>Coupon Discount <b id="summaryCouponDiscount" style="float:right">−₹0.00</b></div>
        <div>Delivery Charges <b id="summaryDelivery" style="float:right">FREE</b></div>
        <hr><div style="font-size:18px"><b>Total Payable</b><b id="summaryTotal" style="float:right">₹0.00</b></div>
        <br><input id="couponInput" placeholder="Coupon code" style="max-width:160px">
        <button class="btn" type="button" onclick="applyCheckoutCoupon()">Apply Coupon</button>
      </div>

      <h3>Payment Method</h3>

      <label class="payoption">

        <input
          type="radio"
          name="payment_method"
          value="razorpay"
          checked
        >

        <b>Online Payment</b>
        — UPI / Card / Net Banking

      </label>

      <label class="payoption">

        <input
          type="radio"
          name="payment_method"
          value="cod"
        >

        <b>Cash on Delivery</b>
        (COD)

      </label>

      <div class="small">

        Online payment me order tabhi
        Paid/Confirmed hoga jab Razorpay
        payment successfully verify ho jayega.

      </div>

      <br>

      <button
        class="btn"
        onclick="placeOrder()"
      >
        Continue
      </button>

      <button
        class="btn alt"
        onclick="
          document
          .getElementById('paymentBox')
          ?.remove()
        "
      >
        Cancel
      </button>

    </div>

    `
  );
}

async function changeCheckoutAddress(){
  if(!currentUser){
    note("Pehle login kijiye.",true);
    show("account");
    return;
  }

  const {data,error}=await sb
    .from("addresses")
    .select("*")
    .eq("customer_id",currentUser.id)
    .order("is_default",{ascending:false})
    .order("created_at",{ascending:false});

  if(error){
    note("Address load nahi hua: "+error.message,true);
    return;
  }

  const box=document.getElementById("paymentBox");
  if(!box)return;

  box.querySelector(".checkout-address-list")?.remove();

  const list=document.createElement("div");
  list.className="checkout-address-list panel";
  list.innerHTML="<h3>Change Delivery Address</h3>";

  (data||[]).forEach(a=>{
    const row=document.createElement("div");
    row.className="panel";
    row.style="border:1px solid #ddd;margin:8px 0";
    const title=document.createElement("b");
    title.textContent=(a.name||"")+" — "+(a.mobile||"");
    const details=document.createElement("div");
    details.className="small";
    details.textContent=(a.house_shop||"")+" "+(a.area||"")+" | "+(a.city||"")+", "+(a.state||"")+" - "+(a.pincode||"");
    const b=document.createElement("button");
    b.className="btn";
    b.type="button";
    b.textContent="Use this address";
    b.onclick=()=>selectCheckoutAddress(a);
    row.append(title,document.createElement("br"),details,b);
    list.appendChild(row);
  });

  list.insertAdjacentHTML("beforeend",`
    <hr>
    <h3>+ Add New Address</h3>
    <input id="newAnam" placeholder="Name">
    <input id="newAmob" placeholder="Mobile">
    <input id="newAhouse" placeholder="House/Shop">
    <input id="newAarea" placeholder="Area">
    <input id="newAcity" placeholder="City">
    <input id="newAstate" placeholder="State">
    <input id="newApin" placeholder="PIN code">
    <button class="btn" type="button" onclick="saveCheckoutAddress()">Save & Use New Address</button>
  `);

  box.insertBefore(list,box.firstChild);
}

async function saveCheckoutAddress(){
  if(!currentUser)return;

  const a={
    customer_id:currentUser.id,
    name:document.getElementById("newAnam")?.value.trim(),
    mobile:document.getElementById("newAmob")?.value.trim(),
    house_shop:document.getElementById("newAhouse")?.value.trim(),
    area:document.getElementById("newAarea")?.value.trim(),
    city:document.getElementById("newAcity")?.value.trim(),
    state:document.getElementById("newAstate")?.value.trim(),
    pincode:document.getElementById("newApin")?.value.trim(),
    is_default:true
  };

  if(!a.name||!a.mobile||!a.city||!a.state||!a.pincode){
    note("Name, Mobile, City, State aur PIN bharna zaroori hai.",true);
    return;
  }

  const {data,error}=await sb.from("addresses").insert(a).select().single();

  if(error){
    note("New address save nahi hua: "+error.message,true);
    return;
  }

  selectedAddress=data;
  note("New delivery address save aur select ho gaya ✅");

  document.getElementById("paymentBox")?.remove();
  checkout();
}

function selectCheckoutAddress(a){
  selectedAddress=a;
  document.getElementById("paymentBox")?.remove();
  note("Delivery address selected ✅");
  checkout();
}


/* PLACE ORDER */

async function placeOrder(){

  if(checkoutBusy)return;

  const {data:{user},error:userError}=await sb.auth.getUser();
  if(userError || !user){
    note("Session expire ho gaya. Dobara login kijiye.",true);
    currentUser=null;
    updateCartBadge();
    show("account");
    return;
  }
  currentUser=user;

  if(!selectedAddress){
    note("Delivery address select kijiye.",true);
    return;
  }

  const method=paymentChoice();
  setCheckoutBusy(true);

  let ord=null;

  try{

    /* SECURE SERVER-SIDE ORDER CREATION */
    const {data:created,error:ce}=await sb.functions.invoke(
      "create-customer-order",
      {
        body:{
          address_id:selectedAddress.id,
          payment_method:method,
          delivery_method:deliveryChoice(),
          coupon_code:checkoutCouponCode
        }
      }
    );

    if(ce || created?.error){
      throw new Error(
        ce?.message ||
        created?.error ||
        "Order create nahi hua"
      );
    }

    ord={
      id:created.order_id,
      total_amount:Number(created.amount||0),
      payment_method:method
    };

    if(!ord.id || !Number.isFinite(ord.total_amount) || ord.total_amount<=0){
      throw new Error("Invalid order response");
    }

    /* COD */
    if(method==="cod"){

      await sb
        .from("cart")
        .delete()
        .eq("customer_id",currentUser.id);

      note("COD order successfully placed 🎉");

      document
        .getElementById("paymentBox")
        ?.remove();

      setCheckoutBusy(false);
      show("orders");
      return;
    }

    /* RAZORPAY CREATE ORDER */
    const {
      data:gatewayData,
      error:fe
    }=await sb.functions.invoke(
      PAYMENT_FUNCTION,
      {
        body:{
          action:"create_order",
          order_id:ord.id,
          amount:ord.total_amount
        }
      }
    );

    if(fe){
      throw new Error(
        fe.message ||
        "Payment gateway connect nahi hua"
      );
    }

    if(gatewayData?.error){
      throw new Error(gatewayData.error);
    }

    if(
      !gatewayData?.key_id ||
      !gatewayData?.razorpay_order_id
    ){
      throw new Error("Razorpay order create nahi hua");
    }

    const options={

      key:gatewayData.key_id,
      amount:gatewayData.amount,
      currency:gatewayData.currency||"INR",
      name:"ShubhMart",
      description:"ShubhMart Order",
      order_id:gatewayData.razorpay_order_id,

      prefill:{
        name:selectedAddress.name,
        email:currentUser.email,
        contact:selectedAddress.mobile
      },

      theme:{color:"#111111"},

      handler:async function(response){

        try{

          const {
            data:v,
            error:ve
          }=await sb.functions.invoke(
            PAYMENT_FUNCTION,
            {
              body:{
                action:"verify_payment",
                order_id:ord.id,
                razorpay_order_id:response.razorpay_order_id,
                razorpay_payment_id:response.razorpay_payment_id,
                razorpay_signature:response.razorpay_signature
              }
            }
          );

          if(ve || v?.error){
            throw new Error(
              ve?.message ||
              v?.error ||
              "Payment verification failed"
            );
          }

          await sb
            .from("cart")
            .delete()
            .eq("customer_id",currentUser.id);

          note("Payment successful ✅ Order confirmed 🎉");

          document
            .getElementById("paymentBox")
            ?.remove();

          show("orders");

        }catch(err){

          note(
            "Payment verify nahi hua: "+
            err.message,
            true
          );

          show("orders");

        }finally{

          setCheckoutBusy(false);

        }

      },

      modal:{
        ondismiss:function(){

          note(
            "Payment window close ho gayi. Order Pending hai; aap dobara payment try kar sakte hain.",
            true
          );

          setCheckoutBusy(false);
          show("orders");

        }
      }

    };

    const rzp=new Razorpay(options);

    rzp.on(
      "payment.failed",
      function(response){

        note(
          "Payment failed: "+
          (
            response.error?.description ||
            "Please try again"
          ),
          true
        );

        setCheckoutBusy(false);

      }
    );

    rzp.open();

  }catch(err){

    note(
      err.message ||
      "Checkout failed",
      true
    );

    setCheckoutBusy(false);

  }

}

/* ORDER IMAGE VIEWER */

function openOrderImage(url,name){
  if(!url)return;
  const old=document.getElementById("orderImageViewer");
  old?.remove();
  const wrap=document.createElement("div");
  wrap.id="orderImageViewer";
  wrap.style="position:fixed;inset:0;background:rgba(0,0,0,.82);z-index:9999;display:flex;align-items:center;justify-content:center;padding:20px";
  wrap.innerHTML=`
    <div style="max-width:95vw;max-height:95vh;text-align:center;position:relative">
      <button class="btn" style="position:absolute;right:0;top:-48px" onclick="document.getElementById('orderImageViewer')?.remove()">✕ Close</button>
      <img src="${esc(url)}" alt="${esc(name||"Product")}" style="max-width:90vw;max-height:82vh;object-fit:contain;border-radius:12px;background:#fff">
      <div style="color:#fff;margin-top:10px;font-weight:700">${esc(name||"Product")}</div>
    </div>
  `;
  wrap.onclick=(e)=>{if(e.target===wrap)wrap.remove();};
  document.body.appendChild(wrap);
}

/* ORDERS */

async function loadOrders(){

  const e=document.getElementById("ordersbox");

  if(!currentUser){
    e.innerHTML="Login karke orders dekhein.";
    return;
  }

  const {data,error}=await sb
    .from("Orders")
    .select("*,Order_items(id,quantity,unit_price,total_price,products(name,image_url,mrp,category))")
    .eq("customer_id",currentUser.id)
    .order("created_at",{ascending:false});

  if(error){
    e.textContent=error.message;
    return;
  }

  if(!data?.length){
    e.innerHTML="No orders yet.";
    return;
  }

  e.innerHTML=data.map(o=>{
    const items=o.Order_items||[];
    const date=o.created_at ? new Date(o.created_at).toLocaleString("en-IN") : "";
    return `
      <div class="panel" style="margin-bottom:14px">
        <div style="display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap">
          <div>
            <b>Order #${String(o.id).slice(0,8)}</b>
            <div class="small">${esc(date)}</div>
          </div>
          <div><b>₹${Number(o.total_amount||0).toFixed(2)}</b></div>
        </div>

        <div style="margin:10px 0">
          <span class="small">Order Status:</span> <b>${esc(o.order_status||"Pending")}</b>
          &nbsp; | &nbsp;
          <span class="small">Payment:</span> <b>${esc(o.payment_status||"Pending")}</b>
          &nbsp; | &nbsp;
          <span class="small">Method:</span> ${esc(o.payment_method||"")}
        </div>

        <hr>

        ${items.map(i=>`
          <div class="row" style="align-items:center;margin:8px 0">
            <img src="${i.products?.image_url||"https://placehold.co/90x70?text=Product"}"
              alt="${esc(i.products?.name||"Product")}"
              onclick="openOrderImage('${esc(i.products?.image_url||"https://placehold.co/600x500?text=Product")}','${esc(i.products?.name||"Product")}')"
              style="width:80px;height:60px;object-fit:cover;border-radius:8px;cursor:zoom-in">
            <div style="flex:1">
              <b>${esc(i.products?.name||"Product")}</b>
              <div class="small">${esc(i.products?.category||"")}</div>
              <div>₹${Number(i.unit_price||0).toFixed(2)} × ${Number(i.quantity||0)}</div>
            </div>
            <b>₹${Number(i.total_price||0).toFixed(2)}</b>
          </div>
        `).join("")}

        <hr>

        <div class="panel" style="margin-top:10px">
          <div>Products Total <b style="float:right">₹${Number(o.item_total||0).toFixed(2)}</b></div>
          <div>Product Discount <b style="float:right">−₹${Number(o.product_discount||0).toFixed(2)}</b></div>
          ${o.coupon_code ? `<div>Coupon (${esc(o.coupon_code)}) <b style="float:right">−₹${Number(o.coupon_discount||0).toFixed(2)}</b></div>` : ""}
          <div>Delivery (${esc(o.delivery_method||"standard")}) <b style="float:right">${Number(o.delivery_charge||0)>0?"₹"+Number(o.delivery_charge).toFixed(2):"FREE"}</b></div>
          <hr>
          <div><b>Total Paid/Payable</b><b style="float:right">₹${Number(o.total_amount||0).toFixed(2)}</b></div>
        </div>
        <div class="small" style="margin-top:10px"><b>Delivery Address:</b><br>${esc(o.shipping_address||"Not available")}</div>
      </div>
    `;
  }).join("");
}

/* INITIAL LOAD */

sb.auth.getSession()
.then(({data})=>{

  currentUser=
    data.session?.user || null;

  loadProducts();
  updateCartBadge();

  loadAccount();

});


/* AUTH STATE */

sb.auth.onAuthStateChange(
  (_event,session)=>{

    currentUser=
      session?.user || null;

    loadAccount();

  }
);
