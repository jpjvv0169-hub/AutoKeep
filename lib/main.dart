import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JobCardFinancePage extends StatefulWidget {
  const JobCardFinancePage({super.key, required this.businessId, required this.jobCardId, this.currency = 'ZAR'});
  final String businessId, jobCardId, currency;
  @override
  State<JobCardFinancePage> createState() => _JobCardFinancePageState();
}

class _JobCardFinancePageState extends State<JobCardFinancePage> {
  final client = Supabase.instance.client;
  bool loading = true, busy = false;
  String? error;
  List<Map<String, dynamic>> labour = [], parts = [], staff = [];
  Map<String, dynamic>? summary;

  String money(num amount) => '${widget.currency} ${amount.toStringAsFixed(2)}';
  num asNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
  num amount(dynamic quantity, dynamic minor) => asNum(quantity) * asNum(minor) / 100;
  String fmt(dynamic quantity, dynamic minor) => money(amount(quantity, minor));

  @override
  void initState() { super.initState(); reload(); }

  Future<void> reload() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final l = await client.from('job_card_labour').select().eq('business_id', widget.businessId).eq('job_card_id', widget.jobCardId).order('created_at');
      final p = await client.from('job_card_parts').select().eq('business_id', widget.businessId).eq('job_card_id', widget.jobCardId).order('created_at');
      final s = await client.from('staff').select('id, full_name').eq('business_id', widget.businessId).order('full_name');
      final result = await client.rpc('job_card_financial_summary', params: {'p_job_card_id': widget.jobCardId});
      if (result is! List || result.length != 1) throw StateError('Financial summary unavailable. Check owner permissions.');
      if (!mounted) return;
      setState(() {
        labour = List<Map<String, dynamic>>.from(l);
        parts = List<Map<String, dynamic>>.from(p);
        staff = List<Map<String, dynamic>>.from(s);
        summary = Map<String, dynamic>.from(result.first as Map);
      });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> addEntry(bool isLabour) async {
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final cost = TextEditingController(text: '0');
    final sell = TextEditingController(text: '0');
    final partNumber = TextEditingController();
    String? selectedStaff;
    final form = GlobalKey<FormState>();
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: Text(isLabour ? 'Add Labour' : 'Add Part'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isLabour) DropdownButtonFormField<String>(
            value: selectedStaff,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Employee (optional)'),
            items: [const DropdownMenuItem<String>(value: null, child: Text('Not assigned')),
              ...staff.map((s) => DropdownMenuItem<String>(value: s['id'].toString(), child: Text(s['full_name'].toString())))],
            onChanged: (v) => update(() => selectedStaff = v),
          ),
          if (!isLabour) TextFormField(controller: partNumber, decoration: const InputDecoration(labelText: 'Part number (optional)')),
          TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Description *'),
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          TextFormField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: isLabour ? 'Hours *' : 'Quantity *'),
            validator: (v) { final n = num.tryParse((v ?? '').replaceAll(',', '.')); return n == null || (isLabour ? n < 0 : n <= 0) ? 'Enter valid number' : null; }),
          TextFormField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: isLabour ? 'Internal cost / hour (${widget.currency})' : 'Purchase price / unit (${widget.currency})'),
            validator: validatePrice),
          TextFormField(controller: sell, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: isLabour ? 'Customer rate / hour (${widget.currency})' : 'Selling price / unit (${widget.currency})'),
            validator: validatePrice),
        ])))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (!form.currentState!.validate()) return;
            final q = num.parse(quantity.text.replaceAll(',', '.'));
            final c = (num.parse(cost.text.replaceAll(',', '.')) * 100).round();
            final s = (num.parse(sell.text.replaceAll(',', '.')) * 100).round();
            Navigator.pop(ctx, {
              'business_id': widget.businessId, 'job_card_id': widget.jobCardId,
              'description': description.text.trim(),
              if (isLabour) ...{'staff_id': selectedStaff, 'hours': q, 'cost_rate_minor': c, 'sell_rate_minor': s}
              else ...{'part_number': partNumber.text.trim().isEmpty ? null : partNumber.text.trim(), 'quantity': q, 'cost_price_minor': c, 'sell_price_minor': s},
            });
          }, child: const Text('Add')),
        ],
      )),
    );
    description.dispose(); quantity.dispose(); cost.dispose(); sell.dispose(); partNumber.dispose();
    if (data == null || !mounted) return;
    setState(() => busy = true);
    try {
      await client.from(isLabour ? 'job_card_labour' : 'job_card_parts').insert(data);
      await reload();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'))); }
    finally { if (mounted) setState(() => busy = false); }
  }

  String? validatePrice(String? v) {
    final n = num.tryParse((v ?? '').replaceAll(',', '.'));
    if (n == null || n < 0 || n > 100000000) return 'Enter a valid non-negative price';
    return null;
  }

  Future<void> remove(bool isLabour, String id) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete entry?'), content: const Text('This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final deleted = await client.from(isLabour ? 'job_card_labour' : 'job_card_parts')
          .delete().eq('id', id).eq('business_id', widget.businessId).eq('job_card_id', widget.jobCardId).select('id');
      if (deleted.isEmpty) throw StateError('No row deleted. Check permissions.');
      await reload();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'))); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Widget total(String label, String key) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label), Text(money(asNum(summary?[key])), style: const TextStyle(fontWeight: FontWeight.bold)),
    ]));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Job Card • Labour & Parts'), actions: [IconButton(onPressed: busy ? null : reload, icon: const Icon(Icons.refresh))]),
    body: loading ? const Center(child: CircularProgressIndicator()) : error != null
      ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(error!), const SizedBox(height: 12), FilledButton(onPressed: reload, child: const Text('Retry')),
        ])))
      : ListView(padding: const EdgeInsets.all(16), children: [
          Text('Labour', style: Theme.of(context).textTheme.titleLarge),
          for (final l in labour) Card(child: ListTile(
            title: Text(l['description'].toString()),
            subtitle: Text('${l['hours']} hours • Cost ${fmt(l['hours'], l['cost_rate_minor'])} • Sell ${fmt(l['hours'], l['sell_rate_minor'])}'),
            trailing: IconButton(onPressed: busy ? null : () => remove(true, l['id'].toString()), icon: const Icon(Icons.delete_outline)),
          )),
          if (labour.isEmpty) const Text('No labour recorded yet.'),
          OutlinedButton.icon(onPressed: busy ? null : () => addEntry(true), icon: const Icon(Icons.add), label: const Text('Add Labour')),
          const SizedBox(height: 22),
          Text('Parts', style: Theme.of(context).textTheme.titleLarge),
          for (final p in parts) Card(child: ListTile(
            title: Text(p['description'].toString()),
            subtitle: Text('${p['part_number'] ?? 'No part number'} • Qty ${p['quantity']}\nCost ${fmt(p['quantity'], p['cost_price_minor'])} • Sell ${fmt(p['quantity'], p['sell_price_minor'])}'),
            isThreeLine: true,
            trailing: IconButton(onPressed: busy ? null : () => remove(false, p['id'].toString()), icon: const Icon(Icons.delete_outline)),
          )),
          if (parts.isEmpty) const Text('No parts recorded yet.'),
          OutlinedButton.icon(onPressed: busy ? null : () => addEntry(false), icon: const Icon(Icons.add), label: const Text('Add Part')),
          const SizedBox(height: 22),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Owner financial summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            total('Labour cost', 'labour_cost'), total('Labour sell', 'labour_sell'),
            total('Parts cost', 'parts_cost'), total('Parts sell', 'parts_sell'),
            const Divider(), total('Total internal cost', 'total_cost'),
            total('Customer total', 'total_sell'), total('Gross profit', 'gross_profit'),
            Text('Gross margin: ${asNum(summary?['gross_margin_percent']).toStringAsFixed(2)}%'),
            const SizedBox(height: 8),
            const Text('Excludes VAT, overheads and other expenses.'),
          ]))),
        ]),
  );
}
