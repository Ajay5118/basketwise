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
import 'design.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool busy = false;
  double progress = 0;
  Timer? draftTimer;
  String message = '';
  StreamSubscription<List<SharedMediaFile>>? shared;
  final List<Json> uploads = [];
  @override
  void initState() {
    super.initState();
    refreshDrafts();
    draftTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (uploads.any((r) => ['queued', 'processing'].contains(r['status']))) {
        refreshDrafts();
      }
    });
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
    draftTimer?.cancel();
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
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: refreshDrafts,
    child: PageBody(
      title: 'A little receipt.\nA lot of clarity.',
      subtitle: 'Add a receipt. We’ll help you put it in perspective.',
      action: IconButton(
        tooltip: 'Refresh receipts',
        onPressed: refreshDrafts,
        icon: const Icon(Icons.refresh_rounded),
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .22),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Icon(
                    Icons.document_scanner_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 38,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Let’s unpack your basket',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 9),
              Text(
                'Upload an invoice PDF or a clear photo. Review the details before saving your purchase.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.6,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : pickFiles,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Choose receipts'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'PDF, JPG or PNG · Up to 10 MB · 10 pages',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
        if (busy)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress, minHeight: 6),
          ),
        if (message.isNotEmpty)
          Text(message, style: Theme.of(context).textTheme.bodySmall),
        const SoftNotice(
          icon: Icons.lightbulb_outline_rounded,
          title: 'A clear photo makes all the difference',
          text:
              'Lay the invoice flat, include every edge and keep the text in focus. Use the original PDF when available.',
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your receipts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${uploads.length} imported',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        if (uploads.isEmpty)
          const Panel(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 30),
                SizedBox(height: 12),
                Text(
                  'Your first receipt starts here',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 5),
                Text(
                  'Imported receipts and their reading status will appear here.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        for (final receipt in uploads)
          ReceiptDraftTile(
            receipt: receipt,
            onTap: () async {
              await context.push('/review/${receipt['id']}');
              await refreshDrafts();
            },
          ),
        const SoftNotice(
          icon: Icons.shield_outlined,
          title: 'Private from the first upload',
          text:
              'No merchant passwords or inbox access. Unreadable details stay unknown until you fill them in.',
        ),
      ],
    ),
  );
}

