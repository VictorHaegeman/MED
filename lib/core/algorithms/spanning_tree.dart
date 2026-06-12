/// Arborescence de la structure du réseau — attendu explicite de l'AO
/// ("afficher l'arborescence de la structure").
///
/// Choix retenu (plan §2) : arbre couvrant minimal par Prim avec tas binaire,
/// O(E log V). L'écran "Impact & Performance" expose la visualisation.
library;

import '../graph.dart';

class SpanningTreeResult {
  const SpanningTreeResult({required this.edges, required this.totalWeight});

  final List<Edge> edges;
  final double totalWeight;
}

class PrimMst {
  /// TODO(V1):
  ///   1. Travailler sur le graphe non-orienté sous-jacent (documenter).
  ///   2. Tas binaire min sur le poids des arêtes frontières.
  ///   3. Précondition : graphe connexe (utiliser ConnectivityChecker avant).
  ///   4. Tests : MST d'un graphe connu (poids total attendu),
  ///      graphe non connexe → lever StateError.
  SpanningTreeResult compute(TransportGraph graph) {
    throw UnimplementedError('Prim — V1');
  }
}
