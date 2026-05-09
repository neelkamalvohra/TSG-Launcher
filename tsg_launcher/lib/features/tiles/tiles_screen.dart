import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/tile_model.dart';
import 'tile_card.dart';
import 'tile_quickinfo_provider.dart';
import 'tiles_provider.dart';

// ── Palette (shared with login) ───────────────────────────────────────────────
const _bgDeep   = Color(0xFF020C1B);
const _bgMid    = Color(0xFF051525);
const _accent   = Color(0xFF2979FF);
const _accentLt = Color(0xFF5C9EFF);
const _muted    = Color(0xFF6B88A8);

// ── Subtle dot-grid background painter ───────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A3A6E).withOpacity(0.45)
      ..style = PaintingStyle.fill;
    const step = 28.0;
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
    // Faint corner glows
    final glowPaint = Paint()
      ..style = PaintingStyle.fill;
    glowPaint.shader = RadialGradient(
      colors: [_accent.withOpacity(0.09), Colors.transparent],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: size.width * 0.55));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);

    // Bottom-right soft glow
    final br = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [_accentLt.withOpacity(0.07), Colors.transparent],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width, size.height),
          radius: size.width * 0.6));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), br);

    // Faint diagonal signal lines
    final linePaint = Paint()
      ..color = const Color(0xFF1E5AAA).withOpacity(0.1)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final rng = Random(42);
    for (var i = 0; i < 6; i++) {
      final sx = rng.nextDouble() * size.width;
      final sy = rng.nextDouble() * size.height * 0.4;
      canvas.drawLine(
        Offset(sx, sy),
        Offset(sx + 80 + rng.nextDouble() * 60, sy + 160 + rng.nextDouble() * 80),
        linePaint,
      );
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class TilesScreen extends ConsumerStatefulWidget {
  const TilesScreen({super.key});

  @override
  ConsumerState<TilesScreen> createState() => _TilesScreenState();
}

class _TilesScreenState extends ConsumerState<TilesScreen> {
  Timer? _retryTimer;
  List<String>? _orderedPks;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  void _startAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      ref.invalidate(tilesProvider);
    });
  }

  void _stopAutoRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  int _columnCount(BoxConstraints constraints, Orientation orientation) {
    final width = constraints.maxWidth;
    if (orientation == Orientation.portrait) {
      return width >= 600 ? 3 : 2;
    } else {
      return width >= 900 ? 5 : (width >= 600 ? 4 : 3);
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return 'Connection timed out.\nThe server may be starting up or unreachable.';
        case DioExceptionType.connectionError:
          return 'Cannot reach the server.\nCheck your network or contact your administrator.';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code != null && code >= 500) {
            return 'Server error ($code).\nPlease wait while the service recovers.';
          }
          return 'Unexpected server response ($code).';
        default:
          break;
      }
    }
    final msg = error.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('Failed host lookup')) {
      return 'Cannot reach the server.\nCheck your network or contact your administrator.';
    }
    return 'Failed to load applications.\nThe server may be down or unreachable.';
  }

  // ── Tile order persistence ────────────────────────────────────────────────
  static const _kOrderKey = 'tile_order';

  Future<void> _loadOrder() async {
    const storage = FlutterSecureStorage();
    final raw = await storage.read(key: _kOrderKey);
    if (raw != null && raw.isNotEmpty && mounted) {
      setState(() => _orderedPks = raw.split(','));
    }
  }

  Future<void> _saveOrder(List<TileModel> newOrder) async {
    const storage = FlutterSecureStorage();
    await storage.write(
        key: _kOrderKey, value: newOrder.map((t) => t.pk).join(','));
    if (mounted) {
      setState(() => _orderedPks = newOrder.map((t) => t.pk).toList());
    }
  }

  List<TileModel> _applyOrder(List<TileModel> serverTiles) {
    if (_orderedPks == null) return serverTiles;
    final map = {for (final t in serverTiles) t.pk: t};
    final result = _orderedPks!
        .map((pk) => map[pk])
        .whereType<TileModel>()
        .toList();
    // Append new tiles from server that aren't in the saved order yet
    for (final t in serverTiles) {
      if (!_orderedPks!.contains(t.pk)) result.add(t);
    }
    return result;
  }

  void _swapTiles(List<TileModel> tiles, int fromIndex, int toIndex) {
    final newTiles = List<TileModel>.from(tiles);
    final item = newTiles.removeAt(fromIndex);
    newTiles.insert(toIndex, item);
    _saveOrder(newTiles);
  }

  // ── Tile grid: roster tile renders 2×2, all others in normal rows ─────────
  // Roster tile spans full-width × double-height (2 columns × 2 rows).
  // availableWidth is the screen width passed by the outer LayoutBuilder.
  Widget _buildTileGrid(
      List<TileModel> tiles, int cols, double availableWidth, BuildContext context) {
    const spacing = 14.0;
    final tileWidth = (availableWidth - (cols - 1) * spacing) / cols;
    final rosterH   = tileWidth * 2 + spacing; // 2 rows + 1 gap

    final items = <Widget>[];
    int i = 0;

    while (i < tiles.length) {
      final tile = tiles[i];

      if (tile.quickPanel == 'roster') {
        // ── Full-width, double-height roster tile ────────────────────
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: spacing),
          child: SizedBox(
            height: rosterH,
            child: _buildDraggableTile(tiles, i, availableWidth, context),
          ),
        ));
        i++;
      } else {
        // ── Normal row: up to `cols` non-roster tiles ────────────────
        final rowIdx = <int>[];
        while (i < tiles.length &&
               rowIdx.length < cols &&
               tiles[i].quickPanel != 'roster') {
          rowIdx.add(i);
          i++;
        }
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: spacing),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int j = 0; j < cols; j++) ...[
                  if (j > 0) const SizedBox(width: spacing),
                  if (j < rowIdx.length)
                    Expanded(
                      child: _buildDraggableTile(
                          tiles, rowIdx[j], tileWidth, context),
                    )
                  else
                    const Expanded(child: SizedBox()),
                ],
              ],
            ),
          ),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: items,
    );
  }

  Widget _buildDraggableTile(List<TileModel> tiles, int index,
      double tileWidth, BuildContext context) {
    final tile = tiles[index];
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != index,
      onAcceptWithDetails: (d) => _swapTiles(tiles, d.data, index),
      builder: (ctx, candidateData, _) {
        final isTargeted = candidateData.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          delay: const Duration(milliseconds: 350),
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(
                width: tileWidth,
                child: TileCard(tile: tile, onTap: () {}),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: TileCard(tile: tile, onTap: () {}),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: isTargeted
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accentLt, width: 2),
                  )
                : null,
            child: TileCard(
              tile: tile,
              onTap: () => context.push(
                '/tile/${tile.slug}',
                extra: {'url': tile.launchUrl, 'name': tile.name},
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final tilesAsync = ref.watch(tilesProvider);
    final auth = ref.watch(authProvider);
    final user = auth is AuthStateAuthenticated ? auth.user : null;
    final displayName = user != null
        ? (user.name.isNotEmpty ? user.name : user.username)
        : '';

    tilesAsync.when(
      loading: () => null,
      error: (_, __) => _startAutoRetry(),
      data: (_) => _stopAutoRetry(),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bgDeep,
        // ── Gradient AppBar via a flexible space ──────────────────────────
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.0, 0.5, 1.0],
                colors: [
                  Color(0xFF0A2A5E),
                  Color(0xFF0D3578),
                  Color(0xFF1A4FA0),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x662979FF),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cell_tower, color: _accentLt, size: 20),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'TSG Launcher',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (user != null) ...[
              // User chip
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.18)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 9,
                      backgroundColor: _accent.withOpacity(0.7),
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      displayName,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              tooltip: 'Logout',
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
            if (user != null && user.highestRole.canAccessAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings_rounded,
                    color: _accentLt),
                tooltip: 'Admin Panel',
                onPressed: () => context.push('/admin'),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: Stack(
          children: [
            // Dark dot-grid background
            CustomPaint(
              painter: _DotGridPainter(),
              child: const SizedBox.expand(),
            ),
            tilesAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: _accentLt)),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.orange.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.cloud_off_rounded,
                            size: 56, color: Colors.orange),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Server Unreachable',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _friendlyError(e),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: _muted, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Retrying automatically every 10 seconds…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF4A6A8A), fontSize: 12),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry Now'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => ref.invalidate(tilesProvider),
                      ),
                    ],
                  ),
                ),
              ),
              data: (serverTiles) {
                if (serverTiles.isEmpty) {
                  return const Center(
                    child: Text(
                      'No applications assigned to your role.',
                      style: TextStyle(color: _muted, fontSize: 16),
                    ),
                  );
                }
                final tiles = _applyOrder(serverTiles);
                return OrientationBuilder(
                  builder: (context, orientation) => LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = _columnCount(constraints, orientation);
                      // Subtract horizontal padding (16+16) to get tile content width
                      final contentWidth = constraints.maxWidth - 32.0;
                      return RefreshIndicator(
                        color: _accentLt,
                        backgroundColor: const Color(0xFF0B1D36),
                        onRefresh: () async {
                          ref.invalidate(tilesProvider);
                          ref.invalidate(tileQuickInfoProvider);
                        },
                        child: _buildTileGrid(tiles, cols, contentWidth, context),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

