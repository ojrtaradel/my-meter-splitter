import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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

// ============================================================================
// MAIN INPUT SCREEN
// ============================================================================

class MeterSplitterHome extends StatefulWidget {
  const MeterSplitterHome({super.key});

  @override
  State<MeterSplitterHome> createState() => _MeterSplitterHomeState();
}

class _MeterSplitterHomeState extends State<MeterSplitterHome> {
  final _motherNameController = TextEditingController(text: "Rosie B6 L39");
  final _subNameController = TextEditingController(text: "Marilyn B6 L41");
  
  final _totalBillController = TextEditingController();
  final _totalKwhController = TextEditingController();
  final _prevReadingController = TextEditingController();
  final _newReadingController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  
  XFile? _scannedBillImage;
  XFile? _scannedMeterImage;

  bool _isScanningBill = false;
  bool _isScanningMeter = false;
  bool _isLoadingHistory = true;
  bool _isPrevReadingLocked = false;
  bool _isCalculating = false; 
  
  double _prevRate = 0.0; 

  @override
  void initState() {
    super.initState();
    _fetchLatestReading();
  }

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

  Future<void> _scanBillImage() async {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      _showErrorSnackBar('API Key missing. Please check your build command.');
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70); 
      if (image == null) return;

      setState(() {
        _isScanningBill = true;
        _scannedBillImage = image; 
      });

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
      final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
      if (image == null) return;

      setState(() {
        _isScanningMeter = true;
        _scannedMeterImage = image; 
      });

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

  Future<void> _calculateBill() async {
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

    setState(() => _isCalculating = true);
    await Future.delayed(const Duration(milliseconds: 1200));

    final rate = totalBill / totalKwh;
    final subConsumed = newReading - prevReading;
    final motherConsumed = totalKwh - subConsumed;
    final subBill = subConsumed * rate;
    final motherBill = motherConsumed * rate;

    setState(() => _isCalculating = false);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          motherName: _motherNameController.text,
          subName: _subNameController.text,
          totalBill: totalBill,
          totalKwh: totalKwh,
          prevReading: prevReading,
          newReading: newReading,
          rate: rate,
          prevRate: _prevRate,
          subConsumed: subConsumed,
          motherConsumed: motherConsumed,
          subBill: subBill,
          motherBill: motherBill,
          billImageFile: _scannedBillImage, 
          meterImageFile: _scannedMeterImage, 
        ),
      ),
    ).then((savedSuccessfully) {
      if (savedSuccessfully == true) {
        setState(() {
          _prevReadingController.text = newReading.toString();
          _isPrevReadingLocked = true;
          _prevRate = rate; 
          
          _totalBillController.clear();
          _totalKwhController.clear();
          _newReadingController.clear();
          
          _scannedBillImage = null;
          _scannedMeterImage = null;
        });
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFDC2626), behavior: SnackBarBehavior.floating));
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: const TextStyle(fontSize: 18)), backgroundColor: const Color(0xFF059669), behavior: SnackBarBehavior.floating));
  }

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
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_rounded, size: 28),
            tooltip: 'View History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminDashboard()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
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
                
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  transform: _isCalculating ? (Matrix4.identity()..scale(0.95, 0.95)) : Matrix4.identity(),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      elevation: _isCalculating ? 2 : 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _isCalculating ? null : _calculateBill,
                    child: _isCalculating
                        ? const SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack)
                        : const Text('Calculate Breakdown', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ).animate(target: _isCalculating ? 1 : 0).boxShadow(
                  end: const BoxShadow(color: Color(0xFF00796B), blurRadius: 20, spreadRadius: 2), 
                  duration: 400.ms,
                ),
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
          Row(
            children: [
              const Text('Main Bill Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
              if (_scannedBillImage != null) 
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.check_circle, color: Color(0xFF059669), size: 20),
                )
            ],
          ),
          if (_isScanningBill) 
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _scanBillImage,
              icon: const Icon(Icons.camera_alt),
              label: Text(_scannedBillImage == null ? 'Scan Bill' : 'Retake'),
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
          Row(
            children: [
              const Text('Sub-meter Readings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
              if (_scannedMeterImage != null) 
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Icon(Icons.check_circle, color: Color(0xFF059669), size: 20),
                )
            ],
          ),
          if (_isScanningMeter) 
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _scanMeterImage,
              icon: const Icon(Icons.camera_alt),
              label: Text(_scannedMeterImage == null ? 'Scan Meter' : 'Retake'),
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
}

// ============================================================================
// RESULTS SCREEN 
// ============================================================================

class ResultsScreen extends StatefulWidget {
  final String motherName;
  final String subName;
  final double totalBill;
  final double totalKwh;
  final double prevReading;
  final double newReading;
  final double rate;
  final double prevRate;
  final double subConsumed;
  final double motherConsumed;
  final double subBill;
  final double motherBill;
  final XFile? billImageFile;
  final XFile? meterImageFile;

