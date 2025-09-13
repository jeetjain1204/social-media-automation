// filename: lib/onboarding/steps/persona_step.dart
import 'package:blob/widgets/hoverable_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../brand_profile_draft.dart';

class PersonaStep extends StatelessWidget {
  final VoidCallback onNext;
  const PersonaStep({super.key, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<BrandProfileDraft>();
    const personas = ['Solo Creator', 'SMB Founder', 'Agency Freelancer'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(width * .0125),
            child: Column(
              children: [
                const Text(
                  'Which best describes you?',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    ...personas.map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: HoverableCard(
                          fatherProperty: 'persona',
                          property: p,
                          onTap: () {
                            d.persona = p;
                            d.notify();
                            onNext();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