class ReceiptDraftTile extends StatelessWidget {
  final Json receipt;
  final VoidCallback onTap;
  const ReceiptDraftTile({
    super.key,
    required this.receipt,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final status = receipt['status'];
    final (label, icon, color) = switch (status) {
      'queued' => (
        'Waiting to read',
        Icons.hourglass_empty_rounded,
        const Color(0xff977025),
      ),
      'processing' => (
        'Reading your receipt',
        Icons.document_scanner_outlined,
        BasketStyle.green,
      ),
      'review' => (
        'Check extracted details',
        Icons.edit_note_rounded,
        BasketStyle.green,
      ),
      'confirmed' => (
        'Saved to your orders',
        Icons.check_circle_outline_rounded,
        BasketStyle.green,
      ),
      'failed' => (
        'Needs another look',
        Icons.info_outline_rounded,
        const Color(0xffb64d38),
      ),
      _ => ('Open receipt', Icons.receipt_long_outlined, BasketStyle.green),
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Receipt #${receipt['id']}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (status == 'failed')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          receipt['processing_error']?.toString().isNotEmpty ==
                                  true
                              ? receipt['processing_error'].toString()
                              : 'Open for retry options.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
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
  bool manualEntry = false;
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
      if (!['queued', 'processing'].contains(result['status'])) {
        timer?.cancel();
      } else if (timer?.isActive != true) {
        timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
      timer?.cancel();
    } finally {
      polling = false;
    }
  }

  Future<void> retryExtraction() async {
    try {
      await ref.read(apiProvider).post('receipts/${widget.id}/retry/', {});
      if (!mounted) return;
      setState(() {
        manualEntry = false;
        receipt = {...?receipt, 'status': 'processing'};
      });
      await poll();
      timer?.cancel();
      if (receipt != null &&
          ['queued', 'processing'].contains(receipt!['status'])) {
        timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = receipt?['status'];
    final extracted = receipt?['data'] as Map?;
    final emptyExtraction =
        status == 'review' &&
        ((extracted?['items'] as List?)?.isEmpty ?? true) &&
        extracted?['grand_total'] == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Review receipt')),
      body: error != null
          ? FlowStatus(
              icon: Icons.cloud_off_outlined,
              title: 'Couldn’t load this receipt',
              message: errorText(error!),
              actions: [
                FilledButton(onPressed: poll, child: const Text('Try again')),
              ],
            )
          : emptyExtraction && !manualEntry
          ? PageBody(
              showBranding: false,
              title: 'This one needs\na little help.',
              subtitle: 'We couldn’t read the invoice details clearly.',
              children: [
                const SoftNotice(
                  icon: Icons.document_scanner_outlined,
                  title: 'Your upload arrived safely',
                  text:
                      'The photo was received, but we couldn’t find usable products or a total. Nothing has been added to your spending.',
                ),
                const Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Try a clearer copy',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Use the original invoice PDF if you have it. For a photo, include the full invoice, keep the camera straight, and make sure small text is sharp.',
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => setState(() => manualEntry = true),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Enter details manually'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to your baskets'),
                ),
                TextButton(
                  onPressed: retryExtraction,
                  child: const Text('Try reading this receipt again'),
                ),
              ],
            )
          : status == 'review'
          ? OrderEditor(
              initial: Json.from(receipt!['data']),
              compact: true,
              submitLabel: 'Confirm and save',
              onSave: (data) async {
                await ref.read(apiProvider).post(
                  'receipts/${widget.id}/confirm/',
                  {...data, 'reviewed': true, 'acknowledge_warnings': true},
                );
                ref.read(revisionProvider.notifier).state++;
                ref.read(homeBannerProvider.notifier).state =
                    'Purchase saved — it’s now in your spending.';
                ref.read(shellTabProvider.notifier).state = 0;
                if (context.mounted) context.go('/');
              },
            )
          : status == 'confirmed'
          ? FlowStatus(
              icon: Icons.check_circle_rounded,
              title: 'Already saved',
              message: 'This receipt is linked to an order in your history.',
              actions: [
                FilledButton(
                  onPressed: () =>
                      context.go('/orders/${receipt!['order_id']}'),
                  child: const Text('View order'),
                ),
                TextButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to Home'),
                ),
              ],
            )
          : status == 'failed'
          ? FlowStatus(
              icon: Icons.document_scanner_outlined,
              title: 'Couldn’t read this file',
              message:
                  receipt!['error']?.toString() ??
                  'Try a clearer PDF or photo, or enter details manually.',
              actions: [
                FilledButton(
                  onPressed: retryExtraction,
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: () => setState(() => manualEntry = true),
                  child: const Text('Enter manually'),
                ),
              ],
            )
          : FlowStatus(
              loading: true,
              icon: Icons.hourglass_top_rounded,
              title: 'Reading your receipt',
              message:
                  'This usually takes a few seconds. You can leave and come back.',
            ),
    );
  }
}

