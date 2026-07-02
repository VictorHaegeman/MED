/// Cœur algorithmique — structure de graphe intermodal.
library;

import 'dart:convert';
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
    return compute(_parseGraph, jsonString);
  }

  static TransportGraph _parseGraph(String jsonString) {
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
      final type = EdgeType.values.byName(m['type'] as String);
      final w = (m['weightSeconds'] as num).toDouble();
      // Élague les correspondances à pied trop longues.
      if (type == EdgeType.transfer && w > maxTransferSecs) continue;
      // Interdit de ROULER en bus de nuit (les correspondances vers ces arrêts
      // restent autorisées, mais pas les trajets ride Noctilien).
      if (type == EdgeType.ride && isNoctilien(from)) continue;
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
      if (graph.nodes.containsKey(edge.from) &&
          graph.nodes.containsKey(edge.to)) {
        graph.addEdge(edge);
      }
    }

    return graph;
  }
}
