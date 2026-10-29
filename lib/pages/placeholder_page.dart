import 'package:flutter/material.dart';

import 'map_page.dart';

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.title,
    required this.icon,
    required this.message,
    required this.fields,
    required this.actionLabel,
    this.statusTitle,
    this.statusMessage,
    super.key,
  });

  final String title;
  final IconData icon;
  final String message;
  final List<PlaceholderField> fields;
  final String actionLabel;
  final String? statusTitle;
  final String? statusMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: const BoxDecoration(
                          color: Color(0xFF302544),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: purple, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ...fields.map((field) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _PlaceholderInput(field: field),
                    )),
                if (statusTitle != null && statusMessage != null) ...[
                  _StatusCard(
                    title: statusTitle!,
                    message: statusMessage!,
                  ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'This information will be connected to BetterRoutes services in a future update.',
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => _showComingSoon(context),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(actionLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: purple,
                      foregroundColor: background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back to map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: const BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature will be available in a future update.'),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pending_actions_rounded, color: purple, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    color: mutedColor,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PlaceholderField {
  const PlaceholderField({
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  final String label;
  final IconData icon;
  final TextInputType keyboardType;
}

class _PlaceholderInput extends StatelessWidget {
  const _PlaceholderInput({required this.field});

  final PlaceholderField field;

  @override
  Widget build(BuildContext context) {
    return TextField(
      keyboardType: field.keyboardType,
      style: const TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: field.label,
        labelStyle: const TextStyle(color: mutedColor),
        prefixIcon: Icon(field.icon, color: purple),
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
      ),
    );
  }
}
