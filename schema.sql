-- Execute todo este arquivo no SQL Editor do projeto Supabase.
create extension if not exists pgcrypto;
create table if not exists public.bookings (
 id uuid primary key default gen_random_uuid(),
 customer_name text not null check(char_length(customer_name) between 2 and 80),
 customer_phone text not null check(char_length(customer_phone) between 10 and 20),
 service text not null check(service in ('Cavanhaque','Gel','Pomada','Barba','Alisamento','Pigmentação','Corte','Corte e Sobrancelha')),
 price numeric(8,2) not null check(price in (15,20,25,30,35)),
 appointment_date date not null, appointment_time time not null,
 status text not null default 'confirmed' check(status in ('confirmed','cancelled')),
 notification_token uuid not null default gen_random_uuid(),
 notifications_sent_at timestamptz, created_at timestamptz not null default now(),
 constraint valid_slot check(extract(isodow from appointment_date) between 1 and 6 and appointment_time>=time '09:00' and appointment_time<time '20:00' and mod(extract(epoch from appointment_time-time '00:00')::integer,1800)=0 and not(appointment_time>=time '12:00' and appointment_time<time '14:00'))
);
create unique index if not exists bookings_one_active_per_slot on public.bookings(appointment_date,appointment_time) where status='confirmed';
alter table public.bookings enable row level security;
revoke all on public.bookings from anon,authenticated;
grant select,update on public.bookings to authenticated;
create table if not exists public.admin_users(user_id uuid primary key references auth.users(id) on delete cascade,created_at timestamptz not null default now());
alter table public.admin_users enable row level security;
revoke all on public.admin_users from anon,authenticated;
grant select on public.admin_users to authenticated;
create policy "admin can read own admin flag" on public.admin_users for select to authenticated using (user_id = auth.uid());
create policy "admin can read bookings" on public.bookings for select to authenticated using(exists(select 1 from public.admin_users a where a.user_id=auth.uid()));
create policy "admin can cancel bookings" on public.bookings for update to authenticated using(exists(select 1 from public.admin_users a where a.user_id=auth.uid())) with check(exists(select 1 from public.admin_users a where a.user_id=auth.uid()));
create or replace function public.create_booking(p_customer_name text,p_customer_phone text,p_service text,p_price numeric,p_date date,p_time time)
returns table(id uuid,status text,notification_token uuid) language plpgsql security definer set search_path=public as $$
declare new_id uuid;
begin
 if p_date<(now() at time zone 'America/Recife')::date then raise exception 'invalid_date'; end if;
 if extract(isodow from p_date) not between 1 and 6 then raise exception 'closed_day'; end if;
 if p_time<time '09:00' or p_time>=time '20:00' or mod(extract(epoch from p_time-time '00:00')::integer,1800)<>0 or (p_time>=time '12:00' and p_time<time '14:00') then raise exception 'invalid_slot'; end if;
 if p_date=(now() at time zone 'America/Recife')::date and p_time<=(now() at time zone 'America/Recife')::time then raise exception 'past_slot'; end if;
 if p_service not in ('Cavanhaque','Gel','Pomada','Barba','Alisamento','Pigmentação','Corte','Corte e Sobrancelha') then raise exception 'invalid_service'; end if;
 if (p_service='Cavanhaque' and p_price<>15) or (p_service in('Gel','Pomada') and p_price<>20) or (p_service in('Barba','Alisamento') and p_price<>25) or (p_service='Pigmentação' and p_price<>30) or (p_service='Corte' and p_price<>30) or (p_service='Corte e Sobrancelha' and p_price<>35) then raise exception 'invalid_price'; end if;
 if char_length(trim(p_customer_name))<2 or char_length(trim(p_customer_name))>80 then raise exception 'invalid_name'; end if;
 if char_length(regexp_replace(p_customer_phone,'\D','','g'))<10 then raise exception 'invalid_phone'; end if;
 insert into public.bookings(customer_name,customer_phone,service,price,appointment_date,appointment_time) values(trim(p_customer_name),regexp_replace(p_customer_phone,'\D','','g'),p_service,p_price,p_date,p_time) returning bookings.id into new_id;
 return query select b.id,b.status,b.notification_token from public.bookings b where b.id=new_id;
exception when unique_violation then raise exception 'slot_taken';
end; $$;
revoke all on function public.create_booking(text,text,text,numeric,date,time) from public;
grant execute on function public.create_booking(text,text,text,numeric,date,time) to anon,authenticated;