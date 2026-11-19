-- TriCoach – letzte Antwort je Verbindung zwischenspeichern: WebUntis und TrainingPeaks werden je Nutzer
-- höchstens alle 15 Minuten wirklich abgerufen (schonend für die Dienste, siehe functions/feeds).
alter table public.integrations add column if not exists cache jsonb;
alter table public.integrations add column if not exists cached_at timestamptz;
