/// Connexité du réseau — attendu explicite de l'AO ("tester la connexité").
///
/// Usage prévu : vérification d'intégrité au chargement du graphe. Un réseau
/// non connexe signale des données corrompues (stations isolées) — le badge
/// "● Connexe" de l'écran d'accueil est branché sur ce résultat.
library;

import '../graph.dart';

class ConnectivityReport {
  const ConnectivityReport({
    required this.isConnected,
    required this.components,
  });

  final bool isConnected;

  /// Composantes connexes, triées par taille décroissante. Si le graphe est
  /// connexe, contient une seule composante avec tous les nœuds.
  final List<Set<String>> components;
}

class ConnectivityChecker {
  /// Parcours en largeur (BFS) depuis un nœud — O(V+E).
  ///
  /// TODO(V1):
  ///   1. BFS itératif avec file (Queue de dart:collection).
  ///   2. Pour la connexité d'un graphe ORIENTÉ : vérifier l'atteignabilité
  ///      dans le graphe ET dans son transposé (ou utiliser le graphe
  ///      non-orienté sous-jacent — choix à documenter).
  ///   3. Tests : graphe connexe, graphe à 2 composantes, graphe vide.
  Set<String> reachableFrom(TransportGraph graph, String startId) {
    throw UnimplementedError('BFS — V1');
  }

  /// TODO(V1): composantes connexes par BFS répétés sur les nœuds non visités.
  ConnectivityReport analyze(TransportGraph graph) {
    throw UnimplementedError('Analyse de connexité — V1');
  }
}
