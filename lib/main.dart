import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B), background: const Color(0xFFF0F4F4)),
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

  Future<String?>? _billUploadFuture;
  Future<String?>? _meterUploadFuture;

  bool _isBillUploaded = false;
  bool _isMeterUploaded = false;

  bool _isLoadingHistory = true;
  bool _isPrevReadingLocked = false;
  bool _isCalculating = false; 
  
  double _prevRate = 0.0; 

  @override
  void initState() {
    super.initState();
    _fetchLatestReading();
    
    _totalBillController.addListener(_updateFormState);
    _totalKwhController.addListener(_updateFormState);
    _newReadingController.addListener(_updateFormState);
  }

  @override
  void dispose() {
    _totalBillController.removeListener(_updateFormState);
    _totalKwhController.removeListener(_updateFormState);
    _newReadingController.removeListener(_updateFormState);
    _totalBillController.dispose();
    _totalKwhController.dispose();
    _prevReadingController.dispose();
    _newReadingController.dispose();
    super.dispose();
  }

  void _updateFormState() {
    setState(() {}); 
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

  Future<String?> _uploadImageInBackground(XFile file, String folderPath) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = FirebaseStorage.instance.ref().child('$folderPath/$fileName');
      final metadata = SettableMetadata(contentType: 'image/jpeg');
      
      TaskSnapshot snapshot;

      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        snapshot = await ref.putData(bytes, metadata);
      } else {
        snapshot = await ref.putFile(File(file.path), metadata);
      }
      
      return await snapshot.ref.getDownloadURL();
      
    } catch (e) {
      debugPrint("Upload error: $e");
      throw Exception(e.toString()); 
    }
  }

  Future<void> _takeBillPhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 70, 
        maxWidth: 1200,    
        maxHeight: 1200,
      ); 
      if (image == null) return;

      setState(() {
        _scannedBillImage = image; 
        _isBillUploaded = false; 
      });
      
      _billUploadFuture = _uploadImageInBackground(image, 'bills');
      _billUploadFuture!.then((url) {
        if (mounted && url != null) {
          setState(() => _isBillUploaded = true);
        }
      }).catchError((e) {
        if (mounted) _showErrorSnackBar("Main Bill Upload Error: $e");
      });
    } catch (e) {
      _showErrorSnackBar('Failed to open camera.');
    }
  }

  Future<void> _takeMeterPhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera, 
        imageQuality: 70, 
        maxWidth: 1200,    
        maxHeight: 1200,
      );
      if (image == null) return;

      setState(() {
        _scannedMeterImage = image; 
        _isMeterUploaded = false; 
      });
      
      _meterUploadFuture = _uploadImageInBackground(image, 'meters');
      _meterUploadFuture!.then((url) {
        if (mounted && url != null) {
          setState(() => _isMeterUploaded = true);
        }
      }).catchError((e) {
        if (mounted) _showErrorSnackBar("Meter Upload Error: $e");
      });
    } catch (e) {
      _showErrorSnackBar('Failed to open camera.');
    }
  }

  Future<void> _calculateBill() async {
    FocusScope.of(context).unfocus(); 
    
    final totalBill = double.tryParse(_totalBillController.text) ?? 0;
    final totalKwh = double.tryParse(_totalKwhController.text) ?? 0;
    final prevReading = double.tryParse(_prevReadingController.text) ?? 0;
    final newReading = double.tryParse(_newReadingController.text) ?? 0;

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
          billUploadFuture: _billUploadFuture, 
          meterUploadFuture: _meterUploadFuture, 
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
          _billUploadFuture = null;
          _meterUploadFuture = null;
          _isBillUploaded = false;
          _isMeterUploaded = false;
        });
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), 
      backgroundColor: const Color(0xFFDC2626), 
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ));
  }

  Widget _buildAnimatedStep({required bool isEnabled, required Widget child}) {
    return AnimatedOpacity(
      opacity: isEnabled ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !isEnabled,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool step1Done = _scannedBillImage != null;
    bool step2Done = step1Done && _totalBillController.text.trim().isNotEmpty;
    bool step3Done = step2Done && _totalKwhController.text.trim().isNotEmpty;
    bool step4Done = step3Done && _scannedMeterImage != null;
    bool step5Done = step4Done && _newReadingController.text.trim().isNotEmpty;

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
            icon: const Icon(Icons.bar_chart_rounded, size: 28),
            tooltip: 'View Charts',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const UsageChartsScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 28),
            tooltip: 'View History',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDashboard()));
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
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _motherNameController, 
                        readOnly: true, 
                        decoration: const InputDecoration(labelText: 'Mother Meter', fillColor: Color(0xFFF3F4F6), suffixIcon: Icon(Icons.lock, color: Color(0xFF9CA3AF))),
                        style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _subNameController, 
                        readOnly: true, 
                        decoration: const InputDecoration(labelText: 'Sub-meter', fillColor: Color(0xFFF3F4F6), suffixIcon: Icon(Icons.lock, color: Color(0xFF9CA3AF))),
                        style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                
                const Padding(padding: EdgeInsets.only(top: 32, bottom: 16), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
                
                // STEP 1
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Flexible(child: Text('Main Bill Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)), overflow: TextOverflow.ellipsis)),
                          if (_scannedBillImage != null) 
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: _isBillUploaded
                                  ? const Icon(Icons.check_circle, color: Color(0xFF059669), size: 20).animate().scale(duration: 400.ms, curve: Curves.easeOutBack)
                                  : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00796B))),
                            )
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _takeBillPhoto,
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: Text(
                        _scannedBillImage == null ? 'Main Bill Photo Required' : 'Retake Photo',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), 
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _scannedBillImage == null ? const Color(0xFFFEE2E2) : const Color(0xFFE8F5E9), 
                        foregroundColor: _scannedBillImage == null ? const Color(0xFFDC2626) : const Color(0xFF2E7D32),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                
                // STEP 2
                _buildAnimatedStep(
                  isEnabled: step1Done,
                  child: TextField(
                    controller: _totalBillController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total Bill Amount (₱)', prefixText: '₱ ', prefixStyle: TextStyle(fontSize: 22)),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 24),

                // STEP 3
                _buildAnimatedStep(
                  isEnabled: step2Done,
                  child: TextField(
                    controller: _totalKwhController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total KWH Consumed', suffixText: ' kWh'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                
                const Padding(padding: EdgeInsets.only(top: 32, bottom: 16), child: Divider(thickness: 2, color: Color(0xFFE5E7EB))),
                
                // STEP 4
                _buildAnimatedStep(
                  isEnabled: step3Done,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Flexible(child: Text('Sub-meter Readings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)), overflow: TextOverflow.ellipsis)),
                            if (_scannedMeterImage != null) 
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: _isMeterUploaded
                                    ? const Icon(Icons.check_circle, color: Color(0xFF059669), size: 20).animate().scale(duration: 400.ms, curve: Curves.easeOutBack)
                                    : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00796B))),
                              )
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: step3Done ? _takeMeterPhoto : null, 
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: Text(
                          _scannedMeterImage == null ? 'Sub-meter Photo Required' : 'Retake Photo',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _scannedMeterImage == null ? const Color(0xFFFEE2E2) : const Color(0xFFE8F5E9), 
                          foregroundColor: _scannedMeterImage == null ? const Color(0xFFDC2626) : const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                _buildAnimatedStep(
                  isEnabled: step3Done,
                  child: TextField(
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
                ),
                
                const SizedBox(height: 24),

                // STEP 5
                _buildAnimatedStep(
                  isEnabled: step4Done,
                  child: TextField(
                    controller: _newReadingController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Sub-meter New Reading'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 32),
                
                // FINAL STEP
                _buildAnimatedStep(
                  isEnabled: step5Done,
                  child: AnimatedContainer(
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
                      onPressed: (_isCalculating || !step5Done) ? null : _calculateBill,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
  final Future<String?>? billUploadFuture;
  final Future<String?>? meterUploadFuture;

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
    this.billUploadFuture,
    this.meterUploadFuture,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  bool _isSaving = false;

  Future<void> _saveToFirebase() async {
    setState(() => _isSaving = true);
    try {
      final billImageUrl = widget.billUploadFuture != null 
          ? await widget.billUploadFuture 
          : null;
          
      final meterImageUrl = widget.meterUploadFuture != null 
          ? await widget.meterUploadFuture 
          : null;

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
          content: Text('Record successfully saved!', style: TextStyle(fontSize: 18)), 
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
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
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
                    label: Text(_isSaving ? 'Finalizing...' : 'Save Record', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
    const String adminPin = "063941"; 

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
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer( 
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
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
          ],
        ).animate() 
         .scale(duration: 400.ms, curve: Curves.easeOutBack)
         .fadeIn(duration: 400.ms),
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
              
              final subKwh = (breakdown['subMeterKwh'] as num?)?.toDouble() ?? 0.0;
              final motherKwh = (breakdown['motherMeterKwh'] as num?)?.toDouble() ?? 0.0;

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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month, color: Color(0xFF6B7280), size: 20),
                                const SizedBox(width: 8),
                                Text(dateStr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                              ],
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(20)),
                                    child: Text('Rate: ₱${rate.toStringAsFixed(4)}', style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '(₱${totalBill.toStringAsFixed(2)} ÷ ${totalKwh.toStringAsFixed(1)} kWh)',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF), fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
                                tooltip: 'Delete Record',
                                splashRadius: 24,
                                onPressed: () => _confirmDelete(context, docId, billImageUrl, meterImageUrl),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 24, thickness: 1.5, color: Color(0xFFF3F4F6)),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$motherNameDisplay Due', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text('₱${motherAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                                const SizedBox(height: 2),
                                Text('${motherKwh.toStringAsFixed(1)} kWh', style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          Container(width: 1.5, height: 56, color: const Color(0xFFF3F4F6)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$subNameDisplay Due', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text('₱${subAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                                const SizedBox(height: 2),
                                Text('${subKwh.toStringAsFixed(1)} kWh', style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      if (billImageUrl != null || meterImageUrl != null) ...[
                        const SizedBox(height: 20),
                        const Text('Audit Photos:', style: TextStyle(color: Color(0xFF4B5563), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (billImageUrl != null)
                              GestureDetector(
                                onTap: () => _showImageDialog(context, billImageUrl, 'Original Bill'),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  height: 64,
                                  width: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFD1D5DB), width: 2),
                                    image: DecorationImage(image: NetworkImage(billImageUrl), fit: BoxFit.cover),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                                    child: const Center(child: Icon(Icons.receipt_long, color: Colors.white, size: 28)),
                                  ),
                                ),
                              ),
                            if (meterImageUrl != null)
                              GestureDetector(
                                onTap: () => _showImageDialog(context, meterImageUrl, 'Meter Reading'),
                                child: Container(
                                  height: 64,
                                  width: 64,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFD1D5DB), width: 2),
                                    image: DecorationImage(image: NetworkImage(meterImageUrl), fit: BoxFit.cover),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                                    child: const Center(child: Icon(Icons.electric_meter, color: Colors.white, size: 28)),
                                  ),
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

// ============================================================================
// USAGE CHARTS SCREEN (FINAL FULLY FIXED DATA VERSION)
// ============================================================================

class UsageChartsScreen extends StatelessWidget {
  const UsageChartsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4),
      appBar: AppBar(
        title: const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF00796B),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('monthly_bills').orderBy('timestamp', descending: true).limit(6).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data!.docs.reversed.toList();
          if (docs.isEmpty) return const Center(child: Text("No data to display"));

          List<BarChartGroupData> kwhData = [];
          List<BarChartGroupData> amountData = [];
          List<String> labels = [];

          double maxKwh = 0;
          double maxAmount = 0;

          for (int i = 0; i < docs.length; i++) {
            final data = docs[i].data() as Map<String, dynamic>;
            final breakdown = data['calculatedBreakdown'] as Map<String, dynamic>? ?? {};
            
            final subKwh = (breakdown['subMeterKwh'] as num?)?.toDouble() ?? 0.0;
            final motherKwh = (breakdown['motherMeterKwh'] as num?)?.toDouble() ?? 0.0;
            final subAmount = (breakdown['subMeterAmount'] as num?)?.toDouble() ?? 0.0;
            final motherAmount = (breakdown['motherMeterAmount'] as num?)?.toDouble() ?? 0.0;
            
            // Find highest values to scale the charts dynamically
            if (motherKwh > maxKwh) maxKwh = motherKwh;
            if (subKwh > maxKwh) maxKwh = subKwh;
            if (motherAmount > maxAmount) maxAmount = motherAmount;
            if (subAmount > maxAmount) maxAmount = subAmount;

            // Extract the date for the labels
            final ts = data['timestamp'] as Timestamp?;
            if (ts != null) {
              final date = ts.toDate();
              labels.add("${date.month}/${date.day}");
            } else {
              labels.add("N/A");
            }

            // REVERTED to standard tap-to-view tooltips (no overlaps!)
            kwhData.add(BarChartGroupData(
              x: i, 
              barRods: [
                BarChartRodData(toY: motherKwh, color: const Color(0xFF1D4ED8), width: 14, borderRadius: BorderRadius.circular(4)),
                BarChartRodData(toY: subKwh, color: const Color(0xFF047857), width: 14, borderRadius: BorderRadius.circular(4)),
              ],
            ));

            amountData.add(BarChartGroupData(
              x: i, 
              barRods: [
                BarChartRodData(toY: motherAmount, color: const Color(0xFF1D4ED8), width: 14, borderRadius: BorderRadius.circular(4)),
                BarChartRodData(toY: subAmount, color: const Color(0xFF047857), width: 14, borderRadius: BorderRadius.circular(4)),
              ],
            ));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildChartCard(context, "Consumption (kWh)", kwhData, labels, maxKwh, false),
                const SizedBox(height: 20),
                _buildChartCard(context, "Amount Due (₱)", amountData, labels, maxAmount, true),
                const SizedBox(height: 20),
                _buildLegend(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, String title, List<BarChartGroupData> data, List<String> labels, double maxValue, bool isAmount) {
    
    // Mathematical step logic to prevent squishing text
    double safeMax = maxValue <= 0 ? 100 : (maxValue * 1.2);
    double stepInterval = (safeMax / 5).ceilToDouble();
    if (stepInterval == 0) stepInterval = 1;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  barGroups: data, // <--- CRITICAL FIX: THE DATA IS NOW CONNECTED
                  minY: 0, 
                  maxY: safeMax, 
                  barTouchData: BarTouchData(
                    enabled: true, // You can now cleanly tap any bar to see its exact value
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      tooltipMargin: 4,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          isAmount ? '₱${rod.toY.toStringAsFixed(2)}' : '${rod.toY.toStringAsFixed(1)} kWh',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, 
                        reservedSize: 45, 
                        interval: stepInterval, 
                        getTitlesWidget: (value, meta) {
                          if (value < 0 || value == safeMax) return const SizedBox.shrink();
                          String text = value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.toInt().toString();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)), textAlign: TextAlign.right),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30, 
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < labels.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(labels[value.toInt()], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B7280))),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: stepInterval),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem("Mother Meter", const Color(0xFF1D4ED8)),
          const SizedBox(width: 24),
          _legendItem("Sub-meter", const Color(0xFF047857)),
        ],
      ),
    );
  }

  Widget _legendItem(String text, Color color) {
    return Row(
      children: [
        Container(width: 16, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF374151))),
      ],
    );
  }
}