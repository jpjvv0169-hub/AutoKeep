
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutoKeepApp());
}

class AutoKeepApp extends StatelessWidget {
  const AutoKeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoKeep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006D63),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

int readInt(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double readDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

class ServiceRecord {
  String description;
  int mileage;
  double cost;
  DateTime date;

  ServiceRecord({
    required this.description,
    required this.mileage,
    required this.cost,
    required this.date,
  });

  factory ServiceRecord.fromJson(Map<String, dynamic> json) {
    return ServiceRecord(
      description: '${json['description'] ?? 'Service'}',
      mileage: readInt(json['mileage']),
      cost: readDouble(json['cost']),
      date: DateTime.tryParse('${json['date']}') ??
          DateTime.now(),
    );
  }

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

  Vehicle({
    required this.name,
    required this.registration,
    required this.mileage,
    required this.interval,
    required this.lastService,
    required this.history,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    final km = readInt(json['mileage']);
    final gap = readInt(json['interval'], 10000);

    return Vehicle(
      name: '${json['name'] ?? 'Vehicle'}',
      registration: '${json['registration'] ?? ''}',
      mileage: km,
      interval: gap > 0 ? gap : 10000,
      lastService: readInt(json['lastService'], km),
      history: (json['history'] is List
              ? json['history'] as List
              : <dynamic>[])
          .whereType<Map>()
          .map((item) => ServiceRecord.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'registration': registration,
        'mileage': mileage,
        'interval': interval,
        'lastService': lastService,
        'history': history.map((s) => s.toJson()).toList(),
      };

  int get nextService => lastService + interval;
  int get remaining => nextService - mileage;
}

String formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
}

Widget formField(
  TextEditingController controller,
  String label, {
  bool numeric = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType:
          numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Vehicle> vehicles = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadVehicles();
  }

  Future<void> loadVehicles() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final raw = prefs.getString('vehicles');
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is List) {
          vehicles = data
              .whereType<Map>()
              .map((item) => Vehicle.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList();
        }
      }
    } catch (error) {
      debugPrint('Vehicle loading failed: $error');
      if (mounted) {
        showMessage(context, 'Could not read saved vehicles');
      }
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> saveVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(
      vehicles.map((v) => v.toJson()).toList(),
    );

    final success = await prefs.setString('vehicles', data);
    if (!success) throw Exception('Could not save data');
  }

  Future<void> saveChange(
    void Function() update,
  ) async {
    final previous = jsonEncode(
      vehicles.map((v) => v.toJson()).toList(),
    );

    try {
      update();
      await saveVehicles();
      if (mounted) setState(() {});
    } catch (error) {
      vehicles = (jsonDecode(previous) as List)
          .map((item) => Vehicle.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();

      if (mounted) {
        setState(() {});
        showMessage(context, 'Save failed: $error');
      }
    }
  }

  Future<void> addVehicle() async {
    if (vehicles.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ProPage(),
        ),
      );
      return;
    }

    final result = await Navigator.push<Vehicle>(
      context,
      MaterialPageRoute(
        builder: (_) => const VehicleForm(),
      ),
    );

    if (result != null) {
      await saveChange(() => vehicles.add(result));
    }
  }

  Future<void> copyBackup() async {
    final backup = jsonEncode({
      'format': 'AutoKeepBackup',
      'version': 1,
      'vehicles': vehicles.map((v) => v.toJson()).toList(),
    });

    await Clipboard.setData(ClipboardData(text: backup));

    if (mounted) {
      showMessage(
        context,
        'Backup copied. Save it in a secure text file.',
      );
    }
  }

  Future<void> restoreBackup() async {
    final controller = TextEditingController();

    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore Backup'),
        content: TextField(
          controller: controller,
          maxLines: 7,
          decoration: const InputDecoration(
            hintText: 'Paste your AutoKeep backup here',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (input == null || input.trim().isEmpty || !mounted) {
      return;
    }

    try {
      final decoded = jsonDecode(input);

      if (decoded is! Map ||
          decoded['format'] != 'AutoKeepBackup' ||
          decoded['vehicles'] is! List) {
        throw const FormatException('Invalid backup');
      }

      final restored = (decoded['vehicles'] as List)
          .map((item) => Vehicle.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList();

      final confirmed = await confirmAction(
        context,
        'Replace existing data?',
        'All current vehicles and service records '
            'will be replaced by this backup.',
      );

      if (!confirmed) return;

      await saveChange(() => vehicles = restored);

      if (mounted) showMessage(context, 'Restore completed');
    } catch (error) {
      if (mounted) {
        showMessage(context, 'Invalid backup: $error');
      }
    }
  }

  Future<void> openVehicle(Vehicle vehicle) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleDetailsPage(
          vehicle: vehicle,
          onSave: saveVehicles,
          onDelete: () async {
            await saveChange(() => vehicles.remove(vehicle));
          },
        ),
      ),
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoKeep'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'backup') copyBackup();
              if (value == 'restore') restoreBackup();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'backup',
                child: Text('Copy Backup'),
              ),
              PopupMenuItem(
                value: 'restore',
                child: Text('Restore Backup'),
              ),
            ],
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : vehicles.isEmpty
              ? const Center(
                  child: Text(
                    'No vehicles yet.\nTap Add Vehicle.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: vehicles.length,
                  itemBuilder: (context, index) {
                    final vehicle = vehicles[index];

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.directions_car),
                        title: Text(vehicle.name),
                        subtitle: Text(
                          '${vehicle.registration}\n'
                          'Current: ${vehicle.mileage} km | '
                          'Next: ${vehicle.nextService} km',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openVehicle(vehicle),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addVehicle,
        icon: const Icon(Icons.add),
        label: const Text('Add Vehicle'),
      ),
    );
  }
}

