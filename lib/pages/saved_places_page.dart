import 'package:flutter/material.dart';

import '../models/saved_place_model.dart';
import '../services/firestore_service.dart';
import 'place_search_service.dart';

class SavedPlacesPage extends StatelessWidget {
  const SavedPlacesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text('Saved places'),
      ),
      body: StreamBuilder<List<SavedPlaceModel>>(
        stream: service.watchSavedPlaces(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _Message('Could not load saved places.');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final places = snapshot.data!;
          if (places.isEmpty) return const _Message('No saved places yet.');
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: places.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final place = places[index];
              return Card(
                color: surface,
                child: ListTile(
                  leading: const Icon(Icons.bookmark, color: purple),
                  title: Text(
                    place.name,
                    style: const TextStyle(color: textColor),
                  ),
                  subtitle: Text(
                    place.address ?? place.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: mutedColor),
                  ),
                  onTap: () => Navigator.pop<PlaceSearchResult>(
                    context,
                    place.toPlaceSearchResult(),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: mutedColor),
                    onPressed: () => service.deleteSavedPlace(place.placeId),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: const TextStyle(color: mutedColor)),
  );
}

const Color background = Color(0xFF17131F);
const Color surface = Color(0xFF211C2B);
const Color purple = Color(0xFFB39DDB);
const Color textColor = Color(0xFFF7F5FC);
const Color mutedColor = Color(0xFFB5AEC5);
