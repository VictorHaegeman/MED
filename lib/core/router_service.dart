/// Service d'itinéraires — point de jonction entre l'UI et le cœur algo.
///
/// Une requête = UN SEUL passage A* multi-source/multi-cible (TransitRouter),
/// quel que soit le nombre de quais/arrêts candidats au départ et à l'arrivée.
/// L'ancien code lançait un A* par PAIRE (départ × arrivée) : pour des arrêts
/// très dupliqués (« Mairie » = 1 118 nœuds), cela explosait en milliers de
/// runs ET sélectionnait des paires absurdes entre deux villes homonymes.
library;

import 'dart:math';
import 'dart:ui' show Color;

import '../models/itinerary.dart';
import '../models/search_result.dart';
import '../services/co2_service.dart';
import 'algorithms/shortest_path.dart';
import 'graph.dart';
import 'graph_store.dart';

/// Extrémité résolue : nœuds candidats avec leur coût d'approche à pied,
/// plus un point de référence géographique (marche directe, carte).
class _Endpoint {
  const _Endpoint({required this.costs, required this.lat, required this.lon});
  final Map<String, double> costs; // nodeId → secondes de marche d'approche
  final double lat;
  final double lon;
}

class RouterService {
  /// [graph] permet d'injecter un graphe pour les tests/benchmarks ;
  /// par défaut, le singleton chargé au démarrage de l'app.
  RouterService({TransportGraph? graph}) : _graphOverride = graph;

  static const _walkMps = 1.35; // vitesse de marche ~4,9 km/h
  static const _walkDetour = 1.25; // détour rues réelles vs vol d'oiseau
  static const _walkRadiusM = 800.0; // rabattement à pied autour d'une adresse
  static const _clusterRadiusM = 800.0; // regroupement des arrêts homonymes

  final TransportGraph? _graphOverride;
  final _transit = TransitRouter();

  /// [modeFilter] null = tous les modes (variantes triées par durée).
  /// Sinon, routes n'utilisant QUE ce mode (+ marche), avec repli combiné.
  Future<List<Itinerary>> findItineraries(
    SearchResult from,
    SearchResult to, {
    TransportMode? modeFilter,
  }) async {
    final g = _graphOverride ?? appGraph;
    final src = _resolveEndpoint(g, from);
    final dst = _resolveEndpoint(g, to);
    if (src == null || dst == null) return [];

    final results = <Itinerary>[];

    if (modeFilter == null) {
      // --- « Tous » : le plus rapide, moins de correspondances, métro+RER ---
      final r1 = _route(g, src, dst);
      if (r1 != null) {
        results.add(_toItinerary(g, r1, from, to, src, dst,
            tag: 'LE PLUS RAPIDE', tagColor: const Color(0xFF3B82F6)));
      }
      // Budget des variantes : au-delà de ~2,5× le plus rapide elles seraient
      // sans intérêt — l'abandon anticipé évite d'explorer tout le graphe.
      final budget = r1 != null
          ? r1.totalSeconds * 2.5 + 1500
          : double.infinity;
      final r2 =
          _route(g, src, dst, transferPenaltySecs: 420, maxCostSecs: budget);
      if (r2 != null && !_isDuplicate(r2, results)) {
        results.add(_toItinerary(g, r2, from, to, src, dst,
            tag: 'MOINS DE CORRESPONDANCES',
            tagColor: const Color(0xFF10B981)));
      }
      // Inutile si le plus rapide est déjà 100 % métro/RER : la variante
      // filtrée redonnerait exactement le même chemin optimal.
      final r3 = (r1 != null && _isPureRail(g, r1))
          ? null
          : _route(g, src, dst,
              edgeFilter: _filterForMode(g, TransportMode.metro),
              maxCostSecs: budget);
      if (r3 != null && !_isDuplicate(r3, results)) {
        results.add(_toItinerary(g, r3, from, to, src, dst,
            tag: 'MÉTRO + RER', tagColor: const Color(0xFF8B5CF6)));
      }
      // Si les variantes se confondent (même chemin optimal), on force une
      // vraie alternative par pénalisation d'arêtes (méthode edge-penalty).
      if (results.length < 2 && r1 != null) {
        final penalized = <String>{
          for (int i = 0; i < r1.path.length - 1; i++)
            '${r1.path[i]}|${r1.path[i + 1]}'
        };
        final alt = _route(g, src, dst,
            penalizedEdges: penalized,
            edgePenaltySecs: 300,
            maxCostSecs: r1.totalSeconds * 1.5 + 1200);
        if (alt != null &&
            !_isDuplicate(alt, results) &&
            _realDurationSecs(g, alt, src, dst) <=
                r1.totalSeconds * 1.5) {
          results.add(_toItinerary(g, alt, from, to, src, dst,
              tag: 'ALTERNATIVE', tagColor: const Color(0xFF10B981)));
        }
      }
    } else {
      // --- Mode filtré : jusqu'à 3 chemins DISTINCTS en mode pur ---
      final filter = _filterForMode(g, modeFilter);
      final paths =
          _distinctPaths(g, src, dst, edgeFilter: filter, count: 3);

      if (paths.isNotEmpty) {
        final modeColor = _colorForMode(modeFilter);
        const labels = ['LE PLUS RAPIDE', 'ALTERNATIVE 1', 'ALTERNATIVE 2'];
        for (int i = 0; i < paths.length; i++) {
          results.add(_toItinerary(g, paths[i], from, to, src, dst,
              tag: '${_tagForMode(modeFilter)} · ${labels[i]}',
              tagColor: modeColor));
        }
      } else {
        // Repli : aucun trajet 100 % dans ce mode → itinéraire combiné.
        final combined = _route(g, src, dst);
        if (combined != null) {
          results.add(_toItinerary(g, combined, from, to, src, dst,
              tag: 'COMBINÉ · ${_tagForMode(modeFilter)} SEUL IMPOSSIBLE',
              tagColor: const Color(0xFFF59E0B)));
        }
      }
    }

    // --- Marche directe, si courte ou compétitive ---
    final bestTransit = results.isEmpty
        ? null
        : results.map((it) => it.totalSeconds).reduce(min);
    final walk = _walkItinerary(from, to, src, dst, bestTransit);
    if (walk != null) results.add(walk);

    // --- Tri par durée : le plus court d'abord, surbrillance sur le 1er ---
    results.sort((a, b) => a.totalSeconds.compareTo(b.totalSeconds));
    return [
      for (int i = 0; i < results.length; i++)
        results[i].copyWith(highlighted: i == 0),
    ];
  }

