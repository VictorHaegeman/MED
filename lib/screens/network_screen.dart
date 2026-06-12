import 'package:flutter/material.dart';

import '../models/itinerary.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: ListView(
            children: [
              const Text('Réseau intermodal',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Graphe Paris & Île-de-France',
                  style:
                      TextStyle(fontSize: 13, color: MedColors.secondary)),
              const SizedBox(height: 20),
              _statusCard(),
              const SizedBox(height: 14),
              _linesCard(),
              const SizedBox(height: 14),
              _statsCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCard() {
    return MedCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MedColors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: MedColors.green, size: 26),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Réseau connexe',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              Text('Toutes les stations sont atteignables',
                  style: TextStyle(
                      fontSize: 12, color: MedColors.secondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linesCard() {
    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lignes actives',
              style:
                  TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              LineBadge(label: '1', color: MedColors.m1, darkText: true),
              LineBadge(label: '4', color: MedColors.m4),
              LineBadge(label: '12', color: MedColors.m12),
              LineBadge(label: '13', color: MedColors.m13, darkText: true),
              LineBadge(label: '14', color: MedColors.m14),
              LineBadge(
                  label: 'T3a',
                  color: MedColors.orange,
                  darkText: true,
                  mode: TransportMode.tram),
              LineBadge(
                  label: '87',
                  color: MedColors.busGrey,
                  mode: TransportMode.bus),
              LineBadge(
                  label: '39',
                  color: MedColors.busGrey,
                  mode: TransportMode.bus),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsCard() {
    return MedCard(
      child: Column(
        children: [
          _stat('1 842', 'Nœuds dans le graphe'),
          const Divider(color: MedColors.dividerColor, height: 22),
          _stat('4 812', 'Arêtes intermodales'),
          const Divider(color: MedColors.dividerColor, height: 22),
          _stat('< 15 ms', 'Temps de calcul moyen (A*)'),
          const Divider(color: MedColors.dividerColor, height: 22),
          _stat('6,2 Mo', 'Pic mémoire du graphe'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: MedColors.secondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
