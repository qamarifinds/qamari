-- ============================================================
-- QÃMÃRI FINDS — Supabase setup  (run ONCE in SQL Editor)
-- ============================================================

-- 0. Old simple test table (from the first version) is replaced.
--    Only dropped if it has the old "code" column. Old test rows are deleted.
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='products' and column_name='code') then
    drop table public.products cascade;
  end if;
end $$;

-- 1. Admin users ------------------------------------------------
create table if not exists admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);
alter table admin_users enable row level security;
drop policy if exists "admin reads self" on admin_users;
create policy "admin reads self" on admin_users for select to authenticated using (user_id = auth.uid());

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_users where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 2. Categories -------------------------------------------------
create table if not exists categories (
  id bigint generated always as identity primary key,
  name text not null,
  slug text not null unique,
  description text,
  image_url text,
  is_active boolean not null default true,
  display_order int not null default 0,
  created_at timestamptz not null default now()
);

-- 3. Products ---------------------------------------------------
create table if not exists products (
  id bigint generated always as identity primary key,
  product_code text not null unique,
  name text not null,
  slug text,
  short_description text,
  description text,
  price numeric not null default 0,
  original_price numeric,
  discount int,
  category_id bigint references categories(id) on delete set null,
  stock_quantity int not null default 0,
  stock_status text not null default 'in_stock' check (stock_status in ('in_stock','low_stock','out_of_stock')),
  is_featured boolean not null default false,
  is_new boolean not null default false,
  is_published boolean not null default false,
  dispatch_time text,
  delivery_available boolean not null default true,
  delivery_charge numeric default 0,
  free_delivery boolean not null default false,
  delivery_info text,
  social_title text, social_subtitle text, social_text text,
  social_cta text, social_caption text, social_hashtags text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists product_images (
  id bigint generated always as identity primary key,
  product_id bigint not null references products(id) on delete cascade,
  image_url text not null,
  storage_path text,
  is_primary boolean not null default false,
  display_order int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_pimg_product on product_images(product_id);

create table if not exists product_specs (
  id bigint generated always as identity primary key,
  product_id bigint not null references products(id) on delete cascade,
  label text not null,
  value text not null,
  display_order int not null default 0
);
create index if not exists idx_pspec_product on product_specs(product_id);

-- 4. Site settings (single row) --------------------------------
create table if not exists site_settings (
  id int primary key default 1 check (id = 1),
  store_name text default 'QÃMÃRI FINDS',
  logo_url text,
  whatsapp_number text default '919567525748',
  instagram_url text,
  facebook_url text,
  currency text default 'INR',
  delivery_info text,
  dispatch_info text,
  updated_at timestamptz default now()
);
insert into site_settings (id, instagram_url, facebook_url, delivery_info, dispatch_info)
values (1,
  'https://www.instagram.com/r1yyaahhhh?stkn=Ym5sMmQ3NHVpYmhl',
  'https://www.facebook.com/share/19to7oL5rv/',
  'Delivery details are confirmed on WhatsApp.',
  'Within 2 days')
on conflict (id) do nothing;

-- 5. Row Level Security ----------------------------------------
alter table categories     enable row level security;
alter table products       enable row level security;
alter table product_images enable row level security;
alter table product_specs  enable row level security;
alter table site_settings  enable row level security;

drop policy if exists "read categories" on categories;
drop policy if exists "admin categories" on categories;
create policy "read categories" on categories for select using (is_active or public.is_admin());
create policy "admin categories" on categories for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read products" on products;
drop policy if exists "admin products" on products;
create policy "read products" on products for select using (is_published or public.is_admin());
create policy "admin products" on products for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read images" on product_images;
drop policy if exists "admin images" on product_images;
create policy "read images" on product_images for select using (
  exists (select 1 from products p where p.id = product_id and (p.is_published or public.is_admin())));
create policy "admin images" on product_images for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read specs" on product_specs;
drop policy if exists "admin specs" on product_specs;
create policy "read specs" on product_specs for select using (
  exists (select 1 from products p where p.id = product_id and (p.is_published or public.is_admin())));
create policy "admin specs" on product_specs for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read settings" on site_settings;
drop policy if exists "admin settings" on site_settings;
create policy "read settings" on site_settings for select using (true);
create policy "admin settings" on site_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 6. Storage bucket for images ---------------------------------
insert into storage.buckets (id, name, public) values ('product-images', 'product-images', true)
on conflict (id) do nothing;

drop policy if exists "admin upload images" on storage.objects;
drop policy if exists "admin update images" on storage.objects;
drop policy if exists "admin delete images" on storage.objects;
create policy "admin upload images" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_admin());
create policy "admin update images" on storage.objects for update to authenticated
  using (bucket_id = 'product-images' and public.is_admin());
create policy "admin delete images" on storage.objects for delete to authenticated
  using (bucket_id = 'product-images' and public.is_admin());

-- 7. Starter categories ----------------------------------------
insert into categories (name, slug, display_order) values
  ('Jewellery','jewellery',1), ('Necklaces','necklaces',2), ('Earrings','earrings',3),
  ('Rings','rings',4), ('Bracelets','bracelets',5), ('Accessories','accessories',6),
  ('Gift Ideas','gift-ideas',7), ('Other','other',8)
on conflict (slug) do nothing;

-- ============================================================
-- AFTER running this:
-- A) Supabase → Authentication → Users → "Add user" → your admin email + password
--    (tick "Auto Confirm User").
-- B) Authentication → Sign In / Providers → turn OFF "Allow new users to sign up".
-- C) Run this ONE line with your admin email:
--
--    insert into admin_users (user_id) select id from auth.users where email = 'YOUR_ADMIN_EMAIL';
--
-- ============================================================
