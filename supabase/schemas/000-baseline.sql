

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "brand_kit";


ALTER SCHEMA "brand_kit" OWNER TO "postgres";


CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";






CREATE SCHEMA IF NOT EXISTS "library";


ALTER SCHEMA "library" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "hypopg" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "index_advisor" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "brand_kit"."Categories" AS ENUM (
    'Comedy',
    'Tech',
    'Education',
    'Lifestyle & Vlogs',
    'Gaming',
    'Beauty & Fashion',
    'Fitness & Wellness',
    'Finance & Investing',
    'Travel & Adventure',
    'Music & Performance',
    'Food & Cooking',
    'Art & DIY',
    'Personal Development',
    'Fashion & Apparel',
    'Food & Beverage',
    'Health & Wellness',
    'Technology & SaaS',
    'Professional Services',
    'Real Estate & Property',
    'Automotive',
    'Education & Training',
    'Creative & Media',
    'Home & Living',
    'Financial Services & FinTech',
    'Logistics & Supply Chain',
    'Manufacturing & Industrial',
    'Agriculture & AgriTech',
    'Energy & Utilities',
    'Marketing & Growth',
    'Design Services',
    'Development & IT',
    'Video & Animation',
    'Writing & Content',
    'Photography & Creative Media',
    'Consulting & Strategy',
    'Translation & Localization',
    'Data & Analytics',
    'Virtual Assistance & Admin',
    'Finance & Legal Advisory',
    'HR & Talent Services',
    'Product & CX Research',
    'Audio & Podcast Production',
    'AR/VR & Immersive Tech',
    'Podcasts & Audio Media',
    'Content Production'
);


ALTER TYPE "brand_kit"."Categories" OWNER TO "postgres";


CREATE TYPE "public"."Idea Category" AS ENUM (
    'Text',
    'Quote',
    'Fact',
    'Tip'
);


ALTER TYPE "public"."Idea Category" OWNER TO "postgres";


COMMENT ON TYPE "public"."Idea Category" IS 'Different types of categories for Idea Generation';



CREATE TYPE "public"."order_status" AS ENUM (
    'confirmed',
    'in_production',
    'shipped',
    'delivered',
    'completed'
);


ALTER TYPE "public"."order_status" OWNER TO "postgres";


CREATE TYPE "public"."payment_status" AS ENUM (
    'pending',
    'partial',
    'completed'
);


ALTER TYPE "public"."payment_status" OWNER TO "postgres";


CREATE TYPE "public"."post_status" AS ENUM (
    'scheduled',
    'processing',
    'success',
    'failed'
);


ALTER TYPE "public"."post_status" OWNER TO "postgres";


CREATE TYPE "public"."quotation_status" AS ENUM (
    'submitted',
    'pending_review',
    'approved',
    'rejected'
);


ALTER TYPE "public"."quotation_status" OWNER TO "postgres";


CREATE TYPE "public"."rfq_db_status" AS ENUM (
    'draft',
    'submitted',
    'approved',
    'rejected',
    'assigned'
);


ALTER TYPE "public"."rfq_db_status" OWNER TO "postgres";


CREATE TYPE "public"."user_type" AS ENUM (
    'buyer',
    'supplier',
    'admin'
);


ALTER TYPE "public"."user_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "brand_kit"."refresh_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'brand_kit', 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION "brand_kit"."refresh_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$select auth.uid()$$;


ALTER FUNCTION "public"."_uid"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buyer_analytics"("_buyer_id" "uuid", "months" integer DEFAULT 6) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
declare
  has_quotes boolean := to_regclass('public.quotations') is not null;
  has_sample_quotes boolean := to_regclass('public.sample_quotes') is not null;
  since timestamptz := date_trunc('month', now()) - (interval '1 month' * (months - 1));
  summary jsonb;
  topcats jsonb;
  monthly jsonb;
begin
  -- base summary
  summary := jsonb_build_object(
    'total_rfqs',        (select count(*) from public.rfqs r where r.buyer_id = _buyer_id),
    'active_rfqs',       (select count(*) from public.rfqs r where r.buyer_id = _buyer_id and r.status in ('approved','matched','quoted')),
    'completed_orders',  (select count(*) from public.orders o where o.buyer_id = _buyer_id and o.status = 'completed'),
    'total_spent',       coalesce((select sum(o.order_value) from public.orders o where o.buyer_id = _buyer_id), 0)
  );

  -- response time + supplier count (quotations -> sample_quotes -> defaults)
  if has_quotes then
    summary := summary || jsonb_build_object(
      'avg_response_time_days',
        (select avg(extract(epoch from (fq.first_quote_at - r.created_at)) / 86400.0)
         from public.rfqs r
         left join (select rfq_id, min(created_at) as first_quote_at
                    from public.quotations group by rfq_id) fq on fq.rfq_id = r.id
         where r.buyer_id = _buyer_id),
      'supplier_count',
        coalesce((select count(distinct q.supplier_id)
                  from public.quotations q
                  join public.rfqs r on r.id = q.rfq_id
                  where r.buyer_id = _buyer_id), 0)
    );
  elsif has_sample_quotes then
    summary := summary || jsonb_build_object(
      'avg_response_time_days',
        (select avg(extract(epoch from (fq.first_quote_at - r.created_at)) / 86400.0)
         from public.rfqs r
         left join (
           select sr.id as rfq_id, min(sq.created_at) as first_quote_at
           from public.sample_requests sr
           join public.sample_quotes sq on sq.sample_request_id = sr.id
           group by sr.id
         ) fq on fq.rfq_id = r.id
         where r.buyer_id = _buyer_id),
      'supplier_count',
        coalesce((select count(distinct sq.supplier_id)
                  from public.sample_quotes sq
                  join public.sample_requests sr on sr.id = sq.sample_request_id
                  where sr.buyer_id = _buyer_id), 0)
    );
  else
    summary := summary || jsonb_build_object('avg_response_time_days', null, 'supplier_count', 0);
  end if;

  -- top categories
  topcats := coalesce((
    select jsonb_agg(jsonb_build_object('category', category, 'count', cnt) order by cnt desc)
    from (
      select r.category, count(*)::int as cnt
      from public.rfqs r
      where r.buyer_id = _buyer_id
      group by r.category
      order by cnt desc
      limit 5
    ) t
  ), '[]'::jsonb);

  -- monthly spend (last N months)
  monthly := coalesce((
    select jsonb_agg(
             jsonb_build_object('key', to_char(month, 'YYYY-MM'), 'amount', amount)
             order by month
           )
    from (
      select date_trunc('month', o.created_at) as month, sum(o.order_value)::numeric as amount
      from public.orders o
      where o.buyer_id = _buyer_id and o.created_at >= since
      group by 1
      order by 1
    ) s
  ), '[]'::jsonb);

  return jsonb_build_object('summary', summary, 'topCategories', topcats, 'monthly', monthly);
end $$;


