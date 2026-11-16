import 'package:flutter/material.dart';

import '../models/saved_place_model.dart';
import '../services/saved_place_service.dart';
import '../theme/app_colors.dart';

class SavedPlacesPage extends StatefulWidget {
  const SavedPlacesPage({this.service, super.key});

  final SavedPlaceService? service;

  @override
  State<SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<SavedPlacesPage> {
  late final SavedPlaceService _service =
      widget.service ?? SavedPlaceService.local();
  final TextEditingController _searchController = TextEditingController();
  List<SavedPlace> _places = [];
  String _query = '';
  String? _error;
  bool _isLoading = true;
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final List<SavedPlace> places = await _service.getAll();
      if (!mounted) return;
      setState(() {
        _places = places;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load saved places: $error';
        _isLoading = false;
      });
    }
  }

  List<SavedPlace> get _visiblePlaces {
    final String query = _query.trim().toLowerCase();
    if (query.isEmpty) return _places;
    return _places
        .where(
          (SavedPlace place) =>
              place.name.toLowerCase().contains(query) ||
              place.displayName.toLowerCase().contains(query) ||
              (place.address?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  Future<void> _deletePlace(SavedPlace place) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Remove saved place?'),
            content: Text('Remove "${place.name}" from your saved places?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _deletingIds.add(place.id));
    try {
      await _service.delete(place.id);
      if (!mounted) return;
      setState(() {
        _places.removeWhere((SavedPlace item) => item.id == place.id);
        _deletingIds.remove(place.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(place.id);
        _error = 'Could not remove this place: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SavedPlace> places = _visiblePlaces;
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text('Saved places'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) => setState(() => _query = value),
              style: const TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'Search saved places',
                hintStyle: const TextStyle(color: mutedColor),
                prefixIcon: const Icon(Icons.search_rounded, color: mutedColor),
                filled: true,
                fillColor: surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderColor),
                ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Material(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: purple),
                  title: Text(_error!, style: const TextStyle(color: textColor)),
                  trailing: IconButton(
                    tooltip: 'Retry',
                    onPressed: _loadPlaces,
                    icon: const Icon(Icons.refresh_rounded, color: purple),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: purple),
                  )
                : places.isEmpty
                ? _SavedPlacesEmptyState(hasSavedPlaces: _places.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    itemCount: places.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final SavedPlace place = places[index];
                      return Material(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          onTap: () => Navigator.of(context).pop(place),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: borderColor),
                          ),
                          leading: const Icon(
                            Icons.bookmark_rounded,
                            color: purple,
                          ),
                          title: Text(
                            place.name,
                            style: const TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (place.address?.isNotEmpty == true)
                                place.address!,
                              '${place.latitude.toStringAsFixed(5)}, '
                                  '${place.longitude.toStringAsFixed(5)}',
                            ].join('\n'),
                            style: const TextStyle(
                              color: mutedColor,
                              height: 1.4,
                            ),
                          ),
                          isThreeLine: true,
                          trailing: _deletingIds.contains(place.id)
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: purple,
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Remove saved place',
                                  onPressed: () => _deletePlace(place),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: mutedColor,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SavedPlacesEmptyState extends StatelessWidget {
  const _SavedPlacesEmptyState({required this.hasSavedPlaces});

  final bool hasSavedPlaces;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_border_rounded, color: purple, size: 44),
            const SizedBox(height: 14),
            Text(
              hasSavedPlaces ? 'No matching places' : 'No saved places yet',
              style: const TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSavedPlaces
                  ? 'Try another search.'
                  : 'Save a place from the map to find it here.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: mutedColor),
            ),
          ],
        ),
      ),
    );
  }
}
