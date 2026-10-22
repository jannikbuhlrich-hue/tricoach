import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/analytics.dart';
import '../core/format.dart';
import '../core/sport.dart';
import 'theme.dart';

/// Form-Kurve: Fitness (CTL), Ermüdung (ATL), Form (TSB) – wie in TrainingPeaks
class LoadChart extends StatelessWidget {
  const LoadChart(this.points, {super.key, this.height = 200});
  final List<LoadPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _LoadPainter(points, c))),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        _legend(c.fit, 'Fitness'),
        _legend(c.fat, 'Ermüdung'),
        _legend(c.form, 'Form'),
      ]),
    ]);
  }

  Widget _legend(Color col, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 3, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

class _LoadPainter extends CustomPainter {
  _LoadPainter(this.p, this.c);
  final List<LoadPoint> p;
  final TriColors c;

  @override
  void paint(Canvas canvas, Size size) {
    if (p.length < 2) return;
    final hi = p.map((x) => math.max(x.ctl, x.atl)).reduce(math.max) * 1.1 + 5;
    final lo = math.min(0.0, p.map((x) => x.tsb).reduce(math.min) * 1.1 - 5);
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => i / (p.length - 1) * size.width;

    final grid = Paint()
      ..color = c.line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), grid);

    // Form als Fläche um die Nulllinie
    final form = Path()..moveTo(0, y(0));
    for (var i = 0; i < p.length; i++) {
      form.lineTo(x(i), y(p[i].tsb));
    }
    form
      ..lineTo(size.width, y(0))
      ..close();
    canvas.drawPath(form, Paint()..color = c.form.withValues(alpha: .18));

    void line(double Function(LoadPoint) f, Color col, double w) {
      final path = Path()..moveTo(0, y(f(p.first)));
      for (var i = 1; i < p.length; i++) {
        path.lineTo(x(i), y(f(p[i])));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeJoin = StrokeJoin.round);
    }

    line((e) => e.tsb, c.form, 1.5);
    line((e) => e.atl, c.fat, 1.5);
    line((e) => e.ctl, c.fit, 2.5);

    // Monatsmarken
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < p.length; i++) {
      if (p[i].date.day != 1) continue;
      canvas.drawLine(Offset(x(i), 0), Offset(x(i), size.height), grid..color = c.line.withValues(alpha: .5));
      tp.text = TextSpan(text: monthNames[p[i].date.month - 1].substring(0, 3), style: TextStyle(color: c.faint, fontSize: 10));
      tp.layout();
      tp.paint(canvas, Offset(x(i) + 3, 2));
    }
  }

  @override
  bool shouldRepaint(_LoadPainter old) => old.p != p || old.c != c;
}

/// Wochenumfang als gestapelte Balken je Sportart (Stunden)
class WeeklyBars extends StatelessWidget {
  const WeeklyBars(this.weeks, {super.key, this.height = 160, this.goalHours});
  final List<({DateTime week, Map<Sport, Totals> bySport, Totals all})> weeks;
  final double height;
  final double? goalHours;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    final maxH = math.max(goalHours ?? 0, weeks.map((w) => w.all.durationS / 3600).fold<double>(1, math.max)) * 1.1;
    return SizedBox(
      height: height,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final w in weeks)
          Expanded(
            child: Tooltip(
              message: 'KW ${isoWeek(w.week)}: ${hm(w.all.durationS)} · ${w.all.count} Einheiten',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: LayoutBuilder(builder: (context, box) {
                      return Stack(alignment: Alignment.bottomCenter, children: [
                        if (goalHours != null && goalHours! > 0)
                          Positioned(bottom: box.maxHeight * goalHours! / maxH, left: 0, right: 0, child: Container(height: 1, color: c.faint)),
                        Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          for (final s in Sport.values.reversed)
                            if ((w.bySport[s]?.durationS ?? 0) > 0)
                              Container(
                                height: box.maxHeight * (w.bySport[s]!.durationS / 3600) / maxH,
                                decoration: BoxDecoration(color: c.sport(s), borderRadius: BorderRadius.circular(2)),
                                margin: const EdgeInsets.only(top: 1),
                              ),
                        ]),
                      ]);
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${isoWeek(w.week)}', style: TextStyle(fontSize: 10, color: c.faint)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Fortschrittsring (Wochenziel)
class Ring extends StatelessWidget {
  const Ring({super.key, required this.value, required this.color, this.size = 64, this.child});
  final double value;
  final Color color;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = TriColors.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(child: CircularProgressIndicator(value: 1, strokeWidth: 7, color: c.surface2)),
        SizedBox.expand(child: CircularProgressIndicator(value: value.clamp(0, 1), strokeWidth: 7, color: color, strokeCap: StrokeCap.round)),
        if (child != null) child!,
      ]),
    );
  }
}
