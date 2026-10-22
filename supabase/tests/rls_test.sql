-- Prüft Zugriffsregeln, Abgleich-Regel und Coach-Einladung. Bricht bei jedem Fehler ab.
\set ON_ERROR_STOP on
insert into auth.users values
 ('00000000-0000-0000-0000-00000000000a','athlet@test.de','{"full_name":"Jannik"}'),
 ('00000000-0000-0000-0000-00000000000c','coach@test.de','{}'),
 ('00000000-0000-0000-0000-00000000000f','fremd@test.de','{}');
select count(*) = 3 as profile_angelegt from public.profiles \gset
\if :profile_angelegt \else \echo 'FEHLER Profile' \quit \endif

set role authenticated;
-- Athlet trägt eine Einheit ein
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
insert into activities (id,user_id,sport,name,start_at,duration_s,distance_m,updated_at)
values ('a1','00000000-0000-0000-0000-00000000000a','swim','Schwimmen','2026-10-20 17:00+02',3600,2000,'2026-10-20 18:00+02');
-- Ältere Version vom anderen Gerät darf die neuere nicht überschreiben
insert into activities (id,user_id,sport,name,start_at,duration_s,distance_m,updated_at)
values ('a1','00000000-0000-0000-0000-00000000000a','swim','ALT','2026-10-20 17:00+02',3600,1500,'2026-10-20 17:30+02')
on conflict (user_id, id) do update set name=excluded.name, distance_m=excluded.distance_m, updated_at=excluded.updated_at;
select (select name from activities where id='a1') = 'Schwimmen' as lww_ok \gset
\if :lww_ok \echo 'OK  letzte Änderung gewinnt' \else \echo 'FEHLER LWW' \quit \endif
-- Neuere Version gewinnt
insert into activities (id,user_id,sport,name,start_at,duration_s,distance_m,updated_at)
values ('a1','00000000-0000-0000-0000-00000000000a','swim','Neu','2026-10-20 17:00+02',3600,2100,'2026-10-20 19:00+02')
on conflict (user_id, id) do update set name=excluded.name, distance_m=excluded.distance_m, updated_at=excluded.updated_at;
select (select distance_m from activities where id='a1') = 2100 as newer_ok \gset
\if :newer_ok \echo 'OK  neuere Version übernommen' \else \echo 'FEHLER neuere Version' \quit \endif

-- Fremder sieht nichts und darf nichts für andere eintragen
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
select count(*) = 0 as fremd_ok from activities \gset
\if :fremd_ok \echo 'OK  Fremde sehen keine Einheiten' \else \echo 'FEHLER Fremde sehen Daten' \quit \endif
do $$ begin
  insert into activities (id,user_id,sport,start_at,duration_s) values ('x','00000000-0000-0000-0000-00000000000a','run',now(),60);
  raise exception 'FEHLER: fremder Insert erlaubt';
exception when insufficient_privilege then raise notice 'OK  fremder Insert blockiert'; end $$;

-- Coach ohne Verbindung sieht nichts
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select count(*) = 0 as coach_vorher from activities \gset
\if :coach_vorher \echo 'OK  Coach ohne Einladung sieht nichts' \else \echo 'FEHLER Coach sieht zu früh' \quit \endif
insert into coach_invites (coach_id) values ('00000000-0000-0000-0000-00000000000c');
select code as invite from coach_invites limit 1 \gset

-- Athlet löst Code ein
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select accept_coach_invite(:'invite') is not null as accepted \gset
\if :accepted \echo 'OK  Einladung angenommen' \else \echo 'FEHLER Einladung' \quit \endif
do $$ begin perform accept_coach_invite((select code from coach_invites limit 1)); raise exception 'FEHLER: Code zweimal nutzbar';
exception when raise_exception then if sqlerrm like 'FEHLER%' then raise; end if; raise notice 'OK  Code nur einmal nutzbar'; end $$;

-- Coach sieht jetzt Einheiten, plant eine Einheit, kann aber keine Einheiten ändern
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select count(*) = 1 as coach_sieht from activities \gset
\if :coach_sieht \echo 'OK  Coach sieht Einheiten des Athleten' \else \echo 'FEHLER Coach sieht nichts' \quit \endif
insert into planned_sessions (id,athlete_id,created_by,sport,title,starts_at,minutes)
values ('p1','00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000c','run','Schwelle 5x1 km','2026-10-24 17:00+02',60);
update activities set name='hack' where id='a1';
select (select name from activities where id='a1') = 'Neu' as coach_readonly \gset
\if :coach_readonly \echo 'OK  Coach kann Einheiten nur lesen' \else \echo 'FEHLER Coach ändert Einheit' \quit \endif

-- Athlet sieht den Plan seines Coaches
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select count(*) = 1 as plan_da from planned_sessions \gset
\if :plan_da \echo 'OK  Athlet sieht Plan des Coaches' \else \echo 'FEHLER Plan fehlt' \quit \endif

-- Fremder kann keinen Plan für den Athleten anlegen
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
do $$ begin
  insert into planned_sessions (id,athlete_id,created_by,title,starts_at) values ('p2','00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000f','x',now());
  raise exception 'FEHLER: fremder Plan erlaubt';
exception when insufficient_privilege then raise notice 'OK  fremder Plan blockiert'; end $$;
-- Kalender-Link erneuern
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select calendar_token as alt from profiles where id = auth.uid() \gset
select rotate_calendar_token() <> :'alt'::uuid as rotiert \gset
\if :rotiert \echo 'OK  Kalender-Link erneuert' \else \echo 'FEHLER Kalender-Link' \quit \endif
-- Fremder löscht seinen Account: seine Daten weg, Daten der anderen bleiben
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000f';
insert into activities (id,user_id,sport,start_at,duration_s) values ('f1','00000000-0000-0000-0000-00000000000f','run',now(),600);
select delete_my_account();
reset role;
select (select count(*) from auth.users where id='00000000-0000-0000-0000-00000000000f') = 0
   and (select count(*) from activities where user_id='00000000-0000-0000-0000-00000000000f') = 0
   and (select count(*) from activities where user_id='00000000-0000-0000-0000-00000000000a') = 1 as geloescht \gset
\if :geloescht \echo 'OK  Account-Löschung entfernt nur eigene Daten' \else \echo 'FEHLER Account-Löschung' \quit \endif
-- Zugangsdaten (WebUntis-Schlüssel, iCal-Link) sind für die App weder les- noch schreibbar – nur für die Server-Funktion
insert into integrations (user_id, kind, config, label) values ('00000000-0000-0000-0000-00000000000a', 'webuntis', '{"key":"geheim"}', 'Schule');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
do $$ begin
  perform * from integrations;
  raise exception 'FEHLER: Zugangsdaten lesbar';
exception when insufficient_privilege then raise notice 'OK  Zugangsdaten für die App nicht lesbar'; end $$;
do $$ begin
  insert into integrations (user_id, kind, config) values ('00000000-0000-0000-0000-00000000000a', 'trainingpeaks', '{}');
  raise exception 'FEHLER: Zugangsdaten schreibbar';
exception when insufficient_privilege then raise notice 'OK  Zugangsdaten für die App nicht schreibbar'; end $$;
reset role;
\echo 'ALLE DATENBANK-TESTS BESTANDEN'
