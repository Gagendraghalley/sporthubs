import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_provider.dart';
import 'payment.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) => PaymentRepository(ref.watch(supabaseProvider)));

/// A venue's payments in one module, from [from] up to (not including) [to].
/// Its owner and managers can read them.
final venuePaymentsProvider =
    FutureProvider.family<List<Payment>, ({String venueId, String moduleKey, DateTime from, DateTime to})>(
  (ref, q) => ref.watch(paymentRepositoryProvider).forVenue(q.venueId, moduleKey: q.moduleKey, from: q.from, to: q.to),
);

class PaymentRepository {
  PaymentRepository(this._client);
  final SupabaseClient _client;

  Future<List<Payment>> forVenue(String venueId,
      {required String moduleKey, required DateTime from, required DateTime to}) async {
    final rows = await _client
        .from('payments')
        .select('*, payer:profiles!payments_user_id_fkey(full_name)')
        .eq('venue_id', venueId)
        .eq('module_key', moduleKey)
        .gte('created_at', from.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return rows.map(Payment.fromJson).toList();
  }
}

/// Totals for an income report.
class IncomeSummary {
  final int total;
  final int count;
  final Map<PaymentMethod, int> byMethod;

  const IncomeSummary({required this.total, required this.count, required this.byMethod});

  factory IncomeSummary.of(Iterable<Payment> payments) {
    final byMethod = <PaymentMethod, int>{};
    var total = 0;
    var count = 0;
    for (final p in payments.where((p) => p.isCompleted)) {
      total += p.amount;
      count++;
      byMethod[p.method] = (byMethod[p.method] ?? 0) + p.amount;
    }
    return IncomeSummary(total: total, count: count, byMethod: byMethod);
  }
}