class OrderEditor extends StatefulWidget {
  final Json initial;
  final String submitLabel;
  final Future<void> Function(Json) onSave;
  final bool compact;
  const OrderEditor({
    super.key,
    required this.initial,
    required this.onSave,
    required this.submitLabel,
    this.compact = true,
  });
  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  final form = GlobalKey<FormState>();
  final Map<String, TextEditingController> fields = {};
  final List<Map<String, TextEditingController>> items = [];
  final List<bool> derived = [];
  bool reviewed = false, busy = false, showAdvanced = false;
  late String platform, status;
  static const moneyFields = [
    'item_subtotal',
    'handling_fee',
    'delivery_fee',
    'packaging_fee',
    'other_fees',
    'taxes',
    'discount',
    'grand_total',
  ];
  @override
  void initState() {
    super.initState();
    platform = widget.initial['platform'] ?? 'other';
    status = widget.initial['status'] ?? 'unknown';
    if (widget.compact && status == 'unknown') {
      status = 'delivered';
    }
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

  String label(String key) => switch (key) {
    'order_date' => 'Purchase date',
    'grand_total' => 'Total paid (₹)',
    'external_order_id' => 'Order ID (optional)',
    'item_subtotal' => 'Item subtotal (optional)',
    'handling_fee' => 'Handling fee (optional)',
    'delivery_fee' => 'Delivery fee (optional)',
    'packaging_fee' => 'Packaging fee (optional)',
    'other_fees' => 'Other fees — small cart, surge (optional)',
    'taxes' => 'Taxes (optional)',
    'discount' => 'Discount (optional)',
    _ =>
      key.split('_').map((s) => s[0].toUpperCase() + s.substring(1)).join(' '),
  };

  Iterable<String> itemFieldKeys() => widget.compact
      ? ['name', 'quantity', 'line_total']
      : ['name', 'quantity', 'unit_price', 'line_total', 'category'];

  Widget moneyField(String key) => TextFormField(
    controller: fields[key],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label(key),
      hintText: 'Leave blank if unknown',
      helperText: widget.initial[key] == null
          ? 'Not found on receipt'
          : 'Read from receipt — change only if wrong',
    ),
    validator: (value) {
      if (key == 'grand_total' && (value == null || value.isEmpty)) {
        return 'Enter the total from your invoice';
      }
      if (value != null &&
          value.isNotEmpty &&
          !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
        return 'Use a valid amount (e.g. 286.00)';
      }
      return null;
    },
  );

