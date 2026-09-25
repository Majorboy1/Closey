import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/theme/closey_typography.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_avatar.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_sheet.dart';
import '../../core/widgets/closey_surface.dart';
import '../../core/widgets/closey_text_field.dart';
import '../../data/models/connection.dart';
import '../../data/models/enums.dart';
import '../../data/models/meeting.dart';
import '../../data/repositories/meeting_repository.dart';
import '../../state/app_providers.dart';
import '../../state/services.dart';

/// Plans â€” real-world meetups.
///
/// **This screen was completely unreachable in the Expo app.** `plans.tsx` was
/// registered with `href: null`, no screen ever pushed to it, and the README
/// described it as a tab. The calendar, the time-slot picker, the status chips
/// and the Google Calendar hand-off were all dead code.
///
/// It is now reachable from the Chats app bar and from Profile. The calendar is
/// secondary by design â€” the DECISIONS log deliberately downgrades it below the
/// conversation mechanic â€” so it lives behind an explicit entry point rather
/// than competing for a tab.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final meetingsAsync = ref.watch(meetingsProvider);
    final meetings = meetingsAsync.value ?? const <Meeting>[];
    final marked = MeetingRepository.markedDays(meetings);

    final forDay =
        meetings
            .where(
              (m) =>
                  MeetingRepository.isoDay(m.scheduledAt) ==
                  MeetingRepository.isoDay(_selected),
            )
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    final upcoming = meetings.where((m) => m.isUpcoming).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

    return CloseyScaffold(
      appBar: const CloseyAppBar(title: 'Plans'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: Gap.pageInsets,
            child: Text(
              'Pick a day, meet up, add it to your calendar.',
              style: context.text.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: Gap.lg),

          Padding(
            padding: Gap.pageInsets,
            child: MeetingCalendar(
              focusedMonth: _focused,
              selectedDay: _selected,
              markedDays: marked,
              onSelect: (d) => setState(() => _selected = d),
              onMonthChanged: (d) => setState(() => _focused = d),
            ),
          ),

          const SizedBox(height: Gap.xl),

          Padding(
            padding: Gap.pageInsets,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dayLabel(_selected),
                    style: context.text.titleLarge,
                  ),
                ),
                CloseyButton(
                  label: 'New meeting',
                  icon: Icons.add_rounded,
                  size: CloseyButtonSize.sm,
                  onPressed: () => _openCreateSheet(_selected),
                ),
              ],
            ),
          ),

          const SizedBox(height: Gap.md),

          if (forDay.isEmpty)
            Padding(
              padding: Gap.pageInsets,
              child: CloseyEmptyState(
                compact: true,
                icon: Icons.event_available_outlined,
                title: 'Nothing planned',
                message:
                    'No meetups on this day. Tap New meeting to suggest a time.',
              ),
            )
          else
            ...forDay.map(
              (m) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  0,
                  Gap.page,
                  Gap.md,
                ),
                child: MeetingCard(meeting: m),
              ),
            ),

          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: Gap.xl),
            const CloseySectionHeader(title: 'Coming up'),
            ...upcoming
                .take(5)
                .map(
                  (m) => Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.page,
                      0,
                      Gap.page,
                      Gap.md,
                    ),
                    child: MeetingCard(meeting: m, compact: true),
                  ),
                ),
          ],

          const SizedBox(height: Gap.giant),
        ],
      ),
    );
  }

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  Future<void> _openCreateSheet(DateTime day) async {
    final connections =
        ref.read(chatListProvider).value ?? const <Connection>[];
    if (connections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect with someone first, then you can plan a meetup.',
          ),
        ),
      );
      return;
    }

    await showCloseySheet<void>(
      context: context,
      child: _CreateMeetingSheet(
        day: day,
        connections: connections,
        onCreate:
            ({required connection, required scheduledAt, String? note}) async {
              final uid = ref.read(uidProvider);
              if (uid == null) return;
              await ref
                  .read(meetingRepositoryProvider)
                  .createMeeting(
                    connection: connection,
                    proposedBy: uid,
                    scheduledAt: scheduledAt,
                    note: note,
                  );
            },
      ),
    );
  }
}

