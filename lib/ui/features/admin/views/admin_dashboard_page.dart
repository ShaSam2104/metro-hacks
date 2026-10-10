import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../../data/repositories/transit_reference_repository.dart';
import 'network_map.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    super.key,
    required this.session,
    required this.onLogout,
  });

  final MetroSession session;
  final VoidCallback onLogout;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _repository = TransitReferenceRepository();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _longName = TextEditingController();
  final _note = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  var _kind = 'station';
  var _operatorName = 'AMTS';
  var _status = 'active';
  var _loading = true;
  var _saving = false;
  String? _error;
  List<TransitReferenceItem> _items = const [];
  List<LatLng> _routeGeometry = [];

  bool get _isStation => _kind == 'station';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _longName.dispose();
    _note.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _repository.list(widget.session);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Network reference is unavailable.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_id.text.trim().isEmpty ||
        _name.text.trim().isEmpty ||
        (!_isStation && _longName.text.trim().isEmpty)) {
      setState(() => _error = 'Complete the required record fields.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isStation) {
        await _repository.saveStation(
          session: widget.session,
          id: _id.text.trim(),
          name: _name.text,
          status: _status,
          latitude: _latitude.text,
          longitude: _longitude.text,
        );
      } else {
        await _repository.saveRoute(
          session: widget.session,
          operatorName: _operatorName,
          id: _id.text.trim(),
          shortName: _name.text,
          longName: _longName.text,
          status: _status,
          note: _note.text,
          geometry: _routeGeometry
              .map(
                (point) => {
                  'latitude': point.latitude,
                  'longitude': point.longitude,
                },
              )
              .toList(),
        );
      }
      _clearForm();
      await _load();
    } on FormatException {
      setState(() => _error = 'Coordinates must be valid numbers.');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Could not save this change.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _edit(TransitReferenceItem item) {
    setState(() {
      _kind = item.entityType;
      _operatorName = item.operatorName == 'Metro' ? 'AMTS' : item.operatorName;
      _status = item.status;
      _id.text = item.payload['source_id'] as String? ?? item.id;
      _name.text =
          (item.payload[_isStation ? 'name' : 'short_name'] as String?) ?? '';
      _longName.text = (item.payload['long_name'] as String?) ?? '';
      _note.text = (item.payload['note'] as String?) ?? '';
      _latitude.text = item.payload['latitude']?.toString() ?? '';
      _longitude.text = item.payload['longitude']?.toString() ?? '';
      final geometry = item.payload['geometry'];
      _routeGeometry = geometry is List
          ? geometry
                .whereType<Map>()
                .map((point) {
                  final latitude = point['latitude'];
                  final longitude = point['longitude'];
                  return latitude is num && longitude is num
                      ? LatLng(latitude.toDouble(), longitude.toDouble())
                      : null;
                })
                .whereType<LatLng>()
                .toList()
          : [];
    });
  }

  Future<void> _delete(TransitReferenceItem item) async {
    try {
      await _repository.delete(session: widget.session, id: item.id);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  void _clearForm() {
    _id.clear();
    _name.clear();
    _longName.clear();
    _note.clear();
    _latitude.clear();
    _longitude.clear();
    _routeGeometry = [];
  }

  void setMapPosition(LatLng point) {
    setState(() {
      if (_isStation) {
        _latitude.text = point.latitude.toStringAsFixed(6);
        _longitude.text = point.longitude.toStringAsFixed(6);
      } else {
        _routeGeometry = [..._routeGeometry, point];
      }
    });
  }

  void clearRouteGeometry() => setState(() => _routeGeometry = []);

  void changeKind(String value) => setState(() {
    _kind = value;
    _status = 'active';
  });

  void changeOperator(String value) => setState(() => _operatorName = value);

  void changeStatus(String value) => setState(() => _status = value);

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 840;
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 20),
              child: Column(
                children: [
                  _AdminHeader(onLogout: widget.onLogout),
                  const SizedBox(height: 12),
                  const _NetworkLayersBand(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        SizedBox(
                          height: compact ? 300 : 410,
                          child: NetworkMap(
                            references: _items,
                            onMapTap: setMapPosition,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (compact) ...[
                          _Editor(state: this),
                          const SizedBox(height: 14),
                          _ReferenceList(state: this),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 398, child: _Editor(state: this)),
                              const SizedBox(width: 14),
                              Expanded(child: _ReferenceList(state: this)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.onLogout});
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            Icons.hub_outlined,
            color: theme.colorScheme.primaryForeground,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Network control', style: theme.textTheme.h3),
              Text('Operator workspace', style: theme.textTheme.muted),
            ],
          ),
        ),
        _RolePill(label: 'OPERATOR', color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Log out',
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }
}

class _NetworkLayersBand extends StatelessWidget {
  const _NetworkLayersBand();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final baseline = _LayerSummary(
      icon: Icons.train_outlined,
      label: 'Operational baseline',
      detail: 'Blue Line corridor + imported Metro, AMTS and BRTS stops',
      color: const Color(0xff1976d2),
    );
    final workspace = _LayerSummary(
      icon: Icons.edit_location_alt_outlined,
      label: 'Operator workspace',
      detail: 'Publish station locations and AMTS/BRTS route paths',
      color: theme.colorScheme.primary,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: narrow
          ? Column(children: [baseline, const Divider(height: 20), workspace])
          : Row(
              children: [
                Expanded(child: baseline),
                Container(
                  width: 1,
                  height: 38,
                  color: theme.colorScheme.border,
                ),
                const SizedBox(width: 16),
                Expanded(child: workspace),
              ],
            ),
    );
  }
}

class _LayerSummary extends StatelessWidget {
  const _LayerSummary({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: ShadTheme.of(context).textTheme.small),
            const SizedBox(height: 2),
            Text(detail, style: ShadTheme.of(context).textTheme.muted),
          ],
        ),
      ),
    ],
  );
}

