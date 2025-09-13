import 'package:blob/widgets/hoverable_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../brand_profile_draft.dart';

class GoalStep extends StatelessWidget {
  final VoidCallback onNext;
  const GoalStep({super.key, required this.onNext});
  @override
  Widget build(BuildContext context) {
    final d = context.watch<BrandProfileDraft>();
    const goals = [
      'Grow audience',
      'Post consistently',
      'Save time',
      'Richer analytics',
      'Manage clients',
    ];
    return LayoutBuilder(
      builder: (_, c) => Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(c.maxWidth * .0125),
          child: Column(
            children: [
              const Text(
                'Biggest outcome you want from Blob?',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  ...goals.map(
                    (g) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: HoverableCard(
                        fatherProperty: 'primary-goal',
                        property: g,
                        onTap: () {
                          d.primary_goal = g;
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
      ),
    );
  }
}
