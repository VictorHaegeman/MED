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
  });

  // Suite ordonnée d'identifiants de nœuds, départ → arrivée.
  final List<String> path;
  final double totalSeconds;
  final int exploredNodes;
  final Duration computeTime;

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
  ShortestPathResult run(TransportGraph graph, String fromId, String toId);
}

// ------------------------------------------------------
//  Tas binaire min — implémenté à la main (exigence AO)
// ------------------------------------------------------

class _Entry {
  final String nodeId;
  final double dist;
  const _Entry(this.nodeId, this.dist);
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
  ShortestPathResult run(TransportGraph graph, String fromId, String toId) {
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
  // Vitesse max du réseau en m/s (métro ≈ 70 km/h en pointe).
  // Hypothèse documentée — voir §1.3 du plan projet.
  static const double maxSpeedMs = 19.4;

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
  ShortestPathResult run(TransportGraph graph, String fromId, String toId) {
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

    // g(n) = coût réel depuis la source
    final gScore = <String, double>{};
    final prev = <String, String?>{};
    for (final id in graph.nodes.keys) {
      gScore[id] = double.infinity;
      prev[id] = null;
    }
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
        final v = edge.to;
        final tentativeG = gU + edge.weightSeconds;
        if (tentativeG < (gScore[v] ?? double.infinity)) {
          gScore[v] = tentativeG;
          prev[v] = u;
          final vNode = graph.nodes[v];
          final h = vNode != null ? _heuristic(vNode, targetNode) : 0.0;
          heap.add(_Entry(v, tentativeG + h));
        }
      }
    }

    stopwatch.stop();

    final path = _reconstructPath(prev, fromId, toId);
    final total = gScore[toId] ?? double.infinity;

    return ShortestPathResult(
      path: path,
      totalSeconds: total.isInfinite ? 0 : total,
      exploredNodes: explored,
      computeTime: stopwatch.elapsed,
    );
  }
}
