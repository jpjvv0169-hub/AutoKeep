
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
    int number(dynamic value, int fallback) {
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    final mileage = number(json['mileage'], 0);
    final interval = number(json['interval'], 10000);

    return Vehicle(
      name: '${json['name'] ?? 'Vehicle'}',
      registration: '${json['registration'] ?? ''}',
      mileage: mileage,
      interval: interval > 0 ? interval : 10000,
      lastService: number(json['lastService'], mileage),
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
        'history': history.map((item) => item.toJson()).toList(),
      };

  int get nextService => lastService + interval;
  int get remaining => nextService - mileage;
}

class ServiceRecord {
  final String description;
  final int mileage;
  final double cost;
  final DateTime date;

  ServiceRecord({
    required this.description,
    required this.mileage,
    required this.cost,
    required this.date,
  });

  factory ServiceRecord.fromJson(Map<String, dynamic> json) {
    return ServiceRecord(
      description: '${json['description'] ?? 'Service'}',
      mileage: (json['mileage'] as num?)?.toInt() ?? 0,
      cost: (json['cost'] as num?)?.toDouble() ?? 0,
      date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'description': description,
        'mileage': mileage,
        'cost': cost,
        'date': date.toIso8601String(),
      };
}

String formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';
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
    loadVehicles();
  }

  Future<void> loadVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('vehicles');

    if (!mounted) return;

    setState(() {
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as List;
          vehicles.addAll(
            decoded.whereType<Map>().map(
                  (item) => Vehicle.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                ),
          );
        } catch (error) {
          debugPrint('Could not read vehicles: $error');
        }
      }
      loading = false;
    });
  }

  Future<void> saveVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(
      vehicles.map((vehicle) => vehicle.toJson()).toList(),
    );
    final saved = await prefs.setString('vehicles', data);

    if (!saved) {
      throw Exception('Vehicle data could not be saved');
    }
  }

  Future<void> addVehicle() async {
    final vehicle = await Navigator.push<Vehicle>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddVehiclePage(),
      ),
    );

    if (vehicle == null || !mounted) return;

    setState(() => vehicles.add(vehicle));

    try {
      await saveVehicles();
    } catch (error) {
      if (!mounted) return;
      setState(() => vehicles.remove(vehicle));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    }
  }

  Future<void> openVehicle(Vehicle vehicle) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleDetailsPage(
          vehicle: vehicle,
          onSave: saveVehicles,
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
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : vehicles.isEmpty
              ? const Center(
                  child: Text(
                    'No vehicles yet.\nTap + to add your first vehicle.',
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
                        trailing: Icon(
                          vehicle.remaining <= 0
                              ? Icons.warning_amber_rounded
                              : Icons.chevron_right,
                          color: vehicle.remaining <= 0
                              ? Colors.red
                              : null,
                        ),
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

class AddVehiclePage extends StatefulWidget {
  const AddVehiclePage({super.key});

  @override
  State<AddVehiclePage> createState() => _AddVehiclePageState();
}

class _AddVehiclePageState extends State<AddVehiclePage> {
  final name = TextEditingController();
  final registration = TextEditingController();
  final mileage = TextEditingController();
  final interval = TextEditingController(text: '10000');
  final lastService = TextEditingController();

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
    final serviceInterval = int.tryParse(interval.text.trim());
    final last = lastService.text.trim().isEmpty
        ? km
        : int.tryParse(lastService.text.trim());

    if (name.text.trim().isEmpty ||
        km == null ||
        km < 0 ||
        serviceInterval == null ||
        serviceInterval <= 0 ||
        last == null ||
        last < 0 ||
        last > km) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid vehicle details'),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      Vehicle(
        name: name.text.trim(),
        registration: registration.text.trim(),
        mileage: km,
        interval: serviceInterval,
        lastService: last,
        history: [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Vehicle')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Make and Model',
            ),
          ),
          TextField(
            controller: registration,
            decoration: const InputDecoration(
              labelText: 'Registration Number',
            ),
          ),
          TextField(
            controller: mileage,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Current Mileage (km)',
            ),
          ),
          TextField(
            controller: lastService,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Last Service Mileage (optional)',
              helperText: 'Leave blank if serviced at current mileage',
            ),
          ),
          TextField(
            controller: interval,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Service Interval (km)',
            ),
          ),
          const SizedBox(height: 24),
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

  const VehicleDetailsPage({
    super.key,
    required this.vehicle,
    required this.onSave,
  });

  @override
  State<VehicleDetailsPage> createState() => _VehicleDetailsPageState();
}

class _VehicleDetailsPageState extends State<VehicleDetailsPage> {
  bool saving = false;

