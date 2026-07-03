import 'package:flutter/material.dart';

import '../core/algorithms/connectivity.dart';
import '../main.dart' show appGraph;
import '../models/itinerary.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NetworkScreen extends StatelessWidget {
  const NetworkScreen({super.key});

  /// Analyse de connexité (BFS, exigence AO) — calculée une seule fois,
  /// à la première ouverture de l'écran, puis mise en cache.
  static Future<ConnectivityReport>? _connectivity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: ListView(
            children: [
              const Text('Réseau intermodal',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Graphe Paris & Île-de-France',
                  style: TextStyle(fontSize: 13, color: MedColors.secondary)),
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
    // Vraie vérification d'intégrité après import (BFS fait main) — le badge
    // n'est plus une affirmation codée en dur.
    _connectivity ??= Future(() => ConnectivityChecker().analyze(appGraph));
    return FutureBuilder<ConnectivityReport>(
      future: _connectivity,
      builder: (context, snap) {
        final Widget icon;
        final String title;
        final String subtitle;
        if (!snap.hasData) {
          icon = const Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: MedColors.accent),
          );
          title = 'Vérification de la connexité…';
          subtitle = 'Parcours BFS sur ${appGraph.nodeCount} nœuds';
        } else {
          final rep = snap.data!;
          final mainSize =
              rep.components.isEmpty ? 0 : rep.components.first.length;
          final pct = appGraph.nodeCount == 0
              ? 100.0
              : mainSize * 100 / appGraph.nodeCount;
          final ok = pct >= 99.0;
          icon = Icon(
              ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: ok ? MedColors.green : MedColors.orange,
              size: 26);
          title = ok ? 'Réseau connexe (BFS)' : 'Réseau fragmenté';
          subtitle = 'Composante principale : ${pct.toStringAsFixed(1)} % '
              'des nœuds · ${rep.components.length} composante'
              '${rep.components.length > 1 ? 's' : ''}';
        }
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
                child: icon,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: MedColors.secondary)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _linesCard() {
    // Lit les lignes directement depuis le graphe IDFM chargé
    final g = appGraph;
    final seen = <String>{};

    // Collecte les infos uniques par lineShortName (tous modes pour les compteurs)
    final lines = <_LineInfo>[];
    for (final node in g.nodes.values) {
      final name = node.lineShortName;
      if (name == null || !seen.add(name)) continue;
      lines.add(_LineInfo(
        label: name,
        color: _colorFromHex(node.lineColor),
        darkText: _isDarkText(node.lineColor),
        mode: _modeFrom(node.routeType),
        routeType: node.routeType ?? 99,
      ));
    }

    // Badges : réseau ferré uniquement (métro/tram/RER). Les ~350 lignes de
    // bus seraient illisibles en badges — on affiche leur nombre.
    final rail = lines.where((l) => l.routeType != 3).toList()
      ..sort((a, b) {
        if (a.routeType != b.routeType) {
          return a.routeType.compareTo(b.routeType);
        }
        return a.label.compareTo(b.label);
      });
    final busCount = lines.where((l) => l.routeType == 3).length;

    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lignes ferrées (${rail.length})',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in rail)
                LineBadge(
                  label: l.label,
                  color: l.color,
                  darkText: l.darkText,
                  mode: l.mode,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${rail.where((l) => l.routeType == 1).length} métro · '
            '${rail.where((l) => l.routeType == 2).length} RER/Transilien · '
            '${rail.where((l) => l.routeType == 0).length} tram · '
            '+ $busCount lignes de bus',
            style: const TextStyle(fontSize: 11, color: MedColors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _statsCard() {
    final g = appGraph;
    final lineCount = g.nodes.values
        .map((n) => n.lineShortName)
        .whereType<String>()
        .toSet()
        .length;
    return MedCard(
      child: Column(
        children: [
          _stat('${g.nodeCount}', 'Nœuds dans le graphe'),
          const Divider(color: MedColors.dividerColor, height: 22),
          _stat('${g.edgeCount}', 'Arêtes intermodales'),
          const Divider(color: MedColors.dividerColor, height: 22),
          _stat('$lineCount', 'Lignes (tous modes)'),
          const Divider(color: MedColors.dividerColor, height: 22),
          // Mesuré par test/core/real_graph_integration_test.dart (benchmark
          // reproductible, seed fixe) — requête complète « Tous » (3 variantes).
          _stat('p95 < 1 s', 'Requête itinéraire (benchmark)'),
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

  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return MedColors.secondary;
    final v = int.tryParse(hex.padLeft(6, '0'), radix: 16);
    return v != null ? Color(0xFF000000 | v) : MedColors.secondary;
  }

  bool _isDarkText(String? hex) {
    if (hex == null) return false;
    final c = int.tryParse(hex.padLeft(6, '0'), radix: 16) ?? 0;
    final lum = 0.299 * ((c >> 16) & 0xFF) +
        0.587 * ((c >> 8) & 0xFF) +
        0.114 * (c & 0xFF);
    return lum > 160;
  }

  TransportMode _modeFrom(int? rt) => switch (rt) {
        0 => TransportMode.tram,
        1 => TransportMode.metro,
        2 => TransportMode.train,
        3 => TransportMode.bus,
        _ => TransportMode.metro,
      };
}

class _LineInfo {
  const _LineInfo({
    required this.label,
    required this.color,
    required this.darkText,
    required this.mode,
    required this.routeType,
  });
  final String label;
  final Color color;
  final bool darkText;
  final TransportMode mode;
  final int routeType;
}
