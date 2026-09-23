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

    document.getElementById("cartbox")
      .innerHTML="Login kijiye.";

    return;
  }

  const {data,error}=await sb
    .from("cart")
    .select(
      "id,quantity,product_id,products(id,name,price,mrp,image_url)"
    )
    .eq(
      "customer_id",
      currentUser.id
    );

  if(error){

    document.getElementById("cartbox")
      .textContent=error.message;
    await updateCartBadge();

    return;
  }

  await updateCartBadge();
  let total=0;

  if(!data?.length){

    document.getElementById("cartbox")
      .innerHTML="Cart empty.";
    await updateCartBadge();

    return;
  }

  document.getElementById("cartbox")
    .innerHTML=data.map(x=>{

      total +=
        Number(x.products?.price||0) *
        x.quantity;

      return `

        <div class="panel row">

          <img
            src="${x.products?.image_url ||
            "https://placehold.co/100x80"}"
            style="
              width:80px;
              height:60px;
              object-fit:cover;
              border-radius:8px
            "
          >

          <div style="flex:1">

            <b>
              ${esc(x.products?.name)}
            </b>

            <br>

            ₹${x.products?.price}
            × ${x.quantity}

          </div>

          <button class="btn"
            onclick="changeQty(
              '${x.id}',
              ${x.quantity-1}
            )">
            −
          </button>

          <button class="btn"
            onclick="changeQty(
              '${x.id}',
              ${x.quantity+1}
            )">
            +
          </button>

          <button class="btn alt"
            onclick="removeCart('${x.id}')">
            Remove
          </button>

        </div>

      `;

    }).join("")+

    `<h3>Total: ₹${total.toFixed(2)}</h3>`;
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
  if(!data?.length){
    note("Koi saved address nahi hai.",true);
    show("account");
    return;
  }
  const box=document.getElementById("paymentBox");
  if(!box)return;
  let list=box.querySelector(".checkout-address-list");
  if(list)list.remove();
  list=document.createElement("div");
  list.className="checkout-address-list panel";
  list.innerHTML="<h3>Delivery Address Change Karein</h3>";
  data.forEach(a=>{
    const row=document.createElement("div");
    row.className="panel";
    row.style="border:1px solid #ddd";
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
  box.insertBefore(list,box.firstChild);
}
function selectCheckoutAddress(a){
  selectedAddress=a;
  const box=document.getElementById("paymentBox");
  if(box)box.remove();
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

/* ORDERS */

async function loadOrders(){

  if(!currentUser){

    document.getElementById(
      "ordersbox"
    ).innerHTML=
      "Login karke orders dekhein.";

    return;
  }

  const {data,error}=
    await sb
    .from("Orders")
    .select(
      "*,Order_items(quantity,unit_price,total_price,products(name,image_url))"
    )
    .eq(
      "customer_id",
      currentUser.id
    )
    .order(
      "created_at",
      {ascending:false}
    );

  const e=
    document.getElementById(
      "ordersbox"
    );

  if(error){

    e.textContent=
      error.message;

    return;
  }

  if(!data?.length){

    e.innerHTML=
      "No orders yet.";

    return;
  }

  e.innerHTML=
    data.map(o=>`

      <div class="panel">

        <b>
          Order #${String(o.id).slice(0,8)}
        </b>

        <br>

        Amount:
        ₹${o.total_amount}

        <br>

        Order Status:
        <b>
          ${esc(o.order_status)}
        </b>

        <br>

        Payment Status:
        <b>
          ${esc(o.payment_status)}
        </b>

        <br>

        Payment Method:
        ${esc(o.payment_method)}

        <hr>

        ${
          (o.Order_items||[])
          .map(i=>`

            ${esc(
              i.products?.name ||
              "Product"
            )}

            × ${i.quantity}

            —
            ₹${i.total_price}

            <br>

          `)
          .join("")
        }

      </div>

    `).join("");
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