ALTER FUNCTION "public"."buyer_analytics"("_buyer_id" "uuid", "months" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buyer_analytics_safe"("_buyer_id" "uuid", "months" integer DEFAULT 6) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $$
declare
  has_rfqs            boolean := to_regclass('public.rfqs')            is not null;
  has_orders          boolean := to_regclass('public.orders')          is not null;
  has_quotes          boolean := to_regclass('public.quotations')      is not null;
  has_sample_requests boolean := to_regclass('public.sample_requests') is not null;
  has_sample_quotes   boolean := to_regclass('public.sample_quotes')   is not null;

  since timestamptz := date_trunc('month', now()) - (interval '1 month' * (months - 1));

  total_rfqs int := 0;
  active_rfqs int := 0;
  completed_orders int := 0;
  total_spent numeric := 0;
  avg_response numeric := null;
  supplier_count int := 0;

  topcats jsonb := '[]'::jsonb;
  monthly jsonb := '[]'::jsonb;
begin
  if has_rfqs then
    select count(*) into total_rfqs
    from public.rfqs r
    where r.buyer_id = _buyer_id;

    select count(*) into active_rfqs
    from public.rfqs r
    where r.buyer_id = _buyer_id
      and r.status in ('approved','matched','quoted');

    select coalesce(jsonb_agg(jsonb_build_object('category', category, 'count', cnt) order by cnt desc), '[]'::jsonb)
      into topcats
    from (
      select r.category, count(*)::int as cnt
      from public.rfqs r
      where r.buyer_id = _buyer_id
      group by r.category
      order by cnt desc
      limit 5
    ) t;
  end if;

  if has_orders then
    select coalesce(sum(o.order_value), 0) into total_spent
    from public.orders o
    where o.buyer_id = _buyer_id;

    select count(*) into completed_orders
    from public.orders o
    where o.buyer_id = _buyer_id
      and o.status = 'completed';

    select coalesce(jsonb_agg(jsonb_build_object('key', to_char(month, 'YYYY-MM'), 'amount', amount) order by month), '[]'::jsonb)
      into monthly
    from (
      select date_trunc('month', o.created_at) as month,
             sum(o.order_value)::numeric as amount
      from public.orders o
      where o.buyer_id = _buyer_id
        and o.created_at >= since
      group by 1
      order by 1
    ) s;
  end if;

  if has_quotes and has_rfqs then
    with fq as (
      select q.rfq_id, min(q.created_at) as first_quote_at
      from public.quotations q
      group by q.rfq_id
    )
    select avg(extract(epoch from (fq.first_quote_at - r.created_at)) / 86400.0)
      into avg_response
    from public.rfqs r
    left join fq on fq.rfq_id = r.id
    where r.buyer_id = _buyer_id;

    select count(distinct q.supplier_id) into supplier_count
    from public.quotations q
    join public.rfqs r on r.id = q.rfq_id
    where r.buyer_id = _buyer_id;

  elsif has_sample_quotes and has_sample_requests and has_rfqs then
    with fq as (
      select sr.rfq_id, min(sq.created_at) as first_quote_at
      from public.sample_requests sr
      join public.sample_quotes sq on sq.sample_request_id = sr.id
      group by sr.rfq_id
    )
    select avg(extract(epoch from (fq.first_quote_at - r.created_at)) / 86400.0)
      into avg_response
    from public.rfqs r
    left join fq on fq.rfq_id = r.id
    where r.buyer_id = _buyer_id;

    select count(distinct sq.supplier_id) into supplier_count
    from public.sample_quotes sq
    join public.sample_requests sr on sr.id = sq.sample_request_id
    where sr.buyer_id = _buyer_id;
  end if;

  return jsonb_build_object(
    'summary', jsonb_build_object(
      'total_rfqs', total_rfqs,
      'active_rfqs', active_rfqs,
      'completed_orders', completed_orders,
      'total_spent', total_spent,
      'avg_response_time_days', avg_response,
      'supplier_count', supplier_count
    ),
    'topCategories', topcats,
    'monthly', monthly
  );
end;
$$;


ALTER FUNCTION "public"."buyer_analytics_safe"("_buyer_id" "uuid", "months" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buyer_orders_for"("_buyer_id" "uuid") RETURNS SETOF "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
  has_rfqs       boolean := to_regclass('public.rfqs') is not null;
  has_profiles   boolean := to_regclass('public.profiles') is not null;
  has_suppliers  boolean := to_regclass('public.suppliers') is not null;

  has_qty            boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='quantity');
  has_unit_price     boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='unit_price');
  has_expected_deliv boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='expected_delivery');
  has_tracking       boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='tracking_number');
  has_payment_status boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='orders' and column_name='payment_status');

  sql text;
  rec record;
begin
  -- If orders table itself is missing, return empty
  if to_regclass('public.orders') is null then
    return;
  end if;

  sql := 'select o.id
               , o.created_at as order_date
               , o.status
               , o.order_value as total_value';

  if has_qty then            sql := sql || ', o.quantity'; end if;
  if has_unit_price then     sql := sql || ', o.unit_price'; end if;
  if has_expected_deliv then sql := sql || ', o.expected_delivery'; end if;
  if has_tracking then       sql := sql || ', o.tracking_number'; end if;
  if has_payment_status then sql := sql || ', o.payment_status'; end if;

  if has_rfqs then           sql := sql || ', r.title as rfq_title'; end if;
  if has_profiles then       sql := sql || ', p.name as supplier_contact, p.company as supplier_company'; end if;
  if has_suppliers then      sql := sql || ', (s.location->>''city'') || coalesce('', '', s.location->>''state'') as supplier_location'; end if;

  sql := sql || ' from public.orders o ';

  if has_rfqs then     sql := sql || ' left join public.rfqs r on r.id = o.rfq_id '; end if;
  if has_profiles then sql := sql || ' left join public.profiles p on p.id = o.supplier_id '; end if;
  if has_suppliers then sql := sql || ' left join public.suppliers s on s.profile_id = o.supplier_id '; end if;

  sql := sql || ' where o.buyer_id = $1 order by o.created_at desc';

  for rec in execute sql using _buyer_id loop
    return next to_jsonb(rec);
  end loop;

  return;
end;
$_$;


ALTER FUNCTION "public"."buyer_orders_for"("_buyer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."buyer_rfqs_for"("_buyer_id" "uuid") RETURNS SETOF "jsonb"
    LANGUAGE "plpgsql" STABLE
    AS $_$
declare
  has_rfqs boolean := to_regclass('public.rfqs') is not null;
  has_quotations boolean := to_regclass('public.quotations') is not null;

  has_desc boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='description');
  has_deliv boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='delivery_timeline');
  has_maxp boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='max_price');
  has_ship boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='shipping_terms');
  has_quality boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='quality_standards');
  has_certs boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='certifications_needed');
  has_addl boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='additional_requirements');
  has_images boolean := exists(select 1 from information_schema.columns where table_schema='public' and table_name='rfqs' and column_name='images');

  sql text;
  rec record;
begin
  if not has_rfqs then return; end if;

  sql := 'select r.id, r.title, r.category, r.quantity, r.unit, r.target_price, r.status, r.created_at';

  if has_desc   then sql := sql || ', r.description'; end if;
  if has_deliv  then sql := sql || ', r.delivery_timeline'; end if;
  if has_maxp   then sql := sql || ', r.max_price'; end if;
  if has_ship   then sql := sql || ', r.shipping_terms'; end if;
  if has_quality then sql := sql || ', r.quality_standards'; end if;
  if has_certs  then sql := sql || ', r.certifications_needed'; end if;
  if has_addl   then sql := sql || ', r.additional_requirements'; end if;
  if has_images then sql := sql || ', r.images'; end if;

  if has_quotations
    then sql := sql || ', coalesce(q.quotations_count,0) as quotations_count';
    else sql := sql || ', 0::int as quotations_count';
  end if;

  sql := sql || ' from public.rfqs r';
  if has_quotations then
    sql := sql || ' left join (select rfq_id, count(*)::int as quotations_count from public.quotations group by rfq_id) q on q.rfq_id = r.id';
  end if;

  sql := sql || ' where r.buyer_id = $1 order by r.created_at desc';

  for rec in execute sql using _buyer_id loop
    return next to_jsonb(rec);
  end loop;

  return;
end;
$_$;


