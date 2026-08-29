-- Paywall source: Oracy branded UI (default) vs RevenueCat dashboard PaywallView

insert into public.remote_config (key, value, description)
values (
  'use_revenuecat_paywall',
  'false'::jsonb,
  'When true, show RevenueCat dashboard PaywallView. When false, use Oracy branded paywall powered by Purchases.offerings().'
)
on conflict (key) do nothing;
