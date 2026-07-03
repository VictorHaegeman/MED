/// Plus court chemin — Dijkstra (référence) et A* (optimisation).
///
/// Exigence AO : algorithmes implémentés À LA MAIN (pas de librairie de
/// graphes), adaptés au volume du réseau RATP — un Dijkstra naïf O(V²) est
/// éliminatoire. Cible : file de priorité (tas binaire), O((V+E) log V).
library;

import 'dart:math';
import '../graph.dart';

// ----------
//  Résultat
// ----------

// Résultat d'un calcul de plus court chemin, instrumenté pour les
// mesures de performance exigées par l'AO (temps, nœuds explorés).
class ShortestPathResult {
  const ShortestPathResult({
    required this.path,
    required this.totalSeconds,
    required this.exploredNodes,
    required this.computeTime,
    this.stepTypes = const [],
  });

  // Suite ordonnée d'identifiants de nœuds, départ → arrivée.
  final List<String> path;
  final double totalSeconds;
  final int exploredNodes;
  final Duration computeTime;

  // Type de l'arête RÉELLEMENT empruntée à chaque pas (path[i] → path[i+1]).
  // Longueur = path.length - 1. Indispensable pour distinguer un trajet
  // véhicule (ride) d'une marche (transfer) quand les deux arêtes coexistent.
  final List<EdgeType> stepTypes;

  // Nombre de correspondances (changement de ligne sur la même station).
  int get transfers {
    int t = 0;
    for (int i = 1; i < path.length; i++) {
      // Format des ids : "stationName#LIGNE" — ex: "chatelet#M1"
      final prevStation = path[i - 1].split('#').first;
      final currStation = path[i].split('#').first;
      final prevLine = path[i - 1].split('#').last;
      final currLine = path[i].split('#').last;
      if (prevStation == currStation && prevLine != currLine) t++;
    }
    return t;
  }

  String get formattedDuration {
    final m = totalSeconds ~/ 60;
    final s = (totalSeconds % 60).round();
    return s == 0 ? '${m}min' : '${m}min ${s}s';
  }

  // Chemin vide = pas de trajet trouvé.
  bool get found => path.isNotEmpty;
}

// --------------------------------------------------------------------------
//  Interface commune (permet de benchmarker Dijkstra vs A* à API identique)
// --------------------------------------------------------------------------

abstract interface class ShortestPathAlgorithm {
  String get name;
  ShortestPathResult run(
    TransportGraph graph,
    String fromId,
    String toId, {
    bool Function(Edge)? edgeFilter,
    double transferPenaltySecs = 0,
    Set<String>? penalizedEdges,
    double edgePenaltySecs = 0,
  });
}

// ------------------------------------------------------
//  Tas binaire min — implémenté à la main (exigence AO)
// ------------------------------------------------------

class _Entry {
  final String nodeId;
  final double dist;
  // État « à bord » (TransitRouter) : true si le nœud a été atteint via une
  // arête ride — rester dans le véhicule ne coûte pas d'attente.
  final bool onboard;
  // Coût réel g (TransitRouter) : dist porte f = g + h, g sert au lazy delete.
  final double g;
  const _Entry(this.nodeId, this.dist, {this.onboard = false, this.g = 0});
}

class _MinHeap {
  final _data = <_Entry>[];

  bool get isEmpty => _data.isEmpty;
  bool get isNotEmpty => _data.isNotEmpty;

  void add(_Entry e) {
    _data.add(e);
    _bubbleUp(_data.length - 1);
  }

  _Entry removeFirst() {
    final first = _data[0];
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _sinkDown(0);
    }
    return first;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_data[i].dist < _data[parent].dist) {
        final tmp = _data[i];
        _data[i] = _data[parent];
        _data[parent] = tmp;
        i = parent;
      } else {
        break;
      }
    }
  }

  void _sinkDown(int i) {
    final n = _data.length;
    while (true) {
      int smallest = i;
      final l = 2 * i + 1;
      final r = 2 * i + 2;
      if (l < n && _data[l].dist < _data[smallest].dist) smallest = l;
      if (r < n && _data[r].dist < _data[smallest].dist) smallest = r;
      if (smallest == i) break;
      final tmp = _data[i];
      _data[i] = _data[smallest];
      _data[smallest] = tmp;
      i = smallest;
    }
  }
}

