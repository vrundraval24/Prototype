import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isLoading = false;
  Map<String, dynamic>? parsedData;

  Future<Map<String, dynamic>> parseFileContent(String content) async {
    try {
      // Clean up content
      content = content.replaceAll(RegExp(r'[\uFEFF\r]'), '');

      // Split into sections
      final sections = content.split(RegExp(r'-{3,}'));
      debugPrint('Found ${sections.length} sections');

      List<Map<String, dynamic>> rotations = [];

      for (var section in sections) {
        if (section.trim().isEmpty) continue;

        try {
          final rotation = parseRotation(section.trim());
          rotations.add(rotation);
        } catch (e) {
          debugPrint('Error parsing section: $e');
        }
      }

      return {
        'header': {
          'base': 'ATL',
          'aircraft_type': 'RIN',
          'position': '',
          'month': 'JAN',
          'year': '2025'
        },
        'bid_package_details': {
          'bid_period_start': '2025-01-01T00:00:00',
          'bid_period_end': '2025-01-30T00:00:00'
        },
        'rotations': rotations,
      };
    } catch (e) {
      debugPrint('Error in parseFileContent: $e');
      rethrow;
    }
  }

  Map<String, dynamic> parseRotation(String text) {
    try {
      final lines = text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        throw Exception('Empty rotation section');
      }

      // Parse header line
      final headerLine = lines[0];
      final rotationMatch = RegExp(r'#?(\d+)').firstMatch(headerLine);
      final rotationNumber = rotationMatch?.group(1);
      if (rotationNumber == null) {
        throw Exception('No rotation number found');
      }

      // Parse check-in time
      final checkinMatch =
          RegExp(r'CHECK-IN AT\s+(\d+\.\d+)').firstMatch(headerLine);
      final checkinTime =
          checkinMatch?.group(1)?.replaceAll('.', '').padLeft(4, '0') ??
              '0000';

      // Parse positions
      final positionLine = lines.length > 1 ? lines[1] : '';
      final posMatch =
          RegExp(r'POS\s*-\s*([A-Z]),\s*([A-Z])').firstMatch(positionLine);
      final position1 = posMatch?.group(1) ?? 'A';
      final position2 = posMatch?.group(2) ?? 'B';

      // Parse flights
      List<Map<String, dynamic>> flights = [];
      for (var i = 2; i < lines.length; i++) {
        final line = lines[i];

        // Skip non-flight lines
        if (!RegExp(r'\d{4}').hasMatch(line)) continue;

        final flightMatch = RegExp(
                r'(?:DH)?\s*(\d+)\s+([A-Z]{3})\s+(\d{4})\s+([A-Z]{3})\s+(\d{4})\s+(\d+\.\d+)')
            .firstMatch(line);

        if (flightMatch != null) {
          flights.add({
            'flight_number': flightMatch.group(1),
            'departure_station': flightMatch.group(2),
            'arrival_station': flightMatch.group(4),
            'published_departure_time': flightMatch.group(3),
            'published_arrival_time': flightMatch.group(5),
            'block_time': parseTime(flightMatch.group(6) ?? '0.00'),
            'deadhead': line.trim().startsWith('DH'),
          });
        }
      }

      return {
        'rotation_number': rotationNumber,
        'position1': position1,
        'position2': position2,
        'published_checkin_time': checkinTime,
        'checkin_times': ['2025-01-01T$checkinTime:00-05:00'],
        'flights': flights,
        'published_rotation_text': text,
      };
    } catch (e) {
      debugPrint('Error parsing rotation: $e');
      rethrow;
    }
  }

  Map<String, dynamic> parseTime(String timeStr) {
    final parts = timeStr.split('.');
    final hours = int.parse(parts[0]);
    final minutes = parts.length > 1 ? (int.parse(parts[1]) * 0.6).round() : 0;
    final totalSeconds = (hours * 3600) + (minutes * 60);

    return {
      'hours': hours,
      'minutes': minutes,
      'total_seconds': totalSeconds,
    };
  }

  Future<void> pickAndParseFile() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      parsedData = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final bytes = result.files.first.bytes;
        if (bytes == null) {
          throw Exception('Could not read file content');
        }

        final content = String.fromCharCodes(bytes);
        final data = await parseFileContent(content);

        if (!mounted) return;
        setState(() {
          parsedData = data;
        });
      }
    } catch (e) {
      debugPrint('Error while parsing: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing file: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prototype'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: isLoading ? null : pickAndParseFile,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(isLoading ? 'Processing...' : 'Upload File'),
            ),
            const SizedBox(height: 20),
            if (parsedData != null)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      JsonEncoder.withIndent('  ').convert(parsedData),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
