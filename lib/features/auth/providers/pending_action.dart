import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a guest was trying to do when we asked them to sign in. Held in
/// memory only (never persisted) and carries ids, not tokens or user data.
sealed class PendingAuthAction {
  const PendingAuthAction();
}

class PendingFavorite extends PendingAuthAction {
  const PendingFavorite(this.kakaoId);
  final String kakaoId;
}

class PendingOpenTab extends PendingAuthAction {
  const PendingOpenTab(this.tab);
  final int tab;
}

final pendingAuthActionProvider =
    NotifierProvider<PendingAuthActionController, PendingAuthAction?>(
      PendingAuthActionController.new,
    );

class PendingAuthActionController extends Notifier<PendingAuthAction?> {
  @override
  PendingAuthAction? build() => null;

  void set(PendingAuthAction? action) => state = action;

  /// Returns the action once, then forgets it.
  PendingAuthAction? take() {
    final a = state;
    state = null;
    return a;
  }
}
