import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/care_enums.dart';
import '../../shared/models/care_event.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/ui_kit.dart';
import '../care/care_controller.dart';

/// Unified care calendar: past records and upcoming due dates on one grid.
///
/// The six care collections are projected into [CareEvent] and bucketed by day,
/// so a single calendar can show feeding, exercise, medication, vaccination,
/// grooming and vet visits without the widget knowing anything about Firestore.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final CareController care = context.watch<CareController>();

    if (care.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Care calendar')),
        body: const LoadingView(),
      );
    }

    final List<CareEvent> events = care.calendarEvents();
    final Map<DateTime, List<CareEvent>> byDay = groupByDay(events);

    List<CareEvent> eventsFor(DateTime day) =>
        byDay[DateTime(day.year, day.month, day.day)] ?? const <CareEvent>[];

    final List<CareEvent> selectedEvents =
        _selected == null ? const <CareEvent>[] : eventsFor(_selected!);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Care calendar'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Jump to today',
            icon: const Icon(Icons.today_rounded),
            onPressed: () => setState(() {
              _focused = DateTime.now();
              _selected = DateTime.now();
            }),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Card(
              margin: const EdgeInsets.all(AppTheme.gapLg),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.gapSm),
                child: TableCalendar<CareEvent>(
                  firstDay: DateTime.now().subtract(const Duration(days: 365)),
                  lastDay: DateTime.now().add(const Duration(days: 365)),
                  focusedDay: _focused,
                  calendarFormat: _format,
                  eventLoader: eventsFor,
                  startingDayOfWeek: StartingDayOfWeek.monday,
                  selectedDayPredicate: (DateTime d) =>
                      _selected != null && isSameDay(_selected, d),
                  onDaySelected: (DateTime selected, DateTime focused) {
                    setState(() {
                      _selected = selected;
                      _focused = focused;
                    });
                  },
                  onFormatChanged: (CalendarFormat f) =>
                      setState(() => _format = f),
                  onPageChanged: (DateTime focused) => _focused = focused,
                  availableCalendarFormats: const <CalendarFormat, String>{
                    CalendarFormat.month: 'Month',
                    CalendarFormat.twoWeeks: '2 weeks',
                    CalendarFormat.week: 'Week',
                  },
                  headerStyle: HeaderStyle(
                    formatButtonVisible: true,
                    titleCentered: true,
                    formatButtonShowsNext: false,
                    titleTextStyle:
                        Theme.of(context).textTheme.titleMedium ??
                            const TextStyle(),
                    formatButtonDecoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    formatButtonTextStyle: const TextStyle(fontSize: 12),
                  ),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                    ),
                    todayTextStyle: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    selectedDecoration: const BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                    ),
                    markersMaxCount: 4,
                    markerSize: 5.5,
                    markerMargin: const EdgeInsets.symmetric(horizontal: 1),
                    outsideDaysVisible: false,
                  ),
                  calendarBuilders: CalendarBuilders<CareEvent>(
                    // Markers are coloured per care domain, so the month view
                    // communicates *what kind* of care happened, not just that
                    // something did.
                    markerBuilder: (context, day, dayEvents) {
                      if (dayEvents.isEmpty) return null;
                      final Set<CareType> types =
                          dayEvents.map((CareEvent e) => e.type).toSet();
                      return Padding(
                        padding: const EdgeInsets.only(top: 30),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: types
                              .take(4)
                              .map((CareType t) => Container(
                                    width: 5.5,
                                    height: 5.5,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 1),
                                    decoration: BoxDecoration(
                                      color: t.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ))
                              .toList(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            Expanded(
              child: selectedEvents.isEmpty
                  ? EmptyState(
                      icon: Icons.event_busy_rounded,
                      compact: true,
                      title: 'Nothing on this day',
                      message: _selected == null
                          ? 'Select a day to see its care records.'
                          : 'No care records for '
                              '${_selected!.day}/${_selected!.month}/${_selected!.year}.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.gapLg,
                        0,
                        AppTheme.gapLg,
                        AppTheme.gapXl,
                      ),
                      itemCount: selectedEvents.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppTheme.gapMd),
                      itemBuilder: (context, i) =>
                          _EventCard(event: selectedEvents[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final CareEvent event;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      accent: event.color,
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) => _EventDetail(event: event),
      ),
      child: Row(
        children: <Widget>[
          CareIconTile(icon: event.icon, color: event.color),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.subtitle != null)
                  Text(
                    event.subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                _time(event.occurredAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (event.status != null) ...<Widget>[
                const SizedBox(height: 3),
                AppPill(
                  label: event.status!.label,
                  color: event.status!.color,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _time(DateTime d) {
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event});

  final CareEvent event;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.gapXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CareIconTile(icon: event.icon, color: event.color, size: 46),
              const SizedBox(width: AppTheme.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(event.title,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(event.type.label,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: AppTheme.gapXl),
          DetailRow(
            label: 'When',
            value: _full(event.occurredAt),
            icon: Icons.event_rounded,
          ),
          if (event.subtitle != null)
            DetailRow(
              label: 'Details',
              value: event.subtitle!,
              icon: Icons.info_outline_rounded,
            ),
          if (event.status != null)
            DetailRow(
              label: 'Status',
              value: event.status!.label,
              icon: event.status!.icon,
            ),
          if ((event.detail ?? '').isNotEmpty)
            DetailRow(
              label: 'Notes',
              value: event.detail!,
              icon: Icons.notes_rounded,
            ),
          const SizedBox(height: AppTheme.gapLg),
        ],
      ),
    );
  }

  static String _full(DateTime d) {
    const List<String> months = <String>[
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final int h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '$h12:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour < 12 ? 'AM' : 'PM'}';
  }
}
