import 'package:blob/widgets/hoverable_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../brand_profile_draft.dart';

class ContentMixStep extends StatefulWidget {
  final VoidCallback onNext;
  const ContentMixStep({super.key, required this.onNext});
  @override
  State<ContentMixStep> createState() => _ContentMixStepState();
}

class _ContentMixStepState extends State<ContentMixStep> {
  // ignore: non_constant_identifier_names
  final content_types = [
    'Text',
    'Images',
    'Short Video',
    'Long Video',
    'Stories',
    'Carousels',
  ];

  @override
  Widget build(BuildContext context) {
    final d = context.watch<BrandProfileDraft>();
    return LayoutBuilder(
      builder: (_, c) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(c.maxWidth * .0125),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What content formats do you care about?',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  ...content_types.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: HoverableCard(
                        fatherProperty: 'content_types',
                        property: t,
                        onTap: () {
                          if (d.content_types.contains(t)) {
                            d.content_types.remove(t);
                            d.notify();
                          } else {
                            d.voice_tags.add(t);
                            d.notify();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: widget.onNext,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
