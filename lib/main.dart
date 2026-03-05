import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  runApp(const BillSplitterApp());
}

class BillSplitterApp extends StatelessWidget {
  const BillSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meter Splitter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00796B),
          background: const Color(0xFFF0F4F4),
        ),
        useMaterial3: true,
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
          titleMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
          bodyLarge: TextStyle(fontSize: 22, color: Color(0xFF111827)),
          bodyMedium: TextStyle(fontSize: 20, color: Color(0xFF374151)),
          labelLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          labelStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
          floatingLabelStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFD1D5DB), width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF00796B), width: 3)),
        ),
      ),
      home: const MeterSplitterHome(),
    );
  }
}

class MeterSplitterHome extends StatefulWidget {
  const MeterSplitterHome({super.key});

  @override
  State<MeterSplitterHome> createState() => _MeterSplitterHomeState();
}

class _MeterSplitterHomeState extends State<MeterSplitterHome> {
  final _motherNameController = TextEditingController(text: "Block 6 Lot 39");
  final _subNameController = TextEditingController(text: "Block 6 Lot 41");
  
  final _totalBillController = TextEditingController();
  final _totalKwhController = TextEditingController();
  final _prevReadingController = TextEditingController();
  final _newReadingController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  
  bool _showResults = false;
  bool _isSaving = false;
  bool _isScanningBill = false;
  bool _isScanningMeter = false;
  
  bool _isLoadingHistory = true;
  bool _isPrevReadingLocked = false;
  
