/// Écran de visualisation de l'arborescence du réseau — attendu explicite AO
/// ("afficher l'arborescence de la structure").
///
/// Rend l'ARBRE COUVRANT MINIMAL (Prim — cf. core/algorithms/spanning_tree.dart)
/// sur une carte, façon `map_screen.dart` : chaque arête retenue est tracée
/// entre ses deux stations, colorée par ligne. Les correspondances (arêtes
/// `transfer`, de longueur géographique nulle) ne sont pas tracées comme des
/// segments, mais leurs stations sont signalées comme pôles d'échange.
///
/// ── État d'avancement ──────────────────────────────────────────────────────
/// V2 (démo) : l'écran calcule un VRAI ACM sur un sous-réseau parisien réel
/// construit par `buildDemoNetwork()` ci-dessous (le pipeline data n'existe
/// pas encore). En V1, il suffit de passer le graphe complet via le paramètre
/// `graph` (`TransportGraph.fromAsset(...)`) : tout le reste est inchangé.
/// NB : sur le graphe complet (~1 842 nœuds) l'arbre est dense ; prévoir un
/// filtre (zone/ligne) côté appelant avant de rendre — non implémenté ici.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/algorithms/spanning_tree.dart';
import '../core/graph.dart';
import '../theme.dart';
import '../widgets/common.dart';

class NetworkTreeScreen extends StatefulWidget {
  /// Si `graph` est fourni (V1), on l'utilise tel quel ; sinon (V2) on retombe
  /// sur le sous-réseau de démonstration.
  const NetworkTreeScreen({super.key, this.graph});

  final TransportGraph? graph;

  @override
  State<NetworkTreeScreen> createState() => _NetworkTreeScreenState();
}

class _NetworkTreeScreenState extends State<NetworkTreeScreen> {
  late final TransportGraph _graph;
  late final SpanningTreeResult _mst;
  late final Duration _computeTime;

  final List<_RideSegment> _segments = [];
  final List<_StationDot> _stations = []; // pôles + racine (avec label)
  final List<CircleMarker> _plainCircles = []; // stations simples (canvas)
  String _rootStation = '';

  @override
  void initState() {
    super.initState();
    _graph = widget.graph ?? buildDemoNetwork();

    final sw = Stopwatch()..start();
    _mst = PrimMst().compute(_graph);
    sw.stop();
    _computeTime = sw.elapsed;

    _prepareRenderData();
  }

  /// Transforme l'ACM (liste d'arêtes) en primitives dessinables.
  void _prepareRenderData() {
    // Racine = nœud jamais "enfant"
    final children = _mst.edges.map((e) => e.to).toSet();
    final rootId =
        _graph.nodes.keys.firstWhere((id) => !children.contains(id));
    _rootStation = _graph.nodes[rootId]!.stationName;

    // Segments ride uniquement (les transfer sont à distance nulle)
    for (final e in _mst.edges) {
      final a = _graph.nodes[e.from];
      final b = _graph.nodes[e.to];
      if (a == null || b == null) continue;
      if (a.line != null && a.line == b.line) {
        _segments.add(_RideSegment(
          from: LatLng(a.lat, a.lon),
          to: LatLng(b.lat, b.lon),
          color: _nodeColor(a),
        ));
      }
    }

    // Un marqueur par station physique
    final linesPerStation = <String, Set<String>>{};
    final colorPerStation = <String, Color>{};
    final coordPerStation = <String, LatLng>{};
    for (final node in _graph.nodes.values) {
      linesPerStation
          .putIfAbsent(node.stationName, () => {})
          .add(node.line ?? '—');
      coordPerStation[node.stationName] = LatLng(node.lat, node.lon);
      colorPerStation[node.stationName] = _nodeColor(node);
    }
    for (final entry in coordPerStation.entries) {
      final isHub = (linesPerStation[entry.key]?.length ?? 0) > 1;
      final isRoot = entry.key == _rootStation;
      final color = colorPerStation[entry.key] ?? MedColors.secondary;
      if (isHub || isRoot) {
        // Pôles & racine → marqueur widget avec label
        _stations.add(_StationDot(
          name: entry.key,
          pos: entry.value,
          showLabel: true,
          isHub: isHub,
          isRoot: isRoot,
          color: color,
        ));
      } else {
        // Stations simples → cercle canvas (léger, ~1800 points)
        _plainCircles.add(CircleMarker(
          point: entry.value,
          radius: 2.4,
          color: color,
          borderColor: Colors.white.withValues(alpha: 0.35),
          borderStrokeWidth: 0.5,
        ));
      }
    }
  }

