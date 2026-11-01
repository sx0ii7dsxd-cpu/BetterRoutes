import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'place_search_service.dart';

const Color _background = Color(0xFF17131F);
const Color _surface = Color(0xFF211C2B);
const Color _surfaceRaised = Color(0xFF292334);
const Color _amethyst = Color(0xFFB39DDB);
const Color _text = Color(0xFFF7F5FC);
const Color _muted = Color(0xFFB5AEC5);
const Color _border = Color(0xFF383044);

class RoutePlanningPage extends StatefulWidget {
  const RoutePlanningPage({
    required this.startingLocation,
    required this.destination,
    this.placeSearchService,
    super.key,
  });

  final PlaceSearchResult? startingLocation;
  final PlaceSearchResult destination;
  final PlaceSearchService? placeSearchService;

  @override
  State<RoutePlanningPage> createState() => _RoutePlanningPageState();
}

class _RoutePlanningPageState extends State<RoutePlanningPage> {
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final PlaceSearchService _placeSearchService;
  late final bool _ownsPlaceSearchService;
  PlaceSearchResult? _fromLocation;
  PlaceSearchResult? _toLocation;
  _RouteField? _activeField;
  List<PlaceSearchResult> _suggestions = [];
  Timer? _suggestionDebounce;
  int _suggestionGeneration = 0;
  bool _isLoadingSuggestions = false;
  bool _hasSearchedQuery = false;
  String? _suggestionMessage;

  @override
  void initState() {
    super.initState();
    _fromLocation = widget.startingLocation;
    _toLocation = widget.destination;
    _fromController = TextEditingController(
      text: widget.startingLocation?.displayName,
    );
    _toController = TextEditingController(text: widget.destination.displayName);
    _ownsPlaceSearchService = widget.placeSearchService == null;
    _placeSearchService =
        widget.placeSearchService ??
        PlaceSearchService(apiKey: PlaceSearchService.configuredApiKey);
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    if (_ownsPlaceSearchService) _placeSearchService.dispose();
    _fromController.dispose();
    _toController.dispose();
    _fromFocusNode.dispose();
    _toFocusNode.dispose();
    super.dispose();
  }

  void _swapLocations() {
    final String from = _fromController.text;
    final PlaceSearchResult? fromLocation = _fromLocation;
    _cancelSuggestions();
    setState(() {
      _fromLocation = _toLocation;
      _toLocation = fromLocation;
      _activeField = null;
      _suggestions = [];
      _hasSearchedQuery = false;
      _suggestionMessage = null;
      _isLoadingSuggestions = false;
    });
    _fromController.value = TextEditingValue(
      text: _toController.text,
      selection: TextSelection.collapsed(offset: _toController.text.length),
    );
    _toController.value = TextEditingValue(
      text: from,
      selection: TextSelection.collapsed(offset: from.length),
    );
  }

