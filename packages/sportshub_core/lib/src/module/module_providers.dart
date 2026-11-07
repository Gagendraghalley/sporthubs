import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profiles/profile_repository.dart';
import '../supabase/supabase_provider.dart';
import 'app_module_row.dart';
import 'sportshub_module.dart';

/// Every module the app is built with, in main.dart's order. main.dart
/// overrides this:
///   registeredModulesProvider.overrideWithValue([GroundBookingModule(), GymModule()])
final registeredModulesProvider = Provider<List<SportsHubModule>>((ref) => const []);

final moduleRepositoryProvider = Provider<ModuleRepository>((ref) => ModuleRepository(ref.watch(supabaseProvider)));

/// app_modules, which everyone can read.
final appModulesProvider = FutureProvider<List<AppModuleRow>>((ref) => ref.watch(moduleRepositoryProvider).list());

/// The modules to show, in app_modules' order: those turned on, and, for
/// admins, those turned off too (so they can try one before it goes live).
/// A module with no app_modules row stays hidden.
final enabledModulesProvider = FutureProvider<List<SportsHubModule>>((ref) async {
  final rows = await ref.watch(appModulesProvider.future);
  final profile = await ref.watch(myProfileProvider.future);
  return visibleModules(ref.watch(registeredModulesProvider), rows, isAdmin: profile?.isAdmin ?? false);
});

/// The module that runs venues of [type], among the enabled ones.
final moduleForVenueTypeProvider = Provider.family<SportsHubModule?, String>((ref, type) {
  final modules = ref.watch(enabledModulesProvider).valueOrNull ?? const [];
  for (final m in modules) {
    if (m.servesVenueType(type)) return m;
  }
  return null;
});

/// [registered] modules that [rows] turn on (or every one with a row, for
/// admins), sorted by sort_order.
List<SportsHubModule> visibleModules(List<SportsHubModule> registered, List<AppModuleRow> rows,
    {required bool isAdmin}) {
  final byKey = {for (final r in rows) r.key: r};
  final visible = registered.where((m) {
    final row = byKey[m.key];
    return row != null && (row.isEnabled || isAdmin);
  }).toList();
  visible.sort((a, b) => byKey[a.key]!.sortOrder.compareTo(byKey[b.key]!.sortOrder));
  return visible;
}

class ModuleRepository {
  ModuleRepository(this._client);
  final SupabaseClient _client;

  Future<List<AppModuleRow>> list() async {
    final rows = await _client.from('app_modules').select().order('sort_order');
    return rows.map(AppModuleRow.fromJson).toList();
  }
}
