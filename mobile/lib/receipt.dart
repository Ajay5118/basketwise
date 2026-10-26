import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'api.dart';
import 'widgets.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool busy = false;
  double progress = 0;
  String message = '';
  StreamSubscription<List<SharedMediaFile>>? shared;
  final List<Json> uploads = [];
  @override
  void initState() {
    super.initState();
    refreshDrafts();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      shared = ReceiveSharingIntent.instance.getMediaStream().listen(
        importShared,
      );
      ReceiveSharingIntent.instance.getInitialMedia().then(importShared);
    }
  }

  Future<void> refreshDrafts() async {
    try {
      final result = await ref.read(apiProvider).get('receipts/');
      if (mounted) {
        setState(() {
          uploads.clear();
          uploads.addAll(
            (result['results'] as List).map((value) => Json.from(value)),
          );
        });
      }
    } catch (error) {
      if (mounted) setState(() => message = errorText(error));
    }
  }

  @override
  void dispose() {
    shared?.cancel();
    super.dispose();
  }

  Future<void> importShared(List<SharedMediaFile> files) async {
    if (files.isEmpty || busy || !mounted) return;
    for (final file in files) {
      await upload(
        await XFile(file.path).readAsBytes(),
        file.path.split('/').last,
      );
    }
    ReceiveSharingIntent.instance.reset();
  }

  Future<void> upload(List<int> bytes, String name) async {
    if (bytes.length > 10 * 1024 * 1024) {
      if (mounted) {
        showError(context, StateError('Maximum file size is 10 MB.'));
      }
      return;
    }
    setState(() {
      busy = true;
      progress = 0;
      message = 'Uploading $name';
    });
    try {
      final result = await ref.read(apiProvider).upload(bytes, name, (value) {
        if (mounted) setState(() => progress = value);
      });
      if (mounted) {
        setState(() {
          uploads.insert(0, result);
          message = 'Uploaded. Processing continues in the background.';
        });
      }
      await refreshDrafts();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickFiles() async {
    final files = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (files == null) return;
    for (final file in files.files) {
      if (file.bytes != null && mounted) await upload(file.bytes!, file.name);
    }
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 4000,
      );
      if (file != null && mounted) {
        await upload(await file.readAsBytes(), file.name);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    title: 'A receipt today.\nClarity tomorrow.',
    subtitle: 'Import, review, and make it yours.',
    children: [
      Panel(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.document_scanner_outlined, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'Bring your baskets together',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose an invoice PDF or a clear receipt photo. You always review the details before anything is saved.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : pickFiles,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose receipts'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy ? null : () => pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'PDF, JPG or PNG · up to 10 MB · 10 PDF pages',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      if (busy) LinearProgressIndicator(value: progress),
      if (message.isNotEmpty) Text(message),
      for (final receipt in uploads)
        Panel(
          child: ListTile(
            leading: const Icon(Icons.receipt_outlined),
            title: Text('Receipt #${receipt['id']}'),
            subtitle: const Text('Open to see processing status and review'),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () => context.push('/review/${receipt['id']}'),
          ),
        ),
      const Panel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Private by design. No merchant passwords, inbox access or automatic verification. Unreadable fields stay unknown.',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class ReviewScreen extends ConsumerStatefulWidget {
  final String id;
  const ReviewScreen({super.key, required this.id});
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  Timer? timer;
  Json? receipt;
  Object? error;
  bool polling = false;
  @override
  void initState() {
    super.initState();
    poll();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> poll() async {
    if (polling) return;
    polling = true;
    try {
      final result = await ref
          .read(apiProvider)
          .get('receipts/${widget.id}/preview/');
      if (!mounted) return;
      setState(() {
        receipt = Json.from(result);
        error = null;
      });
      if (!['queued', 'processing'].contains(result['status'])) timer?.cancel();
    } catch (e) {
      if (mounted) setState(() => error = e);
      timer?.cancel();
    } finally {
      polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = receipt?['status'];
    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(errorText(error!)),
                  TextButton(onPressed: poll, child: const Text('Retry')),
                ],
              ),
            )
          : status == 'review'
          ? OrderEditor(
              initial: Json.from(receipt!['data']),
              submitLabel: 'Confirm and save',
              onSave: (data) async {
                await ref.read(apiProvider).post(
                  'receipts/${widget.id}/confirm/',
                  {...data, 'reviewed': true, 'acknowledge_warnings': true},
                );
                ref.read(revisionProvider.notifier).state++;
                if (context.mounted) context.go('/');
              },
            )
          : status == 'confirmed'
          ? Center(
              child: FilledButton(
                onPressed: () => context.go('/orders/${receipt!['order_id']}'),
                child: const Text('View saved order'),
              ),
            )
          : status == 'failed'
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(receipt!['error']),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(apiProvider)
                              .post('receipts/${widget.id}/retry/', {});
                          await poll();
                          timer = Timer.periodic(
                            const Duration(seconds: 2),
                            (_) => poll(),
                          );
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                      child: const Text('Retry extraction'),
                    ),
                  ],
                ),
              ),
            )
          : const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Reading your receipt…'),
                  Text('You can return while processing continues.'),
                ],
              ),
            ),
    );
  }
}