class _Editor extends StatelessWidget {
  const _Editor({required this.state});
  final _AdminDashboardPageState state;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Publish an operational update', style: theme.textTheme.h4),
      description: const Text(
        'Add or update a Metro station, AMTS route, or BRTS route.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Record type', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            initialValue: state._kind,
            minWidth: double.infinity,
            selectedOptionBuilder: (_, value) =>
                Text(value == 'station' ? 'Metro station' : 'Route'),
            onChanged: (value) {
              if (value != null) state.changeKind(value);
            },
            options: const [
              ShadOption(value: 'station', child: Text('Metro station')),
              ShadOption(value: 'route', child: Text('Route')),
            ],
          ),
          const SizedBox(height: 12),
          if (!state._isStation) ...[
            Text('Operator', style: theme.textTheme.small),
            const SizedBox(height: 6),
            ShadSelect<String>(
              initialValue: state._operatorName,
              minWidth: double.infinity,
              selectedOptionBuilder: (_, value) => Text(value),
              onChanged: (value) {
                if (value != null) state.changeOperator(value);
              },
              options: const [
                ShadOption(value: 'AMTS', child: Text('AMTS')),
                ShadOption(value: 'BRTS', child: Text('BRTS')),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _Field(
            label: state._isStation ? 'Station ID' : 'Route ID',
            controller: state._id,
          ),
          _Field(
            label: state._isStation ? 'Station name' : 'Route short name',
            controller: state._name,
          ),
          if (!state._isStation)
            _Field(label: 'Route direction', controller: state._longName),
          if (state._isStation)
            Row(
              children: [
                Expanded(
                  child: _Field(
                    label: 'Latitude',
                    controller: state._latitude,
                    required: false,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Field(
                    label: 'Longitude',
                    controller: state._longitude,
                    required: false,
                  ),
                ),
              ],
            ),
          if (!state._isStation)
            _Field(
              label: 'Operational note',
              controller: state._note,
              required: false,
            ),
          if (!state._isStation) ...[
            Text(
              'Editable route path: ${state._routeGeometry.length} points',
              style: theme.textTheme.small,
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the map to trace the route.',
              style: theme.textTheme.muted,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.ghost(
                onPressed: state._routeGeometry.isEmpty
                    ? null
                    : state.clearRouteGeometry,
                child: const Text('Clear route path'),
              ),
            ),
          ],
          Text('Status', style: theme.textTheme.small),
          const SizedBox(height: 6),
          ShadSelect<String>(
            key: ValueKey('${state._kind}-${state._status}'),
            initialValue: state._status,
            minWidth: double.infinity,
            selectedOptionBuilder: (_, value) => Text(value),
            onChanged: (value) {
              if (value != null) state.changeStatus(value);
            },
            options: state._isStation
                ? const [
                    ShadOption(value: 'active', child: Text('Active')),
                    ShadOption(value: 'limited', child: Text('Limited')),
                    ShadOption(value: 'closed', child: Text('Closed')),
                  ]
                : const [
                    ShadOption(value: 'active', child: Text('Active')),
                    ShadOption(value: 'diverted', child: Text('Diverted')),
                    ShadOption(value: 'suspended', child: Text('Suspended')),
                  ],
          ),
          if (state._error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                state._error!,
                style: theme.textTheme.small.copyWith(
                  color: theme.colorScheme.destructive,
                ),
              ),
            ),
          const SizedBox(height: 14),
          ShadButton(
            onPressed: state._saving ? null : state._save,
            child: Text(state._saving ? 'Saving...' : 'Save network change'),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.required = true,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          required ? label : '$label (optional)',
          style: ShadTheme.of(context).textTheme.small,
        ),
        const SizedBox(height: 6),
        ShadInput(controller: controller),
      ],
    ),
  );
}

class _ReferenceList extends StatelessWidget {
  const _ReferenceList({required this.state});
  final _AdminDashboardPageState state;
  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ShadCard(
      title: Text('Published reference', style: theme.textTheme.h4),
      description: Text('${state._items.length} active network records'),
      child: state._loading
          ? const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator()),
            )
          : state._items.isEmpty
          ? SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'No operator changes published yet.',
                  style: theme.textTheme.muted,
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state._items.length,
              separatorBuilder: (_, _) => const Divider(height: 20),
              itemBuilder: (context, index) {
                final item = state._items[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.entityType == 'station'
                          ? Icons.train_outlined
                          : Icons.directions_bus_outlined,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: theme.textTheme.small),
                          const SizedBox(height: 3),
                          Text(
                            '${item.operatorName} · ${item.status}',
                            style: theme.textTheme.muted,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit record',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => state._edit(item),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Remove record',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => state._delete(item),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: theme.colorScheme.destructive,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .15),
      border: Border.all(color: color.withValues(alpha: .55)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: ShadTheme.of(context).textTheme.small.copyWith(color: color),
    ),
  );
}
