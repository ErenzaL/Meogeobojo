import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/providers/auth_providers.dart';
import '../models/contribution.dart';
import '../repositories/contribution_repository.dart';

final contributionRepositoryProvider = Provider<ContributionRepository>(
  (ref) => SupabaseContributionRepository(Supabase.instance.client),
);

final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => ImagePickerPhotoPicker(),
);

/// The signed-in user's photo submissions with their review status.
final myContributionsProvider = FutureProvider.autoDispose<List<Contribution>>((
  ref,
) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(contributionRepositoryProvider).mine(user.id);
});
