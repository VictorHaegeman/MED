// Tests d'intégration + mesures de performance sur le graphe IDFM RÉEL
// (~43 000 nœuds, ~500 000 arêtes).
//
// Exigence AO : mesures de temps de calcul sur requêtes réelles, benchmark
// du routeur, optimalité vérifiée contre Dijkstra (la référence).
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:med/core/algorithms/shortest_path.dart';
import 'package:med/core/graph.dart';
import 'package:med/core/router_service.dart';
import 'package:med/models/itinerary.dart';
import 'package:med/models/search_result.dart';

void main() {
  late TransportGraph g;
  late RouterService router;

  setUpAll(() {
    final json =
        File('assets/graph/idfm_graph.json').readAsStringSync();
    g = TransportGraph.fromJsonString(json);
    router = RouterService(graph: g);
  });

  test('invariant données : plus aucune arête au-dessus de la vitesse max',
      () {
    // Le plancher appliqué au chargement garantit l'admissibilité de
    // l'heuristique A* : w ≥ distance / maxSpeedMs pour TOUTE arête.
    int checked = 0;
    for (final id in g.nodes.keys) {
      for (final e in g.neighbors(id)) {
        final a = g.nodes[e.from]!;
        final b = g.nodes[e.to]!;
        final dLat = (b.lat - a.lat) * pi / 180;
        final dLon = (b.lon - a.lon) * pi / 180;
        final h = sin(dLat / 2) * sin(dLat / 2) +
            cos(a.lat * pi / 180) * cos(b.lat * pi / 180) *
                sin(dLon / 2) * sin(dLon / 2);
        final distM = 6371000.0 * 2 * atan2(sqrt(h), sqrt(1 - h));
        expect(e.weightSeconds * TransportGraph.maxSpeedMs,
            greaterThanOrEqualTo(distM - 1e-6),
            reason: 'arête ${e.from} → ${e.to} trop rapide');
        checked++;
      }
    }
    // ~478 000 arêtes après élagage (transferts > 6 min et téléportations).
    expect(checked, greaterThan(400000));
  });

  test('optimalité sur graphe réel : TransitRouter = Dijkstra (même paire)',
      () {
    // Une paire de quais métro concrète, sans attentes ni marche : le
    // multi-source doit retrouver EXACTEMENT l'optimum de Dijkstra.
    final chatelet = g.nodes.values.firstWhere(
        (n) => n.stationName == 'Châtelet' && n.routeType == 1);
    final nation = g.nodes.values.firstWhere(
        (n) => n.stationName == 'Nation' && n.routeType == 1);

    final d = Dijkstra().run(g, chatelet.id, nation.id);
    final r = TransitRouter().route(g,
        sources: {chatelet.id: 0},
        targets: {nation.id: 0},
        boardingWaits: false);

    expect(r.found, isTrue);
    expect(d.found, isTrue);
    expect(r.totalSeconds, closeTo(d.totalSeconds, 1e-6));
  });

  test('Châtelet → Nation : durées plausibles, réponse rapide', () async {
    final sw = Stopwatch()..start();
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'));
    sw.stop();

    expect(list, isNotEmpty);
    // ~10-15 min de métro + attente : borne large 8 à 45 min.
    expect(list.first.totalSeconds,
        inInclusiveRange(8 * 60, 45 * 60));
    // Trié par durée croissante (« le plus court d'abord »).
    for (int i = 1; i < list.length; i++) {
      expect(list[i].totalSeconds,
          greaterThanOrEqualTo(list[i - 1].totalSeconds));
    }
    // Réactivité : requête complète (3 variantes) bien sous la seconde.
    expect(sw.elapsedMilliseconds, lessThan(1000));
    // ignore: avoid_print
    print('Châtelet → Nation : ${list.length} itinéraires en '
        '${sw.elapsedMilliseconds} ms — meilleur : '
        '${(list.first.totalSeconds / 60).round()} min (${list.first.tag})');
  });

  test('« Mairie » (1 118 nœuds homonymes) : résolu en un seul pôle, rapide',
      () async {
    final sw = Stopwatch()..start();
    final list = await router.findItineraries(
        const SearchResult.station('Mairie'),
        const SearchResult.station('Châtelet'));
    sw.stop();

    // Avant : des milliers de runs A* (paires) + choix d'une « Mairie »
    // aberrante à l'autre bout de l'Île-de-France. Désormais : un pôle
    // physique unique, une requête, un temps de trajet cohérent (> 5 min).
    expect(list, isNotEmpty);
    expect(list.first.totalSeconds, greaterThan(5 * 60));
    expect(sw.elapsedMilliseconds, lessThan(2000));
    // ignore: avoid_print
    print('Mairie → Châtelet : ${sw.elapsedMilliseconds} ms — '
        '${(list.first.totalSeconds / 60).round()} min');
  });

  test('filtre BUS : uniquement des trajets bus (ou repli combiné explicite)',
      () async {
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'),
        modeFilter: TransportMode.bus);

    expect(list, isNotEmpty);
    for (final it in list) {
      if (it.tag.startsWith('COMBINÉ') || it.tag == 'À PIED') continue;
      for (final ride in it.legs.whereType<RideLeg>()) {
        expect(ride.mode, TransportMode.bus,
            reason: 'itinéraire « ${it.tag} » contient un mode non-bus');
      }
    }
  });

  test('filtre MÉTRO : uniquement métro/RER (ou repli combiné explicite)',
      () async {
    final list = await router.findItineraries(
        const SearchResult.station('La Défense'),
        const SearchResult.station('Nation'),
        modeFilter: TransportMode.metro);

    expect(list, isNotEmpty);
    for (final it in list) {
      if (it.tag.startsWith('COMBINÉ') || it.tag == 'À PIED') continue;
      for (final ride in it.legs.whereType<RideLeg>()) {
        expect(
            ride.mode == TransportMode.metro ||
                ride.mode == TransportMode.train,
            isTrue,
            reason: 'itinéraire « ${it.tag} » contient un mode hors métro/RER');
      }
    }
  });

  test('adresse → station : marche d\'approche comptée une seule fois',
      () async {
    // Adresse en plein Paris (rue de Rivoli, ~300 m de Châtelet).
    final list = await router.findItineraries(
        const SearchResult.address('80 Rue de Rivoli, Paris', 48.8590, 2.3470),
        const SearchResult.station('Nation'));

    expect(list, isNotEmpty);
    // Cohérence : pas plus lent que 1 h pour ~6 km en plein Paris.
    expect(list.first.totalSeconds, lessThan(3600));
  });

  test('benchmark : 20 requêtes station→station aléatoires (graphe complet)',
      () async {
    final railNames = g.nodes.values
        .where((n) => n.routeType != null && n.routeType! <= 2)
        .map((n) => n.stationName)
        .toSet()
        .toList()
      ..sort();
    final rng = Random(42); // reproductible (exigence AO)
    final timed = <(int, String)>[];

    for (int i = 0; i < 20; i++) {
      final from = railNames[rng.nextInt(railNames.length)];
      final to = railNames[rng.nextInt(railNames.length)];
      if (from == to) continue;
      final sw = Stopwatch()..start();
      await router.findItineraries(
          SearchResult.station(from), SearchResult.station(to));
      sw.stop();
      timed.add((sw.elapsedMilliseconds, '$from → $to'));
    }

    timed.sort((a, b) => a.$1.compareTo(b.$1));
    final times = [for (final t in timed) t.$1];
    final avg = times.reduce((a, b) => a + b) / times.length;
    final p95 = times[(times.length * 0.95).floor().clamp(0, times.length - 1)];
    // ignore: avoid_print
    print('Benchmark ${times.length} requêtes — moyenne ${avg.round()} ms · '
        'p95 $p95 ms · max ${times.last} ms');
    for (final t in timed.reversed.take(3)) {
      // ignore: avoid_print
      print('  plus lentes : ${t.$1} ms — ${t.$2}');
    }
    // Chaque requête « Tous » (3 variantes) doit rester < 2 s.
    expect(times.last, lessThan(2000));
  });
}