  double _rate = 0.0;
  double _prevRate = 0.0; // Variable to hold last month's rate
  double _subConsumed = 0.0;
  double _motherConsumed = 0.0;
  double _subBill = 0.0;
  double _motherBill = 0.0;
  double _checkTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchLatestReading();
  }

  // --- DATABASE FETCH LOGIC ---
  Future<void> _fetchLatestReading() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('monthly_bills')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final latestDoc = snapshot.docs.first.data();
        final inputs = latestDoc['inputs'] as Map<String, dynamic>?;
        final breakdown = latestDoc['calculatedBreakdown'] as Map<String, dynamic>?;
        
        setState(() {
          if (inputs != null && inputs['newReading'] != null) {
            _prevReadingController.text = inputs['newReading'].toString();
            _isPrevReadingLocked = true; 
          }
          if (breakdown != null && breakdown['ratePerKwh'] != null) {
            // Use 'num' cast first to safely handle both int and double from Firestore
            _prevRate = (breakdown['ratePerKwh'] as num).toDouble();
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching history: $e");
    } finally {
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  // --- AI SCANNING LOGIC ---

  Future<void> _scanBillImage() async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    
    if (apiKey.isEmpty) {
      _showErrorSnackBar('API Key missing. Please check your build command.');
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera); 
      if (image == null) return;

      setState(() => _isScanningBill = true);

      final bytes = await image.readAsBytes();
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      
      final prompt = TextPart('''
        Analyze this electric bill. Extract the Total Amount Due and the Total KWH consumed.
        Return ONLY a raw JSON object with exactly these two keys. Do not include markdown formatting or backticks.
        Example: {"totalBill": 3276.00, "totalKwh": 275.0}
      ''');
      final imagePart = DataPart('image/jpeg', bytes);

      final response = await model.generateContent([Content.multi([prompt, imagePart])]);
      final text = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '{}';
      
      final data = jsonDecode(text);
      
      setState(() {
        if (data['totalBill'] != null) _totalBillController.text = data['totalBill'].toString();
        if (data['totalKwh'] != null) _totalKwhController.text = data['totalKwh'].toString();
      });

      _showSuccessSnackBar('Bill scanned successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to read bill. Please try taking the photo closer.');
      debugPrint(e.toString());
    } finally {
      setState(() => _isScanningBill = false);
    }
  }

  Future<void> _scanMeterImage() async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    
    if (apiKey.isEmpty) {
      _showErrorSnackBar('API Key missing. Please check your build command.');
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      setState(() => _isScanningMeter = true);

      final bytes = await image.readAsBytes();
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
      
      final prompt = TextPart('''
        Analyze this electric meter reading. Extract the current numeric reading displayed on the dial/screen.
        Return ONLY a raw JSON object with this key. Do not include markdown formatting or backticks.
        Example: {"reading": 3276}
      ''');
      final imagePart = DataPart('image/jpeg', bytes);

      final response = await model.generateContent([Content.multi([prompt, imagePart])]);
      final text = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '{}';
      
      final data = jsonDecode(text);
      
      if (data['reading'] != null) {
        setState(() {
          _newReadingController.text = data['reading'].toString();
        });
        _showSuccessSnackBar('Meter scanned successfully!');
      } else {
        _showErrorSnackBar('Could not find a clear number.');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to read meter. Please ensure the numbers are clearly visible.');
      debugPrint(e.toString());
    } finally {
      setState(() => _isScanningMeter = false);
    }
  }

  // --- CALCULATION LOGIC ---

  void _calculateBill() {
    FocusScope.of(context).unfocus(); 
    
    final totalBill = double.tryParse(_totalBillController.text) ?? 0;
    final totalKwh = double.tryParse(_totalKwhController.text) ?? 0;
    final prevReading = double.tryParse(_prevReadingController.text) ?? 0;
    final newReading = double.tryParse(_newReadingController.text) ?? 0;

    if (totalBill <= 0 || totalKwh <= 0 || prevReading <= 0 || newReading <= 0) {
      _showErrorSnackBar('Please fill in all fields with valid numbers.');
      return;
    }
    if (newReading < prevReading) {
      _showErrorSnackBar('New reading cannot be lower than previous.');
      return;
    }

    setState(() => _showResults = false);

    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        _rate = totalBill / totalKwh;
        _subConsumed = newReading - prevReading;
        _motherConsumed = totalKwh - _subConsumed;
        _subBill = _subConsumed * _rate;
        _motherBill = _motherConsumed * _rate;
        _checkTotal = _subBill + _motherBill;
        _showResults = true;
      });
    });
  }

  Future<void> _saveToFirebase() async {
    setState(() => _isSaving = true);
    try {
      final billRecord = {
        'timestamp': FieldValue.serverTimestamp(),
        'motherMeterName': _motherNameController.text,
        'subMeterName': _subNameController.text,
        'inputs': {
          'totalBill': double.parse(_totalBillController.text),
          'totalKwh': double.parse(_totalKwhController.text),
          'prevReading': double.parse(_prevReadingController.text),
          'newReading': double.parse(_newReadingController.text),
        },
        'calculatedBreakdown': {
          'ratePerKwh': _rate,
          'subMeterKwh': _subConsumed,
          'subMeterAmount': _subBill,
          'motherMeterKwh': _motherConsumed,
          'motherMeterAmount': _motherBill,
        }
      };

      await FirebaseFirestore.instance.collection('monthly_bills').add(billRecord);
      
      if (mounted) {
        _showSuccessSnackBar('Bill saved successfully!');
        
        setState(() {
          _prevReadingController.text = _newReadingController.text;
          _isPrevReadingLocked = true;
          // Set the current rate as the new "previous rate" for the next calculation
          _prevRate = _rate; 
        });
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFDC2626), behavior: SnackBarBehavior.floating));
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 18)), backgroundColor: const Color(0xFF059669), behavior: SnackBarBehavior.floating));
  }

  // --- UI LAYOUT ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Meter Splitter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ..._buildFormFields().animate(interval: 50.ms).fade(duration: 400.ms).slideY(begin: 0.1, curve: Curves.easeOutQuad),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _calculateBill,
                  child: const Text('Calculate Breakdown', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ).animate().fade(delay: 300.ms).scale(curve: Curves.easeOutBack),

                if (_showResults) ...[
                  const SizedBox(height: 40),
                  _buildResultsCard().animate().fade(duration: 500.ms).slideY(begin: 0.1, curve: Curves.easeOutQuart),
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildFormFields() {
    return [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _motherNameController, 
              readOnly: true, 
              decoration: const InputDecoration(
                labelText: 'Mother Meter',
                fillColor: Color(0xFFF3F4F6),
                suffixIcon: Icon(Icons.lock, color: Color(0xFF9CA3AF)),
              ),
              style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _subNameController, 
              readOnly: true, 
              decoration: const InputDecoration(
                labelText: 'Sub-meter',
                fillColor: Color(0xFFF3F4F6),
                suffixIcon: Icon(Icons.lock, color: Color(0xFF9CA3AF)),
              ),
              style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      
      const Padding(padding: EdgeInsets.only(top: 32, bottom: 16), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
      
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Main Bill Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          if (_isScanningBill) 
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _scanBillImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Bill'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8F5E9), foregroundColor: const Color(0xFF2E7D32)),
            )
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _totalBillController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Total Bill Amount (₱)', prefixText: '₱ ', prefixStyle: TextStyle(fontSize: 22)),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: _totalKwhController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Total KWH Consumed', suffixText: ' kWh'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      
      const Padding(padding: EdgeInsets.only(top: 32, bottom: 16), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
      
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Sub-meter Readings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
          if (_isScanningMeter) 
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _scanMeterImage,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan Meter'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8F5E9), foregroundColor: const Color(0xFF2E7D32)),
            )
        ],
      ),
      const SizedBox(height: 16),
      
      TextField(
        controller: _prevReadingController,
        readOnly: _isPrevReadingLocked,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Sub-meter Previous Reading',
          fillColor: _isPrevReadingLocked ? const Color(0xFFF3F4F6) : Colors.white,
          suffixIcon: _isLoadingHistory
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : (_isPrevReadingLocked ? const Icon(Icons.lock, color: Color(0xFF9CA3AF)) : null),
        ),
        style: TextStyle(
          fontSize: 24, 
          fontWeight: FontWeight.bold,
          color: _isPrevReadingLocked ? const Color(0xFF6B7280) : const Color(0xFF1F2937),
        ),
      ),
      
      const SizedBox(height: 24),
      TextField(
        controller: _newReadingController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Sub-meter New Reading'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    ];
  }

  Widget _buildResultsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          Text('Final Breakdown', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Rate per kWh:', style: TextStyle(fontSize: 20, color: Color(0xFF4B5563))),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${_rate.toStringAsFixed(4)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    
                    // The dynamic visual trend indicator
                    if (_prevRate > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _rate > _prevRate 
                                ? Icons.trending_up_rounded 
                                : (_rate < _prevRate ? Icons.trending_down_rounded : Icons.trending_flat_rounded),
                            color: _rate > _prevRate 
                                ? const Color(0xFFDC2626) // Red for price up
                                : (_rate < _prevRate ? const Color(0xFF059669) : const Color(0xFF9CA3AF)), // Green for down, Grey for same
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _rate == _prevRate 
                                ? 'No change'
                                : '₱${(_rate - _prevRate).abs().toStringAsFixed(4)} vs last mo.',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _rate > _prevRate 
                                  ? const Color(0xFFDC2626) 
                                  : (_rate < _prevRate ? const Color(0xFF059669) : const Color(0xFF9CA3AF)),
                            ),
                          ),
                        ],
                      ).animate().fade(delay: 600.ms).slideY(begin: -0.2, curve: Curves.easeOutQuad),
                  ],
                ),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
          _buildUnitSection(_subNameController.text, 'Sub-meter', _subConsumed, _subBill, const Color(0xFF047857)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
          _buildUnitSection(_motherNameController.text, 'Mother Meter', _motherConsumed, _motherBill, const Color(0xFF1D4ED8)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                side: const BorderSide(color: Color(0xFF00796B), width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isSaving ? null : _saveToFirebase,
              icon: _isSaving ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) : const Icon(Icons.cloud_upload_rounded, size: 28),
              label: Text(_isSaving ? 'Saving...' : 'Save Record', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildUnitSection(String name, String type, double kwh, double amount, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 6, height: 24, decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(4))),
            const SizedBox(width: 12),
            Text(name, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: accentColor)),
            const SizedBox(width: 8),
            Text('($type)', style: const TextStyle(fontSize: 18, color: Color(0xFF6B7280))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Consumed:', style: TextStyle(fontSize: 22, color: Color(0xFF4B5563))),
            Text('${kwh.toStringAsFixed(1)} kWh', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('Amount Due:', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: amount),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutExpo,
              builder: (context, value, child) {
                return Text('₱${value.toStringAsFixed(2)}', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: accentColor, letterSpacing: -1));
              },
            ),
          ],
        ),
      ],
    );
  }
}