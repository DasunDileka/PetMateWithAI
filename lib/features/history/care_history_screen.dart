import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/care_event.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/ui_kit.dart';
import '../care/care_controller.dart';

/// The unified care history: every domain in one chronological feed.
///
/// Filtering happens over the already-loaded window rather than by re-querying
/// Firestore. The listeners feeding [CareController] are bounded to 14 days, so
/// this list is small, and filtering it locally avoids six extra round-trips
/// every time the user taps a chip.
class CareHistoryScreen extends StatefulWidget {
  const CareHistoryScreen({super.key});

  @override
  State<CareHistoryScreen> createState() => _CareHistoryScreenState();
}

class _CareHistoryScreenState extends State<CareHistoryScreen> {
  final Set<CareType> _filter = <CareType>{};

  /// How many day-groups are rendered. Raised by the "load more" control so a
  /// long history does not build hundreds of widgets up front.
  int _visibleDays = 7;

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();

    if (care.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Care history')),
        body: const LoadingView(),
      );
    }

    final List<CareEvent> events = care.historyEvents(filter: _filter);
    final Map<DateTime, List<CareEvent>> grouped = groupByDay(events);

    final List<DateTime> days = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final List<DateTime> visible = days.take(_visibleDays).toList();
    final bool hasMore = days.length > visible.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Care history'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapLg),
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: AppTheme.gapSm),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _filter.isEmpty,
                    onSelected: (_) => setState(_filter.clear),
                  ),
                ),
                ...CareType.values.map((CareType t) => Padding(
                      padding: const EdgeInsets.only(right: AppTheme.gapSm),
                      child: FilterChip(
                        avatar: Icon(
                          t.icon,
                          size: 16,
                          color: _filter.contains(t) ? t.color : null,
                        ),
                        label: Text(t.label),
                        selected: _filter.contains(t),
                        selectedColor: t.color.withValues(alpha: 0.16),
                        checkmarkColor: t.color,
                        onSelected: (bool on) => setState(() {
                          if (on) {
                            _filter.add(t);
                          } else {
                            _filter.remove(t);
                          }
                        }),
                      ),
                    )),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: events.isEmpty
            ? EmptyState(
                icon: Icons.history_rounded,
                title: _filter.isEmpty
                    ? 'No care recorded yet'
                    : 'Nothing matches this filter',
                message: _filter.isEmpty
                    ? 'Record a feeding, walk or dose for ${care.pet.name} and '
                        'it will appear here.'
                    : 'Try selecting a different care type, or clear the '
                        'filter to see everything.',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(AppTheme.gapLg),
                itemCount: visible.length + (hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= visible.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: AppTheme.gapLg),
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _visibleDays += 7),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          'Show earlier '
                          '(${days.length - visible.length} more day'
                          '${days.length - visible.length == 1 ? '' : 's'})',
                        ),
                      ),
                    );
                  }

                  final DateTime day = visible[i];
                  final List<CareEvent> dayEvents = grouped[day]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.only(
                          top: i == 0 ? 0 : AppTheme.gapLg,
                          bottom: AppTheme.gapMd,
                        ),
                        child: Row(
                          children: <Widget>[
                            Text(
                              _dayLabel(day),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(width: AppTheme.gapSm),
                            Expanded(
                              child: Divider(
                                color:
                                    Theme.of(context).colorScheme.outlineVariant,
                              ),
                            ),
                            const SizedBox(width: AppTheme.gapSm),
                            Text(
                              '${dayEvents.length} record'
                              '${dayEvents.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      ...dayEvents.map((CareEvent e) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppTheme.gapMd),
                            child: _HistoryCard(event: e),
                          )),
                    ],
                  );
                },
              ),
      ),
    );
  }

  static String _dayLabel(DateTime day) {
    final DateTime now = DateTime.now();
    final int diff = DateTime(now.year, now.month, now.day)
        .difference(day)
        .inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';

    const List<String> weekdays = <String>[
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    if (diff < 7) return weekdays[day.weekday - 1];
    return '${day.day} ${months[day.month - 1]} ${day.year}';
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.event});

  final CareEvent event;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: event.color,
      child: Row(
        children: <Widget>[
          CareIconTile(icon: event.icon, color: event.color, size: 38),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        event.title,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppTheme.gapSm),
                    Text(
                      _time(event.occurredAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                if (event.subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    event.subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if ((event.detail ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    event.detail!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (event.status != null) ...<Widget>[
            const SizedBox(width: AppTheme.gapSm),
            Icon(event.status!.icon, size: 19, color: event.status!.color),
          ],
        ],
      ),
    );
  }

  static String _time(DateTime d) {
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'am' : 'pm'}';
  }
}
