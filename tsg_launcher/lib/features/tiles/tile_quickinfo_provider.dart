import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_service.dart';

// ── Quick-info API constants ──────────────────────────────────────────────────
// Defaults live in AppConfig; can be overridden at runtime via the Settings tab.

// ── Models ────────────────────────────────────────────────────────────────────

class RosterEntry {
  final String name;
  final String role;
  final String shift;

  const RosterEntry({
    required this.name,
    required this.role,
    required this.shift,
  });

  factory RosterEntry.fromJson(Map<String, dynamic> j) => RosterEntry(
        name: j['employee_name']?.toString() ?? '',
        role: (j['role']?.toString() ?? 'engineer').toLowerCase(),
        shift: j['shift']?.toString() ?? '',
      );

  // ── Shift classification ────────────────────────────────────────────────
  String get _s => shift.toUpperCase();
  bool get isAShift => _s == 'A' || _s == 'AWH';
  bool get isBShift => _s == 'B' || _s == 'BWH';
  bool get isGShift => _s == 'G';
  bool get isWO     => _s == 'WO';
  bool get isLeave  => !isAShift && !isBShift && !isGShift && !isWO;
  bool get isOnDuty => !isWO && !isLeave;

  /// First name only for compact display
  String get firstName => name.split(' ').first;

  /// Short shift label with WFH indicator
  String get shiftLabel {
    if (_s == 'AWH') return 'A(WH)';
    if (_s == 'BWH') return 'B(WH)';
    return _s;
  }
}

class TileQuickInfo {
  final String symbol;
  final List<RosterEntry> engineers;

  const TileQuickInfo({required this.symbol, required this.engineers});

  factory TileQuickInfo.fromJson(Map<String, dynamic> j) {
    final symbol = j['symbol']?.toString() ?? '';
    final engineers = <RosterEntry>[];
    if (j['engineers'] is List) {
      for (final e in j['engineers'] as List) {
        if (e is Map<String, dynamic>) {
          engineers.add(RosterEntry.fromJson(e));
        }
      }
    }
    return TileQuickInfo(symbol: symbol, engineers: engineers);
  }

  List<RosterEntry> _eng(bool Function(RosterEntry) test) =>
      engineers.where((e) => e.role == 'engineer' && test(e)).toList();

  List<RosterEntry> get aShift    => _eng((e) => e.isAShift);
  List<RosterEntry> get bShift    => _eng((e) => e.isBShift);
  List<RosterEntry> get gShift    => _eng((e) => e.isGShift);
  List<RosterEntry> get woList    => _eng((e) => e.isWO);
  List<RosterEntry> get leaveList => _eng((e) => e.isLeave);

  List<RosterEntry> get engineersOnDuty => _eng((e) => e.isOnDuty);
  List<RosterEntry> get engineersOnWO   => _eng((e) => e.isWO);
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// FutureProvider.family keyed by tile slug.
/// Returns null if the tile has no quick-info endpoint or the request fails.
/// Cached for the session (no autoDispose) — invalidate via ref.invalidate(tileQuickInfoProvider).
final tileQuickInfoProvider =
    FutureProvider.family<TileQuickInfo?, String>((ref, slug) async {
  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
    ));
    final resp = await dio.get(
      AppConfig.quickInfoBase,
      queryParameters: {
        'apikey': AppConfig.quickInfoKey,
        'symbol': slug.toUpperCase(),
      },
    );
    if (resp.data is Map<String, dynamic>) {
      return TileQuickInfo.fromJson(resp.data as Map<String, dynamic>);
    }
    return null;
  } catch (_) {
    // Graceful degradation — tile renders without quick info
    return null;
  }
});
