// Tests du TransitRouter (A* multi-source / multi-cible).
//
// Exigence AO : optimalité du chemin (vérifiée contre Dijkstra, la référence),
// admissibilité de l'heuristique (même coût optimal que Dijkstra), cas
// limites (départ = arrivée, station inexistante).

import 'package:flutter_test/flutter_test.dart';
import 'package:med/core/algorithms/shortest_path.dart';
import 'package:med/core/graph.dart';

// Même mini-réseau que algorithm_test.dart :
//   A --30s--> B --60s--> C
//   |                     |
//  120s (transfer)       45s (transfer)
//   |                     |
//   D --90s--> E --20s--> F
//   Transfert B→E : 240s
//   Optimal A→F : A→B→C→F = 135 s ; optimal D→F : D→E→F = 110 s.
//
// NB : les coordonnées sont espacées de ~0,001° (~110 m) pour respecter
// l'invariant du graphe réel (vitesse ≤ TransportGraph.maxSpeedMs, garanti
// par le plancher appliqué au chargement) — condition d'admissibilité de
// l'heuristique A*.
TransportGraph _buildTestGraph() {
  final g = TransportGraph();
  g.addNode(const GraphNode(
      id: 'A#L1', stationName: 'Alpha', line: 'L1',
      lat: 48.850, lon: 2.300, lineShortName: '1', routeType: 1));
  g.addNode(const GraphNode(
      id: 'B#L1', stationName: 'Bravo', line: 'L1',
      lat: 48.851, lon: 2.302, lineShortName: '1', routeType: 1));
  g.addNode(const GraphNode(
      id: 'C#L1', stationName: 'Charlie', line: 'L1',
      lat: 48.852, lon: 2.304, lineShortName: '1', routeType: 1));
  g.addNode(const GraphNode(
      id: 'D#L2', stationName: 'Delta', line: 'L2',
      lat: 48.849, lon: 2.300, lineShortName: '2', routeType: 1));
  g.addNode(const GraphNode(
      id: 'E#L2', stationName: 'Echo', line: 'L2',
      lat: 48.849, lon: 2.302, lineShortName: '2', routeType: 1));
  g.addNode(const GraphNode(
      id: 'F#L2', stationName: 'Foxtrot', line: 'L2',
      lat: 48.852, lon: 2.304, lineShortName: '2', routeType: 1));

  g.addEdge(const Edge(from: 'A#L1', to: 'B#L1', weightSeconds: 30, type: EdgeType.ride));
  g.addEdge(const Edge(from: 'B#L1', to: 'C#L1', weightSeconds: 60, type: EdgeType.ride));
  g.addEdge(const Edge(from: 'C#L1', to: 'F#L2', weightSeconds: 45, type: EdgeType.transfer));
  g.addEdge(const Edge(from: 'A#L1', to: 'D#L2', weightSeconds: 120, type: EdgeType.transfer));
  g.addEdge(const Edge(from: 'D#L2', to: 'E#L2', weightSeconds: 90, type: EdgeType.ride));
  g.addEdge(const Edge(from: 'E#L2', to: 'F#L2', weightSeconds: 20, type: EdgeType.ride));
  g.addEdge(const Edge(from: 'B#L1', to: 'E#L2', weightSeconds: 240, type: EdgeType.transfer));
  return g;
}

