import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/graph.dart' show GraphNode;
import '../main.dart' show appGraph, pathNotifier, tripSecondsNotifier, tripFromNotifier, tripToNotifier;
import '../theme.dart';

/// Appelé sans paramètres depuis le shell (onglet Carte) — lit les notifiers.
/// Appelé avec paramètres depuis DetailScreen ("Démarrer le trajet").
class MapScreen extends StatelessWidget {
  const MapScreen({
    super.key,
    this.pathNodeIds,
    this.totalSeconds,
    this.from,
    this.to,
  });

  final List<String>? pathNodeIds;
  final double? totalSeconds;
  final String? from;
  final String? to;

  @override
  Widget build(BuildContext context) {
    if (pathNodeIds != null) {
      // Mode route — paramètres explicites, pas besoin des notifiers.
      return _MapView(
        pathNodeIds: pathNodeIds,
        totalSeconds: totalSeconds ?? 0,
        from: from ?? '',
        to: to ?? '',
        showDeparturePanel: true,
      );
    }
    // Mode onglet — écoute les notifiers globaux.
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
  });

  final List<String>? pathNodeIds;
  final double totalSeconds;
  final String from;
  final String to;
  final bool showDeparturePanel;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  bool get _hasPath =>
      widget.pathNodeIds != null && widget.pathNodeIds!.isNotEmpty;

  // -------------------------------------------------------------------------
  // Stations clés : départ, correspondances, arrivée uniquement
  // -------------------------------------------------------------------------

  /// Retourne les IDs de nœuds qui méritent un label :
  /// premier nœud, dernier nœud, et chaque nœud où la ligne change.
  Set<String> get _keyNodeIds {
    final ids = widget.pathNodeIds;
    if (ids == null || ids.isEmpty) return {};
    final g = appGraph;
    final keys = <String>{ids.first, ids.last};
    for (int i = 1; i < ids.length - 1; i++) {
      final prevLine = g.nodes[ids[i - 1]]?.line;
      final currLine = g.nodes[ids[i]]?.line;
      final nextLine = g.nodes[ids[i + 1]]?.line;
      // Début ou fin d'un segment de ligne → point clé (correspondance)
      if (currLine != prevLine || currLine != nextLine) {
        keys.add(ids[i]);
      }
    }
    return keys;
  }

  List<_Station> get _stations {
    final g = appGraph;
    if (_hasPath) {
      final ids = widget.pathNodeIds!;
      final keys = _keyNodeIds;
      final seen = <String>{};
      final result = <_Station>[];
      for (int i = 0; i < ids.length; i++) {
        final node = g.nodes[ids[i]];
        if (node == null || !seen.add(node.stationName)) continue;
        final isKey = keys.contains(ids[i]);
        result.add(_Station(
          name: node.stationName,
          lat: node.lat,
          lng: node.lon,
          color: _colorFromHex(node.lineColor),
          isKey: isKey,
        ));
      }
      return result;
    }
    // Vue réseau : un point par station, pas de label
    final seen = <String>{};
    return g.nodes.values
        .where((n) => seen.add(n.stationName))
        .map((n) => _Station(
              name: n.stationName,
              lat: n.lat,
              lng: n.lon,
              color: _colorFromHex(n.lineColor),
              isKey: false,
            ))
        .toList();
  }

  List<_Segment> get _segments {
    if (!_hasPath) return [];
    final g = appGraph;
    final result = <_Segment>[];
    final ids = widget.pathNodeIds!;
    int segStart = 0;
    for (int i = 1; i <= ids.length; i++) {
      final prev = g.nodes[ids[i - 1]];
      if (prev == null) { segStart = i; continue; }
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

  LatLng get _center {
    if (_hasPath) {
      final g = appGraph;
      final nodes = widget.pathNodeIds!
          .map((id) => g.nodes[id])
          .whereType<GraphNode>()
          .toList();
      if (nodes.isNotEmpty) {
        final lat = nodes.map((n) => n.lat).reduce((a, b) => a + b) / nodes.length;
        final lon = nodes.map((n) => n.lon).reduce((a, b) => a + b) / nodes.length;
        return LatLng(lat, lon);
      }
    }
    return const LatLng(48.8566, 2.3522);
  }

  Color _colorFromHex(String? hex) {
    if (hex == null || hex.isEmpty) return MedColors.accent;
    final v = int.tryParse(hex.padLeft(6, '0'), radix: 16);
    return v != null ? Color(0xFF000000 | v) : MedColors.accent;
  }

  // -------------------------------------------------------------------------
  // Horaires
  // -------------------------------------------------------------------------

  String _fmt(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String get _departureTime => _fmt(DateTime.now());

  String get _arrivalTime =>
      _fmt(DateTime.now().add(Duration(seconds: widget.totalSeconds.round())));

  /// Prochain départ estimé : arrondi à la prochaine minute pleine + 1 min.
  String get _nextDeparture {
    final now = DateTime.now();
    final next = now.add(Duration(minutes: 1, seconds: 60 - now.second));
    return _fmt(next);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final segs = _segments;
    final stations = _stations;
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                              color: MedColors.surface2, shape: BoxShape.circle),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 14, color: MedColors.text),
                        ),
                      ),
                    const Icon(Icons.map_rounded, color: MedColors.accent, size: 16),
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

          // Panneau de départ (mode "Démarrer le trajet")
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
              ),
            ),

          // Infos réseau (mode onglet, sans trajet)
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
// Panneau horaires
// ---------------------------------------------------------------------------

class _DeparturePanel extends StatelessWidget {
  const _DeparturePanel({
    required this.departureTime,
    required this.arrivalTime,
    required this.nextDeparture,
    required this.totalSeconds,
  });

  final String departureTime;
  final String arrivalTime;
  final String nextDeparture;
  final double totalSeconds;

  @override
  Widget build(BuildContext context) {
    final mins = (totalSeconds / 60).round();
    return Container(
      decoration: BoxDecoration(
        color: MedColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border:
            Border(top: BorderSide(color: MedColors.dividerColor, width: 0.8)),
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
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
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
            style: const TextStyle(
                fontSize: 10, color: MedColors.secondary)),
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
  const _Station({
    required this.name,
    required this.lat,
    required this.lng,
    required this.color,
    required this.isKey,
  });
  final String name;
  final double lat;
  final double lng;
  final Color color;
  final bool isKey; // true = départ, correspondance ou arrivée
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
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
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
        border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
      ),
    );
  }
}
