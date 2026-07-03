# MED — Metro, Efrei, Dodo 🚇

Application d'optimisation des temps de trajet dans le réseau de transport
francilien (métro, RER/Transilien, tram, bus, marche). Projet Solution
Delivery 2025-2026, EFREI — Filière IT.

**État actuel : V1** — cœur algorithmique implémenté à la main (Dijkstra, A*,
BFS, Prim), graphe IDFM réel (~43 000 nœuds, ~478 600 arêtes après élagage),
recherche multi-source/multi-cible, tests unitaires + tests d'intégration sur
trajets réels, benchmark reproductible.

## Prérequis

- [Flutter](https://docs.flutter.dev/get-started/install) ≥ 3.27 (stable)
- Cible principale : web (`flutter run -d chrome`)

## Installation & lancement

```bash
flutter pub get
flutter run -d chrome
```

Tests et analyse :

```bash
flutter analyze
flutter test          # 55 tests : unités algo + intégration graphe réel
```

## Cœur algorithmique (exigences AO)

| Attendu AO | Implémentation | Fichier |
|---|---|---|
| Connexité | BFS / composantes, O(V+E) — badge calculé (plus codé en dur) | `core/algorithms/connectivity.dart` |
| Arborescence | Prim, tas binaire à la main, O(E log V) | `core/algorithms/spanning_tree.dart` |
| Plus court chemin | Dijkstra, tas binaire à la main, O((V+E) log V) | `core/algorithms/shortest_path.dart` |
| Optimisation | A* heuristique géodésique **admissible par construction** (voir hypothèses) | idem |
| Requête app | `TransitRouter` = même A* étendu **multi-source/multi-cible** : 1 seul run par requête, quel que soit le nombre de quais candidats | idem |

Tout est implémenté à la main (aucune librairie de graphes). Dijkstra et A*
simple paire restent la référence du benchmark ; `TransitRouter` est vérifié
contre Dijkstra (même coût optimal) dans les tests.

## Hypothèses de modélisation (documentées, exigence AO)

- **Nœuds (station, ligne)** ; arêtes `ride` (poids = temps GTFS inter-arrêts,
  meilleure course de la journée) et `transfer` (marche, poids =
  `min_transfer_time` GTFS, défaut 240 s).
- **Plancher de vitesse réseau 38 m/s** (`TransportGraph.maxSpeedMs`) appliqué
  au chargement : corrige les horaires GTFS aberrants (jusqu'à 327 km/h
  observés) et garantit l'admissibilité de l'heuristique A*
  (h = haversine / 38 ≤ coût réel pour toute arête).
- **Plancher de marche 1,6 m/s** sur les transferts (35 000 « téléportations »
  GTFS corrigées), puis élagage des correspondances > 6 min.
- **Attentes d'embarquement** (demi-intervalle de passage moyen) : métro 2 min,
  tram 3,5 min, RER/Transilien 4 min, bus 6 min. L'app fonctionne en « départ
  maintenant » **sans modèle horaire complet** : l'attente moyenne remplace la
  consultation des horaires. Monter dans un véhicule coûte l'attente ; rester
  à bord, non (état « à bord » dans la recherche).
- **Noctilien exclu** des trajets (pas de modèle horaire → pas de bus de nuit).
- **Arrêts homonymes** (« Mairie » = 1 118 nœuds sur 433 sites) : résolution
  par pôle géographique (clustering 800 m, priorité aux pôles ferrés).
- **Adresses** : rabattement à pied multi-arrêts (rayon 800 m, 4,9 km/h,
  détour ×1,25) — le routeur choisit le meilleur arrêt de départ/arrivée.
- Les durées affichées sont recalculées depuis le chemin (poids réels +
  attentes), **hors pénalités artificielles** servant à générer les variantes.

## Performance (mesurée, reproductible)

`test/core/real_graph_integration_test.dart` (seed fixe) : requête complète
« Tous » (3-4 passes A*) — **moyenne ~200-400 ms, p95 ~1 s** sur le graphe
complet en VM debug. Trajets de référence validés (lignes et durées réalistes) :
Châtelet→Nation M1 11 min · Gare du Nord→Gare de Lyon RER D 10 min ·
Villejuif→Châtelet M7 21 min · La Défense→Nation RER A 19 min
(`test/core/real_routes_validation_test.dart`).

## Structure

```
lib/
├── core/                      # Cœur algo (testable sans UI, cf. graph_store)
│   ├── graph.dart             # ✅ Graphe + invariants de chargement
│   ├── graph_store.dart       # ✅ Singleton du graphe (découplé de main.dart)
│   ├── algorithms/
│   │   ├── shortest_path.dart # ✅ Dijkstra + A* + TransitRouter multi-source
│   │   ├── connectivity.dart  # ✅ BFS / composantes connexes
│   │   └── spanning_tree.dart # ✅ Prim (arborescence du réseau)
│   └── router_service.dart    # ✅ Résolution arrêts/adresses → itinéraires
├── data_pipeline/build_graph.dart # GTFS IDFM → assets/graph/idfm_graph.json
├── models/, screens/, widgets/, services/, theme.dart
test/core/                     # 55 tests : contrats, optimalité, admissibilité,
                               # cas limites, trajets réels, benchmark
```

## Données

- Source : GTFS [Île-de-France Mobilités](https://data.iledefrance-mobilites.fr)
  — licence ODbL (citée ici conformément à la licence).
- CO₂ : facteurs transilien.com / ADEME (voir `services/co2_service.dart`).
- Aucune donnée personnelle. Aucune clé API dans le dépôt.

## Équipe & contacts AO

Questions appel d'offres : olivier.girinsky@efrei.fr · stephany.rajeh@efrei.fr · badr.tajini@efrei.fr
