import 'dart:collection';

import '../graph.dart';

class ConnectivityReport {
  const ConnectivityReport({
    required this.isConnected,
    required this.components,
  });

  final bool isConnected;
  final List<Set<String>> components;
}

class ConnectivityChecker {
  Set<String> reachableFrom(
    TransportGraph graph,
    String startId,
  ) {
    final visited = <String>{};
    final queue = Queue<String>();

    visited.add(startId);
    queue.add(startId);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();

      for (final edge in graph.neighbors(current)) {
        final next = edge.to;

        if (!visited.contains(next)) {
          visited.add(next);
          queue.add(next);
        }
      }
    }

    return visited;
  }

  // Composantes connexes par BFS répétés sur noeuds non visités
  ConnectivityReport analyze(TransportGraph graph) {
    // Graphe vide
    if (graph.nodeCount == 0) {
      return const ConnectivityReport(
        isConnected: true,
        components: [],
      );
    }

    final visited = <String>{};
    final components = <Set<String>>[];

    for (final nodeId in graph.nodes.keys) {
      if (visited.contains(nodeId)) continue;

      final component = reachableFrom(graph, nodeId);

      visited.addAll(component);
      components.add(component);
    }
    // Tri décroissant (pour l'affichage)
    components.sort(
      (a, b) => b.length.compareTo(a.length),
    );

    return ConnectivityReport(
      isConnected: components.length == 1,
      components: components,
    );
  }
}
