import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/models/tile_model.dart';
import 'tile_quickinfo_provider.dart';

// ── Local SVG icon map (slug → asset path) ────────────────────────────────────
// Keys are matched against tile.slug first, then against a normalised tile.name.
const _localIcons = <String, String>{
  'quick-response':  'assets/icons/quick_response.svg',
  'quick_response':  'assets/icons/quick_response.svg',
  'roster-edit':     'assets/icons/roster_edit.svg',
  'roster_edit':     'assets/icons/roster_edit.svg',
  'roster-upload':   'assets/icons/roster_upload.svg',
  'roster_upload':   'assets/icons/roster_upload.svg',
};

// ── Palette ───────────────────────────────────────────────────────────────────
const _cardBorder = Color(0xFF1E3F74);
const _cardGlow   = Color(0xFF2979FF);
const _accentBlue = Color(0xFF5C9EFF);
const _mutedColor = Color(0xFF6B88A8);
const _descColor  = Color(0xFF6B88A8);

// Shift colors
const _colA     = Color(0xFF4FC3F7);
const _colB     = Color(0xFFFFB74D);
const _colG     = Color(0xFF81C784);
const _colWO    = Color(0xFF6B88A8);
const _colLeave = Color(0xFFEF9A9A);

// Avatar color palette
const _avatarPalette = [
  Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFFE91E63),
  Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF00BCD4),
  Color(0xFFFF5722), Color(0xFF3F51B5),
];

// ── Helpers ───────────────────────────────────────────────────────────────────
const _kMonths   = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
const _kWeekdays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];

String _ddMon(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${_kMonths[d.month - 1]}';

Color _avatarColor(String name) =>
    _avatarPalette[name.hashCode.abs() % _avatarPalette.length];

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
  return name.isNotEmpty ? name[0].toUpperCase() : '?';
}

Color _dotColor(RosterEntry e) {
  if (e.isAShift) return _colA;
  if (e.isBShift) return _colB;
  if (e.isGShift) return _colG;
  if (e.isWO)     return _colWO;
  return _colLeave;
}

// ── Card shell ────────────────────────────────────────────────────────────────
BoxDecoration _cardDeco({double glow = 0.15}) => BoxDecoration(
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: _cardBorder, width: 1),
  gradient: const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F2347), Color(0xFF071530)],
  ),
  boxShadow: [
    BoxShadow(
      color: _cardGlow.withOpacity(glow),
      blurRadius: 18, spreadRadius: 0, offset: const Offset(0, 4),
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
        content = info != null ? _RosterPanel(info: info) : _DefaultContent(tile: tile);
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
    return _TapCard(onTap: onTap, child: content);
  }
}

// ── Tap-animated card ─────────────────────────────────────────────────────────
class _TapCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TapCard({required this.onTap, required this.child});
  @override State<_TapCard> createState() => _TapCardState();
}

class _TapCardState extends State<_TapCard> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:  (_) => setState(() => _pressed = true),
      onTapUp:    (_) { setState(() => _pressed = false); widget.onTap(); },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.identity()..scale(_pressed ? 0.96 : 1.0),
        transformAlignment: Alignment.center,
        decoration: _cardDeco(glow: _pressed ? 0.38 : 0.15),
        child: widget.child,
      ),
    );
  }
}

// ── Default tile ──────────────────────────────────────────────────────────────
class _DefaultContent extends StatelessWidget {
  final TileModel tile;
  const _DefaultContent({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _icon(),
          const SizedBox(height: 12),
          Text(tile.name,
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w700, letterSpacing: 0.2)),
          if (tile.description != null && tile.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tile.description!,
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _descColor, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }

  Widget _icon() {
    const sz = 60.0;

    // 1. Local SVG by slug
    final slugKey  = tile.slug.toLowerCase();
    final nameKey  = tile.name.toLowerCase().replaceAll(' ', '-');
    final svgAsset = _localIcons[slugKey] ?? _localIcons[nameKey];
    if (svgAsset != null) {
      return SvgPicture.asset(svgAsset, width: sz, height: sz);
    }

    // 2. Remote URL
    if (tile.iconUrl != null && tile.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(imageUrl: tile.iconUrl!, width: sz, height: sz,
          fit: BoxFit.contain, errorWidget: (_, __, ___) => _fallback(sz)),
      );
    }

    // 3. Generic fallback
    return _fallback(sz);
  }

  Widget _fallback(double sz) => Container(
    width: sz, height: sz,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [_accentBlue.withOpacity(0.6), const Color(0xFF0A237A)]),
      border: Border.all(color: _cardBorder),
      boxShadow: [BoxShadow(color: _cardGlow.withOpacity(0.3), blurRadius: 12)],
    ),
    child: const Icon(Icons.web_rounded, size: 30, color: Colors.white),
  );
}

// ── Time panel ────────────────────────────────────────────────────────────────
class _TimePanel extends StatefulWidget {
  final TileModel tile;
  const _TimePanel({required this.tile});
  @override State<_TimePanel> createState() => _TimePanelState();
}

class _TimePanelState extends State<_TimePanel> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    final secs = 60 - _now.second;
    Future.delayed(Duration(seconds: secs), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    });
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(widget.tile.name.toUpperCase(),
            style: const TextStyle(color: _accentBlue, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          Text('$hh:$mm',
            style: const TextStyle(color: Colors.white, fontSize: 38,
                fontWeight: FontWeight.w300, letterSpacing: 4,
                fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 6),
          Text(_ddMon(_now),
            style: const TextStyle(color: _mutedColor, fontSize: 12, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(_kWeekdays[_now.weekday - 1],
            style: const TextStyle(color: Color(0xFF3A5A7A), fontSize: 10.5)),
        ],
      ),
    );
  }
}

