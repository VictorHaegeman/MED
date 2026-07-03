import 'package:flutter/material.dart';

import '../core/algorithms/shortest_path.dart';
import '../main.dart' show appGraph, tripSavedNotifier;
import '../models/saved_trip.dart';
import '../services/co2_service.dart';
import '../services/trip_storage.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'map_screen.dart';
import 'network_tree_screen.dart';

class ImpactScreen extends StatefulWidget {
  const ImpactScreen({super.key});

  @override
  State<ImpactScreen> createState() => _ImpactScreenState();
}

class _ImpactScreenState extends State<ImpactScreen> {
  // Cache : un Future par valeur de tripSavedNotifier.value
  // → FutureBuilder ne se réexécute que si de nouveaux trajets sont sauvés.
  final _futureCache = <int, Future<List<SavedTrip>>>{};

  Future<List<SavedTrip>> _getFuture(int saveCount) =>
      _futureCache.putIfAbsent(saveCount, () => TripStorage.loadAll());

  // Rafraîchissement manuel : invalide le cache du saveCount courant.
  void _manualRefresh() {
    _futureCache.remove(tripSavedNotifier.value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // ValueListenableBuilder ré-exécute le builder dès que
        // tripSavedNotifier.value change, sans passer par initState/dispose.
        child: ValueListenableBuilder<int>(
          valueListenable: tripSavedNotifier,
          builder: (_, saveCount, __) => FutureBuilder<List<SavedTrip>>(
            future: _getFuture(saveCount),
            builder: (context, snapshot) {
              final trips = snapshot.data ?? [];
              return _buildBody(context, trips);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<SavedTrip> trips) {
    final totalCo2Saved = trips.fold(0.0, (s, t) => s + t.co2SavedKg);
    final totalDistKm = trips.fold(0.0, (s, t) => s + t.distanceKm);
    final totalSecs = trips.fold(0.0, (s, t) => s + t.durationSeconds);
    final totalHours = totalSecs / 3600;
    final tripCount = trips.length;
    final carCo2Kg = totalDistKm * Co2Service.voitureGPerKm / 1000;
    final pct = carCo2Kg > 0 ? (totalCo2Saved / carCo2Kg * 100).round() : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Impact & Performance',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            GestureDetector(
              onTap: _manualRefresh,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                    color: MedColors.surface2, shape: BoxShape.circle),
                child: const Icon(Icons.refresh_rounded,
                    size: 17, color: MedColors.secondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _heroCard(totalCo2Saved, pct, trips.isEmpty),
        const SizedBox(height: 14),
        _statsRow(tripCount, totalHours, totalDistKm),
        const SizedBox(height: 14),
        if (trips.isNotEmpty) ...[
          _funFactCard(totalCo2Saved, tripCount),
          const SizedBox(height: 14),
        ],
        _benchmarkCard(),
        const SizedBox(height: 14),
        if (trips.isNotEmpty) ...[
          _historyCard(trips),
          const SizedBox(height: 14),
        ],
        MedCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NetworkTreeScreen(graph: appGraph),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('🌳 Visualiser l\'arborescence du réseau',
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
    );
  }

  Widget _heroCard(double savedKg, int pct, bool isEmpty) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: MedColors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          _Co2Ring(pct: pct.toDouble()),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEmpty ? '–' : '${savedKg.toStringAsFixed(2)} kg',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: MedColors.green),
                ),
                const Text('CO₂ économisé au total',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  isEmpty
                      ? 'Enregistrez un trajet pour commencer'
                      : '−$pct% vs trajet en voiture',
                  style: const TextStyle(
                      fontSize: 11,
                      color: MedColors.secondary,
                      height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(int trips, double hours, double km) {
    String fmtH(double h) {
      if (h >= 1) {
        final i = h.floor();
        final m = ((h - i) * 60).round();
        return m > 0 ? '$i h $m' : '$i h';
      }
      return '${(h * 60).round()} min';
    }

    String fmtKm(double k) {
      if (k >= 100) return '${k.round()} km';
      return '${k.toStringAsFixed(1)} km';
    }

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
                        fontSize: 16, fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: MedColors.secondary)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        stat('$trips', 'trajets'),
        const SizedBox(width: 10),
        stat(fmtH(hours), 'en transport'),
        const SizedBox(width: 10),
        stat(fmtKm(km), 'parcourus'),
      ],
    );
  }

  Widget _funFactCard(double savedKg, int tripCount) {
    final comparisons = <_Comparison>[
      if (savedKg >= 800)
        _Comparison('✈️', 'vols Paris → New York',
            (savedKg / 1000).toStringAsFixed(2)),
      if (savedKg >= 100)
        _Comparison('✈️', 'vols Paris → Barcelone',
            (savedKg / 400).toStringAsFixed(1)),
      if (savedKg >= 5)
        _Comparison('🌳', 'ans d\'absorption d\'un arbre',
            (savedKg / 25).toStringAsFixed(1)),
      if (savedKg >= 0.5)
        _Comparison('🥩', 'steaks bœuf non produits',
            (savedKg / 3.6).toStringAsFixed(1)),
      if (savedKg >= 0.1)
        _Comparison('🍕', 'pizzas de CO₂ évitées',
            (savedKg / 1.7).toStringAsFixed(1)),
      _Comparison('📺', 'h de streaming évitées',
          (savedKg * 1000 / 36).toStringAsFixed(0)),
    ];
    final top = comparisons.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MedColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MedColors.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡 Ça représente…',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final c in top) ...[
            Row(
              children: [
                Text(c.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.value,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: MedColors.green)),
                      Text(c.label,
                          style: const TextStyle(
                              fontSize: 12, color: MedColors.secondary)),
                    ],
                  ),
                ),
              ],
            ),
            if (c != top.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          const Text(
            'Source : ADEME 2023 · transilien.com/calcul-emissions-co2',
            style: TextStyle(fontSize: 10, color: MedColors.secondary),
          ),
        ],
      ),
    );
  }

  // Benchmark RÉEL Dijkstra vs A* — mesuré sur ce navigateur, une seule fois
  // (mise en cache), sur une paire représentative du graphe chargé.
  static Future<_BenchResult>? _benchFuture;

  static Future<_BenchResult> _runBenchmark() async {
    // Laisse la frame courante se peindre avant le calcul.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final g = appGraph;
    String? idOf(String name) {
      for (final n in g.nodes.values) {
        if (n.routeType == 1 && n.stationName == name) return n.id;
      }
      return null;
    }

    var fromId = idOf('Châtelet');
    var toId = idOf('Nation');
    if (fromId == null || toId == null) {
      // Graphe sans ces stations : première/dernière entrée en repli.
      fromId = g.nodes.keys.first;
      toId = g.nodes.keys.last;
    }
    final d = Dijkstra().run(g, fromId, toId);
    final a = AStar().run(g, fromId, toId);
    return _BenchResult(
      dijkstraMs: d.computeTime.inMicroseconds / 1000,
      dijkstraExplored: d.exploredNodes,
      aStarMs: a.computeTime.inMicroseconds / 1000,
      aStarExplored: a.exploredNodes,
    );
  }

  Widget _benchmarkCard() {
    _benchFuture ??= _runBenchmark();

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
      child: FutureBuilder<_BenchResult>(
        future: _benchFuture,
        builder: (context, snap) {
          final b = snap.data;
          final maxExplored = b == null
              ? 1
              : (b.dijkstraExplored > b.aStarExplored
                  ? b.dijkstraExplored
                  : b.aStarExplored);
          String fmt(double ms) =>
              ms >= 10 ? '${ms.round()} ms' : '${ms.toStringAsFixed(1)} ms';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Performance des algorithmes',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              bench(
                  'Dijkstra (tas binaire)',
                  b == null ? '…' : fmt(b.dijkstraMs),
                  b == null ? 0 : b.dijkstraExplored / maxExplored,
                  MedColors.accent),
              const SizedBox(height: 10),
              bench(
                  'A* (heuristique géodésique)',
                  b == null ? '…' : fmt(b.aStarMs),
                  b == null ? 0 : b.aStarExplored / maxExplored,
                  MedColors.green),
              const SizedBox(height: 10),
              Text(
                b == null
                    ? 'Mesure en cours sur ce navigateur…'
                    : 'Mesuré ici même · Châtelet → Nation · '
                        '${b.dijkstraExplored} vs ${b.aStarExplored} nœuds explorés',
                style:
                    const TextStyle(fontSize: 11, color: MedColors.secondary),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _historyCard(List<SavedTrip> trips) {
    final recent = trips.reversed.take(3).toList();
    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Derniers trajets enregistrés',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Touchez un trajet pour le revoir sur la carte',
              style: TextStyle(fontSize: 11, color: MedColors.secondary)),
          const SizedBox(height: 10),
          for (final t in recent) ...[
            InkWell(
              // Les trajets enregistrés avant l'ajout du tracé n'ont pas de
              // pathNodeIds : pas de carte à montrer pour eux.
              onTap: t.pathNodeIds.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MapScreen(
                            pathNodeIds: t.pathNodeIds,
                            totalSeconds: t.durationSeconds,
                            from: t.from,
                            to: t.to,
                          ),
                        ),
                      ),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.directions_transit_filled_rounded,
                        size: 14, color: MedColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${t.from} → ${t.to}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '−${t.co2SavedKg.toStringAsFixed(2)} kg',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: MedColors.green),
                    ),
                    if (t.pathNodeIds.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded,
                          size: 16, color: MedColors.secondary),
                    ],
                  ],
                ),
              ),
            ),
            if (t != recent.last)
              Divider(
                  color: MedColors.dividerColor,
                  height: 14,
                  thickness: 0.5),
          ],
        ],
      ),
    );
  }
}

class _Co2Ring extends StatelessWidget {
  const _Co2Ring({required this.pct});
  final double pct;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            strokeWidth: 7,
            backgroundColor: MedColors.surface2,
            valueColor:
                const AlwaysStoppedAnimation<Color>(MedColors.green),
          ),
          Text(
            pct > 0 ? '−$pct%' : '0%',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: MedColors.green),
          ),
        ],
      ),
    );
  }
}

class _BenchResult {
  const _BenchResult({
    required this.dijkstraMs,
    required this.dijkstraExplored,
    required this.aStarMs,
    required this.aStarExplored,
  });
  final double dijkstraMs;
  final int dijkstraExplored;
  final double aStarMs;
  final int aStarExplored;
}

class _Comparison {
  const _Comparison(this.emoji, this.label, this.value);
  final String emoji;
  final String label;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is _Comparison && other.label == label;
  @override
  int get hashCode => label.hashCode;
}
