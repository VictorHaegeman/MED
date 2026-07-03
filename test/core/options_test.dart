// Tests des options de recherche : accessibilité fauteuil roulant,
// choix de l'horaire (« partir à » / « arriver à ») et service de nuit
// (Noctilien) — sur le graphe IDFM réel.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:med/core/graph.dart';
import 'package:med/core/router_service.dart';
import 'package:med/models/itinerary.dart';
import 'package:med/models/search_result.dart';

void main() {
  late TransportGraph g;
  late RouterService router;

  final tuesday10h = DateTime(2026, 7, 7, 10, 0);
  final tuesday15h = DateTime(2026, 7, 7, 15, 0);
  final night3h = DateTime(2026, 7, 7, 3, 0);

  setUpAll(() {
    g = TransportGraph.fromJsonString(
        File('assets/graph/idfm_graph.json').readAsStringSync());
    router = RouterService(graph: g);
  });

  test('données accessibilité chargées : le métro est presque tout exclu',
      () {
    final metro = g.nodes.values.where((n) => n.routeType == 1).toList();
    final accessibles = metro.where((n) => n.isWheelchairAccessible).length;
    // Réalité parisienne : seule la ligne 14 (et quelques quais) est
    // accessible → une petite minorité des 405 nœuds métro.
    expect(accessibles, greaterThan(10));
    expect(accessibles, lessThan(80));
    // Les nœuds accessibles du métro sont essentiellement la ligne 14.
    final l14 = metro
        .where((n) => n.isWheelchairAccessible && n.lineShortName == '14')
        .length;
    expect(l14, greaterThan(15));
  });

  test('♿ accessible : jamais de métro hors ligne 14, extrémités accessibles',
      () async {
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'),
        accessible: true,
        when: tuesday10h);

    expect(list, isNotEmpty, reason: 'aucun itinéraire accessible trouvé');
    for (final it in list) {
      if (it.tag == 'À PIED') continue;
      // Extrémités du chemin : arrêts accessibles obligatoires.
      expect(g.nodes[it.pathNodeIds.first]!.isWheelchairAccessible, isTrue);
      expect(g.nodes[it.pathNodeIds.last]!.isWheelchairAccessible, isTrue);
      // Le métro parisien est inaccessible sauf la ligne 14.
      for (final ride in it.legs.whereType<RideLeg>()) {
        if (ride.mode == TransportMode.metro) {
          expect(ride.lineLabel, '14',
              reason:
                  'itinéraire accessible utilisant le métro ${ride.lineLabel}');
        }
      }
    }
    // ignore: avoid_print
    print('♿ Châtelet → Nation : ${list.first.durationLabel} '
        '(${list.first.legs.whereType<RideLeg>().map((r) => r.lineLabel).join(" → ")})');
  });

  test('♿ accessible : le chemin ne se correspond que via des arrêts accessibles',
      () async {
    final list = await router.findItineraries(
        const SearchResult.station('Gare de Lyon'),
        const SearchResult.station('La Défense'),
        accessible: true,
        when: tuesday10h);
    expect(list, isNotEmpty);
    final it = list.first;
    // Toute arête transfer empruntée relie deux arrêts accessibles.
    for (int i = 0; i < it.pathNodeIds.length - 1; i++) {
      final from = it.pathNodeIds[i];
      final to = it.pathNodeIds[i + 1];
      final hasRide = g
          .neighbors(from)
          .any((e) => e.to == to && e.type == EdgeType.ride);
      if (!hasRide) {
        // Ce pas est forcément une correspondance à pied.
        expect(g.nodes[from]!.isWheelchairAccessible, isTrue,
            reason: 'transfer via arrêt inaccessible $from');
        expect(g.nodes[to]!.isWheelchairAccessible, isTrue,
            reason: 'transfer via arrêt inaccessible $to');
      }
    }
  });

  test('nuit (3h) : seuls les Noctilien circulent', () async {
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'),
        when: night3h);

    expect(list, isNotEmpty,
        reason: 'aucun itinéraire de nuit (Noctilien attendu)');
    for (final it in list) {
      if (it.tag == 'À PIED') continue;
      for (final ride in it.legs.whereType<RideLeg>()) {
        expect(ride.mode, TransportMode.bus,
            reason: 'mode non-bus à 3h du matin : ${ride.lineLabel}');
        expect(ride.lineLabel.toUpperCase().startsWith('N'), isTrue,
            reason: 'bus de jour à 3h du matin : ${ride.lineLabel}');
      }
    }
    // ignore: avoid_print
    print('Nuit 3h Châtelet → Nation : ${list.first.durationLabel} '
        '(${list.first.legs.whereType<RideLeg>().map((r) => r.lineLabel).join(" → ")})');
  });

  test('jour : aucun Noctilien proposé', () async {
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'),
        when: tuesday10h);
    for (final it in list) {
      for (final ride in it.legs.whereType<RideLeg>()) {
        final isNocti = ride.mode == TransportMode.bus &&
            ride.lineLabel.toUpperCase().startsWith('N') &&
            ride.lineLabel.length > 1 &&
            int.tryParse(ride.lineLabel.substring(1)) != null;
        expect(isNocti, isFalse,
            reason: 'Noctilien ${ride.lineLabel} proposé en pleine journée');
      }
    }
  });

  test('« arriver à 15h » : l\'heure de départ est calculée en conséquence',
      () async {
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'),
        when: tuesday15h,
        arriveBy: true);

    expect(list, isNotEmpty);
    for (final it in list) {
      expect(it.arriveAt, tuesday15h);
      final expectedDepart =
          tuesday15h.subtract(Duration(seconds: it.totalSeconds.round()));
      expect(it.departAt, expectedDepart);
      expect(it.departAt!.isBefore(it.arriveAt!), isTrue);
    }
    // ignore: avoid_print
    print('Arriver à 15:00 → partir à '
        '${list.first.departAt!.hour.toString().padLeft(2, '0')}:'
        '${list.first.departAt!.minute.toString().padLeft(2, '0')}');
  });

  test('« partir à » : arrivée = départ + durée', () async {
    final list = await router.findItineraries(
        const SearchResult.station('Châtelet'),
        const SearchResult.station('Nation'),
        when: tuesday10h);
    expect(list, isNotEmpty);
    for (final it in list) {
      expect(it.departAt, tuesday10h);
      expect(it.arriveAt,
          tuesday10h.add(Duration(seconds: it.totalSeconds.round())));
    }
  });
}
