-- TriCoach – Datenmodell (Supabase / Postgres)
-- Ein Account, alle Geräte: Die App hält eine lokale Kopie und gleicht über diese Tabellen ab.
-- IDs erzeugt das Gerät (auch offline); eindeutig je Nutzer. Uhr-Einheiten bekommen eine feste ID
-- aus Quelle + Quell-ID, damit iPhone und iPad dieselbe Einheit nicht doppelt anlegen.
-- Abgleich-Regel: "letzte Änderung gewinnt" (updated_at kommt vom Gerät), gelöschte Zeilen bleiben
-- als deleted_at-Markierung stehen, damit andere Geräte die Löschung mitbekommen.
-- synced_at setzt der Server – danach fragen die Geräte "was ist seit meinem letzten Abgleich neu?".

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Profile
-- ---------------------------------------------------------------------------
create table public.profiles (
  id             uuid primary key references auth.users (id) on delete cascade,
  display_name   text,
  role           text not null default 'athlete' check (role in ('athlete', 'coach')),
  -- Leistungswerte für die Analysen (Gewicht, FTP, Schwellenpuls, Ruhepuls, Schwellenpace, CSS …)
  settings       jsonb not null default '{}'::jsonb,
  -- Geheimer Schlüssel für den Kalender-Abo-Link (.ics). Neu erzeugen = alter Link ist ungültig.
  calendar_token uuid not null default gen_random_uuid() unique,
  -- Einwilligung zur Verarbeitung von Gesundheitsdaten (DSGVO Art. 9)
  health_consent_at timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- Profil automatisch anlegen, sobald sich jemand registriert
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Einheiten (absolviert) – eigene Einträge, Uhr (Apple Health / Health Connect), intervals.icu, FIT, Import
-- ---------------------------------------------------------------------------
create table public.activities (
  id          text not null,                          -- vom Gerät erzeugt (funktioniert offline), eindeutig je Nutzer
  user_id     uuid not null references auth.users (id) on delete cascade,
  sport       text not null check (sport in ('swim', 'bike', 'run', 'strength', 'other')),
  art         text,                                   -- bei "Sonstiges", z. B. Kitesurfen
  name        text not null default '',
  start_at    timestamptz not null,
  duration_s  integer not null check (duration_s >= 0),
  distance_m  double precision not null default 0 check (distance_m >= 0),
  rpe         smallint check (rpe between 1 and 10),
  avg_hr      smallint check (avg_hr between 20 and 260),
  max_hr      smallint check (max_hr between 20 and 260),
  kcal        integer,
  tss         double precision,
  notes       text not null default '',
  swim_where  text check (swim_where in ('25', '50', 'ow')),
  exercises   jsonb,                                  -- Athletik: [{n, s, r, w}]
  source      text not null default 'manual' check (source in ('manual', 'health', 'icu', 'fit', 'import')),
  ext_id      text,                                   -- ID in der Quelle (z. B. HealthKit-UUID)
  details     jsonb,                                  -- Zusatzdaten (Rad-Leistung, Laufdynamik …)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default now(),
  primary key (user_id, id)
);
create index activities_user_start on public.activities (user_id, start_at desc);
create index activities_user_synced on public.activities (user_id, synced_at);
create unique index activities_user_source_ext on public.activities (user_id, source, ext_id) where ext_id is not null;

-- ---------------------------------------------------------------------------
-- Geplante Einheiten und Termine (vom Athleten selbst oder vom Coach)
-- ---------------------------------------------------------------------------
create table public.planned_sessions (
  id          text not null,
  athlete_id  uuid not null references auth.users (id) on delete cascade,
  created_by  uuid not null references auth.users (id) on delete cascade,
  kind        text not null default 'workout' check (kind in ('workout', 'event', 'race')),
  sport       text check (sport in ('swim', 'bike', 'run', 'strength', 'other')),
  title       text not null default '',
  starts_at   timestamptz not null,
  minutes     integer check (minutes >= 0),
  distance_m  double precision,
  all_day     boolean not null default false,
  notes       text not null default '',
  race_prio   text check (race_prio in ('A', 'B', 'C')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  synced_at   timestamptz not null default now(),
  primary key (athlete_id, id)
);
create index planned_athlete_start on public.planned_sessions (athlete_id, starts_at);
create index planned_athlete_synced on public.planned_sessions (athlete_id, synced_at);

-- ---------------------------------------------------------------------------
-- Coach ↔ Athlet
-- ---------------------------------------------------------------------------
create table public.coach_links (
  coach_id    uuid not null references auth.users (id) on delete cascade,
  athlete_id  uuid not null references auth.users (id) on delete cascade,
  status      text not null default 'active' check (status in ('active', 'ended')),
  created_at  timestamptz not null default now(),
  primary key (coach_id, athlete_id),
  check (coach_id <> athlete_id)
);

create table public.coach_invites (
  code        text primary key default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  coach_id    uuid not null references auth.users (id) on delete cascade,
  expires_at  timestamptz not null default now() + interval '14 days',
  used_by     uuid references auth.users (id),
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);

create or replace function public.is_coach_of(athlete uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.coach_links
    where coach_id = auth.uid() and athlete_id = athlete and status = 'active'
  );
$$;

-- Athlet löst einen Einladungscode seines Coaches ein
create or replace function public.accept_coach_invite(invite_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  inv public.coach_invites;
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet'; end if;
  select * into inv from public.coach_invites where code = upper(trim(invite_code)) for update;
  if inv is null then raise exception 'Code nicht gefunden'; end if;
  if inv.used_by is not null then raise exception 'Code wurde schon benutzt'; end if;
  if inv.expires_at < now() then raise exception 'Code ist abgelaufen'; end if;
  if inv.coach_id = auth.uid() then raise exception 'Eigenen Code kann man nicht einlösen'; end if;
  update public.coach_invites set used_by = auth.uid(), used_at = now() where code = inv.code;
  insert into public.coach_links (coach_id, athlete_id) values (inv.coach_id, auth.uid())
    on conflict (coach_id, athlete_id) do update set status = 'active';
  return inv.coach_id;
end $$;

-- Neuer Kalender-Link: alter Link funktioniert danach nicht mehr
create or replace function public.rotate_calendar_token()
returns uuid language sql security invoker set search_path = public as $$
  update public.profiles set calendar_token = gen_random_uuid() where id = auth.uid() returning calendar_token;
$$;

-- Account mit allen Daten löschen (DSGVO: Recht auf Löschung). Einheiten, Pläne, Profil,
-- Coach-Verbindungen und Einladungen hängen per "on delete cascade" am Nutzer.
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Nicht angemeldet'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Zeitstempel: updated_at kommt vom Gerät ("letzte Änderung gewinnt"), synced_at vom Server
-- ---------------------------------------------------------------------------
create or replace function public.sync_stamp()
returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;  -- ältere Version vom Gerät: still ignorieren, die neuere bleibt
  end if;
  new.synced_at := clock_timestamp();
  return new;
end $$;

create trigger activities_stamp before insert or update on public.activities
  for each row execute function public.sync_stamp();
create trigger planned_stamp before insert or update on public.planned_sessions
  for each row execute function public.sync_stamp();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Zugriffsregeln (Row Level Security): jeder sieht nur seine Daten, Coaches die ihrer Athleten
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.activities enable row level security;
alter table public.planned_sessions enable row level security;
alter table public.coach_links enable row level security;
alter table public.coach_invites enable row level security;

create policy "Profil: selbst" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());
create policy "Profil: Coach liest Athleten" on public.profiles
  for select using (public.is_coach_of(id));
create policy "Profil: Athlet liest Coach" on public.profiles
  for select using (exists (select 1 from public.coach_links l
                            where l.coach_id = profiles.id and l.athlete_id = auth.uid() and l.status = 'active'));

create policy "Einheiten: selbst" on public.activities
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Einheiten: Coach liest" on public.activities
  for select using (public.is_coach_of(user_id));

create policy "Plan: Athlet" on public.planned_sessions
  for all using (athlete_id = auth.uid()) with check (athlete_id = auth.uid());
create policy "Plan: Coach liest" on public.planned_sessions
  for select using (public.is_coach_of(athlete_id));
create policy "Plan: Coach legt an" on public.planned_sessions
  for insert with check (public.is_coach_of(athlete_id) and created_by = auth.uid());
create policy "Plan: Coach ändert eigene" on public.planned_sessions
  for update using (public.is_coach_of(athlete_id) and created_by = auth.uid())
  with check (public.is_coach_of(athlete_id) and created_by = auth.uid());

create policy "Coach-Verbindung: Beteiligte lesen" on public.coach_links
  for select using (coach_id = auth.uid() or athlete_id = auth.uid());
create policy "Coach-Verbindung: Beteiligte beenden" on public.coach_links
  for update using (coach_id = auth.uid() or athlete_id = auth.uid())
  with check (coach_id = auth.uid() or athlete_id = auth.uid());

create policy "Einladung: Coach verwaltet" on public.coach_invites
  for all using (coach_id = auth.uid()) with check (coach_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Echtzeit: Änderungen sofort an alle angemeldeten Geräte schicken
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.activities, public.planned_sessions;
