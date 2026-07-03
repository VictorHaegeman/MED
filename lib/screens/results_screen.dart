import 'package:flutter/material.dart';

import '../core/router_service.dart';
import '../main.dart'
    show appGraph, pathNotifier, tripFromNotifier, tripSecondsNotifier, tripToNotifier;
import '../models/itinerary.dart';
import '../models/search_result.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'detail_screen.dart';

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    required this.from,
    required this.to,
    this.accessible = false,
    this.when,
    this.arriveBy = false,
  });

  final SearchResult from;
  final SearchResult to;

  /// Itinéraires accessibles en fauteuil roulant uniquement.
  final bool accessible;

  /// Horaire choisi (null = maintenant). [arriveBy] : heure d'arrivée visée.
  final DateTime? when;
  final bool arriveBy;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  final _router = RouterService();

  // Résultats "Tous modes" — calculés une fois au démarrage.
  late Future<List<Itinerary>> _baseItineraries;

  // Résultats filtrés — recalculés à chaque changement de mode.
  Future<List<Itinerary>>? _filteredItineraries;

  TransportMode? _filter; // null = Tous

  // Accessibilité fauteuil — modifiable depuis l'écran de résultats
  // (initialisée depuis l'option choisie à l'accueil).
  late bool _accessible = widget.accessible;

  Future<List<Itinerary>> _query({TransportMode? mode}) =>
      _router.findItineraries(
        widget.from,
        widget.to,
        modeFilter: mode,
        accessible: _accessible,
        when: widget.when,
        arriveBy: widget.arriveBy,
      );

  @override
  void initState() {
    super.initState();
    _baseItineraries = _query();
    _baseItineraries.then(_publishFirst);
  }

  void _publishFirst(List<Itinerary> list) {
    if (list.isNotEmpty) {
      pathNotifier.value = list.first.pathNodeIds;
      tripSecondsNotifier.value = list.first.totalSeconds;
      tripFromNotifier.value = widget.from.displayName;
      tripToNotifier.value = widget.to.displayName;
    }
  }

  void _setFilter(TransportMode? mode) {
    setState(() {
      _filter = mode;
      if (mode == null) {
        _filteredItineraries = null; // revient aux résultats de base
        _baseItineraries.then(_publishFirst); // resynchronise la carte
      } else {
        _filteredItineraries = _query(mode: mode).then((list) {
          _publishFirst(list);
          return list;
        });
      }
    });
  }

  /// Bascule le mode accessible : recalcule les résultats courants
  /// (le tri par durée donne le chemin accessible le plus court en tête).
  void _toggleAccessible() {
    setState(() {
      _accessible = !_accessible;
      _baseItineraries = _query();
      if (_filter == null) {
        _filteredItineraries = null;
        _baseItineraries.then(_publishFirst);
      } else {
        _filteredItineraries = _query(mode: _filter).then((list) {
          _publishFirst(list);
          return list;
        });
      }
    });
  }

  Future<List<Itinerary>> get _currentFuture =>
      _filter == null ? _baseItineraries : _filteredItineraries!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête
              Row(
                children: [
                  const BackCircle(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.from.displayName} → ${widget.to.displayName}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(_subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: MedColors.secondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _filterChips(),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Itinerary>>(
                  // force rebuild quand le filtre ou l'accessibilité change
                  key: ValueKey('$_filter-$_accessible'),
                  future: _currentFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: MedColors.accent));
                    }
                    final list = snapshot.data!;
                    if (list.isEmpty) {
                      return _emptyState();
                    }
                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _itineraryCard(list[i]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Graphe intermodal · ${appGraph.nodeCount} stations · ${appGraph.edgeCount} connexions',
                  style: const TextStyle(
                      fontSize: 11, color: MedColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _weekdaysFr = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  static const _monthsFr = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  String get _subtitle {
    final parts = <String>[];
    final w = widget.when;
    if (w == null) {
      parts.add('Aujourd\'hui · départ maintenant');
    } else {
      final now = DateTime.now();
      final sameDay =
          w.year == now.year && w.month == now.month && w.day == now.day;
      final day = sameDay
          ? 'Aujourd\'hui'
          : '${_weekdaysFr[w.weekday - 1]} ${w.day} ${_monthsFr[w.month - 1]}';
      final hm =
          '${w.hour.toString().padLeft(2, '0')}:${w.minute.toString().padLeft(2, '0')}';
      parts.add('$day · ${widget.arriveBy ? 'arriver à' : 'partir à'} $hm');
    }
    if (_accessible) parts.add('♿ accessible');
    return parts.join(' · ');
  }

  Widget _filterChips() {
    final filters = <(TransportMode?, String)>[
      (null, 'Tous'),
      (TransportMode.metro, '🚇 Métro'),
      (TransportMode.tram, '🚊 Tram'),
      (TransportMode.bus, '🚌 Bus'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (mode, label) in filters)
          MedChip(
            label: label,
            selected: _filter == mode,
            onTap: () => _setFilter(mode),
          ),
        // Interrupteur combinable avec le filtre de mode : « accessible +
        // bus » = trajets bus accessibles uniquement.
        MedChip(
          label: '♿ Accessible',
          selected: _accessible,
          onTap: _toggleAccessible,
        ),
      ],
    );
  }

  String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _emptyState() {
    final modeName = switch (_filter) {
      TransportMode.metro => 'métro ou RER',
      TransportMode.tram => 'tram',
      TransportMode.bus => 'bus',
      _ => 'ce mode',
    };
    final msg = _accessible
        ? 'Aucun itinéraire accessible en fauteuil${_filter != null ? ' en $modeName' : ''}\nentre ces deux points.'
        : 'Aucun itinéraire en $modeName\nentre ces deux points.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('😕', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                color: MedColors.secondary,
                height: 1.5),
          ),
          const SizedBox(height: 16),
          MedChip(
            label: 'Voir tous les modes',
            onTap: () => _setFilter(null),
          ),
        ],
      ),
    );
  }

  Widget _itineraryCard(Itinerary it) {
    return MedCard(
      border: it.highlighted ? it.tagColor : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailScreen(itinerary: it)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: it.tagColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(it.tag,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: it.tagColor)),
              ),
              Text(it.durationLabel,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              ..._rideBadges(it),
              const SizedBox(width: 6),
              Flexible(
                child: Text(it.detail,
                    style: const TextStyle(
                        fontSize: 12, color: MedColors.secondary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              if (it.departAt != null && it.arriveAt != null) ...[
                Text('🕐 ${_hm(it.departAt!)} → ${_hm(it.arriveAt!)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MedColors.text)),
                const SizedBox(width: 14),
              ],
              Text('🚶 ${it.walkLabel}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MedColors.secondary)),
              const SizedBox(width: 14),
              Flexible(
                child: Text('🌱 ${it.co2Label}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: MedColors.green),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _rideBadges(Itinerary it) {
    final rides = it.legs.whereType<RideLeg>().toList();
    if (rides.isEmpty) {
      return [const Text('🚶', style: TextStyle(fontSize: 15))];
    }
    final widgets = <Widget>[];
    for (var i = 0; i < rides.length; i++) {
      final r = rides[i];
      widgets.add(LineBadge(
          label: r.lineLabel,
          color: r.lineColor,
          darkText: r.darkText,
          mode: r.mode));
      if (i < rides.length - 1) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('›',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MedColors.secondary)),
        ));
      }
    }
    return widgets;
  }
}
