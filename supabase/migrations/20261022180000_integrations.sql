-- TriCoach – Verbindungen zu WebUntis und TrainingPeaks (eine Zeile je Nutzer und Dienst).
-- Enthält Zugangsdaten (WebUntis-App-Schlüssel, privater iCal-Link). Darum: Zugriffsregeln an, aber KEINE Policies –
-- die App kann die Tabelle weder lesen noch schreiben. Nur die Server-Funktion „feeds“ (Service-Rolle) greift zu.
-- Wird ein Account gelöscht, verschwinden die Zeilen mit (on delete cascade).

create table if not exists public.integrations (
  user_id     uuid not null references auth.users (id) on delete cascade,
  kind        text not null check (kind in ('webuntis', 'trainingpeaks')),
  config      jsonb not null,
  label       text not null default '',
  updated_at  timestamptz not null default now(),
  primary key (user_id, kind)
);

alter table public.integrations enable row level security;
revoke all on table public.integrations from anon, authenticated;
