import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

class VariantGroupCard extends StatefulWidget {
  final VariantGroup variantGroup;
  final VoidCallback onEdit;
  final Function(bool) onStatusToggle;

  const VariantGroupCard({
    Key? key,
    required this.variantGroup,
    required this.onEdit,
    required this.onStatusToggle,
  }) : super(key: key);

  @override
  State<VariantGroupCard> createState() => _VariantGroupCardState();
}

class _VariantGroupCardState extends State<VariantGroupCard> {
  bool isExpanded = false;
  bool isActive = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    isActive = widget.variantGroup.disabled == 0;
  }

  Future<void> _toggleActiveStatus(bool value) async {
    if (!mounted) return; // Prevent updates if widget is disposed

    try {
      await widget.onStatusToggle(value);
      setState(() => isLoading = true); // Show loading state

      if (mounted) {
        setState(() {
          isActive = value;
        });
      }
      Fluttertoast.showToast(
        msg:
            '${widget.variantGroup.variantGroup} ${value ? 'activated' : 'deactivated'}',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: value ? Colors.green : Colors.orange,
        textColor: Colors.white,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Failed to update status: $e',
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              isExpanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              color: isActive ? Colors.black : Colors.grey,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.variantGroup.variantGroup,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.black : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.variantGroup.required == 1)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Required',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '${widget.variantGroup.options.length} options',
              style: TextStyle(color: isActive ? Colors.black54 : Colors.grey),
            ),
            onTap: () => setState(() => isExpanded = !isExpanded),
          ),
          if (isExpanded)
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Variants:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: widget.onEdit,
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text(
                              'Edit',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ...widget.variantGroup.options.map((option) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(option.option),
                            Text(
                              option.additionalCost > 0
                                  ? '+RM ${option.additionalCost.toStringAsFixed(2)}'
                                  : 'Free',
                              style: TextStyle(
                                color: option.additionalCost > 0
                                    ? Colors.green
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Data Models
// Update VariantGroup model
class VariantGroup {
  final String variantGroup;
  final int required;
  final int optionRequiredNo;
  final int maximumSelection; // Add this field
  final List<VariantOption> options;
  final int disabled;

  VariantGroup({
    required this.variantGroup,
    required this.required,
    required this.optionRequiredNo,
    required this.maximumSelection, // Add to constructor
    required this.options,
    this.disabled = 0,
  });

  factory VariantGroup.fromJson(Map<String, dynamic> json) {
    return VariantGroup(
      variantGroup: json['variant_group'] ?? '',
      required: json['required'] ?? 0,
      optionRequiredNo: json['option_required_no'] ?? 0,
      maximumSelection: json['maximum_selection'] ?? 0, // Add this line
      options: (json['options'] as List<dynamic>? ?? [])
          .map((o) => VariantOption.fromJson(o))
          .toList(),
    );
  }
}

class VariantOption {
  final String option;
  final double additionalCost;

  VariantOption({
    required this.option,
    required this.additionalCost,
  });

  factory VariantOption.fromJson(Map<String, dynamic> json) {
    return VariantOption(
      option: json['option'] ?? '', // 👈 fallback to empty string
      additionalCost: (json['additional_cost'] ?? 0).toDouble(),
    );
  }
}
