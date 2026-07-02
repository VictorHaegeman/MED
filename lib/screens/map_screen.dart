import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/graph.dart' show GraphNode;
import '../main.dart'
    show appGraph, pathNotifier, tripSecondsNotifier, tripFromNotifier, tripToNotifier, tripSavedNotifier;
import '../models/saved_trip.dart';
import '../services/co2_service.dart';
import '../services/trip_storage.dart';
import '../theme.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    this.pathNodeIds,
    this.totalSeconds,
    this.from,
    this.to,
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
  });

  final List<String>? pathNodeIds;
  final double? totalSeconds;
  final String? from;
  final String? to;
  final double? fromLat;
  final double? fromLon;
  final double? toLat;
  final double? toLon;

  @override
  Widget build(BuildContext context) {
    if (pathNodeIds != null) {
      return _MapView(
        pathNodeIds: pathNodeIds,
        totalSeconds: totalSeconds ?? 0,
        from: from ?? '',
        to: to ?? '',
        showDeparturePanel: true,
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
      );
    }
    return ValueListenableBuilder<List<String>?>(
      valueListenable: pathNotifier,
      builder: (_, ids, __) => ValueListenableBuilder<double>(
        valueListenable: tripSecondsNotifier,
        builder: (_, secs, __) => ValueListenableBuilder<String>(
          valueListenable: tripFromNotifier,
          builder: (_, from, __) => ValueListenableBuilder<String>(
            valueListenable: tripToNotifier,
            builder: (_, to, __) => _MapView(
              pathNodeIds: ids,
              totalSeconds: secs,
              from: from,
              to: to,
              showDeparturePanel: false,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MapView extends StatefulWidget {
  const _MapView({
    this.pathNodeIds,
    this.totalSeconds = 0,
    this.from = '',
    this.to = '',
    this.showDeparturePanel = false,
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
  });

  final List<String>? pathNodeIds;
  final double totalSeconds;
  final String from;
  final String to;
  final bool showDeparturePanel;
  final double? fromLat;
  final double? fromLon;
  final double? toLat;
  final double? toLon;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  bool _tripSaved = false;

  bool get _hasPath =>
      widget.pathNodeIds != null && widget.pathNodeIds!.isNotEmpty;

  Co2Result get _co2 {
    if (!_hasPath) return const Co2Result(distanceKm: 0, savedKg: 0);
    return Co2Service.forPath(appGraph, widget.pathNodeIds!);
  }

  Future<void> _saveTrip() async {
    if (_tripSaved || !_hasPath) return;
    final co2 = _co2;
    await TripStorage.save(SavedTrip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      from: widget.from,
      to: widget.to,
      distanceKm: co2.distanceKm,
      durationSeconds: widget.totalSeconds,
      co2SavedKg: co2.savedKg,
    ));
    tripSavedNotifier.value++;
    if (!mounted) return;
    setState(() => _tripSaved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: MedColors.green, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Trajet enregistré · ${co2.savedKg.toStringAsFixed(2)} kg CO₂ économisés',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: MedColors.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Données de rendu — mémoïsées pour ne pas reparcourir le graphe à chaque
  // rebuild (les 4 ValueListenableBuilder imbriqués rebuild souvent).
  // -------------------------------------------------------------------------

  List<String>? _dataForPath; // identité du chemin ayant produit le cache
  bool _dataComputed = false;
  List<_Station> _stations = [];
  List<_Segment> _segments = [];
  List<List<LatLng>> _walkLines = [];
  LatLng _center = const LatLng(48.8566, 2.3522);

  /// Recalcule les primitives de rendu uniquement si le chemin a changé.
  void _ensureRenderData() {
    if (_dataComputed && identical(_dataForPath, widget.pathNodeIds)) return;
    _dataComputed = true;
    _dataForPath = widget.pathNodeIds;
    _stations = _computeStations();
    _segments = _computeSegments();
    _walkLines = _computeWalkPolylines();
    _center = _computeCenter();
  }

  Set<String> _keyNodeIds(List<String> ids) {
    if (ids.isEmpty) return {};
    final g = appGraph;
    final keys = <String>{ids.first, ids.last};
    for (int i = 1; i < ids.length - 1; i++) {
      final prevLine = g.nodes[ids[i - 1]]?.line;
      final currLine = g.nodes[ids[i]]?.line;
      final nextLine = g.nodes[ids[i + 1]]?.line;
      if (currLine != prevLine || currLine != nextLine) keys.add(ids[i]);
    }
    return keys;
  }

  /// En mode trajet uniquement : stations du chemin (labels + dots).
  /// Le mode réseau (1842 stations) passe par _networkCircles (CircleLayer).
  List<_Station> _computeStations() {
    if (!_hasPath) return const [];
    final g = appGraph;
    final ids = widget.pathNodeIds!;
    final keys = _keyNodeIds(ids);
    final seen = <String>{};
    final result = <_Station>[];
    for (int i = 0; i < ids.length; i++) {
      final node = g.nodes[ids[i]];
      if (node == null || !seen.add(node.stationName)) continue;
      result.add(_Station(
        name: node.stationName,
        lat: node.lat,
        lng: node.lon,
        color: _colorFromHex(node.lineColor),
        isKey: keys.contains(ids[i]),
      ));
    }
    return result;
  }

  List<_Segment> _computeSegments() {
    if (!_hasPath) return const [];
    final g = appGraph;
    final result = <_Segment>[];
    final ids = widget.pathNodeIds!;
    int segStart = 0;
    for (int i = 1; i <= ids.length; i++) {
      final prev = g.nodes[ids[i - 1]];
      if (prev == null) {
        segStart = i;
        continue;
      }
      final nextLine = i < ids.length ? g.nodes[ids[i]]?.line : null;
      if (i == ids.length || nextLine != prev.line) {
        final pts = ids
            .sublist(segStart, i)
            .map((id) => g.nodes[id])
            .whereType<GraphNode>()
            .map((n) => LatLng(n.lat, n.lon))
            .toList();
        if (pts.length >= 2) {
          result.add(_Segment(_colorFromHex(prev.lineColor), pts));
        }
        segStart = i;
      }
    }
    return result;
  }

  LatLng _computeCenter() {
    if (_hasPath) {
      final g = appGraph;
      final nodes = widget.pathNodeIds!
          .map((id) => g.nodes[id])
          .whereType<GraphNode>()
          .toList();
      if (nodes.isNotEmpty) {
        final lat =
            nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length;
        final lon =
            nodes.map((n) => n.lon).reduce((a, b) => a + b) / nodes.length;
        return LatLng(lat, lon);
      }
    }
    return const LatLng(48.8566, 2.3522);
  }

  // -------------------------------------------------------------------------
  // Vue réseau : cercles canvas (CircleLayer) — 1 seul calcul, pas de widgets.
  // Partagé et calculé une fois (le graphe complet ne change jamais).
  // -------------------------------------------------------------------------

  static List<CircleMarker>? _networkCirclesCache;

  List<CircleMarker> get _networkCircles {
    return _networkCirclesCache ??= _buildNetworkCircles();
  }

  List<CircleMarker> _buildNetworkCircles() {
    final g = appGraph;
    final seen = <String>{};
    final circles = <CircleMarker>[];
    for (final n in g.nodes.values) {
      // Aperçu réseau : réseau ferré uniquement (métro/tram/RER).
      // Les ~41 700 arrêts de bus surchargent la carte — ils restent
      // visibles dans le détail d'un trajet qui les emprunte.
      if (n.routeType == 3) continue;
      if (!seen.add(n.stationName)) continue;
      circles.add(CircleMarker(
        point: LatLng(n.lat, n.lon),
        radius: 2.6,
        color: _colorFromHex(n.lineColor),
        borderColor: Colors.white.withValues(alpha: 0.35),
        borderStrokeWidth: 0.5,
      ));
    }
    return circles;
  }

  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return MedColors.accent;
    final v = int.tryParse(hex.padLeft(6, '0'), radix: 16);
    return v != null ? Color(0xFF000000 | v) : MedColors.accent;
  }

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String get _departureTime => _fmt(DateTime.now());
  String get _arrivalTime =>
      _fmt(DateTime.now().add(Duration(seconds: widget.totalSeconds.round())));
  String get _nextDeparture {
    final now = DateTime.now();
    return _fmt(now.add(Duration(minutes: 1, seconds: 60 - now.second)));
  }

  List<List<LatLng>> _computeWalkPolylines() {
    if (!_hasPath) return const [];
    final g = appGraph;
    final ids = widget.pathNodeIds!;
    final result = <List<LatLng>>[];
    if (widget.fromLat != null && widget.fromLon != null) {
      final firstNode = g.nodes[ids.first];
      if (firstNode != null) {
        result.add([
          LatLng(widget.fromLat!, widget.fromLon!),
          LatLng(firstNode.lat, firstNode.lon),
        ]);
      }
    }
    if (widget.toLat != null && widget.toLon != null) {
      final lastNode = g.nodes[ids.last];
      if (lastNode != null) {
        result.add([
          LatLng(lastNode.lat, lastNode.lon),
          LatLng(widget.toLat!, widget.toLon!),
        ]);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    _ensureRenderData();
    final segs = _segments;
    final stations = _stations;
    final walkLines = _walkLines;
    final hasBack = widget.showDeparturePanel;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _hasPath ? 13.5 : 11.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.efrei.med',
              ),
              if (segs.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final s in segs)
                      Polyline(
                        points: s.points,
                        color: s.color.withValues(alpha: 0.22),
                        strokeWidth: 14.0,
                      ),
                  ],
                ),
              if (segs.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final s in segs)
                      Polyline(
                        points: s.points,
                        color: s.color,
                        strokeWidth: 5.0,
                      ),
                  ],
                ),
              if (walkLines.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    for (final pts in walkLines)
                      Polyline(
                        points: pts,
                        color: Colors.white.withValues(alpha: 0.85),
                        strokeWidth: 3.5,
                        pattern: StrokePattern.dashed(segments: const [10, 7]),
                      ),
                  ],
                ),
              if (walkLines.isNotEmpty)
                MarkerLayer(
                  markers: [
                    if (widget.fromLat != null && widget.fromLon != null)
                      Marker(
                        point: LatLng(widget.fromLat!, widget.fromLon!),
                        width: 28,
                        height: 28,
                        alignment: Alignment.bottomCenter,
                        child: const _AddressPin(),
                      ),
                    if (widget.toLat != null && widget.toLon != null)
                      Marker(
                        point: LatLng(widget.toLat!, widget.toLon!),
                        width: 28,
                        height: 28,
                        alignment: Alignment.bottomCenter,
                        child: const _AddressPin(),
                      ),
                  ],
                ),
              // Mode réseau : cercles canvas (rapide, ~1842 points).
              // Mode trajet : marqueurs widgets (peu nombreux, stylés).
              if (!_hasPath)
                CircleLayer(circles: _networkCircles)
              else
                MarkerLayer(
                  markers: [
                    for (final s in stations)
                      Marker(
                        point: LatLng(s.lat, s.lng),
                        width: s.isKey ? 140 : 12,
                        height: s.isKey ? 52 : 12,
                        alignment: s.isKey
                            ? Alignment.bottomCenter
                            : Alignment.center,
                        child: s.isKey
                            ? _StationLabel(name: s.name, color: s.color)
                            : _StationDot(color: s.color),
                      ),
                  ],
                ),
            ],
          ),

          // Barre supérieure
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: MedColors.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: MedColors.dividerColor),
                ),
                child: Row(
                  children: [
                    if (hasBack)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: const BoxDecoration(
                              color: MedColors.surface2,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 14, color: MedColors.text),
                        ),
                      ),
                    const Icon(Icons.map_rounded,
                        color: MedColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hasPath
                            ? '${widget.from} → ${widget.to}'
                            : 'Réseau Île-de-France',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Panneau de départ
          if (_hasPath && hasBack)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _DeparturePanel(
                departureTime: _departureTime,
                arrivalTime: _arrivalTime,
                nextDeparture: _nextDeparture,
                totalSeconds: widget.totalSeconds,
                co2SavedKg: _co2.savedKg,
                saved: _tripSaved,
                onSave: _saveTrip,
              ),
            ),

          // Infos réseau (onglet carte)
          if (!hasBack)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: MedColors.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(
                      top: BorderSide(
                          color: MedColors.dividerColor, width: 0.8)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Row(
                  children: [
                    const Icon(Icons.hub_rounded,
                        color: MedColors.accent, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _hasPath
                          ? '${widget.pathNodeIds!.length} nœuds · trajet A*'
                          : '${appGraph.nodeCount} stations · ${appGraph.edgeCount} connexions',
                      style: const TextStyle(
                          fontSize: 12, color: MedColors.secondary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panneau horaires + enregistrement
// ---------------------------------------------------------------------------

class _DeparturePanel extends StatelessWidget {
  const _DeparturePanel({
    required this.departureTime,
    required this.arrivalTime,
    required this.nextDeparture,
    required this.totalSeconds,
    required this.co2SavedKg,
    required this.saved,
    required this.onSave,
  });

  final String departureTime;
  final String arrivalTime;
  final String nextDeparture;
  final double totalSeconds;
  final double co2SavedKg;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final mins = (totalSeconds / 60).round();
    return Container(
      decoration: BoxDecoration(
        color: MedColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
            top: BorderSide(color: MedColors.dividerColor, width: 0.8)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, -4)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: MedColors.surface2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Départ / Arrivée
          Row(
            children: [
              Expanded(
                child: _TimeCell(
                  icon: Icons.play_arrow_rounded,
                  iconColor: MedColors.green,
                  label: 'Départ maintenant',
                  time: departureTime,
                ),
              ),
              Container(width: 1, height: 48, color: MedColors.dividerColor),
              Expanded(
                child: _TimeCell(
                  icon: Icons.flag_rounded,
                  iconColor: MedColors.accent,
                  label: 'Arrivée estimée',
                  time: arrivalTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Prochain départ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MedColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: MedColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Prochain départ · $nextDeparture',
                  style: const TextStyle(
                      fontSize: 12, color: MedColors.secondary),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MedColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$mins min',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MedColors.accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Bouton enregistrer
          GestureDetector(
            onTap: saved ? null : onSave,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: saved
                    ? MedColors.green.withValues(alpha: 0.15)
                    : MedColors.green,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    saved
                        ? Icons.check_circle_rounded
                        : Icons.save_alt_rounded,
                    color: saved ? MedColors.green : Colors.black,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    saved
                        ? 'Trajet enregistré · ${co2SavedKg.toStringAsFixed(2)} kg CO₂ éco.'
                        : 'Enregistrer ce trajet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: saved ? MedColors.green : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.time,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(height: 4),
        Text(label,
            style:
                const TextStyle(fontSize: 10, color: MedColors.secondary)),
        const SizedBox(height: 2),
        Text(time,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Types internes
// ---------------------------------------------------------------------------

class _Station {
  const _Station(
      {required this.name,
      required this.lat,
      required this.lng,
      required this.color,
      required this.isKey});
  final String name;
  final double lat;
  final double lng;
  final Color color;
  final bool isKey;
}

class _Segment {
  const _Segment(this.color, this.points);
  final Color color;
  final List<LatLng> points;
}

class _StationLabel extends StatelessWidget {
  const _StationLabel({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: MedColors.bg.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
          ),
          child: Text(
            name,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }
}

class _StationDot extends StatelessWidget {
  const _StationDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
      ),
    );
  }
}

class _AddressPin extends StatelessWidget {
  const _AddressPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4), blurRadius: 6),
            ],
          ),
          child: const Icon(Icons.location_on_rounded,
              size: 14, color: Colors.black87),
        ),
        Container(width: 2, height: 6, color: Colors.white),
      ],
    );
  }
}