ALTER FUNCTION "public"."buyer_rfqs_for"("_buyer_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cleanup_oauth_nonce"() RETURNS "void"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
BEGIN
 DELETE FROM oauth_nonce WHERE expires_at < NOW();
END;
$$;


ALTER FUNCTION "public"."cleanup_oauth_nonce"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_social_connection_status"("user_uuid" "uuid") RETURNS "json"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    result JSON;
    connection_count INT;
    needs_reconnect_count INT;
BEGIN
    SELECT 
        COUNT(*) as total_connections,
        COUNT(*) FILTER (WHERE needs_reconnect = true OR connected_at < NOW() - INTERVAL '50 days') as needs_reconnect
    INTO connection_count, needs_reconnect_count
    FROM social_accounts 
    WHERE user_id = user_uuid 
    AND is_disconnected = false;
    
    SELECT json_build_object(
        'has_connections', connection_count > 0,
        'connection_count', connection_count,
        'needs_reconnect', needs_reconnect_count > 0,
        'needs_reconnect_count', needs_reconnect_count,
        'is_connected', connection_count > 0 AND needs_reconnect_count = 0
    ) INTO result;
    
    RETURN result;
END;
$$;


ALTER FUNCTION "public"."get_social_connection_status"("user_uuid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."orders_set_amount"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  NEW.amount := COALESCE(NEW.quantity,0) * COALESCE(NEW.unit_price,0);
  RETURN NEW;
END$$;


ALTER FUNCTION "public"."orders_set_amount"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."public_are_valid_alt_texts"("arr" "text"[]) RETURNS boolean
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
  -- true if no invalid element exists
  SELECT NOT EXISTS (
    SELECT 1
    FROM unnest($1) AS v
    WHERE NOT public_is_valid_alt_text(v)
  );
$_$;


ALTER FUNCTION "public"."public_are_valid_alt_texts"("arr" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."public_is_valid_alt_text"("t" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE STRICT
    AS $_$
  SELECT ($1 = '' OR length($1) BETWEEN 140 AND 250);
$_$;


ALTER FUNCTION "public"."public_is_valid_alt_text"("t" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."redeem_meta_nonce"("_nonce" "uuid", "_min_time" timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE("encrypted_token" "text", "page_id" "text", "page_name" "text", "ig_user_id" "text", "platform" "text")
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  return query
  delete from public.oauth_nonce as n
  where  n.nonce = _nonce
    and (_min_time is null or n.created_at >= _min_time)
  returning n.encrypted_token,
           n.page_id,
           n.page_name,
           n.ig_user_id,
           n.platform;
end;
$$;


ALTER FUNCTION "public"."redeem_meta_nonce"("_nonce" "uuid", "_min_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."supplier_category_performance_for"("_supplier_id" "uuid") RETURNS TABLE("category" "text", "quotes" integer, "accepted" integer, "win_rate" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  select r.category,
         count(*)::int as quotes,
         count(*) filter (where q.status='approved')::int as accepted,
         case when count(*)=0 then 0 else round((count(*) filter (where q.status='approved')::numeric / count(*)::numeric)*100,1) end as win_rate
  from quotations q
  join rfqs r on r.id = q.rfq_id
  where q.supplier_id = _supplier_id
  group by r.category
  order by quotes desc;
$$;


ALTER FUNCTION "public"."supplier_category_performance_for"("_supplier_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."supplier_monthly_quotes_for"("_supplier_id" "uuid", "_months" integer DEFAULT 6) RETURNS TABLE("month" "date", "quotes" integer, "accepted" integer)
    LANGUAGE "sql" STABLE
    AS $$
  with months as (
    select generate_series(date_trunc('month', now()) - ((_months-1) || ' months')::interval,
                           date_trunc('month', now()),
                           interval '1 month')::date as m
  ),
  q as (
    select date_trunc('month', created_at)::date as m, status
    from quotations
    where supplier_id = _supplier_id
  )
  select m as month,
         coalesce((select count(*) from q where q.m = months.m), 0) as quotes,
         coalesce((select count(*) from q where q.m = months.m and status='approved'), 0) as accepted
  from months
  order by month;
$$;


ALTER FUNCTION "public"."supplier_monthly_quotes_for"("_supplier_id" "uuid", "_months" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."supplier_orders_for"("_supplier_id" "uuid") RETURNS TABLE("id" "uuid", "rfq_title" "text", "buyer_company" "text", "buyer_contact" "text", "buyer_country" "text", "quantity" numeric, "unit_price" numeric, "total_value" numeric, "status" "public"."order_status", "order_date" timestamp with time zone, "expected_delivery" "date", "tracking_number" "text", "payment_status" "public"."payment_status", "payment_received" numeric, "payment_pending" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  with base as (
    select
      o.id,
      o.quantity,
      o.unit_price,
      o.status,
      o.created_at,
      o.expected_delivery,
      o.tracking_number,
      o.payment_status,
      r.title as rfq_title,
      p.company as buyer_company,
      coalesce(p.full_name, p.company) as buyer_contact,
      p.country as buyer_country,
      coalesce(o.amount, coalesce(o.quantity,0)*coalesce(o.unit_price,0)) as total_value_calc
    from orders o
    join profiles p on p.id = o.buyer_id
    left join rfqs r on r.id = o.rfq_id
    where o.supplier_id = _supplier_id
  ),
  pay as (
    select
      *,
      case
        when payment_status = 'pending' then 0
        when payment_status = 'partial' then coalesce(total_value_calc,0) * 0.30
        else coalesce(total_value_calc,0)
      end as paid
    from base
  )
  select
    id,
    rfq_title,
    buyer_company,
    buyer_contact,
    buyer_country,
    quantity,
    unit_price,
    total_value_calc as total_value,
    status,
    created_at as order_date,
    expected_delivery,
    tracking_number,
    payment_status,
    paid as payment_received,
    greatest(coalesce(total_value_calc,0) - paid, 0) as payment_pending
  from pay
  order by order_date desc;
$$;


ALTER FUNCTION "public"."supplier_orders_for"("_supplier_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."supplier_performance_summary"("_supplier_id" "uuid") RETURNS TABLE("total_quotes" integer, "accepted_quotes" integer, "total_revenue" numeric, "avg_response_time_hours" numeric, "rating" numeric, "completed_orders" integer, "win_rate" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  with q as (
    select * from quotations where supplier_id = _supplier_id
  ),
  o as (
    select * from orders where supplier_id = _supplier_id
  ),
  fb as (
    select avg(rating)::numeric as avg_rating
    from supplier_feedback
    where supplier_id = _supplier_id
  )
  select
    (select count(*) from q) as total_quotes,
    (select count(*) from q where status = 'approved') as accepted_quotes,
    coalesce((select sum(amount) from o), 0) as total_revenue,
    0::numeric as avg_response_time_hours,
    coalesce((select avg_rating from fb), 4.8) as rating,
    (select count(*) from o where status = 'completed') as completed_orders,
    case when (select count(*) from q)=0 then 0
         else round(((select count(*) from q where status='approved')::numeric
                    / (select count(*) from q)::numeric) * 100, 1)
    end as win_rate;
$$;


ALTER FUNCTION "public"."supplier_performance_summary"("_supplier_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."supplier_recent_feedback_for"("_supplier_id" "uuid", "_limit" integer DEFAULT 5) RETURNS TABLE("buyer" "text", "rating" integer, "comment" "text", "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE
    AS $$
  select coalesce(p.company, p.full_name) as buyer, f.rating, f.comment, f.created_at
  from supplier_feedback f
  join profiles p on p.id = f.buyer_id
  where f.supplier_id = _supplier_id
  order by f.created_at desc
  limit _limit;
$$;


ALTER FUNCTION "public"."supplier_recent_feedback_for"("_supplier_id" "uuid", "_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."texts_length_between"("arr" "text"[], "lo" integer, "hi" integer) RETURNS boolean
    LANGUAGE "sql" IMMUTABLE PARALLEL SAFE
    AS $$
  SELECT COALESCE(bool_and(length(t) BETWEEN lo AND hi), TRUE)
  FROM unnest(arr) AS t;
$$;


ALTER FUNCTION "public"."texts_length_between"("arr" "text"[], "lo" integer, "hi" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog', 'public', 'pg_temp'
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."update_updated_at_column"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "brand_kit"."aspect_ratios" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "width" integer NOT NULL,
    "height" integer NOT NULL
);


ALTER TABLE "brand_kit"."aspect_ratios" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "brand_kit"."aspect_ratios_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE "brand_kit"."aspect_ratios_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "brand_kit"."aspect_ratios_id_seq" OWNED BY "brand_kit"."aspect_ratios"."id";



CREATE TABLE IF NOT EXISTS "brand_kit"."backgrounds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category" "brand_kit"."Categories",
    "path" "text" NOT NULL,
    "aspect_ratio" "text",
    "tags" "text"[],
    "dominant_color" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "source_type" "text",
    "uploaded_by" "uuid" DEFAULT "auth"."uid"()
);


ALTER TABLE "brand_kit"."backgrounds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "brand_kit"."brand_kits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "brand_name" "text" NOT NULL,
    "brand_logo_path" "text",
    "transparent_logo_path" "text",
    "mark_only_url" "text",
    "colors" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "fonts" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "layout" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "image_style" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "iconography" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "motion" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "voice" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "templates" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "accessibility" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "safe_zone_pct" integer DEFAULT 10 NOT NULL,
    "contrast_min" numeric(3,2) DEFAULT 3.00 NOT NULL,
    "fallback_fonts" "text"[] DEFAULT ARRAY[]::"text"[] NOT NULL,
    "fallback_colors" "text"[] DEFAULT ARRAY[]::"text"[] NOT NULL,
    "feature_flags" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "backgrounds" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL
);


ALTER TABLE "brand_kit"."brand_kits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "brand_kit"."brandkit_usage_aggregates" (
    "brandkit_id" "uuid" NOT NULL,
    "applied_count" bigint DEFAULT 0 NOT NULL,
    "last_applied_at" timestamp with time zone
);


ALTER TABLE "brand_kit"."brandkit_usage_aggregates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "brand_kit"."brandkit_usage_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brandkit_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "event_data" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "brand_kit"."brandkit_usage_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "brand_kit"."brandkit_versions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "brandkit_id" "uuid" NOT NULL,
    "version_data" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "brand_kit"."brandkit_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "brand_kit"."templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "aspect_ratio" "text" NOT NULL,
    "layout_definition" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "brand_kit"."templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."brand_profiles" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "brand_name" "text",
    "primary_color" "text" DEFAULT '#004aad'::"text",
    "voice_tone" "text" DEFAULT 'Friendly-professional'::"text",
    "language" "text" DEFAULT 'en'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "persona" "text",
    "primary_goal" "text",
    "content_types" "text"[],
    "first_platform" "text",
    "target_posts_per_week" integer,
    "voice_tags" "text"[],
    "category" "text",
    "subcategory" "text",
    "timezone" "text",
    "brand_logo_path" "text"
);


ALTER TABLE "public"."brand_profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."content_ideas" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid",
    "idea" "text" NOT NULL,
    "accepted" boolean DEFAULT false NOT NULL,
    "used_in_generation" boolean DEFAULT false NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"(),
    "category" "public"."Idea Category" DEFAULT 'Text'::"public"."Idea Category",
    "source" "text",
    "background" "text",
    "customization" "jsonb"
);


ALTER TABLE "public"."content_ideas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."oauth_nonce" (
    "nonce" "uuid" NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "expires_at" timestamp without time zone NOT NULL,
    "encrypted_token" "text",
    "person_urn" "text",
    "created_at" timestamp with time zone,
    "platform" "text",
    "page_id" "text",
    "page_name" "text",
    "ig_user_id" "text"
);


ALTER TABLE "public"."oauth_nonce" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rfq_id" "uuid",
    "buyer_id" "uuid" NOT NULL,
    "supplier_id" "uuid",
    "order_value" numeric DEFAULT 0,
    "status" "public"."order_status" DEFAULT 'confirmed'::"public"."order_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "payment_status" "public"."payment_status" DEFAULT 'pending'::"public"."payment_status" NOT NULL,
    "quantity" numeric,
    "unit_price" numeric,
    "amount" numeric,
    "expected_delivery" "date",
    "tracking_number" "text"
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."post_analytics" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "platform" "text" NOT NULL,
    "content" "text",
    "engagement" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "post_analytics_platform_check" CHECK (("platform" = 'linkedin'::"text"))
);


ALTER TABLE "public"."post_analytics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prebuilt_backgrounds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "category" "text" NOT NULL,
    "path" "text" NOT NULL,
    "aspect_ratio" "text" DEFAULT '1:1'::"text",
    "prompt" "text",
    "prompt_hash" "text",
    "source_model" "text" DEFAULT 'dall-e-3'::"text",
    "creator_id" "uuid" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "visibility" "text" DEFAULT 'public'::"text",
    "alt_text" "text" DEFAULT ''::"text" NOT NULL,
    CONSTRAINT "check_alt_text_length_optional" CHECK ((("alt_text" IS NULL) OR "public"."public_is_valid_alt_text"("alt_text"))),
    CONSTRAINT "prebuilt_backgrounds_visibility_check" CHECK (("visibility" = ANY (ARRAY['public'::"text", 'draft'::"text", 'archived'::"text"])))
);


ALTER TABLE "public"."prebuilt_backgrounds" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "user_type" "public"."user_type" DEFAULT 'buyer'::"public"."user_type" NOT NULL,
    "full_name" "text",
    "company" "text",
    "country" "text",
    "email" "text",
    "phone" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."quotations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "rfq_id" "uuid" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "price" numeric,
    "total_cost" numeric,
    "lead_time" "text",
    "validity_date" "date",
    "notes" "text",
    "status" "public"."quotation_status" DEFAULT 'submitted'::"public"."quotation_status" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."quotations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."rfqs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "buyer_id" "uuid" NOT NULL,
    "title" "text",
    "category" "text",
    "status" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."rfqs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."scheduled_insight_card_posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" DEFAULT "auth"."uid"(),
    "platform" "text" NOT NULL,
    "image_url" "text" NOT NULL,
    "caption" "text" NOT NULL,
    "category" "text" NOT NULL,
    "scheduled_at" timestamp with time zone NOT NULL,
    "status" "public"."post_status" DEFAULT 'scheduled'::"public"."post_status",
    "linkedin_asset_urn" "text",
    "linkedin_post_urn" "text",
    "error" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "facebook_photo_id" "text",
    "facebook_post_id" "text",
    "instagram_media_id" "text",
    "post_type" "text",
    CONSTRAINT "scheduled_insight_card_posts_platform_check" CHECK (("platform" = ANY (ARRAY['linkedin'::"text", 'facebook'::"text", 'instagram'::"text"])))
);


ALTER TABLE "public"."scheduled_insight_card_posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."scheduled_posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "platform" "text",
    "caption" "text",
    "scheduled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "status" "public"."post_status",
    "posted_at" timestamp with time zone,
    "post_urn" "text",
    "post_id" "uuid",
    "post_type" "text",
    "media_urls" "text"[],
    "alt_texts" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    CONSTRAINT "check_alt_texts_length_optional" CHECK ((("alt_texts" IS NULL) OR ("cardinality"("alt_texts") = 0) OR "public"."public_are_valid_alt_texts"("alt_texts"))),
    CONSTRAINT "scheduled_posts_post_type_check" CHECK (("post_type" = ANY (ARRAY['linkedin_post'::"text", 'linkedin_image'::"text", 'linkedin_carousel'::"text", 'facebook_post'::"text", 'facebook_image'::"text", 'facebook_story'::"text", 'facebook_multi'::"text", 'instagram_post'::"text", 'instagram_story'::"text", 'instagram_carousel'::"text"])))
);


ALTER TABLE "public"."scheduled_posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."social_accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "platform" "text" NOT NULL,
    "access_token" "text",
    "connected_at" timestamp with time zone,
    "author_urn" "text",
    "account_type" "text" DEFAULT 'personal'::"text",
    "provider" "text",
    "organization_urn" "text",
    "page_name" "text",
    "needs_reconnect" boolean,
    "page_id" "text",
    "ig_user_id" "text",
    "is_disconnected" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."social_accounts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."social_accounts"."platform" IS 'linkedin | facebook | instagram';



COMMENT ON COLUMN "public"."social_accounts"."account_type" IS 'org | page | ig | personal (optional)';



COMMENT ON COLUMN "public"."social_accounts"."page_id" IS 'Facebook Page ID or LinkedIn org ID';



COMMENT ON COLUMN "public"."social_accounts"."ig_user_id" IS 'Instagram user ID if linked to page';



CREATE TABLE IF NOT EXISTS "public"."subscription_features" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "key" "text" NOT NULL,
    "name" "text" NOT NULL,
    "unit" "text" NOT NULL,
    "is_metered" boolean DEFAULT false,
    "default_price_per_unit" numeric,
    "description" "text"
);


ALTER TABLE "public"."subscription_features" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscription_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "price_usd" numeric NOT NULL,
    "price_inr" numeric NOT NULL,
    "template_type" "text" DEFAULT 'preset'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."subscription_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "plan_id" "text",
    "status" "text",
    "start_date" "date",
    "end_date" "date",
    "payment_provider" "text",
    "provider_ref" "text"
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."supplier_feedback" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "buyer_id" "uuid" NOT NULL,
    "rating" integer NOT NULL,
    "comment" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "supplier_feedback_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."supplier_feedback" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "name" "text" NOT NULL,
    "config" "jsonb" NOT NULL,
    "background_path" "text" NOT NULL,
    "aspect_ratio" "text" DEFAULT '1:1'::"text",
    "category" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_subscription_status" (
    "user_id" "uuid" NOT NULL,
    "trial_started_at" timestamp with time zone,
    "trial_ends_at" timestamp with time zone,
    "is_trial_active" boolean DEFAULT false NOT NULL,
    "plan_name" "text",
    "plan_started_at" timestamp with time zone,
    "is_active_subscriber" boolean DEFAULT false NOT NULL,
    "billing_provider" "text",
    "billing_id" "text",
    "last_renewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "billing_customer_id" "text",
    "billing_subscription_id" "text",
    "plan_ends_at" timestamp with time zone,
    "status" "text",
    "plan_duration_months" smallint
);


