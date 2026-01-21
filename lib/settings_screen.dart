// lib/settings_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/drill/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch $urlString: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(languageProvider);
    final isPro = ref.watch(isProProvider);
    final user = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentLang == 'es' ? 'Ajustes' : 'Settings'),
      ),
      body: ListView(
        children: [
          // 1. PROFILE SECTION
          _SectionHeader(title: currentLang == 'es' ? 'Perfil' : 'Profile'),
          _ProfileHeader(user: user),
          
          const Divider(),

          // 2. PREFERENCES (Language & Controls)
          _SectionHeader(title: currentLang == 'es' ? 'Preferencias' : 'Preferences'),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(currentLang == 'es' ? 'Idioma' : 'Language'),
            subtitle: Text(currentLang == 'es' ? 'Español' : 'English'),
            trailing: Switch(
              value: currentLang == 'es',
              activeColor: Colors.blue,
              onChanged: (val) {
                ref.read(languageProvider.notifier).state = val ? 'es' : 'en';
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.touch_app),
            title: Text(currentLang == 'es' ? 'Botones en pantalla' : 'Show Callout Buttons'),
            subtitle: Text(currentLang == 'es' ? 'Controles manuales' : 'Manual triggers on screen'),
            value: ref.watch(showCalloutButtonsProvider),
            onChanged: (v) => ref.read(showCalloutButtonsProvider.notifier).state = v,
          ),

          const Divider(),

          // 3. CUSTOM CALLOUTS (Pro Feature)
          _SectionHeader(title: currentLang == 'es' ? 'Comandos Personalizados' : 'Custom Callouts'),
          if (isPro)
            const _CustomCalloutsManager()
          else
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.grey),
              title: Text(currentLang == 'es' ? 'Bloqueado' : 'Locked'),
              subtitle: Text(currentLang == 'es' 
                  ? 'Suscríbete para agregar tus propios comandos' 
                  : 'Subscribe to add your own audio cues'),
              trailing: FilledButton(
                onPressed: () => ref.read(isProProvider.notifier).setStatus(true),
                child: const Text('GO PRO'),
              ),
            ),

          const Divider(),

          // 4. SUBSCRIPTION / DEV TOGGLE
          _SectionHeader(title: currentLang == 'es' ? 'Suscripción' : 'Subscription'),
          SwitchListTile(
            title: const Text('Simulate Pro Mode'),
            subtitle: const Text('Dev Only: Unlock all features'),
            secondary: Icon(Icons.stars, color: isPro ? Colors.amber : Colors.grey),
            value: isPro,
            onChanged: (val) {
              ref.read(isProProvider.notifier).setStatus(val);
            },
          ),

          const Divider(),

          // 5. LINKS
          _SectionHeader(title: currentLang == 'es' ? 'Soporte' : 'Support'),
          ListTile(
            leading: const Icon(Icons.volunteer_activism, color: Colors.red),
            title: const Text('Keep Kids Wrestling'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchURL("https://youtu.be/8rUsjXm799A"),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(currentLang == 'es' ? 'Privacidad' : 'Privacy Policy'),
            onTap: () => _launchURL("https://keepkidswrestling.com/privacy"),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PROFILE WIDGETS
// -----------------------------------------------------------------------------

class _ProfileHeader extends ConsumerWidget {
  final UserProfile user;
  const _ProfileHeader({required this.user});

  Future<void> _pickImage(WidgetRef ref) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      ref.read(userProfileProvider.notifier).updateProfileImage(image.path);
    }
  }

  void _editField(BuildContext context, WidgetRef ref, String label, String currentVal, Function(String) onSave, {bool isNumber = false}) {
    final controller = TextEditingController(text: currentVal);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final isEs = lang == 'es';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Avatar
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  backgroundImage: user.profileImageUrl != null 
                      ? FileImage(File(user.profileImageUrl!)) 
                      : null,
                  child: user.profileImageUrl == null 
                      ? const Icon(Icons.person, size: 50, color: Colors.white) 
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _pickImage(ref),
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          
          // Stats Row
          Row(
            children: [
              Expanded(
                child: _ProfileStatTile(
                  label: isEs ? 'Peso (lbs)' : 'Weight',
                  value: '${user.weightLbs.toStringAsFixed(0)}',
                  onTap: () => _editField(context, ref, 'Weight', user.weightLbs.toString(), (val) {
                    final d = double.tryParse(val);
                    if (d != null) ref.read(userProfileProvider.notifier).updateWeight(d);
                  }, isNumber: true),
                ),
              ),
              Expanded(
                child: _ProfileStatTile(
                  label: isEs ? 'Edad' : 'Age',
                  value: '${user.age}',
                  onTap: () => _editField(context, ref, 'Age', user.age.toString(), (val) {
                    final i = int.tryParse(val);
                    if (i != null) ref.read(userProfileProvider.notifier).updateAge(i);
                  }, isNumber: true),
                ),
              ),
              Expanded(
                child: _ProfileStatTile(
                  label: isEs ? 'Equipo' : 'Team',
                  value: user.teamName ?? '-',
                  onTap: () => _editField(context, ref, 'Team', user.teamName ?? '', (val) {
                    ref.read(userProfileProvider.notifier).updateTeam(val);
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ProfileStatTile({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Card(
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CUSTOM CALLOUTS WIDGETS
// -----------------------------------------------------------------------------

class _CustomCalloutsManager extends ConsumerWidget {
  const _CustomCalloutsManager();

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const _AddCalloutSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calloutsAsync = ref.watch(calloutsProvider);
    final lang = ref.watch(languageProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.add_circle, color: Colors.blue),
          title: Text(lang == 'es' ? 'Agregar Nuevo Comando' : 'Add New Callout'),
          onTap: () => _showAddDialog(context),
        ),
        
        calloutsAsync.when(
          data: (list) {
            final customs = list.where((c) => c.isCustom).toList();
            if (customs.isEmpty) return const SizedBox.shrink();

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: customs.length,
              itemBuilder: (context, index) {
                final c = customs[index];
                return ListTile(
                  leading: const Icon(Icons.mic, color: Colors.grey),
                  title: Text(c.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      ref.read(calloutsProvider.notifier).deleteCallout(c.id);
                    },
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text('Error: $e'),
        ),
      ],
    );
  }
}

class _AddCalloutSheet extends ConsumerStatefulWidget {
  const _AddCalloutSheet();

  @override
  ConsumerState<_AddCalloutSheet> createState() => _AddCalloutSheetState();
}

class _AddCalloutSheetState extends ConsumerState<_AddCalloutSheet> {
  final TextEditingController _nameController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  
  bool _isRecording = false;
  String? _tempPath;

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _tempPath = path;
      });
    } else {
      if (await _recorder.hasPermission()) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/temp_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        await _recorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      }
    }
  }

  void _save(WidgetRef ref) {
    if (_nameController.text.isEmpty || _tempPath == null) return;

    final newCallout = Callout(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      nameEn: _nameController.text,
      nameEs: _nameController.text, // Same name for both for now
      type: 'Movement',
      audioUrl: _tempPath,
      isCustom: true,
    );

    ref.read(calloutsProvider.notifier).addCustomCallout(newCallout);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    final isEs = lang == 'es';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEs ? 'Nuevo Comando' : 'New Callout',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: isEs ? 'Nombre del comando' : 'Callout Name',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _toggleRecording,
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: _isRecording ? Colors.red : Colors.grey[200],
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic, 
                    color: _isRecording ? Colors.white : Colors.black,
                    size: 30,
                  ),
                ),
              ),
              if (_tempPath != null && !_isRecording) ...[
                const SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 40, color: Colors.blue),
                  onPressed: () => _player.play(DeviceFileSource(_tempPath!)),
                ),
              ]
            ],
          ),
          const SizedBox(height: 10),
          Center(child: Text(_isRecording ? "Recording..." : (_tempPath != null ? "Audio Recorded" : "Tap to Record"))),
          
          const SizedBox(height: 30),
          FilledButton(
            onPressed: (_tempPath != null && _nameController.text.isNotEmpty) 
                ? () => _save(ref) 
                : null,
            child: Text(isEs ? 'Guardar' : 'Save Callout'),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// COMMON HELPERS
// -----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
