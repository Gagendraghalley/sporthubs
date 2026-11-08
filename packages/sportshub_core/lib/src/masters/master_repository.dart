import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access/access_repository.dart' show userSearchPattern;
import '../supabase/supabase_provider.dart';
import 'location.dart';

final masterRepositoryProvider = Provider<MasterRepository>((ref) => MasterRepository(ref.watch(supabaseProvider)));

// For forms: the active rows, by name. Kept while the app runs (they rarely
// change); admins' saves refresh them.

final dzongkhagsProvider =
    FutureProvider<List<LocationItem>>((ref) => ref.watch(masterRepositoryProvider).dzongkhags());

final gewogsProvider = FutureProvider.family<List<LocationItem>, int>(
  (ref, dzongkhagId) => ref.watch(masterRepositoryProvider).gewogs(dzongkhagId),
);

final villagesProvider = FutureProvider.family<List<LocationItem>, int>(
  (ref, gewogId) => ref.watch(masterRepositoryProvider).villages(gewogId),
);

/// What Admin -> Master data lists: one level, under a parent, matching a
/// search, turned-off rows too when [withInactive].
typedef MasterQuery = ({LocationLevel level, int? dzongkhagId, int? gewogId, String search, bool withInactive});

final masterListProvider = FutureProvider.autoDispose.family<List<LocationItem>, MasterQuery>(
  (ref, q) => ref.watch(masterRepositoryProvider).list(q),
);

/// How many rows Admin -> Master data shows at once; more means narrow it.
const masterListLimit = 300;

class MasterRepository {
  MasterRepository(this._client);
  final SupabaseClient _client;

  Future<List<LocationItem>> dzongkhags() async {
    final rows = await _client.from('dzongkhags').select('id, name, is_active').eq('is_active', true).order('name');
    return rows.map(LocationItem.dzongkhag).toList();
  }

  Future<List<LocationItem>> gewogs(int dzongkhagId) async {
    final rows = await _client
        .from('gewogs')
        .select('id, name, kind, is_active, dzongkhag_id')
        .eq('dzongkhag_id', dzongkhagId)
        .eq('is_active', true)
        .order('name');
    return rows.map(LocationItem.gewog).toList();
  }

  Future<List<LocationItem>> villages(int gewogId) async {
    final rows = await _client
        .from('villages')
        .select('id, name, code, is_active, gewog_id')
        .eq('gewog_id', gewogId)
        .eq('is_active', true)
        .order('name');
    return rows.map(LocationItem.village).toList();
  }

  Future<List<LocationItem>> list(MasterQuery q) async {
    final search = userSearchPattern(q.search);
    switch (q.level) {
      case LocationLevel.dzongkhag:
        var query = _client.from('dzongkhags').select('id, name, is_active');
        if (!q.withInactive) query = query.eq('is_active', true);
        if (search.isNotEmpty) query = query.ilike('name', '%$search%');
        final rows = await query.order('name');
        return rows.map(LocationItem.dzongkhag).toList();
      case LocationLevel.gewog:
        var query =
            _client.from('gewogs').select('id, name, kind, is_active, dzongkhag_id, dzongkhag:dzongkhags(name)');
        if (!q.withInactive) query = query.eq('is_active', true);
        if (q.dzongkhagId != null) query = query.eq('dzongkhag_id', q.dzongkhagId!);
        if (search.isNotEmpty) query = query.ilike('name', '%$search%');
        final rows = await query.order('name').limit(masterListLimit);
        return rows.map(LocationItem.gewog).toList();
      case LocationLevel.village:
        var query = _client.from('villages').select(
            'id, name, code, is_active, gewog_id, gewog:gewogs(name, dzongkhag_id, dzongkhag:dzongkhags(name))');
        if (!q.withInactive) query = query.eq('is_active', true);
        if (q.gewogId != null) {
          query = query.eq('gewog_id', q.gewogId!);
        } else if (q.dzongkhagId != null) {
          // The dzongkhag's gewogs (17 at most), then their villages.
          final gewogs = await _client.from('gewogs').select('id').eq('dzongkhag_id', q.dzongkhagId!);
          query = query.inFilter('gewog_id', [for (final g in gewogs) g['id'] as int]);
        }
        if (search.isNotEmpty) query = query.ilike('name', '%$search%');
        final rows = await query.order('name').limit(masterListLimit);
        return rows.map(LocationItem.village).toList();
    }
  }

  /// A new row ([id] null) or changes to one. [parentId]: the gewog's
  /// dzongkhag or the village's gewog. Returns its id.
  Future<int> save(LocationLevel level,
      {int? id, int? parentId, required String name, String? kind, required bool active}) async {
    final result = switch (level) {
      LocationLevel.dzongkhag =>
        _client.rpc('master_save_dzongkhag', params: {'dzongkhag_id': id, 'name': name, 'active': active}),
      LocationLevel.gewog => _client.rpc('master_save_gewog', params: {
          'gewog_id': id,
          'dzongkhag_id': parentId,
          'name': name,
          'kind': kind ?? GewogKind.gewog,
          'active': active,
        }),
      LocationLevel.village => _client
          .rpc('master_save_village', params: {'village_id': id, 'gewog_id': parentId, 'name': name, 'active': active}),
    };
    return await result as int;
  }
}
