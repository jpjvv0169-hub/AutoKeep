import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoKeepApp());
}

class AutoKeepApp extends StatelessWidget {
  const AutoKeepApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AutoKeep',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D63)),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

int asInt(dynamic value, int fallback) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

double asDouble(dynamic value, double fallback) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

String dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

class ServiceRecord {
  String description;
  int mileage;
  double cost;
  DateTime date;
  ServiceRecord(this.description, this.mileage, this.cost, this.date);

  factory ServiceRecord.fromJson(Map<String, dynamic> data) => ServiceRecord(
        '${data['description'] ?? 'Service'}',
        asInt(data['mileage'], 0),
        asDouble(data['cost'], 0),
        DateTime.tryParse('${data['date']}') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'description': description,
        'mileage': mileage,
        'cost': cost,
        'date': date.toIso8601String(),
      };
}

class Vehicle {
  String name;
  String registration;
  int mileage;
  int interval;
  int lastService;
  List<ServiceRecord> history;
  Vehicle(this.name, this.registration, this.mileage, this.interval,
      this.lastService, this.history);

  factory Vehicle.fromJson(Map<String, dynamic> data) {
    final km = asInt(data['mileage'], 0);
    final interval = asInt(data['interval'], 10000);
    return Vehicle(
      '${data['name'] ?? 'Vehicle'}',
      '${data['registration'] ?? ''}',
      km,
      interval > 0 ? interval : 10000,
      asInt(data['lastService'], km),
      (data['history'] is List ? data['history'] as List : <dynamic>[])
          .whereType<Map>()
          .map((e) => ServiceRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'registration': registration,
        'mileage': mileage,
        'interval': interval,
        'lastService': lastService,
        'history': history.map((e) => e.toJson()).toList(),
      };
  int get nextService => lastService + interval;
  int get remaining => nextService - mileage;
  Vehicle copy() => Vehicle(name, registration, mileage, interval, lastService,
      history.map((e) => ServiceRecord(e.description, e.mileage, e.cost, e.date)).toList());
}

Future<bool> confirmDelete(BuildContext context, String item) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete $item?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ?? false;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Vehicle> vehicles = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('vehicles');
    if (!mounted) return;
    setState(() {
      if (raw != null) {
        try {
          final items = jsonDecode(raw) as List;
          vehicles.addAll(items.whereType<Map>().map(
              (e) => Vehicle.fromJson(Map<String, dynamic>.from(e))));
        } catch (e) {
          debugPrint('Could not load vehicles: $e');
        }
      }
      loading = false;
    });
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString('vehicles',
        jsonEncode(vehicles.map((e) => e.toJson()).toList()));
    if (!ok) throw Exception('Unable to save data');
  }

  void showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    }
  }

  Future<void> addVehicle() async {
    final created = await Navigator.push<Vehicle>(context,
        MaterialPageRoute(builder: (_) => const VehicleFormPage()));
    if (created == null || !mounted) return;
    setState(() => vehicles.add(created));
    try {
      await persist();
    } catch (e) {
      if (mounted) setState(() => vehicles.remove(created));
      showError(e);
    }
  }

  Future<void> openVehicle(Vehicle vehicle) async {
    await Navigator.push(context, MaterialPageRoute(
      builder: (_) => VehicleDetailsPage(
        vehicle: vehicle,
        persist: persist,
        deleteVehicle: () async {
          final index = vehicles.indexOf(vehicle);
          if (index < 0) return false;
          setState(() => vehicles.removeAt(index));
          try {
            await persist();
            return true;
          } catch (e) {
            if (mounted) setState(() => vehicles.insert(index, vehicle));
            showError(e);
            return false;
          }
        },
      ),
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('AutoKeep'), centerTitle: true),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : vehicles.isEmpty
                ? const Center(child: Text('No vehicles yet.\nTap + to add a vehicle.',
                    textAlign: TextAlign.center))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: vehicles.length,
                    itemBuilder: (context, index) {
                      final v = vehicles[index];
                      return Card(child: ListTile(
                        leading: const Icon(Icons.directions_car),
                        title: Text(v.name),
                        subtitle: Text('${v.registration}\nCurrent: ${v.mileage} km | Next: ${v.nextService} km'),
                        isThreeLine: true,
                        trailing: Icon(v.remaining <= 0
                            ? Icons.warning_amber : Icons.chevron_right,
                            color: v.remaining <= 0 ? Colors.red : null),
                        onTap: () => openVehicle(v),
                      ));
                    },
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: addVehicle,
          icon: const Icon(Icons.add),
          label: const Text('Add Vehicle'),
        ),
      );
}

class VehicleFormPage extends StatefulWidget {
  final Vehicle? existing;
  const VehicleFormPage({super.key, this.existing});
  @override
  State<VehicleFormPage> createState() => _VehicleFormPageState();
}