  const ResultsScreen({
    super.key,
    required this.motherName,
    required this.subName,
    required this.totalBill,
    required this.totalKwh,
    required this.prevReading,
    required this.newReading,
    required this.rate,
    required this.prevRate,
    required this.subConsumed,
    required this.motherConsumed,
    required this.subBill,
    required this.motherBill,
    this.billImageFile,
    this.meterImageFile,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _isSaving = false;

  Future<String?> _uploadImage(XFile? file, String folderPath) async {
    if (file == null) return null;
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child('$folderPath/$fileName');
      
      final bytes = await file.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint("Upload error: $e");
      return null;
    }
  }

  Future<void> _saveToFirebase() async {
    setState(() => _isSaving = true);
    try {
      final billImageUrl = await _uploadImage(widget.billImageFile, 'bills');
      final meterImageUrl = await _uploadImage(widget.meterImageFile, 'meters');

      final billRecord = {
        'timestamp': FieldValue.serverTimestamp(),
        'motherMeterName': widget.motherName,
        'subMeterName': widget.subName,
        'inputs': {
          'totalBill': widget.totalBill,
          'totalKwh': widget.totalKwh,
          'prevReading': widget.prevReading,
          'newReading': widget.newReading,
        },
        'calculatedBreakdown': {
          'ratePerKwh': widget.rate,
          'subMeterKwh': widget.subConsumed,
          'subMeterAmount': widget.subBill,
          'motherMeterKwh': widget.motherConsumed,
          'motherMeterAmount': widget.motherBill,
        },
        'billImageUrl': billImageUrl,
        'meterImageUrl': meterImageUrl,
      };

      await FirebaseFirestore.instance.collection('monthly_bills').add(billRecord);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bill and photos saved successfully!', style: TextStyle(fontSize: 18)), 
          backgroundColor: Color(0xFF059669), 
          behavior: SnackBarBehavior.floating
        ));
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save: $e', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
          backgroundColor: const Color(0xFFDC2626), 
          behavior: SnackBarBehavior.floating
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Computed Breakdown', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Rate per kWh:', style: TextStyle(fontSize: 20, color: Color(0xFF4B5563))),
                          const SizedBox(height: 4),
                          Text(
                            '(₱${widget.totalBill.toStringAsFixed(2)} ÷ ${widget.totalKwh.toStringAsFixed(1)} kWh)',
                            style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF), fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₱${widget.rate.toStringAsFixed(4)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          
                          if (widget.prevRate > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.rate > widget.prevRate 
                                      ? Icons.trending_up_rounded 
                                      : (widget.rate < widget.prevRate ? Icons.trending_down_rounded : Icons.trending_flat_rounded),
                                  color: widget.rate > widget.prevRate 
                                      ? const Color(0xFFDC2626) 
                                      : (widget.rate < widget.prevRate ? const Color(0xFF059669) : const Color(0xFF9CA3AF)), 
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  widget.rate == widget.prevRate 
                                      ? 'No change'
                                      : '₱${(widget.rate - widget.prevRate).abs().toStringAsFixed(4)} vs last mo.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: widget.rate > widget.prevRate 
                                        ? const Color(0xFFDC2626) 
                                        : (widget.rate < widget.prevRate ? const Color(0xFF059669) : const Color(0xFF9CA3AF)),
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
                
                _buildUnitSection(widget.motherName, 'Mother Meter', widget.motherConsumed, widget.motherBill, const Color(0xFF1D4ED8)),
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
                _buildUnitSection(widget.subName, 'Sub-meter', widget.subConsumed, widget.subBill, const Color(0xFF047857)),
                
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
                    icon: _isSaving 
                        ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)) 
                        : const Icon(Icons.cloud_upload_rounded, size: 28),
                    label: Text(_isSaving ? 'Uploading Photos & Saving...' : 'Save Record', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                )
              ].animate(interval: 100.ms).fadeIn(duration: 400.ms).slideY(begin: 0.1, curve: Curves.easeOutQuad),
            ),
          ).animate()
          .fadeIn(duration: 600.ms)
          .flipV(begin: -0.15, end: 0, duration: 800.ms, curve: Curves.easeOutBack)
          .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1), duration: 800.ms, curve: Curves.easeOutBack),
        ),
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
              duration: const Duration(milliseconds: 1600),
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