// --------------------------------------------------------------
//  Utilitaire : reconstruction du chemin depuis la table prev[]
// --------------------------------------------------------------
List<String> _reconstructPath(
    Map<String, String?> prev, String fromId, String toId) {
  final path = <String>[];
  String? current = toId;
  while (current != null) {
    path.add(current);
    current = prev[current];
  }
  if (path.last != fromId) return []; // pas de chemin
  return path.reversed.toList();
}

// -------------------------------------------------
//  Dijkstra — O((V+E) log V) avec tas binaire min
// -------------------------------------------------
class Dijkstra implements ShortestPathAlgorithm {
  @override
  String get name => 'Dijkstra (tas binaire)';

  @override
  ShortestPathResult run(
    TransportGraph graph,
    String fromId,
    String toId, {
    bool Function(Edge)? edgeFilter,
    double transferPenaltySecs = 0,
    Set<String>? penalizedEdges,
    double edgePenaltySecs = 0,
  }) {
    final stopwatch = Stopwatch()..start();

    // Cas limite : départ == arrivée
    if (fromId == toId) {
      stopwatch.stop();
      return ShortestPathResult(
        path: [fromId],
        totalSeconds: 0,
        exploredNodes: 0,
        computeTime: stopwatch.elapsed,
      );
    }

    // Cas limite : nœud inexistant
    if (!graph.nodes.containsKey(fromId) ||
        !graph.nodes.containsKey(toId)) {
      stopwatch.stop();
      return ShortestPathResult(
        path: [],
        totalSeconds: 0,
        exploredNodes: 0,
        computeTime: stopwatch.elapsed,
      );
    }

    // Initialisation : dist[] = +inf, sauf source = 0
    final dist = <String, double>{};
    final prev = <String, String?>{};
    for (final id in graph.nodes.keys) {
      dist[id] = double.infinity;
      prev[id] = null;
    }
    dist[fromId] = 0;

    final heap = _MinHeap();
    heap.add(_Entry(fromId, 0));
    int explored = 0;

    while (heap.isNotEmpty) {
      final entry = heap.removeFirst();
      final u = entry.nodeId;
      final dU = entry.dist;

      // Entrée périmée (lazy deletion)
      if (dU > (dist[u] ?? double.infinity)) continue;

      explored++;

      // Early exit : on a atteint la destination
      if (u == toId) break;

      // Relaxation des arêtes sortantes
      for (final edge in graph.neighbors(u)) {
        if (edgeFilter != null && !edgeFilter(edge)) continue;
        final v = edge.to;
        final newDist = dU + edge.weightSeconds;
        if (newDist < (dist[v] ?? double.infinity)) {
          dist[v] = newDist;
          prev[v] = u;
          heap.add(_Entry(v, newDist));
        }
      }
    }

    stopwatch.stop();

    final path = _reconstructPath(prev, fromId, toId);
    final total = dist[toId] ?? double.infinity;

    return ShortestPathResult(
      path: path,
      totalSeconds: total.isInfinite ? 0 : total,
      exploredNodes: explored,
      computeTime: stopwatch.elapsed,
    );
  }
}

// -------------------------------------------------------------------------
//  A* — heuristique géodésique (distance haversine / vitesse max réseau)
//  Heuristique ADMISSIBLE → optimalité conservée, espace exploré réduit
// -------------------------------------------------------------------------

class AStar implements ShortestPathAlgorithm {
  // Vitesse max du réseau en m/s — partagée avec le plancher de vitesse
  // appliqué aux arêtes au chargement (TransportGraph.maxSpeedMs), ce qui
  // garantit h(n) ≤ coût réel pour TOUTE arête. L'ancienne valeur (19,4 m/s
  // ≈ 70 km/h) était dépassée par 863 arêtes réelles (RER/Transilien jusqu'à
  // 112 km/h) → heuristique inadmissible → chemins sous-optimaux.
  static const double maxSpeedMs = TransportGraph.maxSpeedMs;