  Color _nodeColor(GraphNode node) {
    if (node.lineColor == null || node.lineColor!.isEmpty) {
      return MedColors.secondary;
    }
    final v = int.tryParse(node.lineColor!.padLeft(6, '0'), radix: 16);
    return v != null ? Color(0xFF000000 | v) : MedColors.secondary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          SafeArea(child: _topBar()),
          Positioned(bottom: 0, left: 0, right: 0, child: _bottomPanel()),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(48.8580, 2.3340),
        initialZoom: 12.2,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.efrei.med',
        ),
        // Halo
        PolylineLayer(
          polylines: [
            for (final s in _segments)
              Polyline(
                points: [s.from, s.to],
                color: s.color.withValues(alpha: 0.22),
                strokeWidth: 9.0,
              ),
          ],
        ),
        // Arêtes de l'arbre
        PolylineLayer(
          polylines: [
            for (final s in _segments)
              Polyline(
                points: [s.from, s.to],
                color: s.color,
                strokeWidth: 3.6,
              ),
          ],
        ),
        // Stations simples → cercles canvas (rapide)
        CircleLayer(circles: _plainCircles),
        // Pôles d'échange & racine → marqueurs avec label
        MarkerLayer(
          markers: [
            for (final st in _stations)
              Marker(
                point: st.pos,
                width: 130,
                height: 48,
                alignment: Alignment.bottomCenter,
                child: _StationMarker(station: st),
              ),
          ],
        ),
      ],
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          const BackCircle(),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: MedColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MedColors.dividerColor),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Arborescence du réseau',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('Arbre couvrant minimal · Prim',
                      style:
                          TextStyle(fontSize: 11, color: MedColors.secondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomPanel() {
    final ms = _computeTime.inMicroseconds / 1000.0;
    return Container(
      decoration: BoxDecoration(
        color: MedColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
            top: BorderSide(color: MedColors.dividerColor, width: 0.8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MedColors.surface2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('🌳 Arbre couvrant minimal',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '⚡ Calculé en ${ms.toStringAsFixed(ms < 10 ? 2 : 1)} ms — '
              'Prim (tas binaire) · O(E log V)',
              style: const TextStyle(fontSize: 11, color: MedColors.accent),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _stat('${_mst.edges.length}', 'arêtes'),
                _stat('${_graph.nodeCount}', 'nœuds'),
                _stat(_fmtSeconds(_mst.totalWeight), 'poids total'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _legend(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: MedColors.secondary)),
        ],
      ),
    );
  }

  Widget _legend() {
    // Lignes uniques avec leurs couleurs réelles depuis le graphe
    final seen = <String>{};
    final entries = <(String, Color, bool)>[];
    for (final node in _graph.nodes.values) {
      final name = node.lineShortName ?? node.line;
      if (name == null || !seen.add(name)) continue;
      final color = _nodeColor(node);
      final lum = _luminance(node.lineColor);
      entries.add((name, color, lum > 160));
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, color, dark) in entries)
            LineBadge(label: label, color: color, darkText: dark),
        ],
      ),
    );
  }

  double _luminance(String? hex) {
    if (hex == null) return 0;
    final c = int.tryParse(hex.padLeft(6, '0'), radix: 16) ?? 0;
    return 0.299 * ((c >> 16) & 0xFF) +
        0.587 * ((c >> 8) & 0xFF) +
        0.114 * (c & 0xFF);
  }
}

// ---------------------------------------------------------------------------
//  Helpers de rendu
// ---------------------------------------------------------------------------

String _fmtSeconds(double s) {
  final total = s.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')}';
  return '$m min';
}

class _RideSegment {
  const _RideSegment(
      {required this.from, required this.to, required this.color});
  final LatLng from;
  final LatLng to;
  final Color color;
}

class _StationDot {
  const _StationDot({
    required this.name,
    required this.pos,
    required this.showLabel,
    required this.isHub,
    required this.isRoot,
    required this.color,
  });
  final String name;
  final LatLng pos;
  final bool showLabel;
  final bool isHub;
  final bool isRoot;
  final Color color;
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({required this.station});
  final _StationDot station;

