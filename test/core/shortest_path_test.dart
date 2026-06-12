/// Tests templates du cœur algorithmique.
///
/// Les tests sont écrits AVANT l'implémentation (contrat) et marqués `skip`.
/// Quand vous implémentez un algo : retirez le `skip` correspondant.
/// La CI doit rester verte à chaque étape (exigence AO : reproductibilité).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:med/core/algorithms/connectivity.dart';
import 'package:med/core/algorithms/shortest_path.dart';
import 'package:med/core/algorithms/spanning_tree.dart';
import 'package:med/core/graph.dart';

/// Petit graphe de référence (5 nœuds) au plus court chemin connu :
///
///   A --60--> B --60--> D
///   A --30--> C --30--> D --10--> E
///
/// Plus court chemin A→E : A,C,D,E (coût 70).
TransportGraph buildTinyGraph() {
  final g = TransportGraph();
  for (final id in ['A', 'B', 'C', 'D', 'E']) {
    g.addNode(GraphNode(id: id, stationName: id, line: 'M1', lat: 0, lon: 0));
  }
  const edges = [
    ('A', 'B', 60.0),
    ('B', 'D', 60.0),
    ('A', 'C', 30.0),
    ('C', 'D', 30.0),
    ('D', 'E', 10.0),
  ];
  for (final (from, to, w) in edges) {
    g.addEdge(Edge(from: from, to: to, weightSeconds: w, type: EdgeType.ride));
    g.addEdge(Edge(from: to, to: from, weightSeconds: w, type: EdgeType.ride));
  }
  return g;
}

void main() {
  group('TransportGraph (structure — implémentée)', () {
    test('compte correctement nœuds et arêtes', () {
      final g = buildTinyGraph();
      expect(g.nodeCount, 5);
      expect(g.edgeCount, 10); // 5 liaisons x 2 sens
      expect(g.neighbors('A').length, 2);
    });
  });

  group('Dijkstra', () {
    test('trouve le chemin optimal A→E (coût 70)', () {
      final result = Dijkstra().run(buildTinyGraph(), 'A', 'E');
      expect(result.path, ['A', 'C', 'D', 'E']);
      expect(result.totalSeconds, 70.0);
    }, skip: 'V1 — à activer quand Dijkstra sera implémenté');

    test('départ == arrivée → chemin trivial, coût 0', () {
      final result = Dijkstra().run(buildTinyGraph(), 'A', 'A');
      expect(result.path, ['A']);
      expect(result.totalSeconds, 0.0);
    }, skip: 'V1 — à activer quand Dijkstra sera implémenté');

    test('nœud inexistant → ArgumentError', () {
      expect(() => Dijkstra().run(buildTinyGraph(), 'A', 'Z'),
          throwsArgumentError);
    }, skip: 'V1 — à activer quand Dijkstra sera implémenté');
  });

  group('A*', () {
    test('retourne le même coût optimal que Dijkstra (admissibilité)', () {
      final g = buildTinyGraph();
      final d = Dijkstra().run(g, 'A', 'E');
      final a = AStar().run(g, 'A', 'E');
      expect(a.totalSeconds, d.totalSeconds);
    }, skip: 'V1 — à activer quand A* sera implémenté');

    test('explore au plus autant de nœuds que Dijkstra', () {
      final g = buildTinyGraph();
      final d = Dijkstra().run(g, 'A', 'E');
      final a = AStar().run(g, 'A', 'E');
      expect(a.exploredNodes, lessThanOrEqualTo(d.exploredNodes));
    }, skip: 'V1 — à activer quand A* sera implémenté');
  });

  group('Connexité (BFS)', () {
    test('graphe de référence connexe', () {
      final report = ConnectivityChecker().analyze(buildTinyGraph());
      expect(report.isConnected, isTrue);
      expect(report.components.length, 1);
    }, skip: 'V1 — à activer quand le BFS sera implémenté');

    test('nœud isolé → 2 composantes', () {
      final g = buildTinyGraph();
      g.addNode(const GraphNode(
          id: 'X', stationName: 'X', line: null, lat: 0, lon: 0));
      final report = ConnectivityChecker().analyze(g);
      expect(report.isConnected, isFalse);
      expect(report.components.length, 2);
    }, skip: 'V1 — à activer quand le BFS sera implémenté');
  });

  group('Arborescence (Prim)', () {
    test('MST du graphe de référence : 4 arêtes, poids 130', () {
      // MST attendu : A-C (30), C-D (30), D-E (10), A-B (60) → 130.
      final mst = PrimMst().compute(buildTinyGraph());
      expect(mst.edges.length, 4);
      expect(mst.totalWeight, 130.0);
    }, skip: 'V1 — à activer quand Prim sera implémenté');
  });
}
