
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
          seedColor: const Color(0xFF176B61),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> vehicles = [];
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
          vehicles = (jsonDecode(raw) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        } catch (_) {
          vehicles = [];
        }
      }
      loading = false;
    });
  }

  Future<void> saveVehicles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicles', jsonEncode(vehicles));
  }

  Future<void> addVehicle() async {
    final name = TextEditingController();
    final registration = TextEditingController();
    final mileage = TextEditingController();
    final interval = TextEditingController(text: '10000');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Vehicle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                controller: interval,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Service Interval (km)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final km = int.tryParse(mileage.text);
              final serviceKm = int.tryParse(interval.text);

              if (name.text.trim().isEmpty ||
                  km == null ||
                  km < 0 ||
                  serviceKm == null ||
                  serviceKm <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter valid vehicle details'),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext, {
                'name': name.text.trim(),
                'registration': registration.text.trim(),
                'mileage': km,
                'interval': serviceKm,
                'lastService': km,
                'history': <Map<String, dynamic>>[],
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    name.dispose();
    registration.dispose();
    mileage.dispose();
    interval.dispose();

    if (result != null) {
      setState(() => vehicles.add(result));
      await saveVehicles();
    }
  }

  Future<void> updateMileage(int index) async {
    final controller = TextEditingController(
      text: '${vehicles[index]['mileage']}',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Update Mileage'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Current Mileage (km)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final km = int.tryParse(controller.text);
              final oldKm = vehicles[index]['mileage'] as int;

              if (km == null || km < oldKm) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Mileage cannot decrease'),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext, km);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result != null) {
      setState(() => vehicles[index]['mileage'] = result);
      await saveVehicles();
    }
  }

  Future<void> addService(int index) async {
    final description = TextEditingController();
    final cost = TextEditingController();
    final kmController = TextEditingController(
      text: '${vehicles[index]['mileage']}',
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Service'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Service Description',
                ),
              ),
              TextField(
                controller: kmController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Mileage at Service',
                ),
              ),
              TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cost',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final km = int.tryParse(kmController.text);
              final amount = double.tryParse(cost.text);

              if (description.text.trim().isEmpty ||
                  km == null ||
                  km < 0 ||
                  amount == null ||
                  amount < 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter valid service details'),
                  ),
                );
                return;
              }

              Navigator.pop(dialogContext, {
                'description': description.text.trim(),
                'mileage': km,
                'cost': amount,
                'date': DateTime.now().toIso8601String(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    description.dispose();
    cost.dispose();
    kmController.dispose();

    if (result != null) {
      setState(() {
        final history = vehicles[index]['history'] as List;
        history.insert(0, result);

        final serviceKm = result['mileage'] as int;
        vehicles[index]['lastService'] = serviceKm;

        if (serviceKm > (vehicles[index]['mileage'] as int)) {
          vehicles[index]['mileage'] = serviceKm;
        }
      });
      await saveVehicles();
    }
  }

  void openVehicle(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehiclePage(
          vehicle: vehicles[index],
          onMileage: () => updateMileage(index),
          onService: () => addService(index),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
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
                    final v = vehicles[index];
                    final current = v['mileage'] as int;
                    final next = (v['lastService'] as int) +
                        (v['interval'] as int);
                    final remaining = next - current;

                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.directions_car),
                        title: Text('${v['name']}'),
                        subtitle: Text(
                          '${v['registration']}\n'
                          'Current: $current km | Next: $next km',
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          remaining <= 0
                              ? Icons.warning_amber
                              : Icons.chevron_right,
                          color: remaining <= 0 ? Colors.red : null,
                        ),
                        onTap: () => openVehicle(index),
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

class VehiclePage extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final VoidCallback onMileage;
  final VoidCallback onService;

  const VehiclePage({
    super.key,
    required this.vehicle,
    required this.onMileage,
    required this.onService,
  });

  @override
  Widget build(BuildContext context) {
    final current = vehicle['mileage'] as int;
    final next = (vehicle['lastService'] as int) +
        (vehicle['interval'] as int);
    final remaining = next - current;
    final history = vehicle['history'] as List;

    return Scaffold(
      appBar: AppBar(title: Text('${vehicle['name']}')),
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
                    '${vehicle['name']}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Registration: ${vehicle['registration']}'),
                  Text('Current Mileage: $current km'),
                  Text('Next Service: $next km'),
                  const SizedBox(height: 8),
                  Text(
                    remaining <= 0
                        ? 'SERVICE DUE'
                        : '$remaining km until next service',
                    style: TextStyle(
                      color: remaining <= 0
                          ? Colors.red
                          : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              onMileage();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.speed),
            label: const Text('Update Mileage'),
          ),
          FilledButton.icon(
            onPressed: () {
              onService();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.build),
            label: const Text('Add Service'),
          ),
          const SizedBox(height: 20),
          Text(
            'Service History',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (history.isEmpty)
            const Text('No services recorded yet.'),
          ...history.map((record) {
            final item = Map<String, dynamic>.from(record as Map);
            final date = DateTime.tryParse('${item['date']}');
            final dateText = date == null
                ? ''
                : '${date.day}/${date.month}/${date.year}';

            return Card(
              child: ListTile(
                title: Text('${item['description']}'),
                subtitle: Text(
                  '$dateText | ${item['mileage']} km',
                ),
                trailing: Text(
                  '${(item['cost'] as num).toStringAsFixed(2)}',
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