class _VehicleFormPageState extends State<VehicleFormPage> {
  late final TextEditingController name;
  late final TextEditingController registration;
  late final TextEditingController mileage;
  late final TextEditingController lastService;
  late final TextEditingController interval;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    name = TextEditingController(text: v?.name ?? '');
    registration = TextEditingController(text: v?.registration ?? '');
    mileage = TextEditingController(text: v == null ? '' : '${v.mileage}');
    lastService = TextEditingController(text: v == null ? '' : '${v.lastService}');
    interval = TextEditingController(text: '${v?.interval ?? 10000}');
  }

  @override
  void dispose() {
    name.dispose();
    registration.dispose();
    mileage.dispose();
    lastService.dispose();
    interval.dispose();
    super.dispose();
  }

  void save() {
    final km = int.tryParse(mileage.text.trim());
    final step = int.tryParse(interval.text.trim());
    final last = lastService.text.trim().isEmpty
        ? km : int.tryParse(lastService.text.trim());
    final previous = widget.existing;
    if (name.text.trim().isEmpty || km == null || km < 0 ||
        (previous != null && km < previous.mileage) ||
        step == null || step <= 0 || last == null || last < 0 || last > km) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Check details. Current mileage cannot decrease.'),
      ));
      return;
    }
    Navigator.pop(context, Vehicle(
      name.text.trim(), registration.text.trim(), km, step, last,
      previous?.history ?? [],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'Add Vehicle' : 'Edit Vehicle')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Make and Model')),
          TextField(controller: registration, decoration: const InputDecoration(labelText: 'Registration Number')),
          TextField(controller: mileage, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Current Mileage (km)')),
          TextField(controller: lastService, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Last Service Mileage (km)',
                  helperText: 'Leave blank when adding a newly serviced vehicle')),
          TextField(controller: interval, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Service Interval (km)')),
          const SizedBox(height: 24),
          FilledButton(onPressed: save, child: const Text('Save Vehicle')),
        ]),
      );
}

class VehicleDetailsPage extends StatefulWidget {
  final Vehicle vehicle;
  final Future<void> Function() persist;
  final Future<bool> Function() deleteVehicle;
  const VehicleDetailsPage({super.key, required this.vehicle,
    required this.persist, required this.deleteVehicle});
  @override
  State<VehicleDetailsPage> createState() => _VehicleDetailsPageState();
}

class _VehicleDetailsPageState extends State<VehicleDetailsPage> {
  bool busy = false;

  Future<void> update(Future<void> Function() change, void Function() undo) async {
    setState(() => busy = true);
    try {
      await change();
      await widget.persist();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved successfully')));
    } catch (e) {
      undo();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editVehicle() async {
    final v = widget.vehicle;
    final edited = await Navigator.push<Vehicle>(context,
        MaterialPageRoute(builder: (_) => VehicleFormPage(existing: v)));
    if (edited == null || !mounted) return;
    final backup = v.copy();
    await update(() async {
      v.name = edited.name;
      v.registration = edited.registration;
      v.mileage = edited.mileage;
      v.lastService = edited.lastService;
      v.interval = edited.interval;
    }, () {
      v.name = backup.name;
      v.registration = backup.registration;
      v.mileage = backup.mileage;
      v.lastService = backup.lastService;
      v.interval = backup.interval;
    });
  }

  Future<void> updateMileage() async {
    final v = widget.vehicle;
    final km = await Navigator.push<int>(context,
        MaterialPageRoute(builder: (_) => MileagePage(current: v.mileage)));
    if (km == null || !mounted) return;
    final previous = v.mileage;
    await update(() async { v.mileage = km; }, () { v.mileage = previous; });
  }

  Future<void> serviceForm([int? index]) async {
    final v = widget.vehicle;
    final existing = index == null ? null : v.history[index];
    final result = await Navigator.push<ServiceRecord>(context,
        MaterialPageRoute(builder: (_) => ServiceFormPage(
          existing: existing, currentMileage: v.mileage,
        )));
    if (result == null || !mounted) return;
    final oldHistory = List<ServiceRecord>.from(v.history);
    final oldKm = v.mileage;
    final oldLast = v.lastService;
    await update(() async {
      if (index == null) {
        v.history.insert(0, result);
      } else {
        v.history[index] = result;
      }
      if (result.mileage > v.mileage) v.mileage = result.mileage;
      // Keep the last service as the greatest recorded service mileage.
      // If no records remain, preserve the manually entered baseline.
      final latest = v.history.fold<int>(0,
          (maxKm, item) => item.mileage > maxKm ? item.mileage : maxKm);
      if (latest > 0) v.lastService = latest;
    }, () {
      v.history = oldHistory;
      v.mileage = oldKm;
      v.lastService = oldLast;
    });
  }

  Future<void> deleteService(int index) async {
    if (!await confirmDelete(context, 'service record') || !mounted) return;
    final v = widget.vehicle;
    final previous = List<ServiceRecord>.from(v.history);
    final oldLast = v.lastService;
    await update(() async {
      v.history.removeAt(index);
      if (v.history.isNotEmpty) {
        v.lastService = v.history.fold<int>(0,
            (maxKm, item) => item.mileage > maxKm ? item.mileage : maxKm);
      } else {
        // Unknown baseline after removing the last record: mark as due.
        // The owner can set the correct last service in Edit Vehicle.
        v.lastService = 0;
      }
    }, () {
      v.history = previous;
      v.lastService = oldLast;
    });
  }

  Future<void> deleteVehicle() async {
    if (!await confirmDelete(context, 'vehicle and all service history') || !mounted) return;
    setState(() => busy = true);
    final deleted = await widget.deleteVehicle();
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context);
    } else {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;
    return Scaffold(
      appBar: AppBar(title: Text(v.name), actions: [
        IconButton(tooltip: 'Edit Vehicle', onPressed: busy ? null : editVehicle,
            icon: const Icon(Icons.edit)),
        PopupMenuButton<String>(enabled: !busy, onSelected: (value) {
          if (value == 'delete') deleteVehicle();
        }, itemBuilder: (_) => [const PopupMenuItem(
          value: 'delete', child: Text('Delete Vehicle'))]),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Registration: ${v.registration}'),
            Text('Current Mileage: ${v.mileage} km'),
            Text('Last Service: ${v.lastService} km'),
            Text('Next Service: ${v.nextService} km'),
            const SizedBox(height: 8),
            Text(v.remaining <= 0 ? 'SERVICE DUE' : '${v.remaining} km until next service',
              style: TextStyle(color: v.remaining <= 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold)),
          ]))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: busy ? null : updateMileage,
            icon: const Icon(Icons.speed), label: const Text('Update Mileage')),
        FilledButton.icon(onPressed: busy ? null : () => serviceForm(),
            icon: const Icon(Icons.build), label: const Text('Add Service')),
        const SizedBox(height: 24),
        Text('Service History', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (v.history.isEmpty) const Text('No services recorded yet.'),
        for (int i = 0; i < v.history.length; i++)
          Card(child: ListTile(
            leading: const Icon(Icons.build_circle_outlined),
            title: Text(v.history[i].description),
            subtitle: Text('${dateLabel(v.history[i].date)} | ${v.history[i].mileage} km'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(v.history[i].cost.toStringAsFixed(2)),
              PopupMenuButton<String>(enabled: !busy, onSelected: (choice) {
                if (choice == 'edit') serviceForm(i);
                if (choice == 'delete') deleteService(i);
              }, itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit Service')),
                PopupMenuItem(value: 'delete', child: Text('Delete Service')),
              ]),
            ]),
            onTap: busy ? null : () => serviceForm(i),
          )),
      ]),
    );
  }
}

