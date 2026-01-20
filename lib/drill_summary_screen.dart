import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'dart:io';

// Import your providers
import 'features/drill/providers.dart';

class DrillSummaryScreen extends ConsumerStatefulWidget {
  final Duration totalTime;
  final int calloutsCompleted;
  
  // This screen might receive a video path if recording was enabled
  final String? videoPath;

  const DrillSummaryScreen({
    super.key,
    required this.totalTime,
    required this.calloutsCompleted,
    this.videoPath,
  });

  @override
  ConsumerState<DrillSummaryScreen> createState() => _DrillSummaryScreenState();
}

class _DrillSummaryScreenState extends ConsumerState<DrillSummaryScreen> {
  bool _showStats = false;
  bool _showCalories = false;
  bool _showActions = false;

  @override
  void initState() {
    super.initState();
    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // Stagger the reveal of information for a better UX
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _showStats = true);
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _showCalories = true);
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _showActions = true);
  }

  /// Calculates Calories Burned for Wrestling Drills
  /// Formula: Calories = MET * Weight(kg) * Duration(hours)
  /// 
  /// MET Values derived from Compendium of Physical Activities:
  /// - 6.0: Light drilling / Technique (Easy)
  /// - 8.5: Moderate drilling (Medium)
  /// - 11.5: Hard sparring / Match intensity (Hard)
  double _calculateCalories({
    required double weightLbs, 
    required Duration duration, 
    required double intensityMet
  }) {
    // 1. Convert Weight to Kg
    final double weightKg = weightLbs * 0.453592;
    
    // 2. Convert Duration to Hours
    final double durationHours = duration.inSeconds / 3600.0;
    
    // 3. Calculate
    return intensityMet * weightKg * durationHours;
  }

  Future<void> _saveVideoToGallery(BuildContext context, String? path, String lang) async {
    // Check if the path exists locally in the app's cache/documents
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang == 'es' ? 'Video no encontrado' : 'Video not found')),
      );
      return;
    }

    try {
      // 1. Request permission
      await Gal.requestAccess();

      // 2. Save the branded video
      await Gal.putVideo(path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(lang == 'es' ? '¡Video guardado!' : 'Video saved to Gallery!'),
          ),
        );
      }
    } catch (e) {
      debugPrint("Gallery Save Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lang == 'es' ? 'Error al guardar' : 'Error saving video')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProfileProvider);
    final config = ref.watch(drillConfigProvider);
    final lang = ref.watch(languageProvider);
    
    // --- CALORIE CALCULATION USAGE ---
    final burned = _calculateCalories(
      weightLbs: user.weightLbs,
      duration: widget.totalTime,
      intensityMet: config.metValue, // Derived from DrillConfig model
    );

    // If the DrillEngine passed a processed video path (e.g. from state), use it.
    // Otherwise fallback to the one passed in constructor (legacy logic support)
    final effectiveVideoPath = ref.read(drillEngineProvider).videoPath ?? widget.videoPath;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildHeader(lang, user),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_showStats) _buildStatsRow(lang),
                    const SizedBox(height: 30),
                    // Only show calories if weight is realistic (> 0)
                    if (_showCalories && user.weightLbs > 0) 
                      _buildCaloriesCard(burned, lang),
                  ],
                ),
              ),
            ),

            if (_showActions) _buildActionButtons(lang, effectiveVideoPath),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String lang, UserProfile user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: Colors.grey[300],
          // Future: use user.profileImageUrl if available
          child: const Icon(Icons.person, size: 50), 
        ),
        const SizedBox(height: 12),
        Text(
          user.teamName ?? (lang == 'es' ? 'Luchador' : 'Wrestler'),
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        Text(
          lang == 'es' ? '¡DRILL COMPLETADO!' : 'DRILL COMPLETE!',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.black),
        ),
      ],
    );
  }

  Widget _buildStatsRow(String lang) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem(widget.calloutsCompleted.toString(), lang == 'es' ? 'Comandos' : 'Callouts'),
        _statItem(
          "${widget.totalTime.inMinutes}:${(widget.totalTime.inSeconds % 60).toString().padLeft(2, '0')}", 
          lang == 'es' ? 'Tiempo' : 'Time'
        ),
      ],
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildCaloriesCard(double burned, String lang) {
    return Card(
      elevation: 4,
      color: Colors.orange[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 40),
            Text(
              burned.toStringAsFixed(1),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.black, color: Colors.orange),
            ),
            Text(
              lang == 'es' ? 'CALORÍAS QUEMADAS' : 'CALORIES BURNED',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(String lang, String? videoPath) {
    final engineState = ref.watch(drillEngineProvider);
    // If the engine is currently recording/processing, disable buttons
    final bool isProcessing = engineState.isRecording; 

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          // Show "Save to Gallery" ONLY if we actually have a video path
          if (videoPath != null)
            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                  onPressed: isProcessing 
                      ? null 
                      : () => _saveVideoToGallery(context, videoPath, lang),
                  icon: isProcessing 
                      ? const SizedBox(
                          width: 20, 
                          height: 20, 
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                      : const Icon(Icons.save_alt),
                  label: Text(isProcessing 
                      ? (lang == 'es' ? 'Procesando...' : 'Processing...') 
                      : (lang == 'es' ? 'Guardar en Galería' : 'Save to Gallery')),
                  ),
            ),
          
          if (videoPath != null) const SizedBox(height: 12),

          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(lang == 'es' ? 'Volver al Inicio' : 'Back to Home'),
          ),
        ],
      ),
    );
  }
}
