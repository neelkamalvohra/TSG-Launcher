import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/tile_model.dart';
import '../../core/tsg_auth/tsg_auth_service.dart';

final tilesProvider = FutureProvider<List<TileModel>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth is! AuthStateAuthenticated) return [];
  return TsgAuthService.fetchTiles(auth.accessToken);
});