  Future<void> updateMileage() async {
    final result = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => UpdateMileagePage(
          currentMileage: widget.vehicle.mileage,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final oldMileage = widget.vehicle.mileage;
    setState(() {
      saving = true;
      widget.vehicle.mileage = result;
    });

    try {
      await widget.onSave();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mileage saved')),
      );
    } catch (error) {
      widget.vehicle.mileage = oldMileage;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> addService() async {
    final result = await Navigator.push<ServiceRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => AddServicePage(
          currentMileage: widget.vehicle.mileage,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final vehicle = widget.vehicle;
    final oldMileage = vehicle.mileage;
    final oldLastService = vehicle.lastService;

    setState(() {
      saving = true;
      vehicle.history.insert(0, result);
      if (result.mileage > vehicle.mileage) {
        vehicle.mileage = result.mileage;
      }
      if (result.mileage >= vehicle.lastService) {
        vehicle.lastService = result.mileage;
      }
    });

    try {
      await widget.onSave();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service saved')),
      );
    } catch (error) {
      vehicle.history.remove(result);
      vehicle.mileage = oldMileage;
      vehicle.lastService = oldLastService;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $error')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;

    return Scaffold(
      appBar: AppBar(title: Text(vehicle.name)),
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
                    vehicle.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Registration: ${vehicle.registration}'),
                  Text('Current Mileage: ${vehicle.mileage} km'),
                  Text('Last Service: ${vehicle.lastService} km'),
                  Text('Next Service: ${vehicle.nextService} km'),
                  const SizedBox(height: 12),
                  Text(
                    vehicle.remaining <= 0
                        ? 'SERVICE DUE'
                        : '${vehicle.remaining} km until next service',
                    style: TextStyle(
                      color: vehicle.remaining <= 0
                          ? Colors.red
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saving ? null : updateMileage,
            icon: const Icon(Icons.speed),
            label: const Text('Update Mileage'),
          ),
          FilledButton.icon(
            onPressed: saving ? null : addService,
            icon: const Icon(Icons.build),
            label: const Text('Add Service'),
          ),
          const SizedBox(height: 24),
          Text(
            'Service History',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (vehicle.history.isEmpty)
            const Text('No services recorded yet.'),
          ...vehicle.history.map(
            (service) => Card(
              child: ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: Text(service.description),
                subtitle: Text(
                  '${formatDate(service.date)} | '
                  '${service.mileage} km',
                ),
                trailing: Text(service.cost.toStringAsFixed(2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UpdateMileagePage extends StatefulWidget {
  final int currentMileage;

  const UpdateMileagePage({
    super.key,
    required this.currentMileage,
  });

  @override
  State<UpdateMileagePage> createState() => _UpdateMileagePageState();
}

class _UpdateMileagePageState extends State<UpdateMileagePage> {
  late final TextEditingController mileage;

  @override
  void initState() {
    super.initState();
    mileage = TextEditingController(
      text: '${widget.currentMileage}',
    );
  }

  @override
  void dispose() {
    mileage.dispose();
    super.dispose();
  }

  void save() {
    final km = int.tryParse(mileage.text.trim());

    if (km == null || km < widget.currentMileage) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mileage cannot be lower than current mileage'),
        ),
      );
      return;
    }

    Navigator.pop(context, km);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update Mileage')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: mileage,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New Mileage (km)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: save,
              child: const Text('Save Mileage'),
            ),
          ],
        ),
      ),
    );
  }
}

class AddServicePage extends StatefulWidget {
  final int currentMileage;

  const AddServicePage({
    super.key,
    required this.currentMileage,
  });

  @override
  State<AddServicePage> createState() => _AddServicePageState();
}

class _AddServicePageState extends State<AddServicePage> {
  final description = TextEditingController();
  final cost = TextEditingController(text: '0');
  late final TextEditingController mileage;
  DateTime serviceDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    mileage = TextEditingController(
      text: '${widget.currentMileage}',
    );
  }

  @override
  void dispose() {
    description.dispose();
    cost.dispose();
    mileage.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: serviceDate,
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );

    if (selected != null && mounted) {
      setState(() => serviceDate = selected);
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter valid service details'),
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Service')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: description,
            decoration: const InputDecoration(
              labelText: 'Service Description',
              hintText: 'Example: Oil and filters',
            ),
          ),
          TextField(
            controller: mileage,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Mileage at Service',
            ),
          ),
          TextField(
            controller: cost,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(
              labelText: 'Service Cost',
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text('Service Date'),
            subtitle: Text(formatDate(serviceDate)),
            trailing: const Icon(Icons.edit_calendar),
            onTap: chooseDate,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save),
            label: const Text('Save Service'),
          ),
        ],
      ),
    );
  }
}