  // ---------------------------------------------------------------------------
  // Recherche
  // ---------------------------------------------------------------------------

  ShortestPathResult? _route(
    TransportGraph g,
    _Endpoint src,
    _Endpoint dst, {
    bool Function(Edge)? edgeFilter,
    double transferPenaltySecs = 0,
    Set<String>? penalizedEdges,
    double edgePenaltySecs = 0,
    double maxCostSecs = double.infinity,
  }) {
    final r = _transit.route(
      g,
      sources: src.costs,
      targets: dst.costs,
      edgeFilter: edgeFilter,
      transferPenaltySecs: transferPenaltySecs,
      penalizedEdges: penalizedEdges,
      edgePenaltySecs: edgePenaltySecs,
      maxCostSecs: maxCostSecs,
    );
    return r.found ? r : null;
  }

  /// Durée RÉELLE d'un chemin : marche d'approche/sortie + poids réels des
  /// arêtes + attentes d'embarquement — SANS les pénalités artificielles
  /// (transferPenalty, edgePenalty) qui ne servent qu'à guider la recherche
  /// d'alternatives. Sans ce recalcul, « MOINS DE CORRESPONDANCES » (+420 s
  /// par transfert) affichait des minutes fantômes.
  double _realDurationSecs(
    TransportGraph g,
    ShortestPathResult result,
    _Endpoint src,
    _Endpoint dst,
  ) {
    if (result.path.isEmpty) return 0;
    double total = (src.costs[result.path.first] ?? 0) +
        (dst.costs[result.path.last] ?? 0);
    for (int i = 0; i < result.stepTypes.length; i++) {
      final type = result.stepTypes[i];
      total += _edgeWeightOfType(
          g, result.path[i], result.path[i + 1], type);
      // Embarquement (début d'un groupe ride) : attente du véhicule,
      // même modèle que TransitRouter.
      if (type == EdgeType.ride &&
          (i == 0 || result.stepTypes[i - 1] != EdgeType.ride)) {
        total += kBoardingWaitSecs[g.nodes[result.path[i]]?.routeType] ??
            kDefaultBoardingWaitSecs;
      }
    }
    return total;
  }

