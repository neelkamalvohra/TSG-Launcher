import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/tile_model.dart';
import 'tile_quickinfo_provider.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _cardBorder = Color(0xFF1A3A6E);
const _cardGlow   = Color(0xFF2979FF);
const _iconBg     = Color(0xFF112244);
const _iconColor  = Color(0xFF5C9EFF);
const _descColor  = Color(0xFF6B88A8);
const _accentBlue = Color(0xFF5C9EFF);
const _mutedColor = Color(0xFF6B88A8);

// Shift label colours
const _colA     = Color(0xFF4FC3F7);
const _colB     = Color(0xFFFFB74D);
const _colG     = Color(0xFF81C784);
const _colWO    = Color(0xFF6B88A8);
const _colLeave = Color(0xFFEF9A9A);

// Name text colours per shift
const _nameA     = Color(0xFFCFE9FF);
const _nameB     = Color(0xFFFFE0B2);
const _nameG     = Color(0xFFC8E6C9);
const _nameWO    = Color(0xFF4A6A8A);
const _nameLeave = Color(0xFFBCAAA4);

// ── Shared helpers ────────────────────────────────────────────────────────────
const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _kWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _ddMon(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${_kMonths[d.month - 1]}';

// ── Card shell decoration ─────────────────────────────────────────────────────
BoxDecoration get _cardDecoration => BoxDecoration(
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: _cardBorder, width: 1),
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 1.0],
    colors: [Color(0xFF0D2040), Color(0xFF071530)],
  ),
  boxShadow: [
    BoxShadow(
      color: _cardGlow.withOpacity(0.12),
      blurRadius: 14,
      spreadRadius: 1,
      offset: const Offset(0, 4),
    ),
  ],
);

// ── TileCard ──────────────────────────────────────────────────────────────────
class TileCard extends ConsumerWidget {
  final TileModel tile;
  final VoidCallback onTap;

  const TileCard({super.key, required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget content;

    switch (tile.quickPanel) {
      case 'roster':
        final info = ref.watch(tileQuickInfoProvider(tile.slug)).value;
        content = info != null
            ? _RosterPanel(info: info)
            : _DefaultContent(tile: tile);
        break;
      case 'time':
        content = _TimePanel(tile: tile);
        break;
      case 'date':
        content = _DatePanel(tile: tile);
        break;
      default:
        content = _DefaultContent(tile: tile);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: _cardGlow.withOpacity(0.18),
        highlightColor: _cardGlow.withOpacity(0.08),
        child: Ink(
          decoration: _cardDecoration,
          child: content,
        ),
      ),
    );
  }
}

// ── Default tile (icon + name) ────────────────────────────────────────────────
class _DefaultContent extends StatelessWidget {
  final TileModel tile;
  const _DefaultContent({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIcon(),
          const SizedBox(height: 12),
          Text(
            tile.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          if (tile.description != null && tile.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tile.description!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _descColor, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIcon() {
    const size = 56.0;
    if (tile.iconUrl != null && tile.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: CachedNetworkImage(
          imageUrl: tile.iconUrl!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => _fallbackIcon(size),
        ),
      );
    }
    return _fallbackIcon(size);
  }

  Widget _fallbackIcon(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _iconBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF112855), Color(0xFF0A1A3A)],
          ),
        ),
        child: const Icon(Icons.web_rounded, size: 30, color: _iconColor),
      );
}

// ── Time panel — live updating clock ─────────────────────────────────────────
class _TimePanel extends StatefulWidget {
  final TileModel tile;
  const _TimePanel({required this.tile});

  @override
  State<_TimePanel> createState() => _TimePanelState();
}

class _TimePanelState extends State<_TimePanel> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Align first tick to the next minute boundary
    final secsUntilNextMin = 60 - _now.second;
    Future.delayed(Duration(seconds: secsUntilNextMin), () {
      if (mounted) {
        setState(() => _now = DateTime.now());
        _timer = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted) setState(() => _now = DateTime.now());
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Tile label
          Text(
            widget.tile.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          // Big clock
          Text(
            '$hh:$mm',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w300,
              letterSpacing: 4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          // Date
          Text(
            _ddMon(_now),
            style: const TextStyle(
              color: _mutedColor,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          // Weekday
          Text(
            _kWeekdays[_now.weekday - 1],
            style: const TextStyle(
              color: Color(0xFF3A5A7A),
              fontSize: 10.5,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date panel ────────────────────────────────────────────────────────────────
class _DatePanel extends StatelessWidget {
  final TileModel tile;
  const _DatePanel({required this.tile});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Tile label
          Text(
            tile.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _accentBlue,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          // Big date
          Text(
            _ddMon(now),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w300,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          // Year
          Text(
            now.year.toString(),
            style: const TextStyle(
              color: _mutedColor,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          // Weekday
          Text(
            _kWeekdays[now.weekday - 1],
            style: const TextStyle(
              color: Color(0xFF3A5A7A),
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Roster data panel ─────────────────────────────────────────────────────────
class _RosterPanel extends StatelessWidget {
  final TileQuickInfo info;
  const _RosterPanel({required this.info});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final onDuty = info.engineersOnDuty;
    final onWO   = info.woList;
    final aList  = info.aShift;
    final bList  = info.bShift;
    final gList  = info.gShift;
    final wList  = info.woList;
    final lList  = info.leaveList;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Text(
            "Today's Roster  ${_ddMon(now)}",
            style: const TextStyle(
              color: Color(0xFF5C9EFF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 7),

          // ── On-duty / WO pills ────────────────────────────────────────
          Row(
            children: [
              _pill(
                icon: Icons.circle,
                iconColor: const Color(0xFF4CAF50),
                label: '${onDuty.length} on duty',
                labelColor: const Color(0xFF81C784),
                bg: const Color(0xFF0D3520),
                border: const Color(0xFF1A6A3A),
              ),
              if (onWO.isNotEmpty) ...[
                const SizedBox(width: 5),
                _pill(
                  icon: Icons.circle_outlined,
                  iconColor: _colWO,
                  label: '${onWO.length} WO',
                  labelColor: _colWO,
                  bg: const Color(0xFF0E1828),
                  border: const Color(0xFF2A3A50),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // ── Shift rows ────────────────────────────────────────────────
          if (aList.isNotEmpty) _shiftRow('A', aList, _colA, _nameA),
          if (bList.isNotEmpty) _shiftRow('B', bList, _colB, _nameB),
          if (gList.isNotEmpty) _shiftRow('G', gList, _colG, _nameG),
          if (wList.isNotEmpty) _shiftRow('WO', wList, _colWO, _nameWO),
          if (lList.isNotEmpty) _shiftRow('Leave', lList, _colLeave, _nameLeave),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color labelColor,
    required Color bg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 6, color: iconColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: labelColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _shiftRow(
      String label, List<RosterEntry> entries, Color labelColor, Color nameColor) {
    final names = entries.map((e) => e.firstName).join(' \u00b7 ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Text(
              names,
              style: TextStyle(
                color: nameColor,
                fontSize: 10.5,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
