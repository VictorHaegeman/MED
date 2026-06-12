# MED — Metro, Efrei, Dodo 🚇

Application mobile d'optimisation des temps de trajet dans le réseau de transport parisien (métro, tram, bus, marche). Projet Solution Delivery 2025-2026, EFREI — Filière IT.

**État actuel : V0** — UI complète sur données mockées, cœur algorithmique en templates documentés (à implémenter en V1).

## Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.27 (stable)
- Un émulateur Android/iOS ou un appareil physique

## Installation & lancement

```bash
flutter create . --platforms=android,ios   # génère les dossiers plateformes (1ʳᵉ fois)
flutter pub get
flutter run
```

Tests et analyse :

```bash
flutter analyze
flutter test
```

## Structure

```
lib/
├── core/                      # Dart pur, AUCUN import Flutter — testable sans UI
│   ├── graph.dart             # ✅ Structure du graphe (nœuds (station,ligne), arêtes pondérées)
│   ├── algorithms/
│   │   ├── shortest_path.dart # 🔲 Dijkstra (tas binaire) + A* — templates V1
│   │   ├── connectivity.dart  # 🔲 BFS / composantes connexes — template V1
│   │   └── spanning_tree.dart # 🔲 Prim (arborescence du réseau) — template V1
│   └── router_service.dart    # Jonction UI ↔ algo (V0 : données mockées)
├── data/mock_data.dart        # Itinéraires mockés (à supprimer en V1)
├── models/itinerary.dart      # Modèles UI (Itinerary, RideLeg, WalkLeg…)
├── screens/                   # Accueil, Résultats, Détail, Impact & Perf
├── widgets/common.dart        # Badges de lignes, cartes, chips, boutons
└── theme.dart                 # Palette (couleurs officielles des lignes)
test/
└── core/shortest_path_test.dart  # Tests-contrats écrits AVANT l'implémentation
```

## Où implémenter les algorithmes (V1)

Chaque template contient le plan d'implémentation détaillé en commentaire :

1. **Dijkstra** — `lib/core/algorithms/shortest_path.dart` → classe `Dijkstra`. Tas binaire à la main, O((V+E) log V). Un O(V²) naïf est éliminatoire.
2. **A\*** — même fichier → classe `AStar`. Heuristique géodésique admissible (haversine / vitesse max).
3. **Connexité** — `connectivity.dart` → `ConnectivityChecker`. BFS, branche le badge "● Connexe" de l'accueil.
4. **Arborescence** — `spanning_tree.dart` → `PrimMst`. Alimente la visualisation de l'écran Impact.
5. **Graphe réel** — `graph.dart` → `TransportGraph.fromAsset`. Asset généré par `data-pipeline/` (à créer) depuis le GTFS Île-de-France Mobilités (licence ODbL).

Workflow : implémenter → retirer le `skip:` des tests correspondants dans `test/core/` → CI verte → brancher dans `RouterService` (les `TODO(V1)` marquent chaque point de branchement).

## Données

- Source prévue : GTFS [Île-de-France Mobilités](https://data.iledefrance-mobilites.fr) — licence ODbL, à citer.
- Hypothèses de pondération à documenter ici (temps inter-stations, pénalité de correspondance ~4 min).
- Aucune donnée personnelle. Aucune clé API dans le dépôt.

## Équipe & contacts AO

Questions appel d'offres : olivier.girinsky@efrei.fr · stephany.rajeh@efrei.fr · badr.tajini@efrei.fr