  /// Génère jusqu'à [count] chemins DISTINCTS via la méthode edge-penalty :
  /// on pénalise les arêtes du chemin précédent pour forcer un détour.
  List<ShortestPathResult> _distinctPaths(
    TransportGraph g,
    _Endpoint src,
    _Endpoint dst, {
    bool Function(Edge)? edgeFilter,
    int count = 3,
  }) {
    final results = <ShortestPathResult>[];
    final penalized = <String>{};
    final seenKeys = <String>{};
    double firstRealSecs = 0;

    for (int k = 0; k < count; k++) {
      final r = _route(
        g, src, dst,
        edgeFilter: edgeFilter,
        penalizedEdges: k == 0 ? null : penalized,
        edgePenaltySecs: k == 0 ? 0 : 300,
        // 1er chemin : borné au plus long trajet IdF plausible (3 h).
        // Suivants : au-delà de 1,3× le plus rapide ils seront rejetés.
        maxCostSecs: k == 0 ? 10800 : firstRealSecs * 1.3 + 1200,
      );
      if (r == null) break;
      final key = r.path.join('|');
      if (!seenKeys.add(key)) break; // plus d'alternative distincte
      // Écarte les alternatives peu compétitives (> 1,3× le plus rapide),
      // comparées sur la durée RÉELLE (hors pénalités de recherche).
      final realSecs = _realDurationSecs(g, r, src, dst);
      if (results.isEmpty) {
        firstRealSecs = realSecs;
      } else if (realSecs > firstRealSecs * 1.3) {
        break;
      }
      results.add(r);
      for (int i = 0; i < r.path.length - 1; i++) {
        penalized.add('${r.path[i]}|${r.path[i + 1]}');
      }
    }
    return results;
  }

  /// True si tous les segments véhicule de [r] sont métro ou RER/Transilien.
  bool _isPureRail(TransportGraph g, ShortestPathResult r) {
    for (int i = 0; i < r.stepTypes.length; i++) {
      if (r.stepTypes[i] != EdgeType.ride) continue;
      final rt = g.nodes[r.path[i]]?.routeType;
      if (rt != 1 && rt != 2) return false;
    }
    return true;
  }

  /// Retourne true si [r] a le même chemin qu'un itinéraire déjà dans [list].
  bool _isDuplicate(ShortestPathResult r, List<Itinerary> list) {
    final key = r.path.join('|');
    return list.any((it) => it.pathNodeIds.join('|') == key);
  }

  // ---------------------------------------------------------------------------
  // Résolution SearchResult → extrémité (nœuds candidats + marche)
  // ---------------------------------------------------------------------------

  _Endpoint? _resolveEndpoint(TransportGraph g, SearchResult src) {
    if (src.isAddress) return _resolveAddress(g, src.lat!, src.lon!);
    return _resolveStation(g, src.displayName);
  }

  /// Adresse : tous les arrêts à distance de marche (rayon 800 m), coût =
  /// temps de marche réel. Le routeur multi-source choisit le meilleur départ
  /// — plus de rabattement arbitraire sur « l'arrêt le plus proche ».
  _Endpoint? _resolveAddress(TransportGraph g, double lat, double lon) {
    final costs = <String, double>{};
    GraphNode? nearest;
    double nearestD = double.infinity;
    for (final n in g.nodes.values) {
      final d = _haversine(lat, lon, n.lat, n.lon);
      if (d < nearestD) {
        nearestD = d;
        nearest = n;
      }
      if (d <= _walkRadiusM) costs[n.id] = d * _walkDetour / _walkMps;
    }
    if (costs.isEmpty) {
      if (nearest == null) return null;
      // Aucun arrêt à distance de marche : rabattement sur le pôle le plus
      // proche (tous les arrêts dans un halo autour de lui).
      final haloM = nearestD + 250;
      for (final n in g.nodes.values) {
        final d = _haversine(lat, lon, n.lat, n.lon);
        if (d <= haloM) costs[n.id] = d * _walkDetour / _walkMps;
      }
    }
    return _Endpoint(costs: costs, lat: lat, lon: lon);
  }