/// Light-on-dark calendar.
///
/// The Expo version drew a white card on a near-black shell, which was the one
/// place the two conflicting palettes collided most visibly. Here it uses the
/// theme's surface tokens, so it is legible in both modes and no longer looks
/// like a stray component from a different app.
class MeetingCalendar extends StatelessWidget {
  const MeetingCalendar({
    super.key,
    required this.focusedMonth,
    required this.selectedDay,
    required this.markedDays,
    required this.onSelect,
    required this.onMonthChanged,
  });

  final DateTime focusedMonth;
  final DateTime selectedDay;
  final Set<String> markedDays;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChanged;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final firstOfMonth = DateTime(focusedMonth.year, focusedMonth.month, 1);
    // weekday: Mon = 1 â€¦ Sun = 7, so this gives a Monday-first grid.
    final leadingBlanks = firstOfMonth.weekday - 1;
    final daysInMonth = DateTime(
      focusedMonth.year,
      focusedMonth.month + 1,
      0,
    ).day;
    final today = DateTime.now();

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(focusedMonth.year, focusedMonth.month, day);
      final key = MeetingRepository.isoDay(date);
      final isSelected =
          date.year == selectedDay.year &&
          date.month == selectedDay.month &&
          date.day == selectedDay.day;
      final isToday =
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final hasMeeting = markedDays.contains(key);

