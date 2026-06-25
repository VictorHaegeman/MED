/// Cœur algorithmique — structure de graphe intermodal.
///
library;

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

  final String id; // ex: "chatelet#M1"
  final String stationName;
  final String? line; // null pour un nœud "rue" (marche)
  final double lat;
  final double lon;
  final String? lineColor;
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

  /// TODO(V1): charger le graphe depuis l'asset généré par `data_pipeline/`
  /// (GTFS Île-de-France Mobilités → format compact embarqué).
  ///
  /// Contrat attendu :
  ///   - parsing en O(V+E), aucune requête réseau à l'exécution ;
  ///   - documenter les hypothèses de pondération (temps inter-stations,
  ///     pénalité de correspondance ~4 min) — exigence AO.
  static Future<TransportGraph> fromAsset(String assetPath) {
    throw UnimplementedError(
      'V1 — à implémenter quand data-pipeline/ produira l\'asset graphe.',
    );
  }
}
