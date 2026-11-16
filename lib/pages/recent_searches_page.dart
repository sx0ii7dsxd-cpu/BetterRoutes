import 'package:flutter/material.dart';

import '../models/recent_search_model.dart';
import '../services/recent_search_service.dart';
import '../theme/app_colors.dart';

class RecentSearchesPage extends StatefulWidget {
  const RecentSearchesPage({this.service, super.key});

  final RecentSearchService? service;

  @override
  State<RecentSearchesPage> createState() => _RecentSearchesPageState();
}

class _RecentSearchesPageState extends State<RecentSearchesPage> {
  late final RecentSearchService _service =
      widget.service ?? RecentSearchService.local();
  List<RecentSearch> _searches = [];
  String? _error;
  bool _isLoading = true;
  final Set<String> _deletingIds = {};

  @override
  void initState() {
    super.initState();
    _loadSearches();
  }

  Future<void> _loadSearches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final List<RecentSearch> searches = await _service.getAll();
      if (!mounted) return;
      setState(() {
        _searches = searches;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load recent searches: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSearch(RecentSearch search) async {
    setState(() => _deletingIds.add(search.id));
    try {
      await _service.delete(search.id);
      if (!mounted) return;
      setState(() {
        _searches.removeWhere((RecentSearch item) => item.id == search.id);
        _deletingIds.remove(search.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _deletingIds.remove(search.id);
        _error = 'Could not remove this recent search: $error';
      });
    }
  }

  Future<void> _clearSearches() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Clear recent searches?'),
            content: const Text('This removes all recent search history.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _isLoading = true);
    try {
      await _service.clear();
      if (!mounted) return;
      setState(() {
        _searches = [];
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not clear recent searches: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: textColor,
        title: const Text('Recent searches'),
        actions: [
          if (_searches.isNotEmpty)
            TextButton(
              onPressed: _clearSearches,
              child: const Text('Clear all'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: purple))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadSearches,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _searches.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history_rounded, color: purple, size: 44),
                    SizedBox(height: 14),
                    Text(
                      'No recent searches',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Places you select on the map will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedColor),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: _searches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final RecentSearch search = _searches[index];
                final DateTime localTime = search.searchedAt.toLocal();
                final MaterialLocalizations localizations =
                    MaterialLocalizations.of(context);
                final String timeLabel =
                    '${localizations.formatShortDate(localTime)} · '
                    '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(localTime))}';
                return Material(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    onTap: () => Navigator.of(context).pop(search),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: borderColor),
                    ),
                    leading: const Icon(Icons.history_rounded, color: purple),
                    title: Text(
                      search.placeName ?? search.query,
                      style: const TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (search.address?.isNotEmpty == true) search.address!,
                        timeLabel,
                      ].join('\n'),
                      style: const TextStyle(color: mutedColor, height: 1.4),
                    ),
                    isThreeLine: true,
                    trailing: _deletingIds.contains(search.id)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: purple,
                            ),
                          )
                        : IconButton(
                            tooltip: 'Remove recent search',
                            onPressed: () => _deleteSearch(search),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: mutedColor,
                            ),
                          ),
                  ),
                );
              },
            ),
    );
  }
}
