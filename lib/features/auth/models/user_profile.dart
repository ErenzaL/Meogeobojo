import 'package:flutter/foundation.dart';

import '../../../core/l10n/app_language.dart';

/// Row of `public.profiles`. Holds only what the user gave us or the app
/// needs; the email lives on the Supabase Auth user, not here.
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    this.nickname,
    this.nicknameIsCustom = false,
    this.avatarPath,
    this.selectedUniversityId,
    this.onboardingCompleted = false,
    this.onboardingCompletedAt,
    this.preferredLanguage,
  });

  final String id;
  final String? nickname;

  /// True only when the user chose [nickname] themselves in 먹어보조. A name
  /// copied from Kakao is NOT custom.
  final bool nicknameIsCustom;
  final String? avatarPath;
  final String? selectedUniversityId;
  final bool onboardingCompleted;
  final DateTime? onboardingCompletedAt;

  /// [AppLanguage.code], or null if never saved to the account.
  final String? preferredLanguage;

  AppLanguage? get language => AppLanguage.fromCode(preferredLanguage);

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    nickname: json['nickname'] as String?,
    nicknameIsCustom: json['nickname_is_custom'] as bool? ?? false,
    avatarPath: json['avatar_path'] as String?,
    selectedUniversityId: json['selected_university_id'] as String?,
    onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
    onboardingCompletedAt: json['onboarding_completed_at'] == null
        ? null
        : DateTime.parse(json['onboarding_completed_at'] as String),
    preferredLanguage: json['preferred_language'] as String?,
  );

  UserProfile copyWith({
    String? nickname,
    String? preferredLanguage,
    String? avatarPath,
    String? selectedUniversityId,
  }) => UserProfile(
    id: id,
    nickname: nickname ?? this.nickname,
    nicknameIsCustom: nicknameIsCustom,
    avatarPath: avatarPath ?? this.avatarPath,
    selectedUniversityId: selectedUniversityId ?? this.selectedUniversityId,
    onboardingCompleted: onboardingCompleted,
    onboardingCompletedAt: onboardingCompletedAt,
    preferredLanguage: preferredLanguage ?? this.preferredLanguage,
  );
}
