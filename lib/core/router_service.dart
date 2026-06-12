/// Service d'itinéraires — point de jonction entre l'UI et le cœur algo.
///
/// V0 : retourne des données mockées (lib/data/mock_data.dart) pour permettre
/// le développement de l'UI en parallèle des algorithmes.
///
/// TODO(V1): brancher le vrai pipeline :
///   1. `TransportGraph.fromAsset(...)` au démarrage (une seule fois) ;
///   2. `ConnectivityChecker.analyze(...)` → badge "Connexe" de l'accueil ;
///   3. `Dijkstra` / `AStar` pour chaque requête, avec critères multiples
///      (rapide / moins de correspondances / sobre) via pondérations ;
///   4. remonter `ShortestPathResult.computeTime` et `exploredNodes` dans
///      `Itinerary.perfNote` (transparence algorithmique, exigence AO).
library;

import '../data/mock_data.dart';
import '../models/itinerary.dart';

class RouterService {
  /// Recherche d'itinéraires entre deux stations.
  Future<List<Itinerary>> findItineraries(String from, String to) async {
    // Simule une latence de calcul pour tester les états de chargement UI.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return mockItineraries;
  }
}