ALTER TABLE "public"."user_subscription_status" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "full_name" "text",
    "email" "text" NOT NULL,
    "profile_pic" "text",
    "timezone" "text",
    "created_at" timestamp without time zone DEFAULT "now"(),
    "current_plan_id" "text",
    "is_admin" boolean DEFAULT false,
    "success_kpis" "text"[],
    "posting_preferences" "jsonb"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."waitlist_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text",
    "referral_code" "text",
    "joined_at" timestamp without time zone DEFAULT "now"(),
    "source" "text",
    "name" "text"
);


ALTER TABLE "public"."waitlist_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."webhook_events" (
    "id" "text" NOT NULL,
    "event_type" "text",
    "received_at" timestamp with time zone DEFAULT "now"(),
    "payload" "jsonb"
);


ALTER TABLE "public"."webhook_events" OWNER TO "postgres";


ALTER TABLE ONLY "brand_kit"."aspect_ratios" ALTER COLUMN "id" SET DEFAULT "nextval"('"brand_kit"."aspect_ratios_id_seq"'::"regclass");



ALTER TABLE ONLY "brand_kit"."aspect_ratios"
    ADD CONSTRAINT "aspect_ratios_name_key" UNIQUE ("name");



ALTER TABLE ONLY "brand_kit"."aspect_ratios"
    ADD CONSTRAINT "aspect_ratios_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "brand_kit"."backgrounds"
    ADD CONSTRAINT "backgrounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "brand_kit"."brand_kits"
    ADD CONSTRAINT "brand_kits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "brand_kit"."brandkit_usage_aggregates"
    ADD CONSTRAINT "brandkit_usage_aggregates_pkey" PRIMARY KEY ("brandkit_id");



