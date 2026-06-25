import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'network_tree_screen.dart';

class ImpactScreen extends StatelessWidget {
  const ImpactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: ListView(
            children: [
              const Row(
                children: [
                  BackCircle(),
                  SizedBox(width: 12),
                  Text('Impact & Performance',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 16),
              _heroCard(),
              const SizedBox(height: 14),
              _statsRow(),
              const SizedBox(height: 14),
              _benchmarkCard(),
              const SizedBox(height: 14),
              MedCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NetworkTreeScreen(),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('🌳 Visualiser l’arborescence du réseau',
                        style: TextStyle(fontSize: 13)),
                    Text('→',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: MedColors.accent)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: MedColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: MedColors.green, width: 7),
            ),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('−32%',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: MedColors.green)),
              Text('CO₂ évité ce mois',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              Text('12,4 kg vs trajets en voiture',
                  style: TextStyle(fontSize: 11, color: MedColors.secondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    Widget stat(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: MedColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: MedColors.secondary)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        stat('47', 'trajets'),
        const SizedBox(width: 12),
        stat('18 h', 'en transport'),
        const SizedBox(width: 12),
        stat('96 km', 'parcourus'),
      ],
    );
  }

  Widget _benchmarkCard() {
    // TODO(V3): valeurs réelles depuis benchmarks/ (1 000 requêtes aléatoires).
    Widget bench(String name, String value, double ratio, Color color) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(name, style: const TextStyle(fontSize: 12)),
                Text(value,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: MedColors.surface2,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        );

    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance des algorithmes',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          bench('Dijkstra (tas binaire)', '14 ms', 0.78, MedColors.accent),
          const SizedBox(height: 10),
          bench('A* (heuristique géodésique)', '8 ms', 0.45, MedColors.green),
          const SizedBox(height: 10),
          const Text('Moyenne sur 1 000 requêtes · pic mémoire 6,2 Mo · ~0,4 W',
              style: TextStyle(fontSize: 11, color: MedColors.secondary)),
        ],
      ),
    );
  }
}