  @override
  String get name => 'A* (heuristique géodésique)';

  // Distance haversine en mètres entre deux coordonnées GPS.
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0; // rayon Terre en mètres
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // h(n) = distance_haversine(n, arrivée) / vitesse_max  [en secondes]
  // Toujours ≤ coût réel → admissible.
  double _heuristic(GraphNode from, GraphNode to) {
    return _haversine(from.lat, from.lon, to.lat, to.lon) / maxSpeedMs;
  }

  @override
  ShortestPathResult run(
    TransportGraph graph,
    String fromId,
    String toId, {
    bool Function(Edge)? edgeFilter,
    double transferPenaltySecs = 0,
    Set<String>? penalizedEdges,
    double edgePenaltySecs = 0,
  }) {
    final stopwatch = Stopwatch()..start();

    // Cas limites identiques à Dijkstra
    if (fromId == toId) {
      stopwatch.stop();
      return ShortestPathResult(
        path: [fromId],
        totalSeconds: 0,
        exploredNodes: 0,
        computeTime: stopwatch.elapsed,
      );
    }
    if (!graph.nodes.containsKey(fromId) ||
        !graph.nodes.containsKey(toId)) {
      stopwatch.stop();
      return ShortestPathResult(
        path: [],
        totalSeconds: 0,
        exploredNodes: 0,
        computeTime: stopwatch.elapsed,
      );
    }

    final targetNode = graph.nodes[toId]!;

    // g(n) = coût réel depuis la source. Cartes lazy (pas de pré-remplissage
    // sur les ~43 000 nœuds — l'absence de clé vaut +∞), crucial pour la perf.
    final gScore = <String, double>{};
    final prev = <String, String?>{};
    final prevEdgeType = <String, EdgeType>{}; // arête empruntée pour atteindre v
    gScore[fromId] = 0;

    // File de priorité sur f(n) = g(n) + h(n)
    final heap = _MinHeap();
    final startNode = graph.nodes[fromId]!;
    heap.add(_Entry(fromId, _heuristic(startNode, targetNode)));
    int explored = 0;

    while (heap.isNotEmpty) {
      final entry = heap.removeFirst();
      final u = entry.nodeId;

      explored++;

      if (u == toId) break;

      final gU = gScore[u] ?? double.infinity;

      for (final edge in graph.neighbors(u)) {
        if (edgeFilter != null && !edgeFilter(edge)) continue;
        final v = edge.to;
        final penalty =
            transferPenaltySecs > 0 && edge.type == EdgeType.transfer
                ? transferPenaltySecs
                : 0.0;
        // Pénalité d'arête : force un détour pour générer des itinéraires
        // alternatifs distincts (approche "plateau"/edge-penalty).
        final edgePen = (edgePenaltySecs > 0 &&
                penalizedEdges != null &&
                penalizedEdges.contains('$u|$v'))
            ? edgePenaltySecs
            : 0.0;
        final tentativeG = gU + edge.weightSeconds + penalty + edgePen;
        if (tentativeG < (gScore[v] ?? double.infinity)) {
          gScore[v] = tentativeG;
          prev[v] = u;
          prevEdgeType[v] = edge.type;
          final vNode = graph.nodes[v];
          final h = vNode != null ? _heuristic(vNode, targetNode) : 0.0;
          heap.add(_Entry(v, tentativeG + h));
        }
      }
    }

    stopwatch.stop();

    final path = _reconstructPath(prev, fromId, toId);
    final total = gScore[toId] ?? double.infinity;

    // Type d'arête réellement empruntée pour chaque pas du chemin.
    final stepTypes = <EdgeType>[];
    for (int i = 0; i + 1 < path.length; i++) {
      stepTypes.add(prevEdgeType[path[i + 1]] ?? EdgeType.transfer);
    }

    return ShortestPathResult(
      path: path,
      totalSeconds: total.isInfinite ? 0 : total,
      exploredNodes: explored,
      computeTime: stopwatch.elapsed,
      stepTypes: stepTypes,
    );
  }
}

