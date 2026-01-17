// lib/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      // LaunchMode.externalApplication is better for App Store compliance
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not launch $urlString: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(languageProvider);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentLang == 'es' ? 'Ajustes' : 'Settings'),
      ),
      body: ListView(
        children: [
          _SectionHeader(title: currentLang == 'es' ? 'Perfil de Luchador' : 'Wrestler Profile'),
          
          // 1. WEIGHT INPUT (Crucial for Calories)
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(currentLang == 'es' ? 'Peso Corporal' : 'Body Weight'),
            subtitle: Text('${ref.watch(userProfileProvider).weightLbs} lbs'),
            onTap: () => _showWeightDialog(context, ref),
          ),

          // 2. TEAM NAME
          ListTile(
            leading: const Icon(Icons.group),
            title: Text(currentLang == 'es' ? 'Equipo' : 'Team Name'),
            subtitle: Text(ref.watch(userProfileProvider).teamName ?? (currentLang == 'es' ? 'Sin equipo' : 'No team')),
            onTap: () => _showTeamDialog(context, ref),
          ),

          const Divider(),

          _SectionHeader(title: currentLang == 'es' ? 'Intensidad del Drill' : 'Drill Intensity'),
          
          // 3. DIFFICULTY SELECTOR (Sets MET & Intervals)
          _IntensitySelector(),

          const Divider(),
          
          _SectionHeader(title: currentLang == 'es' ? 'Preferencias' : 'Preferences'),
          
          SwitchListTile(
            secondary: const Icon(Icons.touch_app),
            title: Text(currentLang == 'es' ? 'Mostrar botones de comando' : 'Show Callout Buttons'),
            subtitle: Text(currentLang == 'es' ? 'Manual en pantalla' : 'On-screen manual triggers'),
            value: ref.watch(showCalloutButtonsProvider),
            onChanged: (v) => ref.read(showCalloutButtonsProvider.notifier).state = v,
          ),

          ListTile(
            leading: const Icon(Icons.language),
            title: Text(currentLang == 'es' ? 'Idioma' : 'Language'),
            subtitle: Text(currentLang == 'es' ? 'Español' : 'English'),
            onTap: () => _showLanguageDialog(context, ref),
          ),

          const Divider(),

          _SectionHeader(title: currentLang == 'es' ? 'Suscripción' : 'Subscription'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              // Change color to Green if Pro is active
              color: isPro 
                  ? Colors.green.withOpacity(0.1) 
                  : Theme.of(context).colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isPro ? Colors.green : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          isPro ? Icons.verified : Icons.workspace_premium, 
                          color: isPro ? Colors.green : Colors.amber,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isPro 
                            ? (currentLang == 'es' ? 'MIEMBRO PRO' : 'PRO MEMBER')
                            : (currentLang == 'es' ? 'MODO PRO' : 'PRO MODE'), 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ProFeatureRow(icon: Icons.timer, text: currentLang == 'es' ? 'Grabaciones de 7 minutos' : '7 Minute Recording'),
                    _ProFeatureRow(icon: Icons.remove_circle_outline, text: currentLang == 'es' ? 'Sin marcas de agua' : 'No Watermarks'),
                    _ProFeatureRow(icon: Icons.record_voice_over, text: currentLang == 'es' ? 'Voces personalizadas' : 'Custom Voice Callouts'),
                    const SizedBox(height: 20),
                    if (!isPro)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: () => ref.read(isProProvider.notifier).state = true,
                          child: Text(currentLang == 'es' ? 'Suscribirse \$2.99/mes' : 'Subscribe \$2.99/mo'),
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            currentLang == 'es' ? 'Suscripción Activa' : 'Active Pro Subscription',
                            style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

          const Divider(),

          _SectionHeader(title: currentLang == 'es' ? 'Nuestra Misión' : 'Our Mission'),
          ListTile(
            leading: const Icon(Icons.volunteer_activism, color: Colors.red),
            title: const Text('Keep Kids Wrestling'),
            subtitle: Text(currentLang == 'es' ? 'Ver nuestro video' : 'Watch our mission video'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => _launchURL("https://youtu.be/8rUsjXm799A"),
          ),

          _SectionHeader(title: currentLang == 'es' ? 'Soporte' : 'Support'),
          ListTile(
            leading: const Icon(Icons.star, color: Colors.amber),
            title: Text(currentLang == 'es' ? 'Califica la aplicación' : 'Rate this App'),
            onTap: () => _launchURL("https://keepkidswrestling.com/rateus"),
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

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Language / Idioma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageOption(
              title: 'English',
              isSelected: ref.watch(languageProvider) == 'en',
              onTap: () {
                ref.read(languageProvider.notifier).state = 'en';
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              title: 'Español',
              isSelected: ref.watch(languageProvider) == 'es',
              onTap: () {
                ref.read(languageProvider.notifier).state = 'es';
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

// --- SMALL UI HELPERS ---

class _LanguageOption extends StatelessWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  const _LanguageOption({required this.title, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
      onTap: onTap,
    );
  }
}

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

class _ProFeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProFeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}