ALTER TABLE ONLY "brand_kit"."brandkit_usage_events"
    ADD CONSTRAINT "brandkit_usage_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "brand_kit"."brandkit_versions"
    ADD CONSTRAINT "brandkit_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "brand_kit"."templates"
    ADD CONSTRAINT "templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."brand_profiles"
    ADD CONSTRAINT "brand_profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."content_ideas"
    ADD CONSTRAINT "content_ideas_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."oauth_nonce"
    ADD CONSTRAINT "oauth_nonce_pkey" PRIMARY KEY ("nonce");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_analytics"
    ADD CONSTRAINT "post_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prebuilt_backgrounds"
    ADD CONSTRAINT "prebuilt_backgrounds_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prebuilt_backgrounds"
    ADD CONSTRAINT "prebuilt_backgrounds_prompt_hash_key" UNIQUE ("prompt_hash");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."quotations"
    ADD CONSTRAINT "quotations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."rfqs"
    ADD CONSTRAINT "rfqs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scheduled_insight_card_posts"
    ADD CONSTRAINT "scheduled_insight_card_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."scheduled_posts"
    ADD CONSTRAINT "scheduled_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."social_accounts"
    ADD CONSTRAINT "social_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscription_features"
    ADD CONSTRAINT "subscription_features_key_key" UNIQUE ("key");



ALTER TABLE ONLY "public"."subscription_features"
    ADD CONSTRAINT "subscription_features_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscription_templates"
    ADD CONSTRAINT "subscription_templates_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."subscription_templates"
    ADD CONSTRAINT "subscription_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."supplier_feedback"
    ADD CONSTRAINT "supplier_feedback_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."templates"
    ADD CONSTRAINT "templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."social_accounts"
    ADD CONSTRAINT "unique_linkedin_urn" UNIQUE ("platform", "author_urn");



ALTER TABLE ONLY "public"."brand_profiles"
    ADD CONSTRAINT "unique_owner" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."social_accounts"
    ADD CONSTRAINT "unique_user_platform" UNIQUE ("user_id", "platform");



ALTER TABLE ONLY "public"."user_subscription_status"
    ADD CONSTRAINT "user_subscription_status_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."waitlist_users"
    ADD CONSTRAINT "waitlist_users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."waitlist_users"
    ADD CONSTRAINT "waitlist_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."webhook_events"
    ADD CONSTRAINT "webhook_events_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_bk_backgrounds" ON "brand_kit"."brand_kits" USING "gin" ("backgrounds");



CREATE INDEX "idx_bk_colors" ON "brand_kit"."brand_kits" USING "gin" ("colors");



CREATE INDEX "idx_bk_layout" ON "brand_kit"."brand_kits" USING "gin" ("layout");



CREATE INDEX "idx_bk_templates" ON "brand_kit"."brand_kits" USING "gin" ("templates");



CREATE INDEX "idx_bk_typography" ON "brand_kit"."brand_kits" USING "gin" ("fonts");



CREATE INDEX "idx_bk_user" ON "brand_kit"."brand_kits" USING "btree" ("user_id");



CREATE INDEX "idx_bkv_brandkit" ON "brand_kit"."brandkit_versions" USING "btree" ("brandkit_id");



CREATE INDEX "idx_bue_brandkit" ON "brand_kit"."brandkit_usage_events" USING "btree" ("brandkit_id");



CREATE INDEX "idx_bue_time" ON "brand_kit"."brandkit_usage_events" USING "btree" ("created_at");



CREATE INDEX "idx_content_ideas_user_id" ON "public"."content_ideas" USING "btree" ("user_id");



