'use strict';
/* TriCoach – Live-Herzfrequenz per Bluetooth (Standard-Heart-Rate-Service 0x180D).
   Forerunner 265: Einstellungen → Sensoren & Zubehör → Handgelenk-HF → „HF übertragen“
   (oder während einer Aktivität im Menü „HF übertragen“). */

const BLE = (() => {
  const st = { supported: !!navigator.bluetooth, device: null, hr: null, connected: false, rec: false, recStart: 0, points: [], hist: [], sport: 'run', err: '' };

  function parse(dv) {
    const flags = dv.getUint8(0);
    return flags & 1 ? dv.getUint16(1, true) : dv.getUint8(1);
  }

  async function connect() {
    st.err = '';
    try {
      const device = await navigator.bluetooth.requestDevice({ filters: [{ services: ['heart_rate'] }] });
      st.device = device;
      device.addEventListener('gattserverdisconnected', () => { st.connected = false; render(); });
      const server = await device.gatt.connect();
      const svc = await server.getPrimaryService('heart_rate');
      const ch = await svc.getCharacteristic('heart_rate_measurement');
      ch.addEventListener('characteristicvaluechanged', e => {
        st.hr = parse(e.target.value);
        const now = Date.now();
        st.hist.push({ t: now, hr: st.hr }); if (st.hist.length > 900) st.hist.shift();
        if (st.rec) st.points.push({ t: (now - st.recStart) / 1000, hr: st.hr });
        if (S.view === 'live') renderLiveHr();
      });
      await ch.startNotifications();
      st.connected = true;
    } catch (e) {
      if (e.name !== 'NotFoundError') st.err = e.message;
    }
    render();
  }

  function disconnect() { try { st.device?.gatt?.disconnect(); } catch (e) { } st.connected = false; render(); }
  function start() { st.rec = true; st.recStart = Date.now(); st.points = []; render(); }

  async function stop(save) {
    st.rec = false;
    if (save && st.points.length > 30) {
      const bins = new Map();
      st.points.forEach(p => { const k = Math.floor(p.t / DT), o = bins.get(k) || bins.set(k, []).get(k); o.push(p.hr); });
      const samples = [...bins.entries()].sort((a, b) => a[0] - b[0]).map(([k, v]) => ({ t: (k + 1) * DT, hr: mean(v) }));
      const durS = st.points[st.points.length - 1].t;
      const a = finalize({ id: 'live-' + st.recStart, source: 'live', sport: st.sport, name: `Live-Einheit (${NAME[st.sport]})`, start: new Date(st.recStart), dur: durS, dist: 0, samples, laps: [] });
      await DB.put('acts', [a]);
      if (SET.source !== 'demo') { ACTS.push(a); recompute(); }
      toast(SET.source === 'demo' ? 'Gespeichert. Sichtbar, sobald du Demo-Daten ausschaltest.' : 'Einheit gespeichert');
    }
    st.points = []; render();
  }
  return { st, connect, disconnect, start, stop };
})();
