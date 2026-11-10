import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_palette.dart';
import 'home_search_bar.dart';

/// Full-width search field under the header. Submitting opens the existing
/// search screen with what was typed, so results come from the same search
/// as everywhere else.
class HomeSearchField extends StatefulWidget {
  const HomeSearchField({super.key});

  @override
  State<HomeSearchField> createState() => _HomeSearchFieldState();
}

class _HomeSearchFieldState extends State<HomeSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      openSearch(context);
      return;
    }
    FocusScope.of(context).unfocus();
    _controller.clear();
    openSearch(context, query: q);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    return Semantics(
      label: l10n.homeSearchLabel,
      textField: true,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          hintText: l10n.homeSearchFieldHint,
          hintStyle: TextStyle(fontSize: 16, color: p.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: p.textSecondary),
          filled: true,
          fillColor: p.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: p.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}
