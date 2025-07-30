import 'package:flutter/material.dart';

class VariantGroupCard extends StatefulWidget {
  final VariantGroup variantGroup;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddVariant;

  const VariantGroupCard({
    Key? key,
    required this.variantGroup,
    required this.onEdit,
    required this.onDelete,
    required this.onAddVariant,
  }) : super(key: key);

  @override
  State<VariantGroupCard> createState() => _VariantGroupCardState();
}

class _VariantGroupCardState extends State<VariantGroupCard> {
  bool isExpanded = false;

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
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.variantGroup.variantGroup,
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
            subtitle: Text('${widget.variantGroup.options.length} options'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: true, // Assuming all groups are active by default
                  onChanged: (value) {
                    // Handle active/inactive toggle
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  onPressed: () {
                    // Show info dialog
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: widget.onEdit,
                ),
              ],
            ),
            onTap: () {
              setState(() {
                isExpanded = !isExpanded;
              });
            },
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
                      const Text(
                        'Variants:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      ElevatedButton.icon(
                        onPressed: widget.onAddVariant,
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(
                          'Add Variant',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...widget.variantGroup.options
                      .map(
                        (option) => Container(
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
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Data Models
class VariantGroup {
  final String variantGroup;
  final int required;
  final int optionRequiredNo;
  final List<VariantOption> options;

  VariantGroup({
    required this.variantGroup,
    required this.required,
    required this.optionRequiredNo,
    required this.options,
  });

  factory VariantGroup.fromJson(Map<String, dynamic> json) {
    return VariantGroup(
      variantGroup: json['variant_group'] as String,
      required: json['required'] as int,
      optionRequiredNo: json['option_required_no'] as int,
      options: (json['options'] as List)
          .map((option) => VariantOption.fromJson(option))
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
      option: json['option'] as String,
      additionalCost: (json['additional_cost'] as num).toDouble(),
    );
  }
}
