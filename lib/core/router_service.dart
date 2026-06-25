/// Service d'itinéraires — point de jonction entre l'UI et le cœur algo.
library;

import 'dart:ui' show Color;

import '../main.dart' show appGraph;
import '../models/itinerary.dart';
import 'algorithms/shortest_path.dart';
import 'graph.dart';

class RouterService {
  /// Recherche le meilleur itinéraire entre deux noms de stations.
  Future<List<Itinerary>> findItineraries(String from, String to) async {
    final g = appGraph;
    final fromIds = _nodeIdsForName(g, from);
    final toIds = _nodeIdsForName(g, to);

    if (fromIds.isEmpty || toIds.isEmpty) return [];

    final result = _bestPath(g, fromIds, toIds);
    if (result == null || !result.found) return [];

    return [
      _toItinerary(g, result,
          tag: 'LE PLUS RAPIDE',
          tagColor: const Color(0xFF3B82F6),
          highlighted: true),
    ];
  }

  // ---------------------------------------------------------------------------
  // Recherche de nœuds par nom de station (multi-source)
  // ---------------------------------------------------------------------------

  List<String> _nodeIdsForName(TransportGraph g, String stationName) {
    final lower = stationName.toLowerCase().trim();
    return g.nodes.values
        .where((n) => n.stationName.toLowerCase() == lower)
        .map((n) => n.id)
        .toList();
  }

  // Lance A* depuis chaque paire (source, destination) et garde le meilleur.
  ShortestPathResult? _bestPath(
      TransportGraph g, List<String> fromIds, List<String> toIds) {
    final algo = AStar();
    ShortestPathResult? best;
    for (final f in fromIds) {
      for (final t in toIds) {
        final r = algo.run(g, f, t);
        if (r.found && (best == null || r.totalSeconds < best.totalSeconds)) {
          best = r;
        }
      }
    }
    return best;
  }

  // ---------------------------------------------------------------------------
  // Conversion ShortestPathResult → Itinerary
  // ---------------------------------------------------------------------------

  Itinerary _toItinerary(
    TransportGraph g,
    ShortestPathResult result, {
    required String tag,
    required Color tagColor,
    bool highlighted = false,
  }) {
    final legs = _buildLegs(g, result.path);
    final modes = legs.whereType<RideLeg>().map((r) => r.mode).toSet();
    final transfers = result.transfers;
    final mins = (result.totalSeconds / 60).round();

    final durationLabel = mins >= 60
        ? '${mins ~/ 60} h ${(mins % 60).toString().padLeft(2, '0')}'
        : '$mins min';

    final co2 = _co2Label(modes);
    final perfNote =
        '⚡ Calculé en ${result.computeTime.inMilliseconds} ms'
        ' — A* · ${result.exploredNodes} nœuds explorés';

    return Itinerary(
      tag: tag,
      tagColor: tagColor,
      durationLabel: durationLabel,
      detail: '$transfers correspondance${transfers != 1 ? 's' : ''}',
      walkLabel: '0 min à pied',
      co2Label: co2,
      modes: modes.isEmpty ? {TransportMode.metro} : modes,
      legs: legs,
      summary: '$durationLabel · $transfers correspondance${transfers != 1 ? 's' : ''} · $co2',
      perfNote: perfNote,
      pathNodeIds: result.path,
      totalSeconds: result.totalSeconds,
      highlighted: highlighted,
    );
  }

  // ---------------------------------------------------------------------------
  // Construction des legs depuis le chemin (liste d'IDs de nœuds)
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
        // Émet un RideLeg pour le segment [segStart .. i-1]
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
          final prevStation = prevNode.stationName;
          final isTransfer = (prevStation == nextNode.stationName);
          legs.add(StationPoint(
            name: prevNode.stationName,
            subtitle: isTransfer ? 'Correspondance' : 'Arrivée',
            color: _colorFromHex(prevNode.lineColor),
          ));
          segStart = i;
        }
      }
    }

    // Station d'arrivée finale
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

  /// Hex sans `#` (ex: "D2D200") → Flutter Color.
  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF475774);
    final value = int.tryParse(hex.padLeft(6, '0'), radix: 16);
    if (value == null) return const Color(0xFF475774);
    return Color(0xFF000000 | value);
  }

  /// Détermine si le texte du badge doit être sombre (fond clair) ou clair.
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
      2 => TransportMode.bus, // RER affiché comme bus (pas de mode dédié)
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
