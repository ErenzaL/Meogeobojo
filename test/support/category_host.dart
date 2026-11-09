import 'package:flutter/material.dart';
import 'package:meogeobojo/features/home/widgets/category_section.dart';

/// Hosts the category shortcuts on their own. They used to live on Home; the
/// new Home does not show them, but the widget and the pages it opens are
/// still covered here.
class CategoryHost extends StatelessWidget {
  const CategoryHost({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        key: const PageStorageKey('category-host-scroll'),
        padding: const EdgeInsets.only(top: 16),
        // Tall enough to scroll, like the page it stands in for.
        children: const [CategorySection(), SizedBox(height: 1200)],
      ),
    ),
  );
}
