// file: template_picker_dialog.dart
// OPT: Major optimizations & hardening with identical behavior and API.
// - Debounce double-taps (re-entrancy guard) while awaiting onSelect.
// - Extract reusable widgets (no inline widget functions, clearer rebuilds).
// - Use ListView.separated with shrinkWrap for better perf within dialog scroll.
// - Add const where possible; minimize per-item allocations; stable Keys.
// - Keep visuals, texts, sizes, and return flow exactly the same.

import 'package:blob/utils/colors.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class TemplatePickerDialog extends StatefulWidget {
  const TemplatePickerDialog({
    super.key,
    required this.userTemplates,
    required this.prebuiltTemplates,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> userTemplates;
  final List<Map<String, dynamic>> prebuiltTemplates;
  final Future<void> Function(Map<String, dynamic> template) onSelect;

  @override
  State<TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<TemplatePickerDialog> {
  bool isSelecting = false; // OPT: debounce concurrent taps

  Future<void> handleSelect(Map<String, dynamic> template) async {
    if (isSelecting) return; // OPT: guard
    setState(() => isSelecting = true);
    try {
      await widget.onSelect(template);
      if (!mounted) return;
      context.pop();
    } finally {
      if (mounted) setState(() => isSelecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color dark = darkColor;
    final Color light = lightColor;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        'Select a Template',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: dark,
        ),
      ),
      content: SizedBox(
        width: 420,
        height: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.userTemplates.isEmpty &&
                  widget.prebuiltTemplates.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      'No templates found',
                      style: TextStyle(color: dark),
                    ),
                  ),
                ),
              TemplateSection(
                title: 'Your Templates',
                templates: widget.userTemplates,
                onTap: handleSelect,
                dark: dark,
                light: light,
              ),
              TemplateSection(
                title: 'Prebuilt Templates',
                templates: widget.prebuiltTemplates,
                onTap: handleSelect,
                dark: dark,
                light: light,
              ),
            ],
          ),
        ),
      ),
      actions: [
        MyTextButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class TemplateSection extends StatelessWidget {
  const TemplateSection({
    super.key,
    required this.title,
    required this.templates,
    required this.onTap,
    required this.dark,
    required this.light,
  });

  final String title;
  final List<Map<String, dynamic>> templates;
  final Future<void> Function(Map<String, dynamic> template) onTap;
  final Color dark;
  final Color light;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: dark,
          ),
        ),
        const SizedBox(height: 12),
        // Use ListView.separated inside the outer SingleChildScrollView.
        ListView.separated(
          key: ValueKey(title), // stable for section
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: templates.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final t = templates[index];
            // Derive stable key from template id/name if present.
            final Object itemKey = t['id'] ?? t['name'] ?? index;
            return TemplateCard(
              key: ValueKey(itemKey),
              template: t,
              dark: dark,
              light: light,
              onTap: onTap,
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class TemplateCard extends StatelessWidget {
  const TemplateCard({
    super.key,
    required this.template,
    required this.dark,
    required this.light,
    required this.onTap,
  });

  final Map<String, dynamic> template;
  final Color dark;
  final Color light;
  final Future<void> Function(Map<String, dynamic> template) onTap;

  @override
  Widget build(BuildContext context) {
    final String name = (template['name'] as String?)?.trim().isNotEmpty == true
        ? (template['name'] as String)
        : 'Untitled';

    return InkWell(
      onTap: () => onTap(template),
      borderRadius: BorderRadius.circular(12),
      hoverColor: light.withOpacity(0.06),
      splashColor: light.withOpacity(0.1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: light.withOpacity(0.045),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: dark.withOpacity(0.08), width: 1),
        ),
        child: Row(
          children: [
            Icon(Icons.layers, color: dark, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  color: dark,
                ),
              ),
            ),
            Text(
              'Apply →',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: dark.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