CREATE INDEX "idx_content_ideas_user_used" ON "public"."content_ideas" USING "btree" ("user_id", "used_in_generation");



CREATE INDEX "idx_due_posts" ON "public"."scheduled_insight_card_posts" USING "btree" ("scheduled_at", "status") WHERE ("status" = 'scheduled'::"public"."post_status");



CREATE INDEX "idx_orders_supplier" ON "public"."orders" USING "btree" ("supplier_id");



CREATE INDEX "idx_prebuilt_backgrounds_alt_text" ON "public"."prebuilt_backgrounds" USING "btree" ("alt_text") WHERE ("alt_text" <> ''::"text");



CREATE INDEX "idx_quotations_rfq" ON "public"."quotations" USING "btree" ("rfq_id");



CREATE INDEX "idx_quotations_supplier" ON "public"."quotations" USING "btree" ("supplier_id");



CREATE INDEX "idx_rfqs_buyer" ON "public"."rfqs" USING "btree" ("buyer_id");



CREATE INDEX "idx_scheduled_posts_alt_texts" ON "public"."scheduled_posts" USING "gin" ("alt_texts") WHERE (COALESCE("array_length"("alt_texts", 1), 0) > 0);



CREATE INDEX "idx_supplier_feedback_created" ON "public"."supplier_feedback" USING "btree" ("created_at" DESC);



CREATE INDEX "idx_supplier_feedback_supplier" ON "public"."supplier_feedback" USING "btree" ("supplier_id");



CREATE INDEX "idx_user_subscription_status_user_id" ON "public"."user_subscription_status" USING "btree" ("user_id");



CREATE INDEX "post_analytics_created_at_idx" ON "public"."post_analytics" USING "btree" ("created_at");



CREATE INDEX "post_analytics_user_id_idx" ON "public"."post_analytics" USING "btree" ("user_id");



CREATE INDEX "prebuilt_backgrounds_category_idx" ON "public"."prebuilt_backgrounds" USING "btree" ("category");



CREATE INDEX "prebuilt_backgrounds_prompt_hash_idx" ON "public"."prebuilt_backgrounds" USING "btree" ("prompt_hash");



CREATE INDEX "scheduled_posts_user_id_idx" ON "public"."scheduled_posts" USING "btree" ("user_id");



CREATE UNIQUE INDEX "social_accounts_user_urn_idx" ON "public"."social_accounts" USING "btree" ("user_id", "author_urn");



CREATE UNIQUE INDEX "social_owner_provider_idx" ON "public"."social_accounts" USING "btree" ("user_id", "provider");



CREATE INDEX "subscriptions_user_id_idx" ON "public"."subscriptions" USING "btree" ("user_id");



CREATE INDEX "user_subscription_status_provider_billing_idx" ON "public"."user_subscription_status" USING "btree" ("billing_provider", "billing_id");



CREATE OR REPLACE TRIGGER "tg_brandkits_updated" BEFORE UPDATE ON "brand_kit"."brand_kits" FOR EACH ROW EXECUTE FUNCTION "brand_kit"."refresh_updated_at"();



CREATE OR REPLACE TRIGGER "trg_orders_set_amount" BEFORE INSERT OR UPDATE OF "quantity", "unit_price" ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."orders_set_amount"();



CREATE OR REPLACE TRIGGER "update_user_subscription_status_updated_at" BEFORE UPDATE ON "public"."user_subscription_status" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();



ALTER TABLE ONLY "brand_kit"."brand_kits"
    ADD CONSTRAINT "brand_kits_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "brand_kit"."brandkit_usage_aggregates"
    ADD CONSTRAINT "brandkit_usage_aggregates_brandkit_id_fkey" FOREIGN KEY ("brandkit_id") REFERENCES "brand_kit"."brand_kits"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "brand_kit"."brandkit_usage_events"
    ADD CONSTRAINT "brandkit_usage_events_brandkit_id_fkey" FOREIGN KEY ("brandkit_id") REFERENCES "brand_kit"."brand_kits"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "brand_kit"."brandkit_usage_events"
    ADD CONSTRAINT "brandkit_usage_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "brand_kit"."brandkit_versions"
    ADD CONSTRAINT "brandkit_versions_brandkit_id_fkey" FOREIGN KEY ("brandkit_id") REFERENCES "brand_kit"."brand_kits"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."brand_profiles"
    ADD CONSTRAINT "brand_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."content_ideas"
    ADD CONSTRAINT "content_ideas_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."scheduled_insight_card_posts"
    ADD CONSTRAINT "fk_sub_status" FOREIGN KEY ("user_id") REFERENCES "public"."user_subscription_status"("user_id");



ALTER TABLE ONLY "public"."oauth_nonce"
    ADD CONSTRAINT "oauth_nonce_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."post_analytics"
    ADD CONSTRAINT "post_analytics_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."prebuilt_backgrounds"
    ADD CONSTRAINT "prebuilt_backgrounds_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quotations"
    ADD CONSTRAINT "quotations_rfq_id_fkey" FOREIGN KEY ("rfq_id") REFERENCES "public"."rfqs"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."quotations"
    ADD CONSTRAINT "quotations_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."scheduled_insight_card_posts"
    ADD CONSTRAINT "scheduled_insight_card_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."scheduled_posts"
    ADD CONSTRAINT "scheduled_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."social_accounts"
    ADD CONSTRAINT "social_accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_feedback"
    ADD CONSTRAINT "supplier_feedback_buyer_id_fkey" FOREIGN KEY ("buyer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."supplier_feedback"
    ADD CONSTRAINT "supplier_feedback_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."templates"
    ADD CONSTRAINT "templates_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."user_subscription_status"
    ADD CONSTRAINT "user_subscription_status_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Authenticated can insert backgrounds" ON "brand_kit"."backgrounds" FOR INSERT TO "authenticated" WITH CHECK (("uploaded_by" = "auth"."uid"()));



CREATE POLICY "Authenticated can view backgrounds" ON "brand_kit"."backgrounds" FOR SELECT TO "authenticated" USING (true);



ALTER TABLE "brand_kit"."aspect_ratios" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "brand_kit"."backgrounds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "brand_kit"."brand_kits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "brand_kit"."brandkit_usage_aggregates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "brand_kit"."brandkit_usage_events" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "brand_kit"."brandkit_versions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "compat_all_select" ON "brand_kit"."aspect_ratios" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_all_select" ON "brand_kit"."templates" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_auth_delete" ON "brand_kit"."aspect_ratios" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_delete" ON "brand_kit"."templates" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_insert" ON "brand_kit"."aspect_ratios" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_insert" ON "brand_kit"."templates" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "brand_kit"."aspect_ratios" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "brand_kit"."templates" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "delete_brand_kits" ON "brand_kit"."brand_kits" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "delete_brandkit_aggregates" ON "brand_kit"."brandkit_usage_aggregates" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_usage_aggregates"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "delete_brandkit_events" ON "brand_kit"."brandkit_usage_events" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "delete_brandkit_versions" ON "brand_kit"."brandkit_versions" FOR DELETE USING ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_versions"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "insert_brand_kits" ON "brand_kit"."brand_kits" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "insert_brandkit_aggregates" ON "brand_kit"."brandkit_usage_aggregates" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_usage_aggregates"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "insert_brandkit_events" ON "brand_kit"."brandkit_usage_events" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "insert_brandkit_versions" ON "brand_kit"."brandkit_versions" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_versions"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "select_brand_kits" ON "brand_kit"."brand_kits" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "select_brandkit_aggregates" ON "brand_kit"."brandkit_usage_aggregates" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_usage_aggregates"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "select_brandkit_events" ON "brand_kit"."brandkit_usage_events" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "select_brandkit_versions" ON "brand_kit"."brandkit_versions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_versions"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



ALTER TABLE "brand_kit"."templates" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "update_brand_kits" ON "brand_kit"."brand_kits" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "update_brandkit_aggregates" ON "brand_kit"."brandkit_usage_aggregates" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_usage_aggregates"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_usage_aggregates"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "update_brandkit_events" ON "brand_kit"."brandkit_usage_events" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "update_brandkit_versions" ON "brand_kit"."brandkit_versions" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_versions"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "brand_kit"."brand_kits"
  WHERE (("brand_kits"."id" = "brandkit_versions"."brandkit_id") AND ("brand_kits"."user_id" = "auth"."uid"())))));