  void _onQueryChanged(_RouteField field, String rawQuery) {
    final String query = rawQuery.trim();
    _suggestionDebounce?.cancel();
    final int generation = ++_suggestionGeneration;
    setState(() {
      if (field == _RouteField.from && _fromLocation?.displayName != rawQuery) {
        _fromLocation = null;
      } else if (field == _RouteField.to &&
          _toLocation?.displayName != rawQuery) {
        _toLocation = null;
      }
      _activeField = field;
      _suggestions = [];
      _hasSearchedQuery = query.length >= 2;
      _suggestionMessage = null;
      _isLoadingSuggestions = false;
    });

    if (query.length < 2) return;
    if (_placeSearchService.apiKey.trim().isEmpty ||
        _placeSearchService.apiKey.trim() == 'YOUR_MAPTILER_API_KEY') {
      setState(() {
        _suggestionMessage = 'Place suggestions require a MapTiler API key.';
      });
      return;
    }

    _suggestionDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchSuggestions(field, query, generation),
    );
  }

  Future<void> _fetchSuggestions(
    _RouteField field,
    String query,
    int generation,
  ) async {
    if (!mounted || generation != _suggestionGeneration) return;
    setState(() {
      _activeField = field;
      _isLoadingSuggestions = true;
      _suggestionMessage = null;
    });

    try {
      final List<PlaceSearchResult> results = await _placeSearchService.search(
        query,
        proximityLatitude: widget.startingLocation?.latitude,
        proximityLongitude: widget.startingLocation?.longitude,
      );
      if (!mounted ||
          generation != _suggestionGeneration ||
          field != _activeField) {
        return;
      }
      setState(() {
        _suggestions = results;
        _isLoadingSuggestions = false;
        _suggestionMessage = results.isEmpty ? 'No places found.' : null;
      });
    } catch (error) {
      if (!mounted ||
          generation != _suggestionGeneration ||
          field != _activeField) {
        return;
      }
      setState(() {
        _suggestions = [];
        _isLoadingSuggestions = false;
        if (error is TimeoutException) {
          _suggestionMessage = 'Search took too long. Please try again.';
        } else if (error is PlaceSearchException) {
          _suggestionMessage = error.message;
        } else if (error is FormatException) {
          _suggestionMessage = 'Place search returned invalid results.';
        } else if (error is http.ClientException) {
          _suggestionMessage =
              'Could not connect to place search. Check your connection.';
        } else {
          _suggestionMessage = 'Could not load place suggestions.';
        }
      });
    }
  }

  void _selectSuggestion(_RouteField field, PlaceSearchResult result) {
    _cancelSuggestions();
    setState(() {
      if (field == _RouteField.from) {
        _fromLocation = result;
        _fromController.value = TextEditingValue(
          text: result.displayName,
          selection: TextSelection.collapsed(offset: result.displayName.length),
        );
      } else {
        _toLocation = result;
        _toController.value = TextEditingValue(
          text: result.displayName,
          selection: TextSelection.collapsed(offset: result.displayName.length),
        );
      }
      _activeField = null;
      _suggestions = [];
      _hasSearchedQuery = false;
      _suggestionMessage = null;
      _isLoadingSuggestions = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _clearField(_RouteField field) {
    _cancelSuggestions();
    setState(() {
      if (field == _RouteField.from) {
        _fromLocation = null;
        _fromController.clear();
      } else {
        _toLocation = null;
        _toController.clear();
      }
      _activeField = field;
      _suggestions = [];
      _hasSearchedQuery = false;
      _suggestionMessage = null;
      _isLoadingSuggestions = false;
    });
    _onQueryChanged(field, '');
    FocusScope.of(
      context,
    ).requestFocus(field == _RouteField.from ? _fromFocusNode : _toFocusNode);
  }

  final FocusNode _fromFocusNode = FocusNode();
  final FocusNode _toFocusNode = FocusNode();

  void _cancelSuggestions() {
    _suggestionDebounce?.cancel();
    _suggestionDebounce = null;
    _suggestionGeneration++;
  }

  void _hideSuggestions() {
    _cancelSuggestions();
    setState(() {
      _activeField = null;
      _suggestions = [];
      _hasSearchedQuery = false;
      _suggestionMessage = null;
      _isLoadingSuggestions = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _showRouteNotReady() {
    if (_activeField != null) _hideSuggestions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Route calculation will be added in a later stage.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_background, Color(0xFF1D1827), _background],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _buildHeader(context),
              const SizedBox(height: 34),
              const Text(
                'PLAN A JOURNEY',
                style: TextStyle(
                  color: _amethyst,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Set your direction.',
                style: TextStyle(
                  color: _text,
                  fontSize: 30,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 9),
              const Text(
                'Choose where your journey begins and ends.',
                style: TextStyle(color: _muted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 25),
              _buildStopsCard(),
              const SizedBox(height: 18),
              _buildStatusCard(),
              const SizedBox(height: 28),
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: _showRouteNotReady,
                  style: FilledButton.styleFrom(
                    backgroundColor: _amethyst,
                    foregroundColor: _background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  icon: const Icon(Icons.route_rounded, size: 21),
                  label: const Text('Find Route'),
                ),
              ),
              const SizedBox(height: 13),
              const Center(
                child: Text(
                  'Route preview is coming soon',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        _PlannerIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: 'Back to map',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BETTERROUTES',
                style: TextStyle(
                  color: _text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'ROUTE PLANNER',
                style: TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.25,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: _amethyst.withValues(alpha: 0.09),
            border: Border.all(color: _amethyst.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.circle, size: 7, color: _amethyst),
              SizedBox(width: 7),
              Text(
                'SETUP',
                style: TextStyle(
                  color: _amethyst,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStopsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildLocationField(_RouteField.from),
          Padding(
            padding: const EdgeInsets.only(left: 23, right: 3),
            child: Row(
              children: [
                Container(
                  width: 1,
                  height: 25,
                  color: _amethyst.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 17),
                Expanded(child: Container(height: 1, color: _border)),
                const SizedBox(width: 10),
                _PlannerIconButton(
                  icon: Icons.swap_vert_rounded,
                  tooltip: 'Swap starting point and destination',
                  onPressed: _swapLocations,
                  accent: _amethyst,
                ),
              ],
            ),
          ),
          _buildLocationField(_RouteField.to),
        ],
      ),
    );
  }

  Widget _buildLocationField(_RouteField field) {
    final bool isFrom = field == _RouteField.from;
    final PlaceSearchResult? selectedLocation = isFrom
        ? _fromLocation
        : _toLocation;
    return Column(
      children: [
        _LocationInput(
          controller: isFrom ? _fromController : _toController,
          focusNode: isFrom ? _fromFocusNode : _toFocusNode,
          label: isFrom ? 'FROM' : 'TO',
          hint: isFrom ? 'Add a starting point' : 'Search for a destination',
          icon: isFrom ? Icons.trip_origin_rounded : Icons.location_on_rounded,
          accent: _amethyst,
          helperText: selectedLocation?.address,
          helperValue: selectedLocation?.displayName,
          textInputAction: isFrom ? TextInputAction.next : TextInputAction.done,
          onTap: () => setState(() => _activeField = field),
          onChanged: (value) => _onQueryChanged(field, value),
          onClear: () => _clearField(field),
        ),
        if (_activeField == field) _buildSuggestionsPanel(field),
      ],
    );
  }

  Widget _buildSuggestionsPanel(_RouteField field) {
    if (!_hasSearchedQuery &&
        !_isLoadingSuggestions &&
        _suggestionMessage == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 230),
      decoration: BoxDecoration(
        color: _surfaceRaised,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _isLoadingSuggestions
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _amethyst,
                  ),
                ),
              ),
            )
          : _suggestions.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Text(
                _suggestionMessage ?? 'No places found.',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: _border),
              itemBuilder: (context, index) {
                final PlaceSearchResult result = _suggestions[index];
                return Material(
                  color: _surfaceRaised,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: _amethyst,
                      size: 20,
                    ),
                    title: Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      result.address ?? result.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    onTap: () => _selectSuggestion(field, result),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _amethyst.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _amethyst.withValues(alpha: 0.16)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.explore_outlined, color: _amethyst, size: 21),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your stops are ready',
                  style: TextStyle(
                    color: _text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Route preview and journey details will appear here.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationInput extends StatelessWidget {
  const _LocationInput({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.textInputAction,
    required this.onTap,
    required this.onChanged,
    required this.onClear,
    this.helperText,
    this.helperValue,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final Color accent;
  final String? helperText;
  final String? helperValue;
  final TextInputAction textInputAction;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
      decoration: BoxDecoration(
        color: _surfaceRaised.withValues(alpha: 0.68),
        border: Border.all(color: _border.withValues(alpha: 0.9)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Icon(icon, size: 19, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.35,
                  ),
                ),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: textInputAction,
                  onTap: onTap,
                  onChanged: onChanged,
                  style: const TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: _muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.only(top: 6, bottom: 3),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return IconButton(
                          onPressed: onClear,
                          tooltip: 'Clear ${label.toLowerCase()} location',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 34,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _muted,
                            size: 18,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (helperText?.trim().isNotEmpty == true)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      if (value.text != helperValue) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          helperText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _RouteField { from, to }

class _PlannerIconButton extends StatelessWidget {
  const _PlannerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent = _text,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: accent,
        backgroundColor: _surfaceRaised,
        fixedSize: const Size(46, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: _border),
        ),
      ),
      icon: Icon(icon, size: 21),
    );
  }
}
