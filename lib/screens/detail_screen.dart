import 'package:flutter/material.dart';

import '../models/itinerary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'impact_screen.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.itinerary});

  final Itinerary itinerary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BackCircle(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Itinéraire recommandé',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(itinerary.summary,
                            style: const TextStyle(
                                fontSize: 12, color: MedColors.green)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: [
                    MedCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final leg in itinerary.legs) _legWidget(leg),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: MedColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(itinerary.perfNote,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: MedColors.accent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Démarrer le trajet',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ImpactScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legWidget(Leg leg) {
    return switch (leg) {
      StationPoint() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: leg.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(leg.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(leg.subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: MedColors.secondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      RideLeg() => Padding(
          padding: const EdgeInsets.only(left: 5, top: 6, bottom: 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  constraints: const BoxConstraints(minHeight: 52),
                  decoration: BoxDecoration(
                    color: leg.lineColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        LineBadge(
                            label: leg.lineLabel,
                            color: leg.lineColor,
                            darkText: leg.darkText,
                            mode: leg.mode),
                        const SizedBox(width: 8),
                        Text(leg.direction,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(leg.subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: MedColors.secondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      WalkLeg() => Padding(
          padding: const EdgeInsets.only(left: 5, top: 6, bottom: 6),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DottedBar(),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Text('🚶', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 8),
                        Text(leg.label,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(leg.subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: MedColors.secondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
    };
  }
}

/// Barre pointillée verticale pour les segments de marche.
class _DottedBar extends StatelessWidget {
  const _DottedBar();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: CustomPaint(
        size: const Size(4, double.infinity),
        painter: _DottedBarPainter(),
      ),
    );
  }
}

class _DottedBarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MedColors.secondary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dash = 6.0, gap = 6.0;
    double y = 0;
    final x = size.width / 2;
    while (y < size.height) {
      final yEnd = (y + dash) > size.height ? size.height : y + dash;
      canvas.drawLine(Offset(x, y), Offset(x, yEnd), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
