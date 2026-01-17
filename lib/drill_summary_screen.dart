import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'package:gal/gal.dart';
import 'dart:io';

class DrillSummaryScreen extends ConsumerStatefulWidget {
  final int totalCallouts;
  final Duration duration;
  final String? videoPath;

  const DrillSummaryScreen({
    super.key,
    required this.totalCallouts,
    required this.duration,
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
    // Stagger the reveal of information
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() => _showStats = true);
    
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _showCalories = true);
    
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() => _showActions = true);
  }

Future<void> _saveVideoToGallery(BuildContext context, String? path, String lang) async {
  if (path == null || path.isEmpty) {
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
  double _calculateCalories(double met, double weightKg, Duration duration) {
    double hours = duration.inSeconds / 3600;
    return met * weightKg * hours;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProfileProvider);
    final config = ref.watch(drillConfigProvider);
    final lang = ref.watch(languageProvider);
    
    final burned = _calculateCalories(config.metValue, user.weightKg, widget.duration);

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
                    if (_showCalories) _buildCaloriesCard(burned, lang),
                  ],
                ),
              ),
            ),

            if (_showActions) _buildActionButtons(lang),
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
          child: const Icon(Icons.person, size: 50), // Future: Use user.profileImageUrl
        ),
        const SizedBox(height: 12),
        Text(
          user.teamName ?? (lang == 'es' ? 'Luchador Individual' : 'Independent Wrestler'),
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
        _statItem(widget.totalCallouts.toString(), lang == 'es' ? 'Comandos' : 'Callouts'),
        _statItem("${widget.duration.inMinutes}:${(widget.duration.inSeconds % 60).toString().padLeft(2, '0')}", lang == 'es' ? 'Tiempo' : 'Time'),
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

  Widget _buildActionButtons(String lang) {
    final engineState = ref.watch(drillEngineProvider);
    
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 60,
            FilledButton.icon(
                onPressed: engineState.isProcessing 
                    ? null 
                    : () => _saveVideoToGallery(
                        context, 
                        engineState.processedVideoPath, // The path from FFmpeg
                        lang
                    ),
                icon: engineState.isProcessing 
                    ? const SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                    : const Icon(Icons.save_alt),
                label: Text(engineState.isProcessing 
                    ? (lang == 'es' ? 'Procesando...' : 'Processing...') 
                    : (lang == 'es' ? 'Guardar en Galería' : 'Save to Gallery')),
                ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(lang == 'es' ? 'Volver al Inicio' : 'Back to Home'),
          ),
        ],
      ),
    );
  }
}