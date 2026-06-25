import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/graph.dart' show GraphNode;
import '../main.dart' show appGraph;
import '../models/itinerary.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'results_screen.dart';

// ---------------------------------------------------------------------------
// JS Interop — Geolocation API (Dart 3.x)
// ---------------------------------------------------------------------------

extension type _JsCoords._(JSObject _) implements JSObject {
  external double get latitude;
  external double get longitude;
}

extension type _JsGeoposition._(JSObject _) implements JSObject {
  external _JsCoords get coords;
}

extension type _JsGeolocation._(JSObject _) implements JSObject {
  external void getCurrentPosition(JSFunction success, JSFunction error);
}

@JS('navigator.geolocation')
external _JsGeolocation get _jsGeolocation;

void _jsGetCurrentPosition(JSFunction success, JSFunction error) =>
    _jsGeolocation.getCurrentPosition(success, error);

// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final Set<TransportMode> _enabledModes = {...TransportMode.values};
  bool _locating = false;

  static const _recents = ['Châtelet', 'République', 'Nation'];

  late final List<String> _stationNames = appGraph.nodes.values
      .map((n) => n.stationName)
      .toSet()
      .toList()
    ..sort();

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _swap() {
    final tmp = _fromCtrl.text;
    _fromCtrl.text = _toCtrl.text;
    _toCtrl.text = tmp;
  }

  void _search() {
    final from = _fromCtrl.text.trim();
    final to = _toCtrl.text.trim();
    if (from.isEmpty || to.isEmpty) return;
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultsScreen(from: from, to: to)));
  }

  // -------------------------------------------------------------------------
  // Géolocalisation → station la plus proche
  // -------------------------------------------------------------------------

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final completer = Completer<(double, double)>();
      _jsGetCurrentPosition(
        ((JSAny? jsPos) {
          final pos = jsPos as _JsGeoposition;
          final coords = pos.coords;
          completer.complete((coords.latitude, coords.longitude));
        }).toJS,
        ((JSAny? _) => completer.completeError('denied')).toJS,
      );
      final (lat, lon) =
          await completer.future.timeout(const Duration(seconds: 12));
      _setNearestStation(lat, lon);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Localisation non disponible — autorisez l\'accès dans le navigateur'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _setNearestStation(double lat, double lon) {
    const dist = Distance();
    GraphNode? nearest;
    double minDist = double.infinity;
    final seen = <String>{};
    for (final node in appGraph.nodes.values) {
      if (!seen.add(node.stationName)) continue;
      final d = dist(LatLng(lat, lon), LatLng(node.lat, node.lon));
      if (d < minDist) {
        minDist = d;
        nearest = node;
      }
    }
    if (nearest != null && mounted) {
      setState(() => _fromCtrl.text = nearest!.stationName);
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: ListView(
            children: [
              _header(),
              const SizedBox(height: 20),
              _searchCard(),
              const SizedBox(height: 20),
              _sectionTitle('Modes activés'),
              const SizedBox(height: 8),
              _modeChips(),
              const SizedBox(height: 20),
              _sectionTitle('Récents'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _recents)
                    MedChip(
                      label: r,
                      onTap: () {
                        _toCtrl.text = r;
                        _search();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _networkCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: MedColors.accent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Text('MED',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bonsoir Victor',
                style: TextStyle(fontSize: 13, color: MedColors.secondary)),
            Text('Où allez-vous ?',
                style:
                    TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _searchCard() {
    return MedCard(
      child: Column(
        children: [
          // --- Champ Départ ---
          Row(
            children: [
              const _FieldDot(color: MedColors.green),
              const SizedBox(width: 10),
              Expanded(
                child: _autocompleteField(
                  'Départ',
                  _fromCtrl,
                  hint: 'Ma position ou station…',
                ),
              ),
              // Bouton géolocalisation
              GestureDetector(
                onTap: _locating ? null : _useMyLocation,
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: MedColors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: _locating
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: MedColors.green),
                        )
                      : const Icon(Icons.my_location_rounded,
                          size: 17, color: MedColors.green),
                ),
              ),
              const SizedBox(width: 4),
              // Bouton inverser
              GestureDetector(
                onTap: _swap,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: MedColors.surface2, shape: BoxShape.circle),
                  child: const Icon(Icons.swap_vert,
                      size: 18, color: MedColors.accent),
                ),
              ),
            ],
          ),
          const Divider(color: MedColors.dividerColor, height: 22),
          // --- Champ Arrivée ---
          Row(
            children: [
              const _FieldDot(color: MedColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: _autocompleteField(
                  'Arrivée',
                  _toCtrl,
                  hint: 'Station d\'arrivée…',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Rechercher un itinéraire', onTap: _search),
        ],
      ),
    );
  }

  Widget _autocompleteField(
    String label,
    TextEditingController ctrl, {
    String hint = '',
  }) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: ctrl.text),
      optionsBuilder: (v) {
        final q = v.text.toLowerCase();
        if (q.isEmpty) return const [];
        return _stationNames.where((s) => s.toLowerCase().contains(q)).take(8);
      },
      onSelected: (val) => ctrl.text = val,
      fieldViewBuilder: (_, c, focus, onSubmit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (c.text != ctrl.text) c.text = ctrl.text;
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: MedColors.secondary)),
            TextField(
              controller: c,
              focusNode: focus,
              onSubmitted: (_) => onSubmit(),
              onChanged: (v) => ctrl.text = v,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: MedColors.secondary),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero),
            ),
          ],
        );
      },
      optionsViewBuilder: (_, onSel, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: MedColors.surface2,
          borderRadius: BorderRadius.circular(12),
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 300),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: opts.length,
              itemBuilder: (_, i) {
                final opt = opts.elementAt(i);
                return InkWell(
                  onTap: () => onSel(opt),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Text(opt,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeChips() {
    const labels = {
      TransportMode.metro: '🚇 Métro',
      TransportMode.tram: '🚊 Tram',
      TransportMode.bus: '🚌 Bus',
      TransportMode.walk: '🚶 Marche',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final mode in TransportMode.values)
          MedChip(
            label: labels[mode]!,
            selected: _enabledModes.contains(mode),
            onTap: () => setState(() {
              _enabledModes.contains(mode)
                  ? _enabledModes.remove(mode)
                  : _enabledModes.add(mode);
            }),
          ),
      ],
    );
  }

  Widget _networkCard() {
    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Réseau intermodal',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text('● Connexe',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: MedColors.green)),
            ],
          ),
          const SizedBox(height: 10),
          const Row(
            children: [
              LineBadge(label: '1', color: MedColors.m1, darkText: true),
              SizedBox(width: 8),
              LineBadge(label: '12', color: MedColors.m12),
              SizedBox(width: 8),
              LineBadge(label: '14', color: MedColors.m14),
              SizedBox(width: 8),
              LineBadge(label: 'T3a', color: MedColors.orange,
                  darkText: true, mode: TransportMode.tram),
              SizedBox(width: 8),
              LineBadge(label: '87', color: MedColors.busGrey,
                  mode: TransportMode.bus),
              SizedBox(width: 8),
              Text('🚶', style: TextStyle(fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '1 842 nœuds · métro + tram + bus + marche · graphe vérifié au lancement',
            style: TextStyle(fontSize: 11, color: MedColors.secondary),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Text(s,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: MedColors.secondary));
}

class _FieldDot extends StatelessWidget {
  const _FieldDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