// ---------------------------------------------------------------------------
//  TransitRouter — A* multi-source / multi-cible avec état « à bord »
//
//  Une requête utilisateur = UN SEUL passage A*, quel que soit le nombre de
//  nœuds de départ/arrivée (l'ancien code lançait un A* par PAIRE de nœuds :
//  jusqu'à des centaines de milliers de runs pour des arrêts très dupliqués).
//
//  Modélise aussi l'attente d'embarquement (demi-intervalle de passage) :
//  monter dans un véhicule coûte du temps d'attente, rester à bord non.
//  État = (nœud, à bord ?) — 2 labels par nœud, optimalité conservée.
// ---------------------------------------------------------------------------

/// Attente moyenne d'embarquement par routeType (≈ demi-intervalle de
/// passage en journée) : 0=tram, 1=métro, 2=RER/Transilien, 3=bus.
/// C'est ce qui rend les durées réalistes : sans elle, enchaîner 4 bus
/// paraît « gratuit » et bat systématiquement le métro direct.
const Map<int, double> kBoardingWaitSecs = {
  0: 210, // tram — passage ~7 min
  1: 120, // métro — passage ~4 min
  2: 240, // RER/Transilien — passage ~8 min
  3: 360, // bus — passage ~12 min
};
const double kDefaultBoardingWaitSecs = 240;

