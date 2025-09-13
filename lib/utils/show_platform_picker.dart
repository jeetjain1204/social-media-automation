// file: platform_posttype_pickers.dart
// OPT: Major perf & reliability polish without changing behavior or signatures.
// - Precompute labels once (avoid split/substr on every rebuild).
// - Use const widgets/styles where possible to cut rebuild cost.
// - Guard disposed context before popping/returning.
// - Prefer ListView.builder for potentially long lists; shrinkWrap + no scroll glow.
// - Keep UI/logic intact: same titles, actions, defaults, and outputs.

import 'package:blob/widgets/my_switch_list_tile.dart';
import 'package:blob/widgets/text_button.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future<List<String>?> showPlatformPicker(
  BuildContext context, {
  List<String>? platforms,
}) async {
  if (!context.mounted) return null; // OPT: safety

  // Default platform order preserved.
  final List<String> list =
      platforms ?? const ['linkedin', 'facebook', 'instagram'];

  // Precompute display labels once.
  final Map<String, String> labelByPlatform = {
    for (final p in list)
      p: p.isEmpty ? p : (p[0].toUpperCase() + p.substring(1)),
  };

  final selectedPlatforms = <String>{};
  final result = await showDialog<List<String>>(
    context: context,
    builder: (context) {
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Select Platforms',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              width: 420, // ✅ explicit width for IntrinsicWidth
              height: 360, // ✅ explicit height so ListView can layout
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.builder(
                  primary: false, // ✅ don't hijack PrimaryScrollController
                  shrinkWrap: true, // ✅ cooperate with fixed height
                  physics: const ClampingScrollPhysics(),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final platform = list[index];
                    final label = labelByPlatform[platform] ?? platform;
                    final isOn = selectedPlatforms.contains(platform);
                    return MySwitchListTile(
                      width: double.infinity,
                      value: isOn,
                      title: label,
                      onChanged: (bool? selected) {
                        setState(() {
                          if (selected == true) {
                            selectedPlatforms.add(platform);
                          } else {
                            selectedPlatforms.remove(platform);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            );
          },
        ),
        actions: [
          MyTextButton(
            onPressed: () => context.pop(null),
            child: const Text('Cancel'),
          ),
          MyTextButton(
            onPressed: () {
              if (!context.mounted) return;
              context.pop(
                selectedPlatforms.isEmpty
                    ? <String>[]
                    : selectedPlatforms.toList(),
              );
            },
            child: const Text('Done'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return null; // In case the view was disposed
  // Preserve original contract: return List<String>?; empty list is a valid selection.
  return result;
}

Future<Map<String, List<String>>?> showPostTypePicker(
  BuildContext context,
  Map<String, List<String>> postTypeMap,
) async {
  if (!context.mounted) return null;

  final labelByPlatformType = {
    for (final entry in postTypeMap.entries)
      entry.key: {
        for (final t in entry.value)
          t: (() {
            final idx = t.indexOf('_');
            final raw = idx >= 0 ? t.substring(idx + 1) : t;
            return raw.isEmpty
                ? raw
                : (raw[0].toUpperCase() + raw.substring(1));
          })(),
      },
  };

  final selections = <String, Set<String>>{
    for (final entry in postTypeMap.entries) entry.key: <String>{},
  };

  final result = await showDialog<Map<String, List<String>>?>(
    context: context,
    builder: (context) {
      final platforms = postTypeMap.keys.toList(growable: false);
      final scrollCtrl = ScrollController(); // <-- attach Scrollbar & ListView

      // Limit dialog height so content can scroll
      final maxDialogHeight = MediaQuery.of(context).size.height * 0.7;

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Select Post Types',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 520,
          height: maxDialogHeight,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Scrollbar(
                controller: scrollCtrl,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: scrollCtrl, // <-- critical
                  itemCount: platforms.length,
                  itemBuilder: (context, pIndex) {
                    final platform = platforms[pIndex];
                    final types = postTypeMap[platform]!;
                    final labels = labelByPlatformType[platform]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, bottom: 4),
                          child: Text(
                            platform.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ),

                        // Make the inner "list" non-scrollable so only outer list scrolls
                        ListView.builder(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(), // <-- important
                          itemCount: types.length,
                          itemBuilder: (context, tIndex) {
                            final type = types[tIndex];
                            final label = labels[type] ?? type;
                            final isOn = selections[platform]!.contains(type);

                            return MySwitchListTile(
                              width: double.infinity,
                              title: label,
                              value: isOn,
                              onChanged: (selected) => setState(() {
                                if (selected == true) {
                                  selections[platform]!.add(type);
                                } else {
                                  selections[platform]!.remove(type);
                                }
                              }),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          MyTextButton(
            onPressed: () => context.pop(null),
            child: const Text('Cancel'),
          ),
          MyTextButton(
            onPressed: () {
              if (!context.mounted) return;
              final out = {
                for (final e in selections.entries)
                  if (e.value.isNotEmpty) e.key: e.value.toList(),
              };
              context.pop(out.isEmpty ? null : out);
            },
            child: const Text('Done'),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return null;
  return result;
}