  @override
  Widget build(BuildContext context) {
    final dotColor = station.isRoot ? MedColors.accent : station.color;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (station.showLabel)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: MedColors.bg.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: dotColor.withValues(alpha: 0.6), width: 0.8),
            ),
            child: Text(
              station.isRoot ? '${station.name} · racine' : station.name,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: dotColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (station.showLabel) const SizedBox(height: 3),
        Container(
          width: station.isRoot ? 14 : (station.isHub ? 11 : 7),
          height: station.isRoot ? 14 : (station.isHub ? 11 : 7),
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
              width: station.isHub ? 2.0 : 1.0,
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
//  Sous-réseau de démonstration (V2)
//  -------------------------------------------------------------------------
//  Un vrai graphe intermodal réduit : 4 lignes de métro, stations réelles
//  (coordonnées approximatives), correspondances. Sert à exécuter Prim sur de
//  vraies données tant que `TransportGraph.fromAsset(...)` n'existe pas.
//  Pondérations (hypothèses, cf. plan §1.3) :
//    - trajet inter-stations : ~temps réel approché (s) ;
//    - correspondance        : pénalité fixe de 240 s (~4 min).
// ===========================================================================

const double _transferPenalty = 240;

TransportGraph buildDemoNetwork() {
  final g = TransportGraph();

  const coords = <String, List<double>>{
    'La Défense': [48.8918, 2.2384],
    'Charles de Gaulle–Étoile': [48.8740, 2.2950],
    'Champs-Élysées–Clemenceau': [48.8676, 2.3138],
    'Concorde': [48.8656, 2.3212],
    'Châtelet': [48.8594, 2.3469],
    'Gare de Lyon': [48.8449, 2.3736],
    'Nation': [48.8483, 2.3958],
    'Gare du Nord': [48.8809, 2.3553],
    'Strasbourg–Saint-Denis': [48.8694, 2.3536],
    'Saint-Germain-des-Prés': [48.8540, 2.3338],
    'Montparnasse–Bienvenüe': [48.8422, 2.3217],
    'Saint-Lazare': [48.8757, 2.3253],
    'Madeleine': [48.8700, 2.3245],
    'Bercy': [48.8400, 2.3795],
    'Olympiades': [48.8270, 2.3670],
  };

  const lines = <(String, List<String>, double)>[
    (
      'M1',
      [
        'La Défense',
        'Charles de Gaulle–Étoile',
        'Champs-Élysées–Clemenceau',
        'Concorde',
        'Châtelet',
        'Gare de Lyon',
        'Nation',
      ],
      120
    ),
    (
      'M4',
      [
        'Gare du Nord',
        'Strasbourg–Saint-Denis',
        'Châtelet',
        'Saint-Germain-des-Prés',
        'Montparnasse–Bienvenüe',
      ],
      105
    ),
    (
      'M12',
      [
        'Saint-Lazare',
        'Madeleine',
        'Concorde',
        'Montparnasse–Bienvenüe',
      ],
      135
    ),
    (
      'M14',
      [
        'Saint-Lazare',
        'Madeleine',
        'Châtelet',
        'Gare de Lyon',
        'Bercy',
        'Olympiades',
      ],
      95
    ),
  ];

  String idOf(String station, String line) => '$station#$line';

  // 1) Nœuds (station, ligne) + arêtes "ride" le long de chaque ligne.
  for (final (line, stations, t) in lines) {
    for (final station in stations) {
      final c = coords[station]!;
      final id = idOf(station, line);
      if (!g.nodes.containsKey(id)) {
        g.addNode(GraphNode(
          id: id,
          stationName: station,
          line: line,
          lat: c[0],
          lon: c[1],
        ));
      }
    }
    for (int i = 0; i + 1 < stations.length; i++) {
      g.addEdge(Edge(
        from: idOf(stations[i], line),
        to: idOf(stations[i + 1], line),
        weightSeconds: t,
        type: EdgeType.ride,
      ));
    }
  }

  // 2) Correspondances : relier en chaîne les lignes présentes à une station.
  final linesAtStation = <String, List<String>>{};
  for (final node in g.nodes.values) {
    linesAtStation.putIfAbsent(node.stationName, () => []).add(node.line!);
  }
  for (final entry in linesAtStation.entries) {
    final ls = entry.value;
    for (int i = 0; i + 1 < ls.length; i++) {
      g.addEdge(Edge(
        from: idOf(entry.key, ls[i]),
        to: idOf(entry.key, ls[i + 1]),
        weightSeconds: _transferPenalty,
        type: EdgeType.transfer,
      ));
    }
  }

  return g;
}