class TransitRouter {
  /// [sources] : nœud de départ → coût initial (marche d'approche, s).
  /// [targets] : nœud d'arrivée → coût final (marche de sortie, s).
  /// [maxCostSecs] : abandon anticipé si aucune solution sous ce budget —
  /// évite d'explorer tout le graphe pour une alternative qu'on rejettera.
  /// Le résultat inclut ces coûts et les attentes d'embarquement.
  ShortestPathResult route(
    TransportGraph graph, {
    required Map<String, double> sources,
    required Map<String, double> targets,
    bool Function(Edge)? edgeFilter,
    double transferPenaltySecs = 0,
    Set<String>? penalizedEdges,
    double edgePenaltySecs = 0,
    bool boardingWaits = true,
    double maxCostSecs = double.infinity,
  }) {
    final stopwatch = Stopwatch()..start();

    ShortestPathResult empty() {
      stopwatch.stop();
      return ShortestPathResult(
        path: const [],
        totalSeconds: 0,
        exploredNodes: 0,
        computeTime: stopwatch.elapsed,
      );
    }

    final srcs = <String, double>{
      for (final e in sources.entries)
        if (graph.nodes.containsKey(e.key)) e.key: e.value
    };
    final tgts = <String, double>{
      for (final e in targets.entries)
        if (graph.nodes.containsKey(e.key)) e.key: e.value
    };
    if (srcs.isEmpty || tgts.isEmpty) return empty();

    // --- Heuristique multi-cible admissible ---
    // h(n) = max(0, d(n, centroïde_cibles) − rayon) / vitesse_max.
    // Minorant de d(n, cible) pour toute cible (inégalité triangulaire),
    // et le plancher de vitesse du graphe garantit h ≤ coût réel.
    double cLat = 0, cLon = 0;
    for (final id in tgts.keys) {
      final n = graph.nodes[id]!;
      cLat += n.lat;
      cLon += n.lon;
    }
    cLat /= tgts.length;
    cLon /= tgts.length;
    double radiusM = 0;
    for (final id in tgts.keys) {
      final n = graph.nodes[id]!;
      final d = AStar._haversine(cLat, cLon, n.lat, n.lon);
      if (d > radiusM) radiusM = d;
    }
    double h(GraphNode n) {
      final d = AStar._haversine(n.lat, n.lon, cLat, cLon) - radiusM;
      return d > 0 ? d / TransportGraph.maxSpeedMs : 0;
    }

    // --- 2 labels par nœud : atteint à pied / atteint à bord ---
    final gWalk = <String, double>{};
    final gRide = <String, double>{};
    // prev[état] = (nœud précédent, état précédent à bord ?, type d'arête)
    final prevWalk = <String, (String, bool, EdgeType)>{};
    final prevRide = <String, (String, bool, EdgeType)>{};

    final heap = _MinHeap();

    double bestFinal = double.infinity;
    String? bestNode;
    bool bestOnboard = false;

    void considerTarget(String id, bool onboard, double g) {
      final extra = tgts[id];
      if (extra != null && g + extra < bestFinal) {
        bestFinal = g + extra;
        bestNode = id;
        bestOnboard = onboard;
      }
    }

    for (final e in srcs.entries) {
      final existing = gWalk[e.key];
      if (existing != null && existing <= e.value) continue;
      gWalk[e.key] = e.value;
      heap.add(_Entry(e.key, e.value + h(graph.nodes[e.key]!),
          onboard: false, g: e.value));
      considerTarget(e.key, false, e.value);
    }

    int explored = 0;
    while (heap.isNotEmpty) {
      final entry = heap.removeFirst();
      // f = g + h est un minorant du coût final de toute solution passant
      // par cette entrée : si f ≥ meilleure solution connue (ou dépasse le
      // budget), terminé.
      if (entry.dist >= bestFinal || entry.dist > maxCostSecs) break;
      final u = entry.nodeId;
      final uOnboard = entry.onboard;
      final gU = uOnboard ? gRide[u] : gWalk[u];
      if (gU == null || entry.g > gU) continue; // entrée périmée
      explored++;

      for (final edge in graph.neighbors(u)) {
        if (edgeFilter != null && !edgeFilter(edge)) continue;
        double w = edge.weightSeconds;
        final bool vOnboard;
        if (edge.type == EdgeType.ride) {
          vOnboard = true;
          // Embarquement : on n'était pas à bord → attente du véhicule.
          if (boardingWaits && !uOnboard) {
            w += kBoardingWaitSecs[graph.nodes[u]?.routeType] ??
                kDefaultBoardingWaitSecs;
          }
        } else {
          vOnboard = false;
          if (transferPenaltySecs > 0 && edge.type == EdgeType.transfer) {
            w += transferPenaltySecs;
          }
        }
        if (edgePenaltySecs > 0 &&
            penalizedEdges != null &&
            penalizedEdges.contains('$u|${edge.to}')) {
          w += edgePenaltySecs;
        }
        final v = edge.to;
        final gV = gU + w;
        final gMap = vOnboard ? gRide : gWalk;
        if (gV < (gMap[v] ?? double.infinity)) {
          gMap[v] = gV;
          (vOnboard ? prevRide : prevWalk)[v] = (u, uOnboard, edge.type);
          final vNode = graph.nodes[v];
          final f = gV + (vNode != null ? h(vNode) : 0.0);
          if (f < bestFinal) {
            heap.add(_Entry(v, f, onboard: vOnboard, g: gV));
          }
          considerTarget(v, vOnboard, gV);
        }
      }
    }

    stopwatch.stop();
    if (bestNode == null || bestFinal > maxCostSecs) return empty();

    // --- Reconstruction : chaîne d'états → chemin + types d'arête ---
    final path = <String>[bestNode!];
    final stepTypes = <EdgeType>[];
    var cur = bestNode!;
    var curOnboard = bestOnboard;
    while (true) {
      final p = (curOnboard ? prevRide : prevWalk)[cur];
      if (p == null) break; // remonté jusqu'à une source
      path.add(p.$1);
      stepTypes.add(p.$3);
      cur = p.$1;
      curOnboard = p.$2;
    }

    return ShortestPathResult(
      path: path.reversed.toList(),
      totalSeconds: bestFinal,
      exploredNodes: explored,
      computeTime: stopwatch.elapsed,
      stepTypes: stepTypes.reversed.toList(),
    );
  }
}