  /// Station : les noms d'arrêts se répètent partout en Île-de-France
  /// (« Mairie » = 1 118 nœuds répartis sur 433 sites physiques !). On
  /// regroupe les homonymes en pôles géographiques (800 m) et on ne garde
  /// que le meilleur pôle : d'abord ceux desservis par du rail
  /// (métro/RER/tram), à défaut le plus gros. Sans cela, le routeur
  /// choisissait la paire la plus rapide entre deux villes différentes.
  _Endpoint? _resolveStation(TransportGraph g, String name) {
    final q = name.toLowerCase().trim();
    if (q.isEmpty) return null;

    var matches = <GraphNode>[
      for (final n in g.nodes.values)
        if (n.stationName.toLowerCase() == q) n
    ];
    if (matches.isEmpty) {
      // Saisie libre (pas via suggestions) : préfixe, puis inclusion.
      matches = [
        for (final n in g.nodes.values)
          if (n.stationName.toLowerCase().startsWith(q)) n
      ];
    }
    if (matches.isEmpty) {
      matches = [
        for (final n in g.nodes.values)
          if (n.stationName.toLowerCase().contains(q)) n
      ];
    }
    if (matches.isEmpty) return null;

    // Clustering géographique glouton (rayon _clusterRadiusM).
    final clusters = <List<GraphNode>>[];
    for (final n in matches) {
      var placed = false;
      for (final c in clusters) {
        if (_haversine(n.lat, n.lon, c.first.lat, c.first.lon) <=
            _clusterRadiusM) {
          c.add(n);
          placed = true;
          break;
        }
      }
      if (!placed) clusters.add([n]);
    }

    int score(List<GraphNode> c) {
      final hasRail =
          c.any((n) => n.routeType != null && n.routeType! <= 2);
      return (hasRail ? 100000 : 0) + c.length;
    }

    clusters.sort((a, b) => score(b).compareTo(score(a)));
    final best = clusters.first;
    double lat = 0, lon = 0;
    for (final n in best) {
      lat += n.lat;
      lon += n.lon;
    }
    return _Endpoint(
      costs: {for (final n in best) n.id: 0.0},
      lat: lat / best.length,
      lon: lon / best.length,
    );
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
        TransportMode.train => rt == 2,
        TransportMode.tram => rt == 0,
        TransportMode.bus => rt == 3,
        TransportMode.walk => false,
      };
    };
  }

  String _tagForMode(TransportMode mode) => switch (mode) {
        TransportMode.metro => 'MÉTRO + RER',
        TransportMode.train => 'RER + TRAIN',
        TransportMode.tram => 'TRAM UNIQUEMENT',
        TransportMode.bus => 'BUS UNIQUEMENT',
        TransportMode.walk => 'À PIED',
      };

  Color _colorForMode(TransportMode mode) => switch (mode) {
        TransportMode.metro => const Color(0xFF8B5CF6),
        TransportMode.train => const Color(0xFFEF4444),
        TransportMode.tram => const Color(0xFF14B8A6),
        TransportMode.bus => const Color(0xFFF59E0B),
        TransportMode.walk => const Color(0xFF6B7280),
      };

  // ---------------------------------------------------------------------------
  // Conversion ShortestPathResult → Itinerary
  // ---------------------------------------------------------------------------

  Itinerary _toItinerary(
    TransportGraph g,
    ShortestPathResult result,
    SearchResult from,
    SearchResult to,
    _Endpoint src,
    _Endpoint dst, {
    required String tag,
    required Color tagColor,
  }) {
    // Marche d'approche/sortie réellement retenue par le routeur : celle du
    // nœud de départ/arrivée effectivement choisi dans le chemin optimal.
    final fromWalkSecs =
        result.path.isEmpty ? 0.0 : (src.costs[result.path.first] ?? 0.0);
    final toWalkSecs =
        result.path.isEmpty ? 0.0 : (dst.costs[result.path.last] ?? 0.0);

    final coreLegs = _buildLegs(g, result.path, result.stepTypes);
    final legs = <Leg>[];

    if (from.isAddress && fromWalkSecs > 30) {
      final mins = (fromWalkSecs / 60).ceil().clamp(1, 999);
      legs.add(WalkLeg(
          label: '$mins min à pied', subtitle: 'Depuis ${from.displayName}'));
    }
    legs.addAll(coreLegs);
    if (to.isAddress && toWalkSecs > 30) {
      final mins = (toWalkSecs / 60).ceil().clamp(1, 999);
      legs.add(WalkLeg(
          label: '$mins min à pied', subtitle: 'Vers ${to.displayName}'));
    }

    final modes = legs.whereType<RideLeg>().map((r) => r.mode).toSet();
    // Durée RÉELLE recalculée depuis le chemin (marche + arêtes + attentes),
    // débarrassée des pénalités artificielles de recherche d'alternatives.
    final totalSecs = _realDurationSecs(g, result, src, dst);
    // Correspondances = nombre de trajets véhicule − 1 (basé sur les vrais
    // RideLeg, pas sur les arêtes transfer qui modélisent la marche).
    final rideCount = legs.whereType<RideLeg>().length;
    final transfers = (rideCount - 1).clamp(0, 999);
    final mins = (totalSecs / 60).round();
    final durationLabel = mins >= 60
        ? '${mins ~/ 60} h ${(mins % 60).toString().padLeft(2, '0')}'
        : '$mins min';

    // Marche totale = approche + sortie + correspondances à pied du chemin.
    double walkSecs = fromWalkSecs + toWalkSecs;
    for (int i = 0;
        i < result.stepTypes.length && i + 1 < result.path.length;
        i++) {
      if (result.stepTypes[i] != EdgeType.ride) {
        walkSecs += _edgeWeightOfType(
            g, result.path[i], result.path[i + 1], result.stepTypes[i]);
      }
    }
    final walkMin = (walkSecs / 60).round();

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
      modes: modes.isEmpty ? {TransportMode.walk} : modes,
      legs: legs,
      summary:
          '$durationLabel · $transfers correspondance${transfers != 1 ? 's' : ''} · $co2Label',
      perfNote: '⚡ ${result.computeTime.inMilliseconds} ms'
          ' — A* multi-source · ${result.exploredNodes} états',
      pathNodeIds: result.path,
      totalSeconds: totalSecs,
      fromLat: from.isAddress ? from.lat : null,
      fromLon: from.isAddress ? from.lon : null,
      toLat: to.isAddress ? to.lat : null,
      toLon: to.isAddress ? to.lon : null,
    );
  }

  /// Itinéraire 100 % marche entre les deux points de référence — proposé
  /// quand il est court ou compétitif face au meilleur trajet en transport.
  Itinerary? _walkItinerary(
    SearchResult from,
    SearchResult to,
    _Endpoint src,
    _Endpoint dst,
    double? bestTransitSecs,
  ) {
    final distM =
        _haversine(src.lat, src.lon, dst.lat, dst.lon) * _walkDetour;
    final secs = distM / _walkMps;
    if (secs < 60) return null; // même endroit
    if (secs > 2700) return null; // > 45 min de marche : hors sujet
    if (bestTransitSecs != null &&
        secs > bestTransitSecs * 1.4 &&
        secs > 1200) {
      return null; // pas compétitif
    }

    final mins = (secs / 60).round().clamp(1, 999);
    final km = distM / 1000;
    // Marcher évite l'intégralité des émissions voiture sur cette distance.
    final savedKg = Co2Service.voitureGPerKm * km / 1000;
    final co2Label = savedKg >= 1
        ? '−${savedKg.toStringAsFixed(2)} kg CO₂'
        : '−${(savedKg * 1000).toStringAsFixed(0)} g CO₂';
    final durationLabel = mins >= 60
        ? '${mins ~/ 60} h ${(mins % 60).toString().padLeft(2, '0')}'
        : '$mins min';
    const grey = Color(0xFF6B7280);

    return Itinerary(
      tag: 'À PIED',
      tagColor: grey,
      durationLabel: durationLabel,
      detail: '${km.toStringAsFixed(1)} km · 0 correspondance',
      walkLabel: '$mins min à pied',
      co2Label: co2Label,
      modes: const {TransportMode.walk},
      legs: [
        StationPoint(
            name: from.displayName, subtitle: 'Départ', color: grey),
        WalkLeg(
            label: '$mins min à pied (${km.toStringAsFixed(1)} km)',
            subtitle: 'Trajet direct'),
        StationPoint(
            name: to.displayName, subtitle: 'Arrivée', color: grey),
      ],
      summary: '$durationLabel · marche directe · $co2Label',
      perfNote: '⚡ itinéraire piéton — vol d\'oiseau × $_walkDetour',
      pathNodeIds: const [],
      totalSeconds: secs,
      fromLat: src.lat,
      fromLon: src.lon,
      toLat: dst.lat,
      toLon: dst.lon,
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
        final stopCount = (i - start).clamp(1, 999);
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

  /// routeType GTFS → mode d'affichage. 2 = RER/Transilien (train), qui était
  /// auparavant affiché comme bus (bug).
  TransportMode _modeFromRouteType(int? rt) => switch (rt) {
        0 => TransportMode.tram,
        1 => TransportMode.metro,
        2 => TransportMode.train,
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