class ProPage extends StatelessWidget {
  const ProPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AutoKeep Pro')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.workspace_premium,
              size: 80,
              color: Color(0xFF006D63),
            ),
            SizedBox(height: 20),
            Text(
              'Free includes 1 vehicle',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Upgrade to AutoKeep Pro for unlimited vehicles.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'Planned price: R39.99 per month',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            Text(
              'Subscriptions are not active in this test build. '
              'No payment will be taken.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class VehicleForm extends StatefulWidget {
  final Vehicle? vehicle;

  const VehicleForm({super.key, this.vehicle});

  @override
  State<VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<VehicleForm> {
  late final TextEditingController name;
  late final TextEditingController registration;
  late final TextEditingController mileage;
  late final TextEditingController interval;
  late final TextEditingController lastService;

  @override
  void initState() {
    super.initState();

    final v = widget.vehicle;

    name = TextEditingController(text: v?.name ?? '');
    registration = TextEditingController(
      text: v?.registration ?? '',
    );
    mileage = TextEditingController(
      text: v == null ? '' : '${v.mileage}',
    );
    interval = TextEditingController(
      text: '${v?.interval ?? 10000}',
    );
    lastService = TextEditingController(
      text: v == null ? '' : '${v.lastService}',
    );
  }

  @override
  void dispose() {
    name.dispose();
    registration.dispose();
    mileage.dispose();
    interval.dispose();
    lastService.dispose();
    super.dispose();
  }

  void save() {
    final km = int.tryParse(mileage.text.trim());
    final gap = int.tryParse(interval.text.trim());
    final last = int.tryParse(lastService.text.trim());

    if (name.text.trim().isEmpty ||
        km == null ||
        km < 0 ||
        gap == null ||
        gap <= 0 ||
        last == null ||
        last < 0 ||
        last > km) {
      showMessage(context, 'Enter valid vehicle details');
      return;
    }

    if (widget.vehicle != null &&
        km < widget.vehicle!.mileage) {
      showMessage(context, 'Mileage cannot decrease');
      return;
    }

    Navigator.pop(
      context,
      Vehicle(
        name: name.text.trim(),
        registration: registration.text.trim(),
        mileage: km,
        interval: gap,
        lastService: last,
        history: widget.vehicle?.history.toList() ?? [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.vehicle == null ? 'Add Vehicle' : 'Edit Vehicle',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          formField(name, 'Make and Model'),
          formField(registration, 'Registration Number'),
          formField(mileage, 'Current Mileage', numeric: true),
          formField(
            lastService,
            'Last Service Mileage',
            numeric: true,
          ),
          formField(
            interval,
            'Service Interval (km)',
            numeric: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: save,
            child: const Text('Save Vehicle'),
          ),
        ],
      ),
    );
  }
}

class VehicleDetailsPage extends StatefulWidget {
  final Vehicle vehicle;
  final Future<void> Function() onSave;
  final Future<void> Function() onDelete;

  const VehicleDetailsPage({
    super.key,
    required this.vehicle,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<VehicleDetailsPage> createState() =>
      _VehicleDetailsPageState();
}

class _VehicleDetailsPageState
    extends State<VehicleDetailsPage> {
  bool busy = false;

  Future<void> commit(
    void Function() update,
    void Function() rollback,
  ) async {
    setState(() => busy = true);
    update();

    try {
      await widget.onSave();
      if (mounted) setState(() {});
    } catch (error) {
      rollback();
      if (mounted) {
        showMessage(context, 'Save failed: $error');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editVehicle() async {
    final v = widget.vehicle;

    final result = await Navigator.push<Vehicle>(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleForm(vehicle: v),
      ),
    );

    if (result == null || !mounted) return;

    final oldName = v.name;
    final oldRegistration = v.registration;
    final oldMileage = v.mileage;
    final oldInterval = v.interval;
    final oldLast = v.lastService;

    await commit(
      () {
        v.name = result.name;
        v.registration = result.registration;
        v.mileage = result.mileage;
        v.interval = result.interval;
        v.lastService = result.lastService;
      },
      () {
        v.name = oldName;
        v.registration = oldRegistration;
        v.mileage = oldMileage;
        v.interval = oldInterval;
        v.lastService = oldLast;
      },
    );
  }

  Future<void> updateMileage() async {
    final controller = TextEditingController(
      text: '${widget.vehicle.mileage}',
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update Mileage'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Current Mileage',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    // controller.dispose();

    if (result == null || !mounted) return;

    final km = int.tryParse(result.trim());

    if (km == null || km < widget.vehicle.mileage) {
      showMessage(context, 'Mileage cannot decrease');
      return;
    }

    final old = widget.vehicle.mileage;

    await commit(
      () => widget.vehicle.mileage = km,
      () => widget.vehicle.mileage = old,
    );
  }

  Future<void> addOrEditService({
    ServiceRecord? existing,
  }) async {
    final result = await Navigator.push<ServiceRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceForm(
          existing: existing,
          currentMileage: widget.vehicle.mileage,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final v = widget.vehicle;
    final oldHistory = List<ServiceRecord>.from(v.history);
    final oldMileage = v.mileage;
    final oldLast = v.lastService;

    await commit(
      () {
        if (existing != null) v.history.remove(existing);

        v.history.insert(0, result);

        if (result.mileage > v.mileage) {
          v.mileage = result.mileage;
        }

        recalculateLastService(v);
      },
      () {
        v.history = oldHistory;
        v.mileage = oldMileage;
        v.lastService = oldLast;
      },
    );
  }

  void recalculateLastService(Vehicle v) {
    if (v.history.isNotEmpty) {
      v.lastService = v.history
          .map((service) => service.mileage)
          .reduce((a, b) => a > b ? a : b);
    }
  }

  Future<void> deleteService(ServiceRecord service) async {
    final confirmed = await confirmAction(
      context,
      'Delete Service?',
      'This service record will be permanently removed.',
    );

    if (!confirmed) return;

    final v = widget.vehicle;
    final oldHistory = List<ServiceRecord>.from(v.history);
    final oldLast = v.lastService;

    await commit(
      () {
        v.history.remove(service);
        recalculateLastService(v);
      },
      () {
        v.history = oldHistory;
        v.lastService = oldLast;
      },
    );
  }

  Future<void> deleteVehicle() async {
    final confirmed = await confirmAction(
      context,
      'Delete Vehicle?',
      'This deletes the vehicle and all its service history.',
    );

    if (!confirmed) return;

    await widget.onDelete();

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vehicle;

    return Scaffold(
      appBar: AppBar(
        title: Text(v.name),
        actions: [
          IconButton(
            tooltip: 'Edit Vehicle',
            onPressed: busy ? null : editVehicle,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'Delete Vehicle',
            onPressed: busy ? null : deleteVehicle,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.name,
                    style:
                        Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('Registration: ${v.registration}'),
                  Text('Current Mileage: ${v.mileage} km'),
                  Text('Last Service: ${v.lastService} km'),
                  Text('Next Service: ${v.nextService} km'),
                  const SizedBox(height: 12),
                  Text(
                    v.remaining <= 0
                        ? 'SERVICE DUE'
                        : '${v.remaining} km until next service',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: v.remaining <= 0
                          ? Colors.red
                          : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : updateMileage,
            icon: const Icon(Icons.speed),
            label: const Text('Update Mileage'),
          ),
          FilledButton.icon(
            onPressed: busy
                ? null
                : () => addOrEditService(),
            icon: const Icon(Icons.build),
            label: const Text('Add Service'),
          ),
          const SizedBox(height: 24),
          Text(
            'Service History',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (v.history.isEmpty)
            const Text('No services recorded yet.'),
          ...v.history.map(
            (service) => Card(
              child: ListTile(
                title: Text(service.description),
                subtitle: Text(
                  '${formatDate(service.date)} | '
                  '${service.mileage} km | '
                  '${service.cost.toStringAsFixed(2)}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') {
                      addOrEditService(existing: service);
                    } else {
                      deleteService(service);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Service'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Service'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ServiceForm extends StatefulWidget {
  final ServiceRecord? existing;
  final int currentMileage;

  const ServiceForm({
    super.key,
    this.existing,
    required this.currentMileage,
  });

  @override
  State<ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<ServiceForm> {
  late final TextEditingController description;
  late final TextEditingController mileage;
  late final TextEditingController cost;
  late DateTime serviceDate;

  @override
  void initState() {
    super.initState();

    final s = widget.existing;

    description = TextEditingController(
      text: s?.description ?? '',
    );
    mileage = TextEditingController(
      text: '${s?.mileage ?? widget.currentMileage}',
    );
    cost = TextEditingController(
      text: '${s?.cost ?? 0}',
    );
    serviceDate = s?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    description.dispose();
    mileage.dispose();
    cost.dispose();
    super.dispose();
  }

  void save() {
    final km = int.tryParse(mileage.text.trim());
    final amount = double.tryParse(
      cost.text.trim().replaceAll(',', '.'),
    );

    if (description.text.trim().isEmpty ||
        km == null ||
        km < 0 ||
        amount == null ||
        !amount.isFinite ||
        amount < 0) {
      showMessage(context, 'Enter valid service details');
      return;
    }

    Navigator.pop(
      context,
      ServiceRecord(
        description: description.text.trim(),
        mileage: km,
        cost: amount,
        date: serviceDate,
      ),
    );
  }

  Future<void> chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: serviceDate,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );

    if (picked != null && mounted) {
      setState(() => serviceDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Add Service'
              : 'Edit Service',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          formField(description, 'Service Description'),
          formField(
            mileage,
            'Mileage at Service',
            numeric: true,
          ),
          formField(cost, 'Service Cost'),
          ListTile(
            title: const Text('Service Date'),
            subtitle: Text(formatDate(serviceDate)),
            trailing: const Icon(Icons.calendar_month),
            onTap: chooseDate,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: save,
            child: const Text('Save Service'),
          ),
        ],
      ),
    );
  }
}
