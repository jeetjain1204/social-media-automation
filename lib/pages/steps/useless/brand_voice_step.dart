import 'package:blob/widgets/hoverable_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../brand_profile_draft.dart';

class BrandVoiceStep extends StatefulWidget {
  const BrandVoiceStep({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  State<BrandVoiceStep> createState() => _BrandVoiceStepState();
}

class _BrandVoiceStepState extends State<BrandVoiceStep> {
  final tags = [
    'Friendly',
    'Professional',
    'Playful',
    'Inspiring',
    'Authoritative',
    'Casual',
  ];
  @override
  Widget build(BuildContext context) {
    final d = context.watch<BrandProfileDraft>();
    return LayoutBuilder(
      builder: (_, c) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(c.maxWidth * .0125),
          child: Column(
            children: [
              const Text(
                'Choose up to 3 words that fit your brand voice',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  ...tags.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: HoverableCard(
                        fatherProperty: 'voice_tags',
                        property: t,
                        onTap: () {
                          if (d.voice_tags.contains(t)) {
                            d.voice_tags.remove(t);
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