CREATE POLICY "Allow SELECT for backend" ON "public"."oauth_nonce" FOR SELECT TO "anon" USING (true);



CREATE POLICY "Allow SELECT for own nonce" ON "public"."oauth_nonce" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Allow delete if user is owner" ON "public"."brand_profiles" FOR DELETE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Allow insert if user is owner" ON "public"."brand_profiles" FOR INSERT WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Allow insert only if no row exists for user" ON "public"."user_subscription_status" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() IS NOT NULL) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."user_subscription_status" "existing"
  WHERE ("existing"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Allow select if user is owner" ON "public"."brand_profiles" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Allow service insert" ON "public"."social_accounts" FOR INSERT TO "service_role" WITH CHECK (true);



CREATE POLICY "Allow service update" ON "public"."social_accounts" FOR UPDATE TO "service_role" USING (true);



CREATE POLICY "Allow update if user is owner" ON "public"."brand_profiles" FOR UPDATE USING (("user_id" = "auth"."uid"()));



CREATE POLICY "Block all deletes" ON "public"."social_accounts" AS RESTRICTIVE FOR DELETE USING (false);



CREATE POLICY "Logged-in users can insert" ON "public"."prebuilt_backgrounds" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "Service can update scheduled_posts" ON "public"."scheduled_posts" FOR UPDATE TO "service_role" USING (true);



CREATE POLICY "Service role can insert/update" ON "public"."prebuilt_backgrounds" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "Unified nonce insertion" ON "public"."oauth_nonce" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") = "user_id") OR (("auth"."jwt"() ->> 'service_role'::"text") = 'edge_function'::"text")));



CREATE POLICY "User can delete own post" ON "public"."scheduled_posts" FOR DELETE USING (("user_id" = "public"."_uid"()));



CREATE POLICY "User can update own post" ON "public"."scheduled_posts" FOR UPDATE USING (("user_id" = "public"."_uid"()));



CREATE POLICY "Users can delete their own insight posts" ON "public"."scheduled_insight_card_posts" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own social accounts" ON "public"."social_accounts" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own templates" ON "public"."templates" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own analytics" ON "public"."post_analytics" FOR INSERT WITH CHECK (("user_id" = "public"."_uid"()));



CREATE POLICY "Users can insert their own insight posts" ON "public"."scheduled_insight_card_posts" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own social accounts" ON "public"."social_accounts" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert their own templates" ON "public"."templates" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read their own & prebuilt templates" ON "public"."templates" FOR SELECT USING ((("auth"."uid"() = "user_id") OR ("user_id" IS NULL)));



CREATE POLICY "Users can read their own insight posts" ON "public"."scheduled_insight_card_posts" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own analytics" ON "public"."post_analytics" FOR UPDATE USING (("user_id" = "public"."_uid"()));



CREATE POLICY "Users can update their own insight posts" ON "public"."scheduled_insight_card_posts" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own social accounts" ON "public"."social_accounts" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own subscription status" ON "public"."user_subscription_status" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own templates" ON "public"."templates" FOR UPDATE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view their own analytics" ON "public"."post_analytics" FOR SELECT USING (("user_id" = "public"."_uid"()));



CREATE POLICY "Users can view their own social accounts" ON "public"."social_accounts" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "auto_merged_select_service_role" ON "public"."oauth_nonce" FOR SELECT TO "service_role" USING ((true OR true OR true OR true));



ALTER TABLE "public"."brand_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "compat_all_select" ON "public"."content_ideas" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_all_select" ON "public"."subscription_features" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_all_select" ON "public"."subscription_templates" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_all_select" ON "public"."subscriptions" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_all_select" ON "public"."users" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_all_select" ON "public"."webhook_events" FOR SELECT TO "authenticated", "anon" USING (true);



CREATE POLICY "compat_auth_delete" ON "public"."content_ideas" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_delete" ON "public"."subscription_features" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_delete" ON "public"."subscription_templates" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_delete" ON "public"."subscriptions" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_delete" ON "public"."users" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_delete" ON "public"."webhook_events" FOR DELETE TO "authenticated" USING (true);



CREATE POLICY "compat_auth_insert" ON "public"."content_ideas" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_insert" ON "public"."subscription_features" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_insert" ON "public"."subscription_templates" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_insert" ON "public"."subscriptions" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_insert" ON "public"."users" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_insert" ON "public"."webhook_events" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "public"."content_ideas" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "public"."subscription_features" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "public"."subscription_templates" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "public"."subscriptions" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "public"."users" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



CREATE POLICY "compat_auth_update" ON "public"."webhook_events" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."content_ideas" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "feedback_buyer_insert" ON "public"."supplier_feedback" FOR INSERT WITH CHECK (("auth"."uid"() = "buyer_id"));



CREATE POLICY "feedback_supplier_read" ON "public"."supplier_feedback" FOR SELECT USING (("auth"."uid"() = "supplier_id"));



ALTER TABLE "public"."oauth_nonce" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_supplier_read" ON "public"."orders" FOR SELECT USING (("auth"."uid"() = "supplier_id"));



CREATE POLICY "orders_supplier_update" ON "public"."orders" FOR UPDATE USING (("auth"."uid"() = "supplier_id")) WITH CHECK (("auth"."uid"() = "supplier_id"));



CREATE POLICY "owner write" ON "public"."prebuilt_backgrounds" USING (("auth"."uid"() = "creator_id")) WITH CHECK (("auth"."uid"() = "creator_id"));



ALTER TABLE "public"."post_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prebuilt_backgrounds" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_all" ON "public"."profiles" FOR SELECT USING (true);



ALTER TABLE "public"."quotations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "quotes_supplier_read" ON "public"."quotations" FOR SELECT USING (("auth"."uid"() = "supplier_id"));



ALTER TABLE "public"."rfqs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rfqs_supplier_read_via_orders" ON "public"."rfqs" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders" "o"
  WHERE (("o"."rfq_id" = "rfqs"."id") AND ("o"."supplier_id" = "auth"."uid"())))));



CREATE POLICY "rfqs_supplier_read_via_quotes" ON "public"."rfqs" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."quotations" "q"
  WHERE (("q"."rfq_id" = "rfqs"."id") AND ("q"."supplier_id" = "auth"."uid"())))));



ALTER TABLE "public"."scheduled_insight_card_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."scheduled_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."social_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscription_features" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscription_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."supplier_feedback" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_subscription_status" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."waitlist_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."webhook_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "z_merged_all_public" ON "public"."social_accounts" USING ((("user_id" = "auth"."uid"()) OR ("user_id" = "public"."_uid"()))) WITH CHECK ((("user_id" = "auth"."uid"()) OR true));



CREATE POLICY "z_merged_ins_public" ON "public"."scheduled_posts" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."user_subscription_status" "us"
  WHERE (("us"."user_id" = "auth"."uid"()) AND ("us"."is_active_subscriber" = true)))) OR ("user_id" = "public"."_uid"())));



CREATE POLICY "z_merged_ins_public" ON "public"."user_subscription_status" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") OR ("user_id" = "auth"."uid"())));



CREATE POLICY "z_merged_ins_public" ON "public"."waitlist_users" FOR INSERT WITH CHECK ((true OR true));



CREATE POLICY "z_merged_sel_public" ON "public"."prebuilt_backgrounds" FOR SELECT USING ((true OR ("visibility" = 'public'::"text")));



