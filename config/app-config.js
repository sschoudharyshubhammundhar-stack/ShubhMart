// Public application configuration only.
// Never place service-role keys, SMTP passwords, payment secrets or other private credentials here.

window.SHUBHMART_CONFIG = Object.freeze({
  appName: "ShubhMart",
  tagline: "Har Zaroorat, Ek Jagah",
  currency: "INR",
  supabaseUrl: "https://yauveaexbpokhytqijae.supabase.co",
  supabasePublishableKey: "sb_publishable_79SNGwvCzpL4OqWBAInVoA_d4xFht6g",
  mode: "demo",
  features: Object.freeze({
    retailMarketplace: true,
    wholesaleMarketplace: false,
    multiSpeedDelivery: false,
    aiListing: false,
    shubhCoins: false,
    realOtp: false,
    realPayments: false,
    shubhCredit: false
  })
});
