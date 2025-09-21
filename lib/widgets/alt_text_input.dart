import 'package:flutter/material.dart';
import 'package:blob/alt_text_draft.dart';
import 'package:blob/utils/colors.dart';

class AltTextInput extends StatefulWidget {
  final AltTextDraft altTextDraft;
  final int imageCount;
  final double width;

  const AltTextInput({
    super.key,
    required this.altTextDraft,
    required this.imageCount,
    required this.width,
  });

  @override
  State<AltTextInput> createState() => _AltTextInputState();
}

class _AltTextInputState extends State<AltTextInput> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    widget.altTextDraft.initializeForImages(widget.imageCount);
  }

  @override
  void didUpdateWidget(AltTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageCount != widget.imageCount) {
      _disposeControllers();
      _initializeControllers();
      widget.altTextDraft.initializeForImages(widget.imageCount);
    }
  }

  void _initializeControllers() {
    _controllers = List.generate(
      widget.imageCount,
      (index) => TextEditingController(
        text: widget.altTextDraft.getAltTextForIndex(index),
      ),
    );

    _focusNodes = List.generate(
      widget.imageCount,
      (index) => FocusNode(),
    );

    // Add listeners to update the draft when text changes
    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].addListener(() {
        widget.altTextDraft.setAltTextForIndexWithSave(i, _controllers[i].text);
      });
    }
  }

  void _disposeControllers() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(
              Icons.accessibility,
              color: darkColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Alt-text for Accessibility',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: darkColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: darkColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Required',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: darkColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Description
        Text(
          'Describe your images for screen readers. Each description should be 140-250 characters.',
          style: TextStyle(
            fontSize: 14,
            color: darkColor.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 16),

        // Alt-text inputs
        if (widget.imageCount == 1) ...[
          _buildSingleImageInput(),
        ] else ...[
          _buildCarouselInputs(),
        ],

        const SizedBox(height: 12),

        // Validation message
        AnimatedBuilder(
          animation: widget.altTextDraft,
          builder: (context, child) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.altTextDraft.isValid
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.altTextDraft.isValid
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.altTextDraft.isValid
                        ? Icons.check_circle
                        : Icons.error,
                    color:
                        widget.altTextDraft.isValid ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.altTextDraft.validationMessage,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.altTextDraft.isValid
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSingleImageInput() {
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: darkColor, width: 1),
      ),
      child: TextFormField(
        controller: _controllers[0],
        focusNode: _focusNodes[0],
        maxLines: 3,
        maxLength: 250,
        decoration: InputDecoration(
          hintText: 'Describe this image in detail (140-250 characters)...',
          hintStyle: TextStyle(color: darkColor.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          counterText: '${_controllers[0].text.length}/250',
        ),
        style: TextStyle(
          color: darkColor,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildCarouselInputs() {
    return Column(
      children: List.generate(widget.imageCount, (index) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: index < widget.imageCount - 1 ? 16 : 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: darkColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: lightColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Image ${index + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: darkColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: widget.width,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: darkColor, width: 1),
                ),
                child: TextFormField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  maxLines: 3,
                  maxLength: 250,
                  decoration: InputDecoration(
                    hintText:
                        'Describe image ${index + 1} in detail (140-250 characters)...',
                    hintStyle: TextStyle(color: darkColor.withOpacity(0.5)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    counterText: '${_controllers[index].text.length}/250',
                  ),
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