CREATE POLICY "z_merged_sel_public" ON "public"."scheduled_posts" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR ("user_id" = "public"."_uid"())));



CREATE POLICY "z_merged_sel_public" ON "public"."user_subscription_status" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR ("auth"."uid"() = "user_id") OR ("user_id" = "auth"."uid"())));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






GRANT USAGE ON SCHEMA "brand_kit" TO "anon";
GRANT USAGE ON SCHEMA "brand_kit" TO "authenticated";






GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




































































































































































































































GRANT ALL ON FUNCTION "public"."_uid"() TO "anon";
GRANT ALL ON FUNCTION "public"."_uid"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_uid"() TO "service_role";



GRANT ALL ON FUNCTION "public"."buyer_analytics"("_buyer_id" "uuid", "months" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."buyer_analytics"("_buyer_id" "uuid", "months" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."buyer_analytics"("_buyer_id" "uuid", "months" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."buyer_analytics_safe"("_buyer_id" "uuid", "months" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."buyer_analytics_safe"("_buyer_id" "uuid", "months" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."buyer_analytics_safe"("_buyer_id" "uuid", "months" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."buyer_orders_for"("_buyer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."buyer_orders_for"("_buyer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buyer_orders_for"("_buyer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."buyer_rfqs_for"("_buyer_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."buyer_rfqs_for"("_buyer_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."buyer_rfqs_for"("_buyer_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."cleanup_oauth_nonce"() TO "anon";
GRANT ALL ON FUNCTION "public"."cleanup_oauth_nonce"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."cleanup_oauth_nonce"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_social_connection_status"("user_uuid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_social_connection_status"("user_uuid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_social_connection_status"("user_uuid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."orders_set_amount"() TO "anon";
GRANT ALL ON FUNCTION "public"."orders_set_amount"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."orders_set_amount"() TO "service_role";



GRANT ALL ON FUNCTION "public"."public_are_valid_alt_texts"("arr" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."public_are_valid_alt_texts"("arr" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."public_are_valid_alt_texts"("arr" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."public_is_valid_alt_text"("t" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."public_is_valid_alt_text"("t" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."public_is_valid_alt_text"("t" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."redeem_meta_nonce"("_nonce" "uuid", "_min_time" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."redeem_meta_nonce"("_nonce" "uuid", "_min_time" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."redeem_meta_nonce"("_nonce" "uuid", "_min_time" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."supplier_category_performance_for"("_supplier_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."supplier_category_performance_for"("_supplier_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."supplier_category_performance_for"("_supplier_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."supplier_monthly_quotes_for"("_supplier_id" "uuid", "_months" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."supplier_monthly_quotes_for"("_supplier_id" "uuid", "_months" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."supplier_monthly_quotes_for"("_supplier_id" "uuid", "_months" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."supplier_orders_for"("_supplier_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."supplier_orders_for"("_supplier_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."supplier_orders_for"("_supplier_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."supplier_performance_summary"("_supplier_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."supplier_performance_summary"("_supplier_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."supplier_performance_summary"("_supplier_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."supplier_recent_feedback_for"("_supplier_id" "uuid", "_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."supplier_recent_feedback_for"("_supplier_id" "uuid", "_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."supplier_recent_feedback_for"("_supplier_id" "uuid", "_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."texts_length_between"("arr" "text"[], "lo" integer, "hi" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."texts_length_between"("arr" "text"[], "lo" integer, "hi" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."texts_length_between"("arr" "text"[], "lo" integer, "hi" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at_column"() TO "service_role";












GRANT SELECT ON TABLE "brand_kit"."aspect_ratios" TO PUBLIC;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."aspect_ratios" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."aspect_ratios" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."backgrounds" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."backgrounds" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brand_kits" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brand_kits" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brandkit_usage_aggregates" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brandkit_usage_aggregates" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brandkit_usage_events" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brandkit_usage_events" TO "authenticated";



GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brandkit_versions" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."brandkit_versions" TO "authenticated";



GRANT SELECT ON TABLE "brand_kit"."templates" TO PUBLIC;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."templates" TO "anon";
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "brand_kit"."templates" TO "authenticated";





















GRANT ALL ON TABLE "public"."brand_profiles" TO "anon";
GRANT ALL ON TABLE "public"."brand_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."brand_profiles" TO "service_role";



GRANT ALL ON TABLE "public"."content_ideas" TO "anon";
GRANT ALL ON TABLE "public"."content_ideas" TO "authenticated";
GRANT ALL ON TABLE "public"."content_ideas" TO "service_role";



GRANT ALL ON TABLE "public"."oauth_nonce" TO "anon";
GRANT ALL ON TABLE "public"."oauth_nonce" TO "authenticated";
GRANT ALL ON TABLE "public"."oauth_nonce" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."post_analytics" TO "anon";
GRANT ALL ON TABLE "public"."post_analytics" TO "authenticated";
GRANT ALL ON TABLE "public"."post_analytics" TO "service_role";



GRANT ALL ON TABLE "public"."prebuilt_backgrounds" TO "anon";
GRANT ALL ON TABLE "public"."prebuilt_backgrounds" TO "authenticated";
GRANT ALL ON TABLE "public"."prebuilt_backgrounds" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."quotations" TO "anon";
GRANT ALL ON TABLE "public"."quotations" TO "authenticated";
GRANT ALL ON TABLE "public"."quotations" TO "service_role";



GRANT ALL ON TABLE "public"."rfqs" TO "anon";
GRANT ALL ON TABLE "public"."rfqs" TO "authenticated";
GRANT ALL ON TABLE "public"."rfqs" TO "service_role";



GRANT ALL ON TABLE "public"."scheduled_insight_card_posts" TO "anon";
GRANT ALL ON TABLE "public"."scheduled_insight_card_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."scheduled_insight_card_posts" TO "service_role";



GRANT ALL ON TABLE "public"."scheduled_posts" TO "anon";
GRANT ALL ON TABLE "public"."scheduled_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."scheduled_posts" TO "service_role";



GRANT ALL ON TABLE "public"."social_accounts" TO "anon";
GRANT ALL ON TABLE "public"."social_accounts" TO "authenticated";
GRANT ALL ON TABLE "public"."social_accounts" TO "service_role";



GRANT ALL ON TABLE "public"."subscription_features" TO "anon";
GRANT ALL ON TABLE "public"."subscription_features" TO "authenticated";
GRANT ALL ON TABLE "public"."subscription_features" TO "service_role";



GRANT ALL ON TABLE "public"."subscription_templates" TO "anon";
GRANT ALL ON TABLE "public"."subscription_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."subscription_templates" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."supplier_feedback" TO "anon";
GRANT ALL ON TABLE "public"."supplier_feedback" TO "authenticated";
GRANT ALL ON TABLE "public"."supplier_feedback" TO "service_role";



GRANT ALL ON TABLE "public"."templates" TO "anon";
GRANT ALL ON TABLE "public"."templates" TO "authenticated";
GRANT ALL ON TABLE "public"."templates" TO "service_role";



GRANT ALL ON TABLE "public"."user_subscription_status" TO "anon";
GRANT ALL ON TABLE "public"."user_subscription_status" TO "authenticated";
GRANT ALL ON TABLE "public"."user_subscription_status" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."waitlist_users" TO "anon";
GRANT ALL ON TABLE "public"."waitlist_users" TO "authenticated";
GRANT ALL ON TABLE "public"."waitlist_users" TO "service_role";



GRANT ALL ON TABLE "public"."webhook_events" TO "anon";
GRANT ALL ON TABLE "public"."webhook_events" TO "authenticated";
GRANT ALL ON TABLE "public"."webhook_events" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "brand_kit" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "brand_kit" GRANT SELECT,INSERT,DELETE,UPDATE ON TABLES  TO "authenticated";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";






























RESET ALL;
