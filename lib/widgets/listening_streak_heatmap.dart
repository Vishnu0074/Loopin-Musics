import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ListeningStreakHeatmap extends StatefulWidget {
  final Map<String, dynamic> dailyPlays;
  final int streakDays;
  final int totalPlays;

  const ListeningStreakHeatmap({
    super.key,
    required this.dailyPlays,
    required this.streakDays,
    this.totalPlays = 0,
  });

  @override
  State<ListeningStreakHeatmap> createState() => _ListeningStreakHeatmapState();
}

class _ListeningStreakHeatmapState extends State<ListeningStreakHeatmap> {
  final ScrollController _allMonthsScrollController = ScrollController();

  DateTime? _selectedDate;
  int? _selectedCount;

  static const _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // Tiny cell dimensions
  static const double _allMonthsCellSize = 10.0;
  static const double _allMonthsCellSpacing = 2.5;

  @override
  void initState() {
    super.initState();
    _scrollToEnd();
  }

  @override
  void dispose() {
    _allMonthsScrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_allMonthsScrollController.hasClients) {
        _allMonthsScrollController.jumpTo(_allMonthsScrollController.position.maxScrollExtent);
      }
    });
  }

  String _formatKey(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String _formatFriendlyDate(DateTime d) {
    const fullWeekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final weekdayName = fullWeekdays[d.weekday % 7];
    final monthName = _monthNames[d.month];
    return '$weekdayName, $monthName ${d.day}';
  }

  int _countFor(DateTime d) {
    final key = _formatKey(d);
    final val = widget.dailyPlays[key];
    if (val is num) return val.toInt();
    return 0;
  }

  Color _cellColor(int count) {
    if (count <= 0) return const Color(0xFF1B1B20);
    if (count <= 2) return AppColors.accent.withValues(alpha: 0.28);
    if (count <= 5) return AppColors.accent.withValues(alpha: 0.52);
    if (count <= 9) return AppColors.accent.withValues(alpha: 0.78);
    return AppColors.accent;
  }

  Border _cellBorder(int count, bool isSelected, {bool isToday = false}) {
    if (isSelected) {
      return Border.all(color: Colors.white, width: 1.4);
    }
    if (isToday) {
      return Border.all(color: AppColors.accent, width: 1.4);
    }
    if (count <= 0) {
      return Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8);
    }
    if (count >= 10) {
      return Border.all(color: Colors.white.withValues(alpha: 0.7), width: 0.8);
    }
    return Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 0.8);
  }

  List<BoxShadow>? _cellShadow(int count) {
    if (count >= 10) {
      return [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.5),
          blurRadius: 4,
          spreadRadius: 0.3,
        ),
      ];
    }
    return null;
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final currentSunday = today.subtract(Duration(days: today.weekday % 7));
    final startSunday = currentSunday.subtract(const Duration(days: 51 * 7));

    // Annual total
    int annualTotal = 0;
    for (int w = 0; w < 52; w++) {
      for (int r = 0; r < 7; r++) {
        final d = startSunday.add(Duration(days: w * 7 + r));
        if (!d.isAfter(today)) {
          annualTotal += _countFor(d);
        }
      }
    }
    if (annualTotal == 0 && widget.totalPlays > 0) {
      annualTotal = widget.totalPlays;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate how many months to display based on:
        // 1. User streak (at least cover streak span)
        // 2. Display width (fit past months to left)
        const monthCardWidth = 202.0;
        final fitByWidth = (constraints.maxWidth / monthCardWidth).floor().clamp(1, 12);
        final fitByStreak = max(1, (widget.streakDays / 28).ceil() + 1);
        final monthsCount = max(fitByWidth, fitByStreak).clamp(1, 12);

        // Generate list of months: oldest month on the left -> current month on the right
        final List<DateTime> monthsList = [];
        for (int i = monthsCount - 1; i >= 0; i--) {
          monthsList.add(DateTime(now.year, now.month - i, 1));
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Sleek compact header row
              _buildCompactHeader(monthsCount),
              const SizedBox(height: 8),

              // Feedback banner when day is tapped
              if (_selectedDate != null) ...[
                _buildSelectedDayBanner(),
                const SizedBox(height: 8),
              ],

              // Annual activity view: a compact, responsive year overview.
              _buildAllMonthsView(startSunday, today),

              const SizedBox(height: 8),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 6),

              // Tiny Footer
              _buildCompactFooter(annualTotal, 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactHeader(int monthsCount) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.calendar_month_rounded,
            color: AppColors.accent,
            size: 14,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Listening Activity',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),
        Text(
          'Last 12 months',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDayBanner() {
    final count = _selectedCount ?? 0;
    final friendly = _formatFriendlyDate(_selectedDate!);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: count > 0 ? AppColors.accent.withValues(alpha: 0.3) : Colors.white10,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _cellColor(count),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$friendly: ',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            count == 0 ? '0 plays' : '$count plays',
            style: TextStyle(
              color: count > 0 ? AppColors.accent : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // ALL MONTHS VIEW (Tiny Full Year)
  // ==========================================

  Widget _buildAllMonthsView(DateTime startSunday, DateTime today) {
    return SingleChildScrollView(
      controller: _allMonthsScrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left row labels (M, W, F)
            _buildDayLabels(),
            const SizedBox(width: 6),

            // Weeks grid with month header
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMonthHeader(startSunday),
                const SizedBox(height: 3),
                _buildWeeksGrid(startSunday, today),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayLabels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 15),
        for (int r = 0; r < 7; r++)
          SizedBox(
            height: _allMonthsCellSize + _allMonthsCellSpacing,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                r == 1 ? 'M' : r == 3 ? 'W' : r == 5 ? 'F' : '',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMonthHeader(DateTime startSunday) {
    final List<Widget> headers = [];
    int lastMonth = -1;
    int weeksSinceLastMonth = 99;

    for (int w = 0; w < 52; w++) {
      final weekSunday = startSunday.add(Duration(days: w * 7));
      final month = weekSunday.month;
      final isNewMonth = month != lastMonth && weeksSinceLastMonth >= 3;

      if (isNewMonth) {
        lastMonth = month;
        weeksSinceLastMonth = 0;
        headers.add(
          SizedBox(
            width: _allMonthsCellSize + _allMonthsCellSpacing,
            child: Text(
              _monthNames[month],
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      } else {
        weeksSinceLastMonth++;
        headers.add(
          const SizedBox(width: _allMonthsCellSize + _allMonthsCellSpacing),
        );
      }
    }

    return SizedBox(
      height: 14,
      child: Row(children: headers),
    );
  }

  Widget _buildWeeksGrid(DateTime startSunday, DateTime today) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int w = 0; w < 52; w++)
          Padding(
            padding: const EdgeInsets.only(right: _allMonthsCellSpacing),
            child: Column(
              children: [
                for (int r = 0; r < 7; r++) ...[
                  _buildAllMonthsDayCell(startSunday, w, r, today),
                  if (r < 6) const SizedBox(height: _allMonthsCellSpacing),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAllMonthsDayCell(
    DateTime startSunday,
    int weekIndex,
    int rowIndex,
    DateTime today,
  ) {
    final date = startSunday.add(Duration(days: weekIndex * 7 + rowIndex));
    final isFuture = date.isAfter(today);

    if (isFuture) {
      return const SizedBox(
        width: _allMonthsCellSize,
        height: _allMonthsCellSize,
      );
    }

    final count = _countFor(date);
    final isTodayDate = _isToday(date);
    final isSelected = _selectedDate != null &&
        _selectedDate!.year == date.year &&
        _selectedDate!.month == date.month &&
        _selectedDate!.day == date.day;
    final friendly = _formatFriendlyDate(date);
    final tooltipText = count == 0
        ? '0 plays on $friendly'
        : '$count plays on $friendly';

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 150),
      textStyle: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
        color: const Color(0xFF26262B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(2),
        onTap: () {
          setState(() {
            _selectedDate = date;
            _selectedCount = count;
          });
        },
        child: Container(
          width: _allMonthsCellSize,
          height: _allMonthsCellSize,
          decoration: BoxDecoration(
            color: _cellColor(count),
            borderRadius: BorderRadius.circular(2),
            border: _cellBorder(count, isSelected, isToday: isTodayDate),
            boxShadow: _cellShadow(count),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactFooter(int totalSongs, int monthsCount) {
    final periodText = '$totalSongs plays in the past year';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          periodText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Less',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            _legendCell(0),
            const SizedBox(width: 2.5),
            _legendCell(2),
            const SizedBox(width: 2.5),
            _legendCell(4),
            const SizedBox(width: 2.5),
            _legendCell(7),
            const SizedBox(width: 2.5),
            _legendCell(12),
            const SizedBox(width: 4),
            Text(
              'More',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendCell(int count) {
    return Container(
      width: 7.5,
      height: 7.5,
      decoration: BoxDecoration(
        color: _cellColor(count),
        borderRadius: BorderRadius.circular(1.5),
        border: _cellBorder(count, false),
      ),
    );
  }
}
