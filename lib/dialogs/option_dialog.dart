import 'package:flutter/material.dart';

class OptionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> options;
  const OptionDialog({Key? key, required this.options}) : super(key: key);

  @override
  State<OptionDialog> createState() => _OptionDialogState();
}

class _OptionDialogState extends State<OptionDialog> {  

  final List<_OptionRow> _rows = [];

  @override
  void initState() {
    super.initState();

    // Deep copy initial options into controllers
    for (final m in widget.options) {
      final opt = (m['option'] ?? '').toString();
      final cost = (m['additional_cost'] ?? 0).toString();
      _rows.add(_OptionRow(
        nameCtrl: TextEditingController(text: opt),
        costCtrl: TextEditingController(text: cost),
      ));
    }

    // If empty, start with one row
    if (_rows.isEmpty) {
      _rows.add(_OptionRow(
        nameCtrl: TextEditingController(),
        costCtrl: TextEditingController(text: '0'),
      ));
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.nameCtrl.dispose();
      r.costCtrl.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _collect() {
    // build sanitized list
    final out = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final name = r.nameCtrl.text.trim();
      if (name.isEmpty) continue; // drop empty names
      final cost = double.tryParse(r.costCtrl.text.trim()) ?? 0.0;
      out.add({"option": name, "additional_cost": cost});
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Variant Options"),
      content: SizedBox(
        width: 420,
        // make the dialog scrollable
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: ListView.builder(
            itemCount: _rows.length + 1, // +1 for add button at the end
            itemBuilder: (context, index) {
              if (index == _rows.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _rows.add(_OptionRow(
                          nameCtrl: TextEditingController(),
                          costCtrl: TextEditingController(text: '0'),
                        ));
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Add Option"),
                  ),
                );
              }

              final row = _rows[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    // Option name
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: row.nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Option",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Cost
                    Expanded(
                      child: TextField(
                        controller: row.costCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Cost",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: "Remove",
                      onPressed: () {
                        setState(() {
                          _rows.removeAt(index);
                        });
                      },
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                    )
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), // cancel returns null
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            final result = _collect();
            Navigator.pop(context, result); // ✅ return full list to edit dialog
          },
          child: const Text("Confirm"),
        ),
      ],
    );
  }
}

class _OptionRow {
    final TextEditingController nameCtrl;
    final TextEditingController costCtrl;
    _OptionRow({required this.nameCtrl, required this.costCtrl});
  }
