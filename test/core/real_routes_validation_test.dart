// Validation de trajets RÉELS sur le graphe IDFM complet : les lignes
// empruntées et les durées doivent correspondre à la réalité du réseau.
//
// Chaque cas affiche l'itinéraire détaillé (lignes, arrêts, marche) pour
// inspection, et vérifie : bonne ligne attendue, durée plausible, chemin
// connecté (les legs s'enchaînent sans trou).
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

  setUpAll(() {
    g = TransportGraph.fromJsonString(
        File('assets/graph/idfm_graph.json').readAsStringSync());
    router = RouterService(graph: g);
  });

  String legsToString(Itinerary it) {
    final b = StringBuffer('  [${it.tag}] ${it.durationLabel} — ${it.detail}');
    for (final leg in it.legs) {
      switch (leg) {
        case StationPoint():
          b.write('\n    ● ${leg.name} (${leg.subtitle})');
        case RideLeg():
          b.write('\n    ▶ ${leg.mode.name} ${leg.lineLabel} '
              '${leg.direction} — ${leg.subtitle}');
        case WalkLeg():
          b.write('\n    ○ ${leg.label} — ${leg.subtitle}');
      }
    }
    return b.toString();
  }

  Set<String> rideLines(Itinerary it) =>
      it.legs.whereType<RideLeg>().map((r) => r.lineLabel).toSet();

  /// Vérifie qu'un itinéraire est bien CONNECTÉ : chaque paire de nœuds
  /// consécutifs du chemin est reliée par une arête réelle du graphe.
  void expectConnected(Itinerary it) {
    for (int i = 0; i < it.pathNodeIds.length - 1; i++) {
      final from = it.pathNodeIds[i];
      final to = it.pathNodeIds[i + 1];
      final linked = g.neighbors(from).any((e) => e.to == to);
      expect(linked, isTrue,
          reason: 'chemin cassé entre $from et $to (${it.tag})');
    }
  }

  // Heure de référence FIXE (mardi 10h) : les tests sont déterministes
  // quelle que soit l'heure d'exécution (la nuit, le métro est fermé).
  final tuesday10h = DateTime(2026, 7, 7, 10, 0);

  Future<Itinerary> best(String from, String to,
      {TransportMode? mode}) async {
    final list = await router.findItineraries(
        SearchResult.station(from), SearchResult.station(to),
        modeFilter: mode, when: tuesday10h);
    expect(list, isNotEmpty, reason: 'aucun itinéraire $from → $to');
    // ignore: avoid_print
    print('$from → $to :');
    for (final it in list) {
      // ignore: avoid_print
      print(legsToString(it));
      expectConnected(it);
    }
    return list.first;
  }

  test('Châtelet → Nation : M1 (ou RER A), ~10-20 min', () async {
    final it = await best('Châtelet', 'Nation');
    expect(it.totalSeconds, inInclusiveRange(8 * 60, 22 * 60));
    expect(rideLines(it).intersection({'1', 'A'}), isNotEmpty,
        reason: 'attendu M1 ou RER A, obtenu ${rideLines(it)}');
  });

  test('Bastille → République : M5 ou M8 direct, ~5-15 min', () async {
    final it = await best('Bastille', 'République');
    expect(it.totalSeconds, inInclusiveRange(4 * 60, 16 * 60));
    expect(rideLines(it).intersection({'5', '8'}), isNotEmpty,
        reason: 'attendu M5 ou M8, obtenu ${rideLines(it)}');
    // Direct : une seule ligne, 0 correspondance.
    expect(it.legs.whereType<RideLeg>().length, 1);
  });

  test('Gare du Nord → Gare de Lyon : RER D (ou B+…), ~10-25 min', () async {
    final it = await best('Gare du Nord', 'Gare de Lyon');
    expect(it.totalSeconds, inInclusiveRange(8 * 60, 26 * 60));
    expect(rideLines(it).intersection({'D', 'B', '14', '5'}), isNotEmpty,
        reason: 'lignes inattendues : ${rideLines(it)}');
  });

  test('Montparnasse Bienvenue → Saint-Lazare : M13 ou M12/M14, ~10-25 min',
      () async {
    final it = await best('Montparnasse Bienvenue', 'Saint-Lazare');
    expect(it.totalSeconds, inInclusiveRange(8 * 60, 26 * 60));
    expect(rideLines(it).intersection({'13', '12', '14'}), isNotEmpty,
        reason: 'lignes inattendues : ${rideLines(it)}');
  });

  test('Villejuif - Louis Aragon → Châtelet : M7 direct, ~20-40 min',
      () async {
    final it = await best('Villejuif - Louis Aragon', 'Châtelet');
    expect(it.totalSeconds, inInclusiveRange(18 * 60, 42 * 60));
    expect(rideLines(it), contains('7'),
        reason: 'attendu M7, obtenu ${rideLines(it)}');
  });

  test('La Défense → Nation : RER A nettement plus rapide que M1 complet',
      () async {
    final it = await best('La Défense', 'Nation');
    expect(it.totalSeconds, inInclusiveRange(12 * 60, 35 * 60));
    expect(rideLines(it), contains('A'),
        reason: 'attendu RER A, obtenu ${rideLines(it)}');
  });

  test('filtre BUS sur un trajet courte distance : lignes de bus réelles',
      () async {
    final it =
        await best('Bastille', 'République', mode: TransportMode.bus);
    // Soit un vrai trajet bus (toutes les lignes en mode bus),
    // soit le repli combiné explicitement étiqueté.
    if (!it.tag.startsWith('COMBINÉ') && it.tag != 'À PIED') {
      for (final r in it.legs.whereType<RideLeg>()) {
        expect(r.mode, TransportMode.bus);
      }
    }
  });

  test('cohérence attente : durée ≥ somme des temps de parcours purs',
      () async {
    // La durée affichée inclut l'attente d'embarquement : elle doit être
    // strictement supérieure au temps véhicule + marche seuls.
    final it = await best('Châtelet', 'Nation');
    double pureSecs = 0;
    for (int i = 0; i < it.pathNodeIds.length - 1; i++) {
      final from = it.pathNodeIds[i];
      final to = it.pathNodeIds[i + 1];
      final e = g.neighbors(from).firstWhere((e) => e.to == to);
      pureSecs += e.weightSeconds;
    }
    expect(it.totalSeconds, greaterThan(pureSecs));
    expect(it.totalSeconds - pureSecs, lessThanOrEqualTo(3 * 360 + 1),
        reason: 'attente cumulée aberrante');
  });
}
