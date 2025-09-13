import 'package:blob/widgets/auto_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:blob/utils/colors.dart';

class MyDropDown extends StatefulWidget {
  const MyDropDown({
    super.key,
    this.width,
    this.height,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hint,
    this.canSearch = false,
  });

  final double? width;
  final double? height;
  final List<String> items;
  final String? value;
  final String? hint;
  final bool canSearch;
  final ValueChanged<String?> onChanged;

  @override
  State<MyDropDown> createState() => _MyDropDownState();
}

class _MyDropDownState extends State<MyDropDown> {
  late List<String> filteredItems;
  final TextEditingController searchController = TextEditingController();

  // OPT: cache text styles so they’re not rebuilt every frame
  static final _hintStyle = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: darkColor,
  );
  static final _itemStyle = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: darkColor,
  );
  static final _menuItemStyle = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: darkColor,
  );
  static final _animDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
  }

  // OPT: only setState when the filtered list actually changes
  void handleSearch(String query) {
    final q = query.toLowerCase();
    final newList =
        widget.items.where((item) => item.toLowerCase().contains(q)).toList();
    if (newList.length != filteredItems.length) {
      setState(() => filteredItems = newList);
    }
  }

  @override
  void dispose() {
    searchController.dispose(); // OPT: avoid memory leak
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(16); // --radius-card

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AutoSkeleton(
        enabled: widget.items.isEmpty,
        preserveSize: true,
        clipPadding: const EdgeInsets.symmetric(vertical: 12),
        child: RepaintBoundary(
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: widget.value,
            onChanged: widget.onChanged,
            iconEnabledColor: darkColor,
            dropdownColor: const Color(0xffbae2ff),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xffbae2ff),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide.none,
              ),
            ),
            hint: widget.hint == null
                ? null
                : Text(widget.hint!, style: _hintStyle),
            style: _itemStyle,
            selectedItemBuilder: (_) => widget.items
                .map((e) => Text(e, style: _itemStyle))
                .toList(growable: false),
            items: [
              if (widget.canSearch)
                DropdownMenuItem<String>(
                  enabled: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Semantics(
                      label: 'Search input for dropdown options',
                      child: TextField(
                        controller: searchController,
                        onChanged: handleSearch,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.black,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Type to filter...',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Search',
                        ),
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                  ),
                ),
              if (filteredItems.isEmpty)
                const DropdownMenuItem<String>(
                  enabled: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No matches found',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
              ...filteredItems.map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: AnimatedOpacity(
                    opacity: 1,
                    duration: _animDuration,
                    child: Text(item, style: _menuItemStyle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
