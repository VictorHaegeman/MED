/// Service d'itinéraires — point de jonction entre l'UI et le cœur algo.
library;

import 'dart:math';
import 'dart:ui' show Color;

import '../main.dart' show appGraph;
import '../models/itinerary.dart';
import '../models/search_result.dart';
import '../services/co2_service.dart';
import 'algorithms/shortest_path.dart';
import 'graph.dart';

class RouterService {
  static const _walkMps = 1.389; // 5 km/h

  /// [modeFilter] null = tous les modes (retourne jusqu'à 3 variantes).
  /// Sinon, retourne uniquement les routes utilisant ce mode.
  Future<List<Itinerary>> findItineraries(
    SearchResult from,
    SearchResult to, {
    TransportMode? modeFilter,
  }) async {
    final g = appGraph;
    final (fromIds, fromWalkSecs) = _resolveSource(g, from);
    final (toIds, toWalkSecs) = _resolveSource(g, to);
    if (fromIds.isEmpty || toIds.isEmpty) return [];

    final results = <Itinerary>[];

    if (modeFilter == null) {
      // --- 3 variantes : rapide, moins de correspondances, métro+RER ---

      // 1. Le plus rapide (tous modes)
      final r1 = _bestPath(g, fromIds, toIds);
      if (r1 != null && r1.found) {
        results.add(_toItinerary(g, r1,
            tag: 'LE PLUS RAPIDE',
            tagColor: const Color(0xFF3B82F6),
            highlighted: true,
            from: from, to: to,
            fromWalkSecs: fromWalkSecs, toWalkSecs: toWalkSecs));
      }

      // 2. Moins de correspondances (pénalité 7 min par transfert)
      final r2 = _bestPath(g, fromIds, toIds, transferPenaltySecs: 420);
      if (r2 != null && r2.found && !_isDuplicate(r2, results)) {
        results.add(_toItinerary(g, r2,
            tag: 'MOINS DE CORRESPONDANCES',
            tagColor: const Color(0xFF10B981),
            highlighted: false,
            from: from, to: to,
            fromWalkSecs: fromWalkSecs, toWalkSecs: toWalkSecs));
      }

      // 3. Métro + RER uniquement
      final r3 = _bestPath(g, fromIds, toIds,
          edgeFilter: _filterForMode(g, TransportMode.metro));
      if (r3 != null && r3.found && !_isDuplicate(r3, results)) {
        results.add(_toItinerary(g, r3,
            tag: 'MÉTRO + RER',
            tagColor: const Color(0xFF8B5CF6),
            highlighted: false,
            from: from, to: to,
            fromWalkSecs: fromWalkSecs, toWalkSecs: toWalkSecs));
      }
    } else {
      // --- Mode filtré : jusqu'à 3 chemins DISTINCTS en mode pur ---
      final filter = _filterForMode(g, modeFilter);
      final paths = _distinctPaths(g, fromIds, toIds,
          edgeFilter: filter, count: 3);

      if (paths.isNotEmpty) {
        final modeColor = _colorForMode(modeFilter);
        const labels = ['LE PLUS RAPIDE', 'ALTERNATIVE 1', 'ALTERNATIVE 2'];
        for (int i = 0; i < paths.length; i++) {
          final prefix = _tagForMode(modeFilter);
          results.add(_toItinerary(g, paths[i],
              tag: '$prefix · ${labels[i]}',
              tagColor: modeColor,
              highlighted: i == 0,
              from: from, to: to,
              fromWalkSecs: fromWalkSecs, toWalkSecs: toWalkSecs));
        }
      } else {
        // --- Fallback : aucun trajet 100 % en mode pur ---
        // On complète avec les autres moyens (itinéraire combiné).
        final combined = _bestPath(g, fromIds, toIds);
        if (combined != null && combined.found) {
          results.add(_toItinerary(g, combined,
              tag: 'COMBINÉ · ${_tagForMode(modeFilter)} SEUL IMPOSSIBLE',
              tagColor: const Color(0xFFF59E0B),
              highlighted: true,
              from: from, to: to,
              fromWalkSecs: fromWalkSecs, toWalkSecs: toWalkSecs));
        }
      }
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Filtres par mode
  // ---------------------------------------------------------------------------

  bool Function(Edge) _filterForMode(TransportGraph g, TransportMode mode) {
    return (Edge edge) {
      if (edge.type == EdgeType.transfer) return true;
      if (edge.type == EdgeType.walk) return false;
      final rt = g.nodes[edge.from]?.routeType;
      return switch (mode) {
        TransportMode.metro => rt == 1 || rt == 2, // métro + RER
        TransportMode.tram => rt == 0,
        TransportMode.bus => rt == 3,
        TransportMode.walk => false,
      };
    };
  }

  String _tagForMode(TransportMode mode) => switch (mode) {
        TransportMode.metro => 'MÉTRO + RER',
        TransportMode.tram => 'TRAM UNIQUEMENT',
        TransportMode.bus => 'BUS UNIQUEMENT',
        TransportMode.walk => 'À PIED',
      };

  Color _colorForMode(TransportMode mode) => switch (mode) {
        TransportMode.metro => const Color(0xFF8B5CF6),
        TransportMode.tram => const Color(0xFF14B8A6),
        TransportMode.bus => const Color(0xFFF59E0B),
        TransportMode.walk => const Color(0xFF6B7280),
      };

  // ---------------------------------------------------------------------------
  // Résolution SearchResult → node IDs + marche
  // ---------------------------------------------------------------------------

  (List<String>, double) _resolveSource(TransportGraph g, SearchResult src) {
    if (!src.isAddress) return (_nodeIdsForName(g, src.displayName), 0);
    final nearest = _nearestNode(g, src.lat!, src.lon!);
    if (nearest == null) return ([], 0);
    final distM = _haversine(src.lat!, src.lon!, nearest.lat, nearest.lon);
    return (_nodeIdsForName(g, nearest.stationName), distM / _walkMps);
  }

  GraphNode? _nearestNode(TransportGraph g, double lat, double lon) {
    GraphNode? best;
    double minD = double.infinity;
    final seen = <String>{};
    for (final n in g.nodes.values) {
      if (!seen.add(n.stationName)) continue;
      final d = _haversine(lat, lon, n.lat, n.lon);
      if (d < minD) { minD = d; best = n; }
    }
    return best;
  }

  List<String> _nodeIdsForName(TransportGraph g, String name) {
    final lower = name.toLowerCase().trim();
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
    double transferPenaltySecs = 0,
    Set<String>? penalizedEdges,
    double edgePenaltySecs = 0,
  }) {
    final algo = AStar();
    ShortestPathResult? best;
    for (final f in fromIds) {
      for (final t in toIds) {
        final r = algo.run(g, f, t,
            edgeFilter: edgeFilter,
            transferPenaltySecs: transferPenaltySecs,
            penalizedEdges: penalizedEdges,
            edgePenaltySecs: edgePenaltySecs);
        if (r.found && (best == null || r.totalSeconds < best.totalSeconds)) {
          best = r;
        }
      }
    }
    return best;
  }

  /// Génère jusqu'à [count] chemins DISTINCTS via la méthode edge-penalty :
  /// on pénalise les arêtes du chemin précédent pour forcer un détour.
  List<ShortestPathResult> _distinctPaths(
    TransportGraph g,
    List<String> fromIds,
    List<String> toIds, {
    bool Function(Edge)? edgeFilter,
    int count = 3,
  }) {
    final results = <ShortestPathResult>[];
    final penalized = <String>{};
    final seenKeys = <String>{};

    for (int k = 0; k < count; k++) {
      // 1er chemin : le plus rapide. Suivants : détour forcé (+300 s/arête).
      final r = _bestPath(
        g, fromIds, toIds,
        edgeFilter: edgeFilter,
        penalizedEdges: k == 0 ? null : penalized,
        edgePenaltySecs: k == 0 ? 0 : 300,
      );
      if (r == null || !r.found) break;
      final key = r.path.join('|');
      if (!seenKeys.add(key)) break; // plus d'alternative distincte
      // Écarte les alternatives peu compétitives (> 1,3× le plus rapide) :
      // mieux vaut 1 seule option propre qu'un détour absurde.
      if (results.isNotEmpty &&
          r.totalSeconds > results.first.totalSeconds * 1.3) {
        break;
      }
      results.add(r);
      // Pénalise les arêtes de ce chemin pour l'itération suivante
      for (int i = 0; i < r.path.length - 1; i++) {
        penalized.add('${r.path[i]}|${r.path[i + 1]}');
      }
    }
    return results;
  }

  /// Retourne true si [r] a le même chemin qu'un itinéraire déjà dans [list].
  bool _isDuplicate(ShortestPathResult r, List<Itinerary> list) {
    final key = r.path.join('|');
    return list.any((it) => it.pathNodeIds.join('|') == key);
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
    final coreLeg = _buildLegs(g, result.path, result.stepTypes);
    final legs = <Leg>[];

    if (from.isAddress && fromWalkSecs > 0) {
      final mins = (fromWalkSecs / 60).ceil().clamp(1, 999);
      legs.add(WalkLeg(
          label: '$mins min à pied', subtitle: 'Depuis ${from.displayName}'));
    }
    legs.addAll(coreLeg);
    if (to.isAddress && toWalkSecs > 0) {
      final mins = (toWalkSecs / 60).ceil().clamp(1, 999);
      legs.add(WalkLeg(
          label: '$mins min à pied', subtitle: 'Vers ${to.displayName}'));
    }

    final modes = legs.whereType<RideLeg>().map((r) => r.mode).toSet();
    final totalSecs = result.totalSeconds + fromWalkSecs + toWalkSecs;
    // Correspondances = nombre de trajets véhicule − 1 (basé sur les vrais
    // RideLeg, pas sur les arêtes transfer qui modélisent la marche).
    final rideCount = legs.whereType<RideLeg>().length;
    final transfers = (rideCount - 1).clamp(0, 999);
    final mins = (totalSecs / 60).round();
    final durationLabel = mins >= 60
        ? '${mins ~/ 60} h ${(mins % 60).toString().padLeft(2, '0')}'
        : '$mins min';

    final walkMin = ((fromWalkSecs + toWalkSecs) / 60).round();

    // CO₂ réel calculé par trajet (source : transilien.com/calcul-emissions-co2)
    final co2 = Co2Service.forPath(g, result.path, result.stepTypes);
    final co2Label = co2.savedKg >= 1
        ? '−${co2.savedKg.toStringAsFixed(2)} kg CO₂'
        : '−${(co2.savedKg * 1000).toStringAsFixed(0)} g CO₂';

    return Itinerary(
      tag: tag,
      tagColor: tagColor,
      durationLabel: durationLabel,
      detail: '$transfers correspondance${transfers != 1 ? 's' : ''}',
      walkLabel: walkMin > 0 ? '$walkMin min à pied' : '0 min à pied',
      co2Label: co2Label,
      modes: modes.isEmpty ? {TransportMode.metro} : modes,
      legs: legs,
      summary: '$durationLabel · $transfers correspondance${transfers != 1 ? 's' : ''} · $co2Label',
      perfNote: '⚡ ${result.computeTime.inMilliseconds} ms'
          ' — A* · ${result.exploredNodes} nœuds',
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
  // Legs
  // ---------------------------------------------------------------------------

  /// Construit les segments d'itinéraire en s'appuyant sur le TYPE d'arête
  /// réel (ride = trajet véhicule → badge de ligne ; transfer = marche/
  /// correspondance → segment à pied). Indispensable car le graphe modélise
  /// la marche par ~493 000 arêtes `transfer` : sans ça, deux arrêts reliés
  /// à pied seraient affichés comme un faux trajet en bus.
  List<Leg> _buildLegs(
      TransportGraph g, List<String> path, List<EdgeType> stepTypes) {
    if (path.length < 2) {
      final n = path.isNotEmpty ? g.nodes[path.first] : null;
      return n == null
          ? const []
          : [
              StationPoint(
                  name: n.stationName,
                  subtitle: 'Départ',
                  color: _colorFromHex(n.lineColor))
            ];
    }

    // Filet de sécurité si l'algo n'a pas fourni les types d'arête.
    if (stepTypes.length != path.length - 1) {
      stepTypes = [
        for (int i = 0; i < path.length - 1; i++)
          _edgeBetween(g, path[i], path[i + 1])?.type ?? EdgeType.transfer
      ];
    }

    final legs = <Leg>[];
    final first = g.nodes[path.first]!;
    legs.add(StationPoint(
        name: first.stationName,
        subtitle: 'Départ',
        color: _colorFromHex(first.lineColor)));

    int i = 0;
    while (i < stepTypes.length) {
      if (stepTypes[i] == EdgeType.ride) {
        // --- Trajet véhicule : on regroupe les pas ride de même ligne ---
        final rideNode = g.nodes[path[i]]!;
        final line = rideNode.line;
        final start = i;
        while (i < stepTypes.length &&
            stepTypes[i] == EdgeType.ride &&
            g.nodes[path[i]]?.line == line) {
          i++;
        }
        final stops = path
            .sublist(start, i + 1)
            .map((id) => g.nodes[id]?.stationName)
            .whereType<String>()
            .toSet()
            .length;
        final stopCount = (stops - 1).clamp(1, 999);
        legs.add(RideLeg(
          mode: _modeFromRouteType(rideNode.routeType),
          lineLabel: rideNode.lineShortName ?? '?',
          lineColor: _colorFromHex(rideNode.lineColor),
          darkText: _isDarkText(rideNode.lineColor),
          direction: _headsignFor(g, path, start),
          subtitle: '$stopCount arrêt${stopCount > 1 ? 's' : ''}',
        ));
        if (i < stepTypes.length) {
          final atNode = g.nodes[path[i]]!;
          legs.add(StationPoint(
              name: atNode.stationName,
              subtitle: 'Correspondance',
              color: _colorFromHex(atNode.lineColor)));
        }
      } else {
        // --- Marche / correspondance : on cumule les pas non-ride ---
        final start = i;
        double secs = 0;
        while (i < stepTypes.length && stepTypes[i] != EdgeType.ride) {
          secs += _edgeWeightOfType(g, path[i], path[i + 1], stepTypes[i]);
          i++;
        }
        final fromN = g.nodes[path[start]]!;
        final toN = g.nodes[path[i]]!;
        // Marche visible uniquement si on change réellement de lieu.
        // Un simple changement de quai (même station) reste implicite.
        if (fromN.stationName != toN.stationName) {
          final mins = (secs / 60).ceil().clamp(1, 999);
          legs.add(WalkLeg(
              label: '$mins min à pied', subtitle: 'Vers ${toN.stationName}'));
          if (i < stepTypes.length) {
            legs.add(StationPoint(
                name: toN.stationName,
                subtitle: 'Correspondance',
                color: _colorFromHex(toN.lineColor)));
          }
        }
      }
    }

    final last = g.nodes[path.last]!;
    legs.add(StationPoint(
        name: last.stationName,
        subtitle: 'Arrivée',
        color: _colorFromHex(last.lineColor)));

    return legs;
  }

  /// Retourne l'arête reliant [from] à [to] (ou null).
  Edge? _edgeBetween(TransportGraph g, String from, String to) {
    for (final e in g.neighbors(from)) {
      if (e.to == to) return e;
    }
    return null;
  }

  /// Poids de l'arête [from]→[to] du type [type] (celle empruntée par A*).
  double _edgeWeightOfType(
      TransportGraph g, String from, String to, EdgeType type) {
    for (final e in g.neighbors(from)) {
      if (e.to == to && e.type == type) return e.weightSeconds;
    }
    // Repli : n'importe quelle arête vers [to]
    return _edgeBetween(g, from, to)?.weightSeconds ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF475774);
    final v = int.tryParse(hex.padLeft(6, '0'), radix: 16);
    return v != null ? Color(0xFF000000 | v) : const Color(0xFF475774);
  }

  bool _isDarkText(String? hex) {
    if (hex == null) return false;
    final c = int.tryParse(hex.padLeft(6, '0'), radix: 16) ?? 0;
    final lum = 0.299 * ((c >> 16) & 0xFF) +
        0.587 * ((c >> 8) & 0xFF) +
        0.114 * (c & 0xFF);
    return lum > 160;
  }

  TransportMode _modeFromRouteType(int? rt) => switch (rt) {
        0 => TransportMode.tram,
        1 => TransportMode.metro,
        2 => TransportMode.bus,
        3 => TransportMode.bus,
        _ => TransportMode.metro,
      };

  String _headsignFor(TransportGraph g, List<String> path, int segStart) {
    if (segStart >= path.length - 1) return '';
    final nextId = path[segStart + 1];
    for (final e in g.neighbors(path[segStart])) {
      if (e.to == nextId && e.type == EdgeType.ride && e.headsign != null) {
        return 'Direction ${e.headsign}';
      }
    }
    return '';
  }

}