// ── Date panel — with weekday strip ──────────────────────────────────────────
class _DatePanel extends StatelessWidget {
  final TileModel tile;
  const _DatePanel({required this.tile});

  @override
  Widget build(BuildContext context) {
    final now     = DateTime.now();
    final todayWd = now.weekday; // 1=Mon…7=Sun

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tile.name.toUpperCase(),
            style: const TextStyle(color: _accentBlue, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(now.day.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 50,
                    fontWeight: FontWeight.w800, height: 1.0)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_kMonths[now.month - 1],
                      style: const TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Text(now.year.toString(),
                        style: const TextStyle(color: _mutedColor, fontSize: 11)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _accentBlue.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _accentBlue.withOpacity(0.45)),
                        ),
                        child: Text(_kWeekdays[todayWd - 1],
                          style: const TextStyle(color: _accentBlue, fontSize: 10,
                              fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (i) {
              final isToday = (i + 1) == todayWd;
              return Expanded(
                child: Center(
                  child: Container(
                    width: 26, height: 20,
                    decoration: isToday
                        ? BoxDecoration(
                            color: _accentBlue.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: _accentBlue.withOpacity(0.55)))
                        : null,
                    child: Center(
                      child: Text(_kWeekdays[i],
                        style: TextStyle(
                          color: isToday ? _accentBlue : _mutedColor,
                          fontSize: 9,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Roster panel ─────────────────────────────────────────────────────────────
class _RosterPanel extends StatefulWidget {
  final TileQuickInfo info;
  const _RosterPanel({required this.info});
  @override State<_RosterPanel> createState() => _RosterPanelState();
}

class _RosterPanelState extends State<_RosterPanel> {
  bool _woExpanded = false;

  @override
  Widget build(BuildContext context) {
    final now    = DateTime.now();
    final onDuty = widget.info.engineersOnDuty;
    final woList = widget.info.woList;
    final leave  = widget.info.leaveList;

    return ClipRect(
      child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODAY\'S ROSTER',
            style: TextStyle(color: _accentBlue, fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 2),
          Text('${_ddMon(now)} \u00b7 ${_kWeekdays[now.weekday - 1]}',
            style: const TextStyle(color: Colors.white, fontSize: 13,
                fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            _statPill('${onDuty.length} ON DUTY',
                const Color(0xFF4CAF50), const Color(0xFF0D3520), const Color(0xFF1A5E30)),
            if (woList.isNotEmpty) ...[
              const SizedBox(width: 6),
              _statPill('${woList.length} WO',
                  _mutedColor, const Color(0xFF0E1828), const Color(0xFF1E2E40)),
            ],
            if (leave.isNotEmpty) ...[
              const SizedBox(width: 6),
              _statPill('${leave.length} Leave',
                  _colLeave, const Color(0xFF1E0E0E), const Color(0xFF3E1818)),
            ],
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Person rows — Expanded forces tight fit; ClipRect silences any overflow
                Expanded(
                  child: ClipRect(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: onDuty.take(8).map(_personRow).toList(),
                    ),
                  ),
                ),
                // WO section — pinned inside Expanded, never overflows
                if (woList.isNotEmpty || leave.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setState(() => _woExpanded = !_woExpanded),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _cardBorder.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedRotation(
                            turns: _woExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.arrow_drop_down, color: _mutedColor, size: 16)),
                          const SizedBox(width: 4),
                          Text(
                            '${_woExpanded ? 'HIDE' : 'VIEW'} ${woList.length + leave.length} WEEK OFF',
                            style: const TextStyle(color: _mutedColor, fontSize: 10,
                                fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: _woExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ...woList.map((e) => _offRow(e, 'WO', _colWO)),
                                ...leave.map((e) => _offRow(e, 'LV', _colLeave)),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ));
  }

  Widget _statPill(String label, Color text, Color bg, Color border) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg,
            borderRadius: BorderRadius.circular(20), border: Border.all(color: border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: text, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: text, fontSize: 10,
              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ]),
      );

  Widget _personRow(RosterEntry e) {
    final dot = _dotColor(e);
    final av  = _avatarColor(e.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: dot.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: dot.withOpacity(0.45))),
          child: Center(child: Text(e.shiftLabel,
              style: TextStyle(color: dot, fontSize: 9, fontWeight: FontWeight.w900))),
        ),
        const SizedBox(width: 6),
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: av, shape: BoxShape.circle),
          child: Center(child: Text(_initials(e.name),
              style: const TextStyle(color: Colors.white, fontSize: 10,
                  fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(e.name.split(' ').first,
            style: const TextStyle(color: Colors.white, fontSize: 12.5,
                fontWeight: FontWeight.w500))),
        _PulseDot(color: dot),
      ]),
    );
  }

  Widget _offRow(RosterEntry e, String label, Color col) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          color: col.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: col.withOpacity(0.4))),
        child: Center(child: Text(label,
            style: TextStyle(color: col, fontSize: 8, fontWeight: FontWeight.w900))),
      ),
      const SizedBox(width: 6),
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: _avatarColor(e.name), shape: BoxShape.circle),
        child: Center(child: Text(_initials(e.name),
            style: const TextStyle(color: Colors.white, fontSize: 10,
                fontWeight: FontWeight.w800))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(e.name.split(' ').first,
          style: TextStyle(color: col.withOpacity(0.8), fontSize: 12,
              fontWeight: FontWeight.w500))),
    ]),
  );
}

// ── Animated pulse dot ────────────────────────────────────────────────────────
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: 20, height: 20,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Container(
            width: 6 + 12 * _anim.value, height: 6 + 12 * _anim.value,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: widget.color.withOpacity(0.35 * (1 - _anim.value))),
          ),
        ),
        Container(width: 7, height: 7,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
      ]),
    );
  }
}