void main() {
  late TransportGraph graph;
  late TransitRouter router;

  setUp(() {
    graph = _buildTestGraph();
    router = TransitRouter();
  });

  group('TransitRouter — optimalité (référence Dijkstra)', () {
    test('mono-source sans attentes = même coût optimal que Dijkstra', () {
      final d = Dijkstra().run(graph, 'A#L1', 'F#L2');
      final r = router.route(graph,
          sources: {'A#L1': 0},
          targets: {'F#L2': 0},
          boardingWaits: false);
      expect(r.found, isTrue);
      expect(r.totalSeconds, equals(d.totalSeconds)); // 135 s
      expect(r.path, equals(d.path));
    });

    test('multi-source = min des Dijkstra sur chaque paire', () {
      final dA = Dijkstra().run(graph, 'A#L1', 'F#L2'); // 135
      final dD = Dijkstra().run(graph, 'D#L2', 'F#L2'); // 110
      final r = router.route(graph,
          sources: {'A#L1': 0, 'D#L2': 0},
          targets: {'F#L2': 0},
          boardingWaits: false);
      expect(r.totalSeconds,
          equals([dA.totalSeconds, dD.totalSeconds].reduce((a, b) => a < b ? a : b)));
      expect(r.path.first, equals('D#L2'));
    });

    test('coûts d\'approche (marche) intégrés au choix de la source', () {
      // A coûte 100 s d'approche (total 235), D coûte 50 s (total 160).
      final r = router.route(graph,
          sources: {'A#L1': 100, 'D#L2': 50},
          targets: {'F#L2': 0},
          boardingWaits: false);
      expect(r.totalSeconds, equals(160.0));
      expect(r.path.first, equals('D#L2'));
    });

    test('coût de sortie (marche) intégré au choix de la cible', () {
      final r = router.route(graph,
          sources: {'D#L2': 0},
          targets: {'F#L2': 40},
          boardingWaits: false);
      expect(r.totalSeconds, equals(150.0)); // 110 + 40
    });

    test('stepTypes reflète les arêtes réellement empruntées', () {
      final r = router.route(graph,
          sources: {'A#L1': 0},
          targets: {'F#L2': 0},
          boardingWaits: false);
      // A→B (ride), B→C (ride), C→F (transfer)
      expect(r.stepTypes,
          equals([EdgeType.ride, EdgeType.ride, EdgeType.transfer]));
    });
  });

  group('TransitRouter — attentes d\'embarquement', () {
    test('embarquer coûte l\'attente du mode, rester à bord non', () {
      // A→B→C→F : 1 seul embarquement métro (120 s) + 30 + 60 + 45 = 255.
      final r = router.route(graph,
          sources: {'A#L1': 0}, targets: {'F#L2': 0});
      expect(r.totalSeconds, equals(255.0));
      expect(r.path, equals(['A#L1', 'B#L1', 'C#L1', 'F#L2']));
    });

    test('chaque nouvel embarquement re-paye l\'attente', () {
      // D→E→F sans C→F : embarquement unique = 120 + 90 + 20 = 230.
      final r = router.route(graph,
          sources: {'D#L2': 0}, targets: {'F#L2': 0});
      expect(r.totalSeconds, equals(230.0));
    });
  });

  group('TransitRouter — cas limites (exigence AO)', () {
    test('départ = arrivée → coût 0, chemin trivial', () {
      final r = router.route(graph,
          sources: {'A#L1': 0}, targets: {'A#L1': 0});
      expect(r.found, isTrue);
      expect(r.totalSeconds, equals(0.0));
      expect(r.path, equals(['A#L1']));
    });

    test('station inexistante → not found', () {
      final r = router.route(graph,
          sources: {'Z#L9': 0}, targets: {'F#L2': 0});
      expect(r.found, isFalse);
    });

    test('sources vides → not found', () {
      final r = router.route(graph, sources: {}, targets: {'F#L2': 0});
      expect(r.found, isFalse);
    });

    test('cible inatteignable → not found', () {
      // F n'a aucune arête sortante → F→A impossible.
      final r = router.route(graph,
          sources: {'F#L2': 0}, targets: {'A#L1': 0});
      expect(r.found, isFalse);
    });

    test('filtre d\'arêtes respecté (mode pur impossible → not found)', () {
      // En interdisant les transferts, aucun chemin A→F n'existe (C→F est
      // un transfer).
      final r = router.route(graph,
          sources: {'A#L1': 0},
          targets: {'F#L2': 0},
          edgeFilter: (e) => e.type == EdgeType.ride);
      expect(r.found, isFalse);
    });
  });
}
