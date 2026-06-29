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
  const ResultsScreen({super.key, required this.from, required this.to});

  final SearchResult from;
  final SearchResult to;

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

  @override
  void initState() {
    super.initState();
    _baseItineraries = _router.findItineraries(widget.from, widget.to);
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
      } else {
        _filteredItineraries = _router
            .findItineraries(widget.from, widget.to, modeFilter: mode)
            .then((list) {
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
                        const Text('Aujourd\'hui · départ maintenant',
                            style: TextStyle(
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
                  key: ValueKey(_filter), // force rebuild quand le filtre change
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
      ],
    );
  }

  Widget _emptyState() {
    final modeName = switch (_filter) {
      TransportMode.metro => 'métro ou RER',
      TransportMode.tram => 'tram',
      TransportMode.bus => 'bus',
      _ => 'ce mode',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('😕', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            'Aucun itinéraire en $modeName\nentre ces deux points.',
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
              Text('🚶 ${it.walkLabel}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MedColors.secondary)),
              const SizedBox(width: 14),
              Text('🌱 ${it.co2Label}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: MedColors.green)),
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
