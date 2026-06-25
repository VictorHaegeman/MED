/// Service d'itinéraires — point de jonction entre l'UI et le cœur algo.
library;

import 'dart:math';
import 'dart:ui' show Color;

import '../main.dart' show appGraph;
import '../models/itinerary.dart';
import '../models/search_result.dart';
import 'algorithms/shortest_path.dart';
import 'graph.dart';

class RouterService {
  /// Vitesse de marche : 5 km/h = 1.389 m/s
  static const _walkMps = 1.389;

  Future<List<Itinerary>> findItineraries(
      SearchResult from, SearchResult to) async {
    final g = appGraph;

    // Résolution : si c'est une adresse, on trouve la station la plus proche.
    final (fromIds, fromWalkSecs) = _resolveSource(g, from);
    final (toIds, toWalkSecs) = _resolveSource(g, to);

    if (fromIds.isEmpty || toIds.isEmpty) return [];

    final results = <Itinerary>[];

    // --- Route 1 : le plus rapide (tous modes) ---
    final best = _bestPath(g, fromIds, toIds);
    if (best != null && best.found) {
      results.add(_toItinerary(
        g,
        best,
        tag: 'LE PLUS RAPIDE',
        tagColor: const Color(0xFF3B82F6),
        highlighted: true,
        from: from,
        to: to,
        fromWalkSecs: fromWalkSecs,
        toWalkSecs: toWalkSecs,
      ));
    }

    // --- Route 2 : métro + RER uniquement ---
    final metroFilter = _metroRerFilter(g);
    final metroResult = _bestPath(g, fromIds, toIds, edgeFilter: metroFilter);
    if (metroResult != null &&
        metroResult.found &&
        (results.isEmpty ||
            metroResult.path.join() != results.first.pathNodeIds.join())) {
      results.add(_toItinerary(
        g,
        metroResult,
        tag: 'MÉTRO + RER',
        tagColor: const Color(0xFF8B5CF6),
        highlighted: false,
        from: from,
        to: to,
        fromWalkSecs: fromWalkSecs,
        toWalkSecs: toWalkSecs,
      ));
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Résolution d'une SearchResult → liste de node IDs + temps de marche (s)
  // ---------------------------------------------------------------------------

  (List<String>, double) _resolveSource(TransportGraph g, SearchResult src) {
    if (!src.isAddress) {
      return (_nodeIdsForName(g, src.displayName), 0);
    }
    // Adresse → station la plus proche
    final nearest = _nearestNode(g, src.lat!, src.lon!);
    if (nearest == null) return ([], 0);
    final distM = _haversine(src.lat!, src.lon!, nearest.lat, nearest.lon);
    final walkSecs = distM / _walkMps;
    return (_nodeIdsForName(g, nearest.stationName), walkSecs);
  }

  GraphNode? _nearestNode(TransportGraph g, double lat, double lon) {
    GraphNode? best;
    double minD = double.infinity;
    final seen = <String>{};
    for (final n in g.nodes.values) {
      if (!seen.add(n.stationName)) continue;
      final d = _haversine(lat, lon, n.lat, n.lon);
      if (d < minD) {
        minD = d;
        best = n;
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------

  List<String> _nodeIdsForName(TransportGraph g, String stationName) {
    final lower = stationName.toLowerCase().trim();
    return g.nodes.values
        .where((n) => n.stationName.toLowerCase() == lower)
        .map((n) => n.id)
        .toList();
  }

  ShortestPathResult? _bestPath(
    TransportGraph g,
    List<String> fromIds,
    List<String> toIds, {
    bool Function(Edge)? edgeFilter,
  }) {
    final algo = AStar();
    ShortestPathResult? best;
    for (final f in fromIds) {
      for (final t in toIds) {
        final r = algo.run(g, f, t, edgeFilter: edgeFilter);
        if (r.found && (best == null || r.totalSeconds < best.totalSeconds)) {
          best = r;
        }
      }
    }
    return best;
  }

  /// Filtre : métro (routeType 1) + RER (routeType 2) + correspondances.
  bool Function(Edge) _metroRerFilter(TransportGraph g) {
    return (Edge edge) {
      if (edge.type == EdgeType.transfer) return true;
      if (edge.type == EdgeType.walk) return false;
      final routeType = g.nodes[edge.from]?.routeType;
      return routeType == 1 || routeType == 2;
    };
  }

  // ---------------------------------------------------------------------------
  // Conversion ShortestPathResult → Itinerary
  // ---------------------------------------------------------------------------

  Itinerary _toItinerary(
    TransportGraph g,
    ShortestPathResult result, {
    required String tag,
    required Color tagColor,
    required bool highlighted,
    required SearchResult from,
    required SearchResult to,
    required double fromWalkSecs,
    required double toWalkSecs,
  }) {
    final coreLeg = _buildLegs(g, result.path);
    final legs = <Leg>[];

    if (from.isAddress && fromWalkSecs > 0) {
      final mins = (fromWalkSecs / 60).ceil().clamp(1, 999);
      legs.add(WalkLeg(
        label: '$mins min à pied',
        subtitle: 'Depuis ${from.displayName}',
      ));
    }

    legs.addAll(coreLeg);

    if (to.isAddress && toWalkSecs > 0) {
      final mins = (toWalkSecs / 60).ceil().clamp(1, 999);
      legs.add(WalkLeg(
        label: '$mins min à pied',
        subtitle: 'Vers ${to.displayName}',
      ));
    }

    final modes = legs.whereType<RideLeg>().map((r) => r.mode).toSet();
    final totalSecs = result.totalSeconds + fromWalkSecs + toWalkSecs;
    final transfers = result.transfers;
    final mins = (totalSecs / 60).round();
    final durationLabel = mins >= 60
        ? '${mins ~/ 60} h ${(mins % 60).toString().padLeft(2, '0')}'
        : '$mins min';

    final walkMinTotal = ((fromWalkSecs + toWalkSecs) / 60).round();
    final walkLabel =
        walkMinTotal > 0 ? '$walkMinTotal min à pied' : '0 min à pied';

    final co2 = _co2Label(modes);
    final perfNote = '⚡ Calculé en ${result.computeTime.inMilliseconds} ms'
        ' — A* · ${result.exploredNodes} nœuds explorés';

    return Itinerary(
      tag: tag,
      tagColor: tagColor,
      durationLabel: durationLabel,
      detail: '$transfers correspondance${transfers != 1 ? 's' : ''}',
      walkLabel: walkLabel,
      co2Label: co2,
      modes: modes.isEmpty ? {TransportMode.metro} : modes,
      legs: legs,
      summary:
          '$durationLabel · $transfers correspondance${transfers != 1 ? 's' : ''} · $co2',
      perfNote: perfNote,
      pathNodeIds: result.path,
      totalSeconds: totalSecs,
      highlighted: highlighted,
      fromLat: from.isAddress ? from.lat : null,
      fromLon: from.isAddress ? from.lon : null,
      toLat: to.isAddress ? to.lat : null,
      toLon: to.isAddress ? to.lon : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Construction des legs depuis le chemin
  // ---------------------------------------------------------------------------

  List<Leg> _buildLegs(TransportGraph g, List<String> path) {
    if (path.isEmpty) return [];
    final legs = <Leg>[];

    final firstNode = g.nodes[path.first]!;
    legs.add(StationPoint(
      name: firstNode.stationName,
      subtitle: 'Départ',
      color: _colorFromHex(firstNode.lineColor),
    ));

    int segStart = 0;
    for (int i = 1; i <= path.length; i++) {
      final prevNode = g.nodes[path[i - 1]];
      if (prevNode == null) continue;
      final currentLine = prevNode.line;
      final nextLine = i < path.length ? g.nodes[path[i]]?.line : null;

      if (i == path.length || nextLine != currentLine) {
        final segNodes = path
            .sublist(segStart, i)
            .map((id) => g.nodes[id])
            .whereType<GraphNode>()
            .toList();

        final uniqueStations =
            segNodes.map((n) => n.stationName).toSet().length;
        final stopCount = uniqueStations > 1 ? uniqueStations - 1 : 1;
        final direction = _headsignFor(g, path, segStart);

        legs.add(RideLeg(
          mode: _modeFromRouteType(prevNode.routeType),
          lineLabel: prevNode.lineShortName ?? '?',
          lineColor: _colorFromHex(prevNode.lineColor),
          darkText: _isDarkText(prevNode.lineColor),
          direction: direction,
          subtitle: '$stopCount arrêt${stopCount > 1 ? 's' : ''}',
        ));

        if (i < path.length) {
          final nextNode = g.nodes[path[i]]!;
          final isTransfer = (prevNode.stationName == nextNode.stationName);
          legs.add(StationPoint(
            name: prevNode.stationName,
            subtitle: isTransfer ? 'Correspondance' : 'Arrivée',
            color: _colorFromHex(prevNode.lineColor),
          ));
          segStart = i;
        }
      }
    }

    final lastNode = g.nodes[path.last]!;
    legs.add(StationPoint(
      name: lastNode.stationName,
      subtitle: 'Arrivée',
      color: _colorFromHex(lastNode.lineColor),
    ));

    return legs;
  }

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF475774);
    final value = int.tryParse(hex.padLeft(6, '0'), radix: 16);
    if (value == null) return const Color(0xFF475774);
    return Color(0xFF000000 | value);
  }

  bool _isDarkText(String? hex) {
    if (hex == null || hex.isEmpty) return false;
    final c = int.tryParse(hex.padLeft(6, '0'), radix: 16) ?? 0;
    final lum = 0.299 * ((c >> 16) & 0xFF) +
        0.587 * ((c >> 8) & 0xFF) +
        0.114 * (c & 0xFF);
    return lum > 160;
  }

  TransportMode _modeFromRouteType(int? routeType) {
    return switch (routeType) {
      0 => TransportMode.tram,
      1 => TransportMode.metro,
      2 => TransportMode.bus,
      3 => TransportMode.bus,
      _ => TransportMode.metro,
    };
  }

  String _headsignFor(TransportGraph g, List<String> path, int segStart) {
    if (segStart >= path.length - 1) return '';
    final edges = g.neighbors(path[segStart]);
    final nextId = path[segStart + 1];
    for (final e in edges) {
      if (e.to == nextId && e.type == EdgeType.ride && e.headsign != null) {
        return 'Direction ${e.headsign}';
      }
    }
    return '';
  }

  String _co2Label(Set<TransportMode> modes) {
    if (modes.isEmpty || modes.every((m) => m == TransportMode.walk)) {
      return '−100% CO₂';
    }
    if (modes.contains(TransportMode.metro)) return '−75% CO₂';
    if (modes.contains(TransportMode.tram)) return '−80% CO₂';
    if (modes.contains(TransportMode.bus)) return '−60% CO₂';
    return '−70% CO₂';
  }
}
