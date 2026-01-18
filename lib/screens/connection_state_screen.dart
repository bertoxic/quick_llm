import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class OllamaConnectionScreen extends StatefulWidget {
  final VoidCallback onConnectionSuccess;

  const OllamaConnectionScreen({
    super.key,
    required this.onConnectionSuccess,
  });

  @override
  State<OllamaConnectionScreen> createState() => _OllamaConnectionScreenState();
}

class _OllamaConnectionScreenState extends State<OllamaConnectionScreen> {
  bool _isChecking = false;
  String _statusMessage = 'Checking Ollama connection...';

  @override
  void initState() {
    super.initState();
    _checkOllamaConnection();
  }

  Future<void> _checkOllamaConnection() async {
    setState(() {
      _isChecking = true;
      _statusMessage = 'Checking Ollama connection...';
    });

    try {
      final response = await http
          .get(Uri.parse('http://localhost:11434/api/tags'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        // Connection successful
        widget.onConnectionSuccess();
      } else {
        setState(() {
          _statusMessage = 'Ollama is running but returned an error';
          _isChecking = false;
        });
      }
    } on TimeoutException {
      setState(() {
        _statusMessage = 'Connection timeout - Ollama may not be running';
        _isChecking = false;
      });
    } on SocketException {
      setState(() {
        _statusMessage = 'Cannot connect to Ollama';
        _isChecking = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
        _isChecking = false;
      });
    }
  }

  Future<void> _launchOllamaWebsite() async {
    final uri = Uri.parse('https://ollama.com/download');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Ollama Logo/Icon
              Icon(
                Icons.cloud_off_outlined,
                size: 80,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                'Ollama Not Connected',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Status Message
              Text(
                _statusMessage,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              if (!_isChecking) ...[
                // Instructions Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'To use this app, you need:',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildStep(
                          context,
                          '1',
                          'Download and install Ollama',
                          'Visit ollama.com to download',
                        ),
                        const SizedBox(height: 12),
                        _buildStep(
                          context,
                          '2',
                          'Run Ollama on your system',
                          'Make sure Ollama is running in the background',
                        ),
                        const SizedBox(height: 12),
                        _buildStep(
                          context,
                          '3',
                          'Download a model',
                          'Run: ollama pull llama3.2',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _checkOllamaConnection,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry Connection'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _launchOllamaWebsite,
                        icon: const Icon(Icons.download),
                        label: const Text('Download Ollama'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Loading Indicator
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}