  Future<void> save() async {
    if (!form.currentState!.validate() || !reviewed) return;
    final warnings = (widget.initial['warnings'] as List?) ?? [];
    final duplicates = (widget.initial['potential_duplicates'] as List?) ?? [];
    final warningText = warnings.isEmpty ? '' : '\n\n${warnings.join('\n')}';
    final duplicateText = duplicates.isEmpty
        ? ''
        : '\nPossible duplicate order: ${duplicates.join(', ')}.';
    if (!await approve(
      context,
      widget.compact ? 'Save this purchase?' : 'Save reviewed purchase?',
      widget.compact
          ? 'This adds the total to your spending. Check the date, total and products first.$warningText$duplicateText'
          : 'Confirm that you checked every field. Unknown values remain unknown.$warningText$duplicateText',
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
              'category': items[i]['category']?.text.trim().isNotEmpty == true
                  ? items[i]['category']!.text.trim()
                  : 'Uncategorized',
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

  void quickAdd(String category) => setState(
    () => addItem({'name': category, 'quantity': '1', 'category': category}),
  );

  Widget categoryPicker(int index) {
    final controller = items[index]['category']!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (name, icon) in productCategories)
            ChoiceChip(
              avatar: Icon(icon, size: 18),
              label: Text(name),
              selected: controller.text == name,
              onSelected: (selected) => setState(
                () => controller.text = selected ? name : 'Uncategorized',
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> buildProductEditors() {
    return [
      Text('Products', style: Theme.of(context).textTheme.titleLarge),
      Text(
        'Quick add — tap what you bought, then enter its amount.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (name, icon) in productCategories)
            ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(name),
              onPressed: () => quickAdd(name),
            ),
        ],
      ),
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
              categoryPicker(index),
              for (final key in itemFieldKeys())
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: items[index][key],
                    keyboardType:
                        ['quantity', 'unit_price', 'line_total'].contains(key)
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    decoration: InputDecoration(
                      labelText: label(key),
                      helperText: key == 'unit_price' && derived[index]
                          ? 'Derived from line total ÷ quantity'
                          : null,
                    ),
                    onChanged: (_) {
                      if (key == 'unit_price') {
                        setState(() => derived[index] = false);
                      } else if (key == 'category') {
                        setState(() {});
                      }
                    },
                    validator: (value) {
                      if (key == 'name') {
                        return value == null || value.trim().isEmpty
                            ? 'Product name is required'
                            : null;
                      }
                      if (!widget.compact && key == 'category') {
                        return value == null || value.trim().isEmpty
                            ? 'Required'
                            : null;
                      }
                      if (value == null || value.isEmpty) return null;
                      final number = num.tryParse(value);
                      if (number == null ||
                          !number.isFinite ||
                          number < 0 ||
                          (key == 'quantity' && number == 0)) {
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
          'Add at least one product from your receipt.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final optionalFees = [
      'item_subtotal',
      'handling_fee',
      'delivery_fee',
      'packaging_fee',
      'other_fees',
      'taxes',
      'discount',
    ];
    final hasExtractedFees = optionalFees.any(
      (key) => widget.initial[key] != null,
    );
    return Form(
      key: form,
      child: PageBody(
        showBranding: !compact,
        title: compact ? 'Quick review' : 'Check the details.',
        subtitle: compact
            ? 'Confirm the purchase date, total and products. Fees and order ID are optional.'
            : 'You’re in control. Check the date, total and products before saving.',
        children: [
          if (compact && platform != 'other')
            Panel(
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'From ${platformLabel(platform)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (!compact) ...[
            const SoftNotice(
              icon: Icons.fact_check_outlined,
              title: 'A quick check before it counts',
              text:
                  'Blank fields mean we couldn’t read them. Add products and correct the details from your invoice. Nothing counts toward spending until you confirm.',
            ),
          ],
          if ((widget.initial['warnings'] as List?)?.isNotEmpty == true)
            Panel(
              child: Text(
                (widget.initial['warnings'] as List).join('\n'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!compact) ...[
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
          ],
          TextFormField(
            controller: fields['order_date'],
            decoration: InputDecoration(
              labelText: label('order_date'),
              hintText: 'YYYY-MM-DD',
              helperText: widget.initial['order_date'] == null
                  ? 'Usually not on the invoice — pick the delivery or purchase date'
                  : 'Read from receipt — change only if wrong',
            ),
            validator: (value) {
              final parsed = DateTime.tryParse(value ?? '');
              if (parsed == null ||
                  parsed.toIso8601String().substring(0, 10) != value) {
                return 'Enter a valid date as YYYY-MM-DD';
              }
              return null;
            },
          ),
          moneyField('grand_total'),
          ...buildProductEditors(),
          if (compact)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: showAdvanced || hasExtractedFees,
              onExpansionChanged: (value) =>
                  setState(() => showAdvanced = value),
              title: Text(
                'Optional details',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: const Text(
                'Order ID, fees and platform — only if you want to refine analytics',
              ),
              children: [
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
                  decoration: const InputDecoration(labelText: 'Order status'),
                  items: [
                    for (final value in [
                      'delivered',
                      'pending',
                      'cancelled',
                      'refunded',
                    ])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (v) => setState(() => status = v!),
                ),
                TextFormField(
                  controller: fields['external_order_id'],
                  decoration: InputDecoration(
                    labelText: label('external_order_id'),
                  ),
                ),
                for (final key in optionalFees) moneyField(key),
              ],
            )
          else ...[
            for (final entry in fields.entries)
              if (!['order_date', 'grand_total'].contains(entry.key))
                entry.key == 'external_order_id'
                    ? TextFormField(
                        controller: entry.value,
                        decoration: InputDecoration(
                          labelText: label(entry.key),
                        ),
                      )
                    : moneyField(entry.key),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: reviewed,
            onChanged: (v) => setState(() => reviewed = v!),
            title: Text(
              compact
                  ? 'These details match my receipt.'
                  : 'I reviewed the products, amounts, date and status.',
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
                    compact: false,
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
            '${platformLabel(order['platform']?.toString())} · ${order['order_date']} · ${orderStatusLabel(order['status']?.toString())}',
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
                  'other_fees',
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
