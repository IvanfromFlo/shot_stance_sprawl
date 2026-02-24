import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'dart:io';

import 'features/drill/providers.dart';

class DrillSummaryScreen extends ConsumerStatefulWidget {
  final Duration totalTime;
  final int calloutsCompleted;
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

class _DrillSummaryScreenState extends ConsumerState<DrillSummaryScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _calculateCalories({
    required double weightLbs, 
    required Duration duration, 
    required double intensityMet
  }) {
    if (weightLbs <= 0) return 0.0;
    final double weightKg = weightLbs * 0.453592;
    final double durationHours = duration.inSeconds / 3600.0;
    return intensityMet * weightKg * durationHours;
  }

  Future<void> _saveVideoToGallery(BuildContext context, String? path, String lang) async {
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lang == 'es' ? 'Video no encontrado' : 'Video not found')),
      );
      return;
    }

    try {
      await Gal.requestAccess();
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
    final isPro = ref.watch(isProProvider);
    
    final burned = _calculateCalories(
      weightLbs: user.weightLbs,
      duration: widget.totalTime,
      intensityMet: config.metValue, 
    );

    final effectiveVideoPath = widget.videoPath; 
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: 20),
              _buildHeader(lang, user),
              
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _buildStatsRow(lang),
                      const SizedBox(height: 30),
                      
                      _buildCaloriesCard(burned, lang),
                      
                      const SizedBox(height: 30),
                      
                      // FIX: Safe state protection if branding failed or was locked
                      if (effectiveVideoPath != null && File(effectiveVideoPath).existsSync())
                        _buildVideoCard(context, effectiveVideoPath, lang)
                      else if (!isPro && config.videoEnabled)
                        _buildFailedBrandingCard(lang)
                    ],
                  ),
                ),
              ),

              _buildFooterButtons(context, lang),
            ],
          ),
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
          backgroundImage: user.profileImageUrl != null ? FileImage(File(user.profileImageUrl!)) : null,
          child: user.profileImageUrl == null ? const Icon(Icons.person, size: 50) : null,
        ),
        const SizedBox(height: 12),
        Text(
          user.teamName ?? (lang == 'es' ? 'Luchador' : 'Wrestler'),
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        Text(
          lang == 'es' ? '¡DRILL COMPLETADO!' : 'DRILL COMPLETE!',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900, 
            color: Theme.of(context).primaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(String lang) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem(widget.calloutsCompleted.toString(), lang == 'es' ? 'Comandos' : 'Callouts'),
        Container(width: 1, height: 40, color: Colors.grey[300]),
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
        Text(label, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildCaloriesCard(double burned, String lang) {
    return Card(
      elevation: 8,
      shadowColor: Colors.orange.withOpacity(0.4),
      color: Colors.orange[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
        child: Column(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrange, size: 48),
            const SizedBox(height: 8),
            Text(
              burned.toStringAsFixed(0),
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: Colors.deepOrange),
            ),
            Text(
              lang == 'es' ? 'CALORÍAS QUEMADAS' : 'CALORIES BURNED',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(BuildContext context, String path, String lang) {
    final engineState = ref.watch(drillEngineProvider);
    final bool isProcessing = engineState.isRecording;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue[50], shape: BoxShape.circle),
          child: const Icon(Icons.videocam, color: Colors.blue),
        ),
        title: Text(lang == 'es' ? 'Video del Drill' : 'Drill Video'),
        subtitle: Text(lang == 'es' ? 'Listo para guardar' : 'Ready to save'),
        trailing: FilledButton.icon(
          onPressed: isProcessing ? null : () => _saveVideoToGallery(context, path, lang),
          icon: isProcessing 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.download),
          label: Text(lang == 'es' ? 'Guardar' : 'Save'),
        ),
      ),
    );
  }

  // FIX: Custom fallback card for Free-tier users who triggered a watermark native failure
  Widget _buildFailedBrandingCard(String lang) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.red[50],
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: const Icon(Icons.error_outline, color: Colors.red),
        ),
        title: Text(
          lang == 'es' ? 'Error al Procesar Video' : 'Video Processing Failed', 
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)
        ),
        subtitle: Text(
          lang == 'es' ? 'No se pudo aplicar la marca de agua obligatoria.' : 'Mandatory watermark could not be applied.'
        ),
      ),
    );
  }

  Widget _buildFooterButtons(BuildContext context, String lang) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          side: BorderSide(color: Theme.of(context).primaryColor),
        ),
        child: Text(
          lang == 'es' ? 'VOLVER AL INICIO' : 'BACK TO HOME',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}