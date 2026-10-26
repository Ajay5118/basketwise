import 'package:flutter/material.dart';
import 'api.dart';

class OrderFilters extends StatefulWidget {
  final Json initial;
  const OrderFilters({super.key, required this.initial});
  @override
  State<OrderFilters> createState() => _OrderFiltersState();
}

class _OrderFiltersState extends State<OrderFilters> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String source = '';
  @override
  void initState() {
    super.initState();
    for (final key in ['start', 'end', 'min_amount', 'max_amount']) {
      fields[key] = TextEditingController(
        text: widget.initial[key]?.toString() ?? '',
      );
    }
    source = widget.initial['import_source'] ?? '';
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Filter orders'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in fields.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: entry.value,
                  decoration: InputDecoration(
                    labelText: {
                      'start': 'From (YYYY-MM-DD)',
                      'end': 'To (YYYY-MM-DD)',
                      'min_amount': 'Minimum amount (₹)',
                      'max_amount': 'Maximum amount (₹)',
                    }[entry.key],
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    if (['start', 'end'].contains(entry.key)) {
                      final date = DateTime.tryParse(value);
                      if (date == null ||
                          date.toIso8601String().substring(0, 10) != value) {
                        return 'Use a valid YYYY-MM-DD date';
                      }
                    } else {
                      final amount = num.tryParse(value);
                      if (amount == null || !amount.isFinite || amount < 0) {
                        return 'Enter a nonnegative amount';
                      }
                    }
                    return null;
                  },
                ),
              ),
            DropdownButtonFormField<String>(
              initialValue: source,
              decoration: const InputDecoration(labelText: 'Import source'),
              items: const [
                DropdownMenuItem(value: '', child: Text('All sources')),
                DropdownMenuItem(
                  value: 'receipt',
                  child: Text('Uploaded receipt'),
                ),
              ],
              onChanged: (value) => setState(() => source = value!),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, <String, dynamic>{}),
        child: const Text('Clear'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, {
              for (final entry in fields.entries)
                if (entry.value.text.isNotEmpty) entry.key: entry.value.text,
              if (source.isNotEmpty) 'import_source': source,
            });
          }
        },
        child: const Text('Apply'),
      ),
    ],
  );
}
