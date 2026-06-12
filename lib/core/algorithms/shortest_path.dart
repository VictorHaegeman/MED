/// Plus court chemin — Dijkstra (référence) et A* (optimisation).
///
/// ⚠️ Exigence AO : algorithmes implémentés À LA MAIN (pas de librairie de
/// graphes), adaptés au volume du réseau RATP — un Dijkstra naïf O(V²) est
/// éliminatoire. Cible : file de priorité (tas binaire), O((V+E) log V).
library;

import '../graph.dart';

/// Résultat d'un calcul de plus court chemin, instrumenté pour les
/// mesures de performance exigées par l'AO (temps, nœuds explorés).
class ShortestPathResult {
  const ShortestPathResult({
    required this.path,
    required this.totalSeconds,
    required this.exploredNodes,
    required this.computeTime,
  });

  /// Suite ordonnée d'identifiants de nœuds, départ → arrivée.
  final List<String> path;
  final double totalSeconds;
  final int exploredNodes;
  final Duration computeTime;
}

/// Interface commune — permet de benchmarker Dijkstra vs A* à API identique.
abstract interface class ShortestPathAlgorithm {
  String get name;

  /// Lance le calcul entre deux nœuds. Lève [ArgumentError] si un nœud
  /// n'existe pas ; retourne un chemin vide si aucun chemin n'existe.
  ShortestPathResult run(TransportGraph graph, String fromId, String toId);
}

/// Dijkstra avec file de priorité (tas binaire min).
///
/// Plan d'implémentation (V1) :
///   1. Implémenter un tas binaire min indexé (decrease-key) — à la main.
///   2. dist[] initialisé à +inf, dist[from] = 0 ; prev[] pour reconstruire.
///   3. Extraire le min, relâcher les arêtes sortantes via graph.neighbors().
///   4. S'arrêter dès que `toId` est extrait (early exit).
///   5. Instrumenter : Stopwatch pour computeTime, compteur exploredNodes.
///   6. Tests : optimalité sur petit graphe connu, départ == arrivée,
///      nœud inexistant, graphe non connexe (chemin vide).
class Dijkstra implements ShortestPathAlgorithm {
  @override
  String get name => 'Dijkstra (tas binaire)';

  @override
  ShortestPathResult run(TransportGraph graph, String fromId, String toId) {
    // TODO(V1): implémenter — voir plan ci-dessus.
    throw UnimplementedError('Dijkstra — V1');
  }
}

/// A* avec heuristique géodésique.
///
/// Heuristique : h(n) = distance_haversine(n, arrivée) / vitesse_max_réseau.
/// Elle est ADMISSIBLE (ne surestime jamais le coût réel) → l'optimalité de
/// Dijkstra est conservée tout en réduisant l'espace exploré.
/// À justifier et benchmarker contre Dijkstra (exigence AO).
class AStar implements ShortestPathAlgorithm {
  /// Vitesse max du réseau en m/s, utilisée par l'heuristique.
  /// Hypothèse à documenter : métro ≈ 70 km/h en pointe de vitesse.
  static const double maxSpeedMs = 19.4;

  @override
  String get name => 'A* (heuristique géodésique)';

  /// TODO(V1): distance haversine entre deux nœuds (lat/lon en degrés).
  double heuristicSeconds(GraphNode from, GraphNode goal) {
    throw UnimplementedError('Heuristique A* — V1');
  }

  @override
  ShortestPathResult run(TransportGraph graph, String fromId, String toId) {
    // TODO(V1): Dijkstra + priorité f(n) = g(n) + h(n).
    throw UnimplementedError('A* — V1');
  }
}
