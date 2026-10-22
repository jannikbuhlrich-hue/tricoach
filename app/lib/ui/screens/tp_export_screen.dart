import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../data/health_import.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

Future<void> openTpExport(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TpExportScreen()));

/// Alles, was in TrainingPeaks fehlt, auf einmal nachtragen (wie tpBulkSheet() in js/tp.js):
/// PC/iPad/Android → ZIP mit FIT-Dateien, alle zusammen auf den TrainingPeaks-Kalender ziehen.
/// iPhone → zusätzlich direkt an Apple Health; TrainingPeaks holt Health-Workouts der letzten 7 Tage.
class TpExportScreen extends StatefulWidget {
  const TpExportScreen({super.key});

  @override
  State<TpExportScreen> createState() => _TpExportScreenState();
}

class _TpExportScreenState extends State<TpExportScreen> {
  int days = 30;
  final off = <String>{};
  bool busy = false;
  ({String how, List<Activity> list})? handedOver;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), c = TriColors.of(context);
    final miss = app.tpMissing(days), chosen = miss.where((a) => !off.contains(a.id)).toList();
    final ios = HealthImport.supported && Theme.of(context).platform == TargetPlatform.iOS;
    final week = chosen.where((a) => a.start.isAfter(DateTime.now().subtract(const Duration(days: 7)))).length;

    Future<void> run(Future<void> Function() f) async {
      setState(() => busy = true);
      try {
        await f();
      } catch (e) {
        if (context.mounted) showMsg(context, '$e');
      }
      if (mounted) setState(() => busy = false);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('In TrainingPeaks nachtragen')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text(
          miss.isEmpty
              ? 'Alles drin – nichts nachzutragen.'
              : '${miss.length} Einheit${miss.length == 1 ? '' : 'en'} der letzten $days Tage ${miss.length == 1 ? 'ist' : 'sind'} noch nicht in TrainingPeaks. '
                  'Uhr-Einheiten kommen normalerweise automatisch über Garmin Connect.',
          style: TextStyle(color: c.muted),
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 Tage')),
            ButtonSegment(value: 30, label: Text('30 Tage')),
            ButtonSegment(value: 90, label: Text('90 Tage')),
            ButtonSegment(value: 365, label: Text('1 Jahr')),
          ],
          selected: {days},
          onSelectionChanged: (s) => setState(() => days = s.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Garmin Connect ist nicht mit TrainingPeaks verbunden'),
          subtitle: const Text('Dann auch alle Uhr-Einheiten mitnehmen'),
          value: !app.garminTp,
          onChanged: (v) => app.setGarminTp(!v),
        ),
        for (final a in miss)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: !off.contains(a.id),
            onChanged: (v) => setState(() {
              if (v == true) {
                off.remove(a.id);
              } else {
                off.add(a.id);
              }
            }),
            title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${shortDate(a.start.toLocal())} · ${hm(a.durationS)}${a.distanceM > 0 ? ' · ${distTxt(a.sport, a.distanceM)}' : ''}${a.isManual ? '' : ' · Uhr'}'),
          ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 12),
          TriCard(
            title: 'Alle auf einmal als FIT-Dateien',
            icon: Icons.folder_zip_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('1. ZIP speichern (${chosen.length} FIT-Datei${chosen.length == 1 ? '' : 'en'}) und entpacken.\n'
                  '2. app.trainingpeaks.com → Kalender: alle .fit-Dateien markieren und zusammen auf den Kalender ziehen. '
                  'Jede landet am richtigen Tag und wird mit der geplanten Einheit verbunden; schon vorhandene überspringt TrainingPeaks.'),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final list = List<Activity>.of(chosen);
                          final bytes = app.tpZip(list);
                          final path = await FilePicker.platform.saveFile(
                            dialogTitle: 'ZIP für TrainingPeaks speichern',
                            fileName: 'TriCoach-fuer-TrainingPeaks_${DateTime.now().toIso8601String().substring(0, 10)}.zip',
                            bytes: bytes,
                          );
                          // Im Browser gibt saveFile keinen Pfad zurück, lädt aber herunter
                          if (path != null || kIsWeb) setState(() => handedOver = (how: 'fit', list: list));
                          if (context.mounted) showMsg(context, '${list.length} FIT-Dateien gepackt – jetzt in TrainingPeaks auf den Kalender ziehen');
                        }),
                icon: const Icon(Icons.download_rounded),
                label: Text(busy ? 'Packe …' : 'ZIP speichern'),
              ),
            ]),
          ),
          if (ios) ...[
            const SizedBox(height: 12),
            TriCard(
              title: 'Am iPhone über Apple Health',
              icon: Icons.favorite_rounded,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('TrainingPeaks übernimmt Health-Workouts nur aus den letzten 7 Tagen – hier $week ausgewählt.', style: TextStyle(color: c.muted)),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: busy || week == 0
                      ? null
                      : () => run(() async {
                            final n = await app.tpToHealth(chosen);
                            if (context.mounted) showMsg(context, '$n Einheit${n == 1 ? '' : 'en'} in Apple Health eingetragen – TrainingPeaks-App einmal öffnen');
                          }),
                  icon: const Icon(Icons.favorite_border_rounded),
                  label: Text('Alle $week an Apple Health'),
                ),
              ]),
            ),
          ],
        ],
        if (handedOver != null) ...[
          const SizedBox(height: 12),
          TriCard(
            title: '${handedOver!.list.length} Einheiten übergeben',
            icon: Icons.check_circle_rounded,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Sind sie in TrainingPeaks angekommen? Dann hier abhaken – TriCoach merkt sich das auf allen Geräten.', style: TextStyle(color: c.muted)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  final h = handedOver!;
                  await app.markTp(h.list, h.how);
                  if (!context.mounted) return;
                  setState(() => handedOver = null);
                  showMsg(context, '${h.list.length} Einheiten als „in TrainingPeaks“ markiert');
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Alle als „in TrainingPeaks“ markieren'),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}
