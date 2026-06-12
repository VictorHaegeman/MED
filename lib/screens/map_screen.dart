import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int _selectedRoute = 0;

  static const _stations = [
    _Station('Gare de Lyon', 48.8449, 2.3736, MedColors.green, true),
    _Station('Châtelet', 48.8594, 2.3469, MedColors.orange, true),
    _Station('Porte de Versailles', 48.8315, 2.2885, MedColors.accent, true),
    _Station('Avenue de France', 48.8360, 2.3775, MedColors.green, true),
    _Station('Montparnasse', 48.8422, 2.3217, MedColors.secondary, true),
    _Station('Sèvres-Lecourbe', 48.8413, 2.3094, MedColors.secondary, true),
  ];

  static final _routes = [
    // 0: Métro 1 + Métro 12 (plus rapide)
    [
      _RouteSegment(MedColors.m1, [
        LatLng(48.8449, 2.3736),
        LatLng(48.8534, 2.3620),
        LatLng(48.8594, 2.3469),
      ]),
      _RouteSegment(MedColors.m12, [
        LatLng(48.8594, 2.3469),
        LatLng(48.8497, 2.3282),
        LatLng(48.8422, 2.3217),
        LatLng(48.8350, 2.3050),
        LatLng(48.8315, 2.2885),
      ]),
    ],
    // 1: T3a tram
    [
      _RouteSegment(MedColors.orange, [
        LatLng(48.8360, 2.3775),
        LatLng(48.8345, 2.3550),
        LatLng(48.8330, 2.3200),
        LatLng(48.8315, 2.2885),
      ]),
    ],
    // 2: Bus 87 + Bus 39
    [
      _RouteSegment(MedColors.busGrey, [
        LatLng(48.8440, 2.3741),
        LatLng(48.8430, 2.3500),
        LatLng(48.8413, 2.3094),
        LatLng(48.8370, 2.2980),
        LatLng(48.8315, 2.2885),
      ]),
    ],
    // 3: Tout à pied
    [
      _RouteSegment(MedColors.green, [
        LatLng(48.8449, 2.3736),
        LatLng(48.8480, 2.3600),
        LatLng(48.8470, 2.3400),
        LatLng(48.8430, 2.3200),
        LatLng(48.8380, 2.3050),
        LatLng(48.8315, 2.2885),
      ]),
    ],
  ];

  static const _routeCards = [
    _RouteCard('LE PLUS RAPIDE', '28 min', MedColors.accent),
    _RouteCard('TRAM DIRECT', '34 min', MedColors.orange),
    _RouteCard('BUS + MARCHE', '41 min', MedColors.busGrey),
    _RouteCard('TOUT À PIED', '1 h 52', MedColors.green),
  ];

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
        initialCenter: LatLng(48.8450, 2.3320),
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.efrei.med',
        ),
        // Routes non-sélectionnées (transparentes)
        PolylineLayer(
          polylines: [
            for (var i = 0; i < _routes.length; i++)
              if (i != _selectedRoute)
                for (final seg in _routes[i])
                  Polyline(
                    points: seg.points,
                    color: seg.color.withValues(alpha: 0.18),
                    strokeWidth: 3.0,
                  ),
          ],
        ),
        // Halo de la route active
        PolylineLayer(
          polylines: [
            for (final seg in _routes[_selectedRoute])
              Polyline(
                points: seg.points,
                color: seg.color.withValues(alpha: 0.25),
                strokeWidth: 12.0,
              ),
          ],
        ),
        // Trait principal de la route active
        PolylineLayer(
          polylines: [
            for (final seg in _routes[_selectedRoute])
              Polyline(
                points: seg.points,
                color: seg.color,
                strokeWidth: 4.5,
              ),
          ],
        ),
        // Marqueurs de stations
        MarkerLayer(
          markers: [
            for (final s in _stations)
              Marker(
                point: LatLng(s.lat, s.lng),
                width: 120,
                height: 52,
                alignment: Alignment.bottomCenter,
                child: _StationMarker(name: s.name, color: s.color),
              ),
          ],
        ),
      ],
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: MedColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MedColors.dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.my_location_rounded,
                color: MedColors.accent, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Gare de Lyon',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('→  Porte de Versailles',
                      style: TextStyle(
                          fontSize: 11, color: MedColors.secondary)),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: MedColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: MedColors.accent, size: 17),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomPanel() {
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
                Text('Itinéraires',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gare de Lyon  →  Porte de Versailles',
                    style: TextStyle(
                        fontSize: 11, color: MedColors.secondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _routeCards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final card = _routeCards[i];
                final active = i == _selectedRoute;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRoute = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 128,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: active
                          ? card.color.withValues(alpha: 0.15)
                          : MedColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? card.color : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(card.tag,
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                color: card.color,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 5),
                        Text(card.duration,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Station {
  const _Station(this.name, this.lat, this.lng, this.color, this.showLabel);
  final String name;
  final double lat;
  final double lng;
  final Color color;
  final bool showLabel;
}

class _RouteSegment {
  const _RouteSegment(this.color, this.points);
  final Color color;
  final List<LatLng> points;
}

class _RouteCard {
  const _RouteCard(this.tag, this.duration, this.color);
  final String tag;
  final String duration;
  final Color color;
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: MedColors.bg.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color == MedColors.secondary ? MedColors.text : color,
              letterSpacing: 0.1,
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
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 5),
            ],
          ),
        ),
      ],
    );
  }
}