      cells.add(
        _DayCell(
          day: day,
          isSelected: isSelected,
          isToday: isToday,
          hasMeeting: hasMeeting,
          onTap: () => onSelect(date),
        ),
      );
    }

    return CloseyCard(
      child: Column(
        children: [
          Row(
            children: [
              CloseyIconButton(
                icon: Icons.chevron_left_rounded,
                size: 36,
                iconSize: 19,
                semanticLabel: 'Previous month',
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month - 1, 1),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthNames[focusedMonth.month - 1]} ${focusedMonth.year}',
                    style: context.text.titleSmall,
                  ),
                ),
              ),
              CloseyIconButton(
                icon: Icons.chevron_right_rounded,
                size: 36,
                iconSize: 19,
                semanticLabel: 'Next month',
                onPressed: () => onMonthChanged(
                  DateTime(focusedMonth.year, focusedMonth.month + 1, 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: _weekdays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: context.text.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: Gap.sm),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: cells,
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.hasMeeting,
    required this.onTap,
  });

  final int day;
  final bool isSelected;
  final bool isToday;
  final bool hasMeeting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      selected: isSelected,
      button: true,
      label: 'Day $day${hasMeeting ? ', has a meetup' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? colors.brand : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected || isToday
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: isSelected
                      ? colors.textOnBrand
                      : isToday
                      ? colors.accentText
                      : colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasMeeting ? colors.brand : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single meetup.
class MeetingCard extends ConsumerStatefulWidget {
  const MeetingCard({super.key, required this.meeting, this.compact = false});

  final Meeting meeting;
  final bool compact;

  @override
  ConsumerState<MeetingCard> createState() => _MeetingCardState();
}

class _MeetingCardState extends ConsumerState<MeetingCard> {
  bool _busy = false;

  Future<void> _update(MeetingStatus status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(meetingRepositoryProvider)
          .updateStatus(widget.meeting.id, status);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCalendar() async {
    final url = Uri.parse(widget.meeting.googleCalendarUrl());
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final meeting = widget.meeting;
    final uid = ref.watch(uidProvider);
    final name = meeting.otherUser?.fullName ?? 'your connection';

    final (tone, label) = switch (meeting.status) {
      MeetingStatus.proposed => (CloseyBadgeTone.warning, 'Proposed'),
      MeetingStatus.accepted => (CloseyBadgeTone.success, 'Confirmed'),
      MeetingStatus.completed => (CloseyBadgeTone.success, 'Met up'),
      MeetingStatus.declined => (CloseyBadgeTone.neutral, 'Declined'),
      MeetingStatus.cancelled => (CloseyBadgeTone.danger, 'Cancelled'),
    };

    return CloseyCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CloseyAvatar(
                name: name,
                imageUrl: meeting.otherUser?.primaryPhoto,
                size: widget.compact ? 40 : 46,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('With $name', style: context.text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      _formatWhen(meeting.scheduledAt),
                      style: context.text.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              CloseyBadge(label: label, tone: tone),
            ],
          ),

          if (meeting.note != null && meeting.note!.isNotEmpty) ...[
            const SizedBox(height: Gap.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gap.md),
              decoration: BoxDecoration(
                color: colors.surfaceSunken,
                borderRadius: Radii.allSm,
              ),
              child: Text(
                meeting.note!,
                style: context.text.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: Gap.md),

          if (meeting.canRespond(uid ?? ''))
            Row(
              children: [
                Expanded(
                  child: CloseyButton(
                    label: 'Accept',
                    size: CloseyButtonSize.sm,
                    fullWidth: true,
                    loading: _busy,
                    onPressed: () => _update(MeetingStatus.accepted),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Expanded(
                  child: CloseyButton(
                    label: 'Decline',
                    size: CloseyButtonSize.sm,
                    variant: CloseyButtonVariant.secondary,
                    fullWidth: true,
                    onPressed: _busy
                        ? null
                        : () => _update(MeetingStatus.declined),
                  ),
                ),
              ],
            )
          else if (meeting.status == MeetingStatus.accepted)
            CloseyButton(
              label: 'Open in Google Calendar',
              icon: Icons.open_in_new_rounded,
              variant: CloseyButtonVariant.secondary,
              size: CloseyButtonSize.sm,
              fullWidth: true,
              onPressed: _openCalendar,
            )
          else if (meeting.isMine(uid ?? '') &&
              meeting.status == MeetingStatus.proposed)
            Text(
              'Waiting for them to confirm.',
              style: context.text.bodySmall?.copyWith(
                color: colors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  static String _formatWhen(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} Â· $hh:$mm';
  }
}

/// Sheet for proposing a meetup: pick a person, pick a slot, add a note.
class _CreateMeetingSheet extends StatefulWidget {
  const _CreateMeetingSheet({
    required this.day,
    required this.connections,
    required this.onCreate,
  });

  final DateTime day;
  final List<Connection> connections;
  final Future<void> Function({
    required Connection connection,
    required DateTime scheduledAt,
    String? note,
  })
  onCreate;

  @override
  State<_CreateMeetingSheet> createState() => _CreateMeetingSheetState();
}

class _CreateMeetingSheetState extends State<_CreateMeetingSheet> {
  Connection? _connection;
  String? _slot;
  final _note = TextEditingController();
  bool _busy = false;

  /// 30-minute slots across the evening. Chosen deliberately narrow: this is a
  /// dating app, and a wall of every half hour in the day is worse than a short
  /// list of plausible times.
  static const _slots = [
    '12:00',
    '13:00',
    '17:30',
    '18:00',
    '18:30',
    '19:00',
    '19:30',
    '20:00',
    '21:00',
  ];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final connection = _connection;
    final slot = _slot;
    if (connection == null || slot == null) return;

    final parts = slot.split(':');
    final when = DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );

    setState(() => _busy = true);
    try {
      await widget.onCreate(
        connection: connection,
        scheduledAt: when,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = signedInUid(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CloseySheetHeader(
              title: 'Set a meeting',
              subtitle: 'They will get a request to confirm.',
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: Gap.sheetInsets,
                children: [
                  Text('Who', style: context.eyebrow()),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    children: widget.connections
                        .map(
                          (c) => CloseyChip(
                            label: c.otherUser(uid).fullName,
                            selected: _connection?.id == c.id,
                            onTap: () => setState(() => _connection = c),
                            dense: true,
                          ),
                        )
                        .toList(),
                  ),

                  const SizedBox(height: Gap.xl),
                  Text('When', style: context.eyebrow()),
                  const SizedBox(height: Gap.sm),
                  Wrap(
                    spacing: Gap.sm,
                    runSpacing: Gap.sm,
                    children: _slots
                        .map(
                          (s) => CloseyChip(
                            label: s,
                            selected: _slot == s,
                            onTap: () => setState(() => _slot = s),
                            dense: true,
                          ),
                        )
                        .toList(),
                  ),

                  const SizedBox(height: Gap.xl),
                  CloseyTextField(
                    label: 'Note (optional)',
                    controller: _note,
                    hint: 'Where to meet, or what you have in mind',
                    maxLines: 2,
                    maxLength: 160,
                  ),

                  const SizedBox(height: Gap.xxl),
                  CloseyButton(
                    label: 'Send request',
                    fullWidth: true,
                    size: CloseyButtonSize.lg,
                    loading: _busy,
                    onPressed: (_connection == null || _slot == null)
                        ? null
                        : _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The create sheet needs the signed-in uid for its "who" chips. A tiny helper
/// keeps the widget tree from having to become a `ConsumerStatefulWidget` just
/// to read one provider.
String signedInUid(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  return container.read(uidProvider) ?? '';
}