class OrderEditor extends StatefulWidget {
  final Json initial;
  final String submitLabel;
  final Future<void> Function(Json) onSave;
  const OrderEditor({
    super.key,
    required this.initial,
    required this.onSave,
    required this.submitLabel,
  });
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> fields = {};
  final List<Map<String, TextEditingController>> items = [];
  final List<bool> derived = [];
  bool reviewed = false, busy = false;
  late String platform, status;
  static const moneyFields = [
    'item_subtotal',
    'handling_fee',
    'delivery_fee',
    'packaging_fee',
    'taxes',
    'discount',
    'grand_total',
  ];
  @override
  void initState() {
    super.initState();
    platform = widget.initial['platform'] ?? 'other';
    status = widget.initial['status'] ?? 'unknown';
    for (final key in ['external_order_id', 'order_date', ...moneyFields]) {
      fields[key] = TextEditingController(
        text: widget.initial[key]?.toString() ?? '',
      );
    }
    for (final item in widget.initial['items'] ?? []) {
      addItem(Json.from(item));
    }
  }

  void addItem([Json? data]) {
    items.add({
      for (final key in [
        'name',
        'quantity',
        'unit_price',
        'line_total',
        'category',
      ])
        key: TextEditingController(
          text:
              data?[key]?.toString() ??
              (key == 'category' ? 'Uncategorized' : ''),
        ),
    });
    derived.add(data?['unit_price_derived'] == true);
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    for (final item in items) {
      for (final field in item.values) {
        field.dispose();
      }
    }
    super.dispose();
  }

  String label(String key) =>
      key.split('_').map((s) => s[0].toUpperCase() + s.substring(1)).join(' ');
  Future<void> save() async {
    if (!form.currentState!.validate() || !reviewed) return;
    final warnings = (widget.initial['warnings'] as List?) ?? [];
    final duplicates = (widget.initial['potential_duplicates'] as List?) ?? [];
    if (!await approve(
      context,
      'Save reviewed purchase?',
      'Confirm that you checked every field. Unknown values remain unknown. Financial warnings may remain where components are missing.${warnings.isEmpty ? '' : '\n\n${warnings.join('\n')}'}${duplicates.isEmpty ? '' : '\nPotential duplicate order IDs: ${duplicates.join(', ')}. Saving could count the purchase twice.'}',
    )) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.onSave({
        'platform': platform,
        'status': status,
        'currency': 'INR',
        for (final entry in fields.entries)
          entry.key: entry.value.text.trim().isEmpty
              ? null
              : entry.value.text.trim(),
        'items': [
          for (var i = 0; i < items.length; i++)
            {
              for (final entry in items[i].entries)
                entry.key: entry.value.text.trim().isEmpty
                    ? null
                    : entry.value.text.trim(),
              'unit_price_derived': derived[i],
            },
        ],
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: PageBody(
      title: 'Check the details.',
      subtitle:
          'Blank fields are unknown. Correct anything that needs attention.',
      children: [
        if ((widget.initial['warnings'] as List?)?.isNotEmpty == true)
          Panel(
            child: Text(
              (widget.initial['warnings'] as List).join('\n'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: platform,
          decoration: const InputDecoration(labelText: 'Platform'),
          items: [
            for (final value in [
              'instamart',
              'blinkit',
              'zepto',
              'bigbasket',
              'other',
            ])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (v) => setState(() => platform = v!),
        ),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            for (final value in [
              'unknown',
              'delivered',
              'pending',
              'cancelled',
              'refunded',
            ])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (v) => setState(() => status = v!),
        ),
        for (final entry in fields.entries)
          TextFormField(
            controller: entry.value,
            keyboardType: moneyFields.contains(entry.key)
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            decoration: InputDecoration(
              labelText: label(entry.key),
              hintText: entry.key == 'order_date' ? 'YYYY-MM-DD' : 'Unknown',
              helperText: widget.initial[entry.key] == null
                  ? 'Missing in document — verify before entering'
                  : null,
            ),
            validator: (value) {
              if (entry.key == 'order_date') {
                final parsed = DateTime.tryParse(value ?? '');
                if (parsed == null ||
                    parsed.toIso8601String().substring(0, 10) != value) {
                  return 'Enter a valid date as YYYY-MM-DD';
                }
              }
              if (entry.key == 'grand_total' &&
                  (value == null || value.isEmpty)) {
                return 'Grand total is required';
              }
              if (moneyFields.contains(entry.key) &&
                  value != null &&
                  value.isNotEmpty &&
                  !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
                return 'Enter a nonnegative amount with at most two decimals';
              }
              return null;
            },
          ),
        Text('Products', style: Theme.of(context).textTheme.titleLarge),
        for (var index = 0; index < items.length; index++)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Product ${index + 1}')),
                    IconButton(
                      tooltip: 'Remove product',
                      onPressed: () => setState(() {
                        final removed = items.removeAt(index);
                        derived.removeAt(index);
                        for (final controller in removed.values) {
                          controller.dispose();
                        }
                      }),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                for (final entry in items[index].entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: entry.value,
                      decoration: InputDecoration(
                        labelText: label(entry.key),
                        helperText: entry.key == 'unit_price' && derived[index]
                            ? 'Derived from line total ÷ quantity'
                            : null,
                      ),
                      onChanged: (_) {
                        if (entry.key == 'unit_price') {
                          setState(() => derived[index] = false);
                        }
                      },
                      validator: (value) {
                        if (['name', 'category'].contains(entry.key)) {
                          return value == null || value.trim().isEmpty
                              ? 'Required'
                              : null;
                        }
                        if (value == null || value.isEmpty) return null;
                        final number = num.tryParse(value);
                        if (number == null ||
                            !number.isFinite ||
                            number < 0 ||
                            (entry.key == 'quantity' && number == 0)) {
                          return 'Enter a valid positive value';
                        }
                        return null;
                      },
                    ),
                  ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => setState(() => addItem()),
          icon: const Icon(Icons.add),
          label: const Text('Add product'),
        ),
        if (items.isEmpty)
          Text(
            'At least one product is required.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: reviewed,
          onChanged: (v) => setState(() => reviewed = v!),
          title: const Text(
            'I reviewed the products, amounts, date and status.',
          ),
        ),
        FilledButton(
          onPressed: busy || !reviewed || items.isEmpty ? null : save,
          child: Text(busy ? 'Saving…' : widget.submitLabel),
        ),
        TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

class DetailScreen extends ConsumerStatefulWidget {
  final String id;
  const DetailScreen({super.key, required this.id});
  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late Future<dynamic> data;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    data = ref.read(apiProvider).get('orders/${widget.id}/');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Order #${widget.id}'),
      actions: [
        IconButton(
          tooltip: 'Edit order',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () async {
            final order = Json.from(await data);
            if (!context.mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Correct order')),
                  body: OrderEditor(
                    initial: order,
                    submitLabel: 'Save corrections',
                    onSave: (values) async {
                      await ref
                          .read(apiProvider)
                          .patch('orders/${widget.id}/', values);
                      ref.read(revisionProvider.notifier).state++;
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
              ),
            );
            if (mounted) setState(load);
          },
        ),
      ],
    ),
    body: RemoteData(
      future: data,
      retry: () => setState(load),
      builder: (order) => PageBody(
        title: rupees(order['grand_total']),
        subtitle:
            '${order['platform']} · ${order['order_date']} · ${order['status']}',
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order['verification_status']} · ${order['import_source']}',
                ),
                Text('External ID: ${order['external_order_id'] ?? 'Unknown'}'),
                const Divider(),
                for (final item in order['items'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['name']),
                    subtitle: Text(
                      'Quantity ${item['quantity'] ?? 'Unknown'} · ${rupees(item['unit_price'])}${item['unit_price_derived'] ? ' (derived)' : ''}\n${item['category']}',
                    ),
                    trailing: Text(rupees(item['line_total'])),
                  ),
              ],
            ),
          ),
          Panel(
            child: Column(
              children: [
                for (final field in [
                  'item_subtotal',
                  'handling_fee',
                  'delivery_fee',
                  'packaging_fee',
                  'taxes',
                  'discount',
                  'grand_total',
                  'refunded_amount',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(field.replaceAll('_', ' ')),
                        Text(rupees(order[field])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RefundScreen(orderId: widget.id),
                ),
              );
              if (mounted) setState(load);
            },
            child: const Text('Record a refund'),
          ),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Correction history',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final correction in order['corrections'])
                  ExpansionTile(
                    title: Text(correction['created_at']),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(correction['before']),
                      ),
                    ],
                  ),
                if ((order['corrections'] as List).isEmpty)
                  const Text('No corrections yet.'),
                for (final refund in order['refunds'])
                  Text(
                    'Refund ${rupees(refund['amount'])} · ${refund['status']} · ${refund['refund_date']}',
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              if (!await approve(
                context,
                'Delete order?',
                'This removes the saved purchase and its correction and refund history.',
              )) {
                return;
              }
              try {
                await ref.read(apiProvider).delete('orders/${widget.id}/');
                ref.read(revisionProvider.notifier).state++;
                if (context.mounted) context.go('/');
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: Text(
              'Delete order',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    ),
  );
}

class RefundScreen extends ConsumerStatefulWidget {
  final String orderId;
  const RefundScreen({super.key, required this.orderId});
  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  final amount = TextEditingController(), date = TextEditingController();
  bool confirmed = false, busy = false;
  @override
  void dispose() {
    amount.dispose();
    date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record refund')),
    body: PageBody(
      title: 'Keep the balance right.',
      subtitle: 'Only a confirmed refund reduces net spending.',
      children: [
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (₹)'),
        ),
        TextField(
          controller: date,
          decoration: const InputDecoration(
            labelText: 'Refund date (YYYY-MM-DD)',
          ),
        ),
        SwitchListTile(
          value: confirmed,
          onChanged: (v) => setState(() => confirmed = v),
          title: const Text('Refund received and confirmed'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await ref
                        .read(apiProvider)
                        .post('orders/${widget.orderId}/refunds/', {
                          'amount': amount.text,
                          'refund_date': date.text,
                          'status': confirmed ? 'confirmed' : 'pending',
                        });
                    ref.read(revisionProvider.notifier).state++;
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('Save refund'),
        ),
      ],
    ),
  );
}