// ============================================================================
// ADMIN DASHBOARD SCREEN
// ============================================================================

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _confirmDelete(BuildContext context, String docId, String? billUrl, String? meterUrl) async {
    final pinController = TextEditingController();
    const String adminPin = "123456"; 

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin Authorization', style: TextStyle(fontWeight: FontWeight.bold)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the Admin PIN to permanently delete this billing record and its photos.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true, 
              decoration: InputDecoration(
                labelText: 'PIN Code',
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
                ),
              ),
              style: const TextStyle(fontSize: 20, letterSpacing: 4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280), fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (pinController.text == adminPin) {
                Navigator.pop(context, true); 
              } else {
                Navigator.pop(context, false); 
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect PIN. Deletion aborted.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    backgroundColor: Color(0xFFDC2626),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (billUrl != null) await FirebaseStorage.instance.refFromURL(billUrl).delete();
        if (meterUrl != null) await FirebaseStorage.instance.refFromURL(meterUrl).delete();

        await FirebaseFirestore.instance.collection('monthly_bills').doc(docId).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Record and photos successfully deleted.', style: TextStyle(fontSize: 16)),
              backgroundColor: Color(0xFF374151),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting: $e', style: const TextStyle(fontSize: 16)),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _showImageDialog(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer( 
              child: Center(
                child: Image.network(
                  url, 
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Billing History', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('monthly_bills').orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Something went wrong.'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Text('No bills saved yet.', style: TextStyle(fontSize: 20, color: Colors.grey)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final document = docs[index]; 
              final docId = document.id; 
              final data = document.data() as Map<String, dynamic>;
              
              final timestamp = data['timestamp'] as Timestamp?;
              final dateStr = timestamp != null 
                  ? "${timestamp.toDate().month}/${timestamp.toDate().day}/${timestamp.toDate().year}"
                  : "Pending...";

              final inputs = data['inputs'] as Map<String, dynamic>? ?? {};
              final breakdown = data['calculatedBreakdown'] as Map<String, dynamic>? ?? {};

              final totalBill = (inputs['totalBill'] as num?)?.toDouble() ?? 0.0;
              final totalKwh = (inputs['totalKwh'] as num?)?.toDouble() ?? 0.0;
              final rate = (breakdown['ratePerKwh'] as num?)?.toDouble() ?? 0.0;
              final subAmount = (breakdown['subMeterAmount'] as num?)?.toDouble() ?? 0.0;
              final motherAmount = (breakdown['motherMeterAmount'] as num?)?.toDouble() ?? 0.0;

              final billImageUrl = data['billImageUrl'] as String?;
              final meterImageUrl = data['meterImageUrl'] as String?;
              
              final motherNameDisplay = data['motherMeterName'] as String? ?? 'Mother Meter';
              final subNameDisplay = data['subMeterName'] as String? ?? 'Sub-meter';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TOP ROW: Date & Delete Button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_month, color: Color(0xFF6B7280), size: 20),
                              const SizedBox(width: 8),
                              Text(dateStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                            tooltip: 'Delete Record',
                            splashRadius: 24,
                            onPressed: () => _confirmDelete(context, docId, billImageUrl, meterImageUrl),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // NEW EXPLICIT MATH BOX (Prevents screen overflow hiding the text)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rate: ₱${rate.toStringAsFixed(4)} per kWh', 
                              style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 16)
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Formula: ₱${totalBill.toStringAsFixed(2)} ÷ ${totalKwh.toStringAsFixed(1)} kWh',
                              style: const TextStyle(color: Color(0xFF065F46), fontSize: 13, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                      
                      const Divider(height: 32, thickness: 1.5, color: Color(0xFFF3F4F6)),
                      
                      // THE SPLIT WITH DYNAMIC NAMES
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$motherNameDisplay Due', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text('₱${motherAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                              ],
                            ),
                          ),
                          Container(width: 1.5, height: 40, color: const Color(0xFFF3F4F6)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$subNameDisplay Due', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text('₱${subAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      if (billImageUrl != null || meterImageUrl != null) ...[
                        const SizedBox(height: 20),
                        const Text('Attachments:', style: TextStyle(color: Color(0xFF4B5563), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (billImageUrl != null)
                              GestureDetector(
                                onTap: () => _showImageDialog(context, billImageUrl, 'Original Bill'),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  height: 60,
                                  width: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFD1D5DB)),
                                    image: DecorationImage(image: NetworkImage(billImageUrl), fit: BoxFit.cover),
                                  ),
                                  child: const Icon(Icons.receipt_long, color: Colors.white70, size: 28),
                                ),
                              ),
                            if (meterImageUrl != null)
                              GestureDetector(
                                onTap: () => _showImageDialog(context, meterImageUrl, 'Meter Reading'),
                                child: Container(
                                  height: 60,
                                  width: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFD1D5DB)),
                                    image: DecorationImage(image: NetworkImage(meterImageUrl), fit: BoxFit.cover),
                                  ),
                                  child: const Icon(Icons.electric_meter, color: Colors.white70, size: 28),
                                ),
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Original Total Bill:', style: TextStyle(color: Color(0xFF4B5563), fontWeight: FontWeight.w600)),
                            Text('₱${totalBill.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ).animate().fade().slideY(begin: 0.1, curve: Curves.easeOut);
            },
          );
        },
      ),
    );
  }
}