class MileagePage extends StatefulWidget {
  final int current;
  const MileagePage({super.key, required this.current});
  @override
  State<MileagePage> createState() => _MileagePageState();
}

class _MileagePageState extends State<MileagePage> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: '${widget.current}');
  }
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  void save() {
    final km = int.tryParse(controller.text.trim());
    if (km == null || km < widget.current) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Mileage cannot be lower than the current reading')));
      return;
    }
    Navigator.pop(context, km);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Update Mileage')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: controller, keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Current Mileage (km)')),
      const SizedBox(height: 24),
      FilledButton(onPressed: save, child: const Text('Save Mileage')),
    ]),
  );
}

class ServiceFormPage extends StatefulWidget {
  final ServiceRecord? existing;
  final int currentMileage;
  const ServiceFormPage({super.key, this.existing, required this.currentMileage});
  @override
  State<ServiceFormPage> createState() => _ServiceFormPageState();
}

class _ServiceFormPageState extends State<ServiceFormPage> {
  late final TextEditingController description;
  late final TextEditingController mileage;
  late final TextEditingController cost;
  late DateTime date;
  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    description = TextEditingController(text: old?.description ?? '');
    mileage = TextEditingController(text: '${old?.mileage ?? widget.currentMileage}');
    cost = TextEditingController(text: '${old?.cost ?? 0}');
    date = old?.date ?? DateTime.now();
  }
  @override
  void dispose() {
    description.dispose(); mileage.dispose(); cost.dispose(); super.dispose();
  }
  Future<void> chooseDate() async {
    final chosen = await showDatePicker(context: context, initialDate: date,
      firstDate: DateTime(1990), lastDate: DateTime.now());
    if (chosen != null && mounted) setState(() => date = chosen);
  }
  void save() {
    final km = int.tryParse(mileage.text.trim());
    final amount = double.tryParse(cost.text.trim().replaceAll(',', '.'));
    if (description.text.trim().isEmpty || km == null || km < 0 ||
        amount == null || !amount.isFinite || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter valid service details')));
      return;
    }
    Navigator.pop(context, ServiceRecord(description.text.trim(), km, amount, date));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? 'Add Service' : 'Edit Service')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: description,
          decoration: const InputDecoration(labelText: 'Service Description')),
      TextField(controller: mileage, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Mileage at Service')),
      TextField(controller: cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Service Cost')),
      ListTile(leading: const Icon(Icons.calendar_month),
          title: const Text('Service Date'), subtitle: Text(dateLabel(date)),
          onTap: chooseDate),
      const SizedBox(height: 24),
      FilledButton(onPressed: save, child: const Text('Save Service')),
    ]),
  );
}
