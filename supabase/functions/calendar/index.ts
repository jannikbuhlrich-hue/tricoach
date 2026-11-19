// TriCoach – Kalender-Abo (.ics) für PC, Outlook, Google Kalender und alle anderen.
// Aufruf: https://<projekt>.supabase.co/functions/v1/calendar?token=<calendar_token aus dem Profil>
// Kalender-Apps können keine Anmeldung schicken – der geheime Token im Link ersetzt sie.
// Neuer Token in der App = alter Link funktioniert nicht mehr.
import { createClient } from 'npm:@supabase/supabase-js@2';
import { buildCalendar } from './ics.js';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = (url.searchParams.get('token') ?? '').replace(/\.ics$/i, '');
  if (!UUID.test(token)) return new Response('Ungültiger Kalender-Link', { status: 404 });

  const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });

  const { data: profile } = await db.from('profiles').select('id, display_name').eq('calendar_token', token).maybeSingle();
  if (!profile) return new Response('Ungültiger Kalender-Link', { status: 404 });

  const now = new Date();
  const from = new Date(now.getTime() - 90 * 86400000).toISOString();
  const to = new Date(now.getTime() + 180 * 86400000).toISOString();

  const [acts, plan] = await Promise.all([
    db.from('activities')
      .select('id, sport, art, name, start_at, duration_s, distance_m, avg_hr, rpe, tss, notes, deleted_at')
      .eq('user_id', profile.id).is('deleted_at', null).gte('start_at', from).lte('start_at', to)
      .order('start_at').limit(2000),
    db.from('planned_sessions')
      .select('id, kind, sport, title, starts_at, minutes, distance_m, all_day, notes, race_prio, deleted_at')
      .eq('athlete_id', profile.id).is('deleted_at', null).gte('starts_at', from).lte('starts_at', to)
      .order('starts_at').limit(2000),
  ]);
  if (acts.error || plan.error) return new Response('Kalender gerade nicht verfügbar', { status: 503 });

  const body = buildCalendar({
    name: 'TriCoach' + (profile.display_name ? ` – ${profile.display_name}` : ''),
    activities: acts.data ?? [],
    planned: plan.data ?? [],
    now,
  });
  return new Response(body, {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'inline; filename="tricoach.ics"',
      'Cache-Control': 'public, max-age=900',
    },
  });
});
