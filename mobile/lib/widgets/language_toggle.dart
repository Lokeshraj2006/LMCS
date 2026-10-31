import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../providers/language_provider.dart';

/// One tap between English and Tamil. Shows the language it switches *to*,
/// written in that language, so someone who can't read the current one can
/// still find it.
class LanguageToggle extends StatelessWidget {
  final Color? color;

  const LanguageToggle({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    return Tooltip(
      message: tr('Change language'),
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: color),
        icon: const Icon(Icons.translate, size: 18),
        label: Text(lang.tamil ? 'English' : 'தமிழ்',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        onPressed: lang.toggle,
      ),
    );
  }
}
