/// Cœur algorithmique — structure de graphe intermodal.
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

/// Type d'arête du graphe intermodal.
enum EdgeType { ride, transfer, walk }

/// Nœud du graphe : couple (station, ligne).
///
/// Modéliser un nœud par (station, ligne) — et non par station seule — permet
/// de pondérer finement les correspondances : changer de ligne à Châtelet
/// coûte un arc `transfer`, rester sur la même ligne ne coûte rien.
class GraphNode {
  const GraphNode({
    required this.id,
    required this.stationName,
    required this.line,
    required this.lat,
    required this.lon,
    this.lineColor,
    this.lineShortName,
    this.routeType, //0=tram, 1=métro, 2=train, 3=bus
    this.headsign,
  });

  final String id; // ex: "IDFM:71673#IDFM:C01379"
  final String stationName;
  final String? line; // null pour un nœud "rue" (marche)
  final double lat;
  final double lon;
  final String? lineColor; // hex sans #, ex: "D2D200"
  final String? lineShortName;
  final int? routeType;
  final String? headsign;
}

/// Arête orientée pondérée.
class Edge {
  const Edge({
    required this.from,
    required this.to,
    required this.weightSeconds,
    required this.type,
    this.headsign,
  });

  final String from;
  final String to;
  final double weightSeconds;
  final EdgeType type;
  final String? headsign;
}

/// Graphe orienté pondéré, en listes d'adjacence.
class TransportGraph {
  /// Vitesse plafond du réseau en m/s (~137 km/h, Transilien en pointe).
  ///
  /// Double rôle :
  /// 1. Garde-fou données : toute arête `ride` impliquant une vitesse
  ///    supérieure (glitchs GTFS observés jusqu'à 327 km/h) voit son poids
  ///    relevé à distance/vitesse.
  /// 2. Ce plancher garantit PAR CONSTRUCTION l'admissibilité de
  ///    l'heuristique A* h(n) = distance_vol_d_oiseau / maxSpeedMs.
  static const double maxSpeedMs = 38.0;

  /// Vitesse de marche plafond (m/s). Les arêtes `transfer` du GTFS
  /// contiennent ~35 000 « téléportations » (min_transfer_time très inférieur
  /// au temps de marche physique) : on relève leur poids au temps de marche
  /// réel avant l'élagage à 6 min.
  static const double maxWalkMps = 1.6;

  final Map<String, GraphNode> nodes = {};
  final Map<String, List<Edge>> _adjacency = {};

  int get nodeCount => nodes.length;
  int get edgeCount =>
      _adjacency.values.fold(0, (sum, edges) => sum + edges.length);

  void addNode(GraphNode node) {
    nodes[node.id] = node;
    _adjacency.putIfAbsent(node.id, () => []);
  }

  void addEdge(Edge edge) {
    assert(nodes.containsKey(edge.from), 'Nœud inconnu: ${edge.from}');
    assert(nodes.containsKey(edge.to), 'Nœud inconnu: ${edge.to}');
    _adjacency[edge.from]!.add(edge);
  }

  /// Arêtes sortantes d'un nœud.
  List<Edge> neighbors(String nodeId) => _adjacency[nodeId] ?? const [];

  /// Charge le graphe depuis l'asset JSON généré par data_pipeline/.
  /// Parsing hors du thread UI via compute() pour ne pas bloquer l'interface.
  static Future<TransportGraph> fromAsset(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    return compute(fromJsonString, jsonString);
  }

  /// Parsing synchrone — public pour les tests (chargement via dart:io).
  static TransportGraph fromJsonString(String jsonString) {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    final graph = TransportGraph();

    for (final n in data['nodes'] as List<dynamic>) {
      final m = n as Map<String, dynamic>;
      graph.addNode(GraphNode(
        id: m['id'] as String,
        stationName: m['stationName'] as String,
        line: m['line'] as String?,
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        lineColor: m['lineColor'] as String?,
        lineShortName: m['lineShortName'] as String?,
        routeType: m['routeType'] as int?,
      ));
    }

    // Plafond de correspondance à pied : au-delà, ce n'est plus une
    // correspondance réaliste (le JSON contient des "transferts" jusqu'à 60 min).
    // Élaguer allège aussi fortement le graphe (~493 000 arêtes transfer).
    const maxTransferSecs = 360.0; // 6 min de marche

    // Lignes Noctilien (bus de nuit) : identifiées par lineShortName "N…" sur
    // du bus (routeType 3). L'app fonctionne en « départ maintenant » sans
    // modèle horaire → on ne doit pas proposer de rouler en bus de nuit.
    bool isNoctilien(String? nodeId) {
      final n = nodeId != null ? graph.nodes[nodeId] : null;
      final name = n?.lineShortName;
      return n?.routeType == 3 &&
          name != null &&
          name.isNotEmpty &&
          (name[0] == 'N' || name[0] == 'n');
    }

    // Garde le meilleur arc par triple (from, to, type) — filet de sécurité
    // contre les doublons résiduels dans le JSON.
    final best = <String, Edge>{};
    for (final e in data['edges'] as List<dynamic>) {
      final m = e as Map<String, dynamic>;
      final from = m['from'] as String;
      final to = m['to'] as String;
      final fromNode = graph.nodes[from];
      final toNode = graph.nodes[to];
      if (fromNode == null || toNode == null) continue;
      final type = EdgeType.values.byName(m['type'] as String);
      double w = (m['weightSeconds'] as num).toDouble();

      final distM =
          _haversineM(fromNode.lat, fromNode.lon, toNode.lat, toNode.lon);
      if (type == EdgeType.ride) {
        // Plancher de vitesse réseau : corrige les horaires GTFS aberrants
        // et garantit l'admissibilité de l'heuristique A*.
        final minW = distM / maxSpeedMs;
        if (w < minW) w = minW;
        // Interdit de ROULER en bus de nuit (les correspondances vers ces
        // arrêts restent autorisées, mais pas les trajets ride Noctilien).
        if (isNoctilien(from)) continue;
      } else {
        // Plancher de vitesse de marche : neutralise les « téléportations »
        // (min_transfer_time GTFS incohérent avec la distance physique).
        final minW = distM / maxWalkMps;
        if (w < minW) w = minW;
        // Élague les correspondances à pied trop longues.
        if (w > maxTransferSecs) continue;
      }

      final key = '$from|$to|${type.name}';
      final ex = best[key];
      if (ex == null || w < ex.weightSeconds) {
        best[key] = Edge(
          from: from,
          to: to,
          weightSeconds: w,
          type: type,
          headsign: m['headsign'] as String?,
        );
      }
    }

    for (final edge in best.values) {
      graph.addEdge(edge);
    }

    return graph;
  }

  static double _haversineM(
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
}
