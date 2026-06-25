import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/graph.dart' show GraphNode;
import '../main.dart' show appGraph;
import '../models/itinerary.dart';
import '../models/search_result.dart';
import '../services/geocoding_service.dart';
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

  // Suggestions pour chaque champ (stations + adresses mélangées)
  List<SearchResult> _fromSuggestions = [];
  List<SearchResult> _toSuggestions = [];

  // Résultats sélectionnés — si null, on wrap le texte en SearchResult.station
  SearchResult? _fromResult;
  SearchResult? _toResult;

  Timer? _fromDebounce;
  Timer? _toDebounce;

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
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Suggestions
  // -------------------------------------------------------------------------

  void _onFromChanged(String q) {
    _fromResult = null;
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 350), () async {
      final suggestions = await _buildSuggestions(q);
      if (mounted) setState(() => _fromSuggestions = suggestions);
    });
    // Stations immédiates
    setState(() {
      _fromSuggestions = _stationMatches(q);
    });
  }

  void _onToChanged(String q) {
    _toResult = null;
    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 350), () async {
      final suggestions = await _buildSuggestions(q);
      if (mounted) setState(() => _toSuggestions = suggestions);
    });
    setState(() {
      _toSuggestions = _stationMatches(q);
    });
  }

  Future<List<SearchResult>> _buildSuggestions(String q) async {
    if (q.trim().length < 2) return [];
    final stations = _stationMatches(q);
    final addresses = await GeocodingService.searchAddress(q, limit: 4);
    // Stations en premier, adresses ensuite (dédupliquées)
    return [...stations, ...addresses];
  }

  List<SearchResult> _stationMatches(String q) {
    if (q.trim().isEmpty) return [];
    final lower = q.toLowerCase();
    return _stationNames
        .where((s) => s.toLowerCase().contains(lower))
        .take(5)
        .map(SearchResult.station)
        .toList();
  }

  void _selectFrom(SearchResult r) {
    _fromResult = r;
    _fromCtrl.text = r.displayName;
    setState(() => _fromSuggestions = []);
  }

  void _selectTo(SearchResult r) {
    _toResult = r;
    _toCtrl.text = r.displayName;
    setState(() => _toSuggestions = []);
  }

  // -------------------------------------------------------------------------
  // Géolocalisation → vraie adresse (geocodage inverse)
  // -------------------------------------------------------------------------

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final completer = Completer<(double, double)>();
      _jsGetCurrentPosition(
        ((JSAny? jsPos) {
          final pos = jsPos as _JsGeoposition;
          completer.complete((pos.coords.latitude, pos.coords.longitude));
        }).toJS,
        ((JSAny? _) => completer.completeError('denied')).toJS,
      );
      final (lat, lon) =
          await completer.future.timeout(const Duration(seconds: 12));

      // Essai de géocodage inverse
      final address = await GeocodingService.reverseGeocode(lat, lon);
      if (address != null) {
        _selectFrom(address);
      } else {
        // Fallback : station la plus proche
        _selectFrom(SearchResult.station(_nearestStationName(lat, lon)));
      }
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

  String _nearestStationName(double lat, double lon) {
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
    return nearest?.stationName ?? '';
  }

  // -------------------------------------------------------------------------
  // Navigation
  // -------------------------------------------------------------------------

  void _swap() {
    final tmpText = _fromCtrl.text;
    final tmpResult = _fromResult;
    _fromCtrl.text = _toCtrl.text;
    _fromResult = _toResult;
    _toCtrl.text = tmpText;
    _toResult = tmpResult;
    setState(() {});
  }

  void _search() {
    final fromText = _fromCtrl.text.trim();
    final toText = _toCtrl.text.trim();
    if (fromText.isEmpty || toText.isEmpty) return;
    final from = _fromResult ?? SearchResult.station(fromText);
    final to = _toResult ?? SearchResult.station(toText);
    // Ferme les dropdowns
    setState(() {
      _fromSuggestions = [];
      _toSuggestions = [];
    });
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResultsScreen(from: from, to: to)));
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
                        _selectTo(SearchResult.station(r));
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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ],
        ),
      ],
    );
  }

  Widget _searchCard() {
    return MedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Champ Départ ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _FieldDot(color: MedColors.green),
              const SizedBox(width: 10),
              Expanded(child: _textField('Départ', _fromCtrl, _onFromChanged,
                  hint: 'Adresse ou station…')),
              // Géolocalisation
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
              // Inverser
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
          if (_fromSuggestions.isNotEmpty)
            _SuggestionDropdown(
              suggestions: _fromSuggestions,
              onSelect: _selectFrom,
            ),
          const Divider(color: MedColors.dividerColor, height: 22),
          // --- Champ Arrivée ---
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const _FieldDot(color: MedColors.accent),
              const SizedBox(width: 10),
              Expanded(child: _textField('Arrivée', _toCtrl, _onToChanged,
                  hint: 'Adresse ou station…')),
            ],
          ),
          if (_toSuggestions.isNotEmpty)
            _SuggestionDropdown(
              suggestions: _toSuggestions,
              onSelect: _selectTo,
            ),
          const SizedBox(height: 14),
          PrimaryButton(label: 'Rechercher un itinéraire', onTap: _search),
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController ctrl,
    void Function(String) onChanged, {
    String hint = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: MedColors.secondary)),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          onSubmitted: (_) => _search(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: MedColors.secondary),
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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
              LineBadge(
                  label: 'T3a',
                  color: MedColors.orange,
                  darkText: true,
                  mode: TransportMode.tram),
              SizedBox(width: 8),
              LineBadge(
                  label: '87',
                  color: MedColors.busGrey,
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

// ---------------------------------------------------------------------------
// Dropdown de suggestions (stations + adresses)
// ---------------------------------------------------------------------------

class _SuggestionDropdown extends StatelessWidget {
  const _SuggestionDropdown({
    required this.suggestions,
    required this.onSelect,
  });

  final List<SearchResult> suggestions;
  final void Function(SearchResult) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: MedColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MedColors.dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < suggestions.length; i++) ...[
            InkWell(
              onTap: () => onSelect(suggestions[i]),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      suggestions[i].isAddress
                          ? Icons.location_on_outlined
                          : Icons.train_rounded,
                      size: 14,
                      color: suggestions[i].isAddress
                          ? MedColors.accent
                          : MedColors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        suggestions[i].displayName,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (i < suggestions.length - 1)
              const Divider(height: 1, color: MedColors.dividerColor),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
