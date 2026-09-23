// ShubhMart Supabase client boundary.
// Public browser code may use only the publishable key.
// Never place secret/service-role keys in this file.
(function(){
  const cfg = window.SHUBHMART_CONFIG || {};
  if (!window.supabase) throw new Error("Supabase client library not loaded");
  if (!cfg.supabaseUrl || !cfg.supabasePublishableKey) {
    throw new Error("ShubhMart Supabase configuration is missing");
  }
  window.shubhSupabase = window.supabase.createClient(
    cfg.supabaseUrl,
    cfg.supabasePublishableKey
  );
})();
