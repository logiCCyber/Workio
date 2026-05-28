import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../dialogs/add_property_dialog.dart';
import '../models/client_model.dart';
import '../models/property_model.dart';
import '../services/client_service.dart';
import '../services/property_service.dart';
import 'property_details_screen.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key});

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _showArchivedOnly = false;

  List<PropertyModel> _allProperties = [];
  List<PropertyModel> _filteredProperties = [];
  List<ClientModel> _clients = [];

  final Map<String, ClientModel> _clientsById = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        PropertyService.getProperties(
          archivedOnly: _showArchivedOnly,
        ),
        ClientService.getClients(),
      ]);

      final properties = results[0] as List<PropertyModel>;
      final clients = results[1] as List<ClientModel>;

      _clientsById
        ..clear()
        ..addEntries(clients.map((e) => MapEntry(e.id, e)));

      if (!mounted) return;

      setState(() {
        _allProperties = properties;
        _filteredProperties = properties;
        _clients = clients;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load properties');
    }
  }

  Future<void> _openPropertyDetails(PropertyModel property) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyDetailsScreen(property: property),
      ),
    );

    await _loadData();
  }

  Future<void> _restoreProperty(PropertyModel property) async {
    try {
      await PropertyService.restoreProperty(property.id);

      if (!mounted) return;

      await _loadData();
      _showSnack('Property restored');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to restore property');
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _allProperties.where((property) {
      final clientName =
      (_clientsById[property.clientId]?.fullName ?? '').toLowerCase();
      final address = property.addressLine1.toLowerCase();
      final address2 = (property.addressLine2 ?? '').toLowerCase();
      final city = (property.city ?? '').toLowerCase();
      final province = (property.province ?? '').toLowerCase();
      final postalCode = (property.postalCode ?? '').toLowerCase();
      final propertyType = (property.propertyType ?? '').toLowerCase();

      if (query.isEmpty) return true;

      return clientName.contains(query) ||
          address.contains(query) ||
          address2.contains(query) ||
          city.contains(query) ||
          province.contains(query) ||
          postalCode.contains(query) ||
          propertyType.contains(query);
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredProperties = filtered;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addProperty() async {
    if (_clients.isEmpty) {
      _showSnack('Create at least one client first');
      return;
    }

    final selectedClient = await _selectClient();
    if (selectedClient == null) return;

    final created = await showAddPropertyDialog(
      context,
      clientId: selectedClient.id,
    );

    if (created == null) return;

    await _loadData();
    _showSnack('Property created');
  }

  Future<void> _editProperty(PropertyModel property) async {
    final updated = await showAddPropertyDialog(
      context,
      clientId: property.clientId,
      existingProperty: property,
    );

    if (updated == null) return;

    await _loadData();
    _showSnack('Property updated');
  }

  Future<void> _deleteProperty(PropertyModel property) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete property?'),
        content: Text(
          'Property "${property.addressLine1}" will be deleted.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await PropertyService.deleteProperty(property.id);

      if (!mounted) return;

      await _loadData();
      _showSnack('Property deleted');
    } catch (e) {
      if (!mounted) return;

      final text = e.toString();

      if (text.contains('estimates_property_id_fkey') ||
          text.contains('invoices_property_id_fkey')) {
        if (property.isArchived) {
          _showSnack('Cannot delete property: it is used in estimates or invoices');
          return;
        }

        final archive = await showCupertinoDialog<bool>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Cannot delete'),
            content: const Text(
              'This property is already used in estimates or invoices. Archive it instead of deleting?',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Archive'),
              ),
            ],
          ),
        );

        if (archive == true) {
          await PropertyService.archiveProperty(property.id);

          if (!mounted) return;

          await _loadData();
          _showSnack('Property archived');
        }

        return;
      }

      _showSnack('Failed to delete property');
    }
  }

  Future<ClientModel?> _selectClient() async {
    return showModalBottomSheet<ClientModel>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _ClientSelectionSheet(
          clients: _clients,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);

    return Scaffold(
      backgroundColor: background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(150),
        child: _PropertiesTopBar(
          searchController: _searchController,
          showArchivedOnly: _showArchivedOnly,
          propertiesCount: _filteredProperties.length,
          onBack: () => Navigator.of(context).maybePop(),
          onAddProperty: _addProperty,
          onShowActive: () async {
            if (!_showArchivedOnly) return;

            setState(() {
              _showArchivedOnly = false;
            });

            await _loadData();
          },
          onShowArchived: () async {
            if (_showArchivedOnly) return;

            setState(() {
              _showArchivedOnly = true;
            });

            await _loadData();
          },
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF5B8CFF),
          backgroundColor: const Color(0xFF15161C),
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(
                  child: CupertinoActivityIndicator(radius: 16),
                )
                    : _filteredProperties.isEmpty
                    ? const _EmptyPropertiesState()
                    : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
                  children: [
                    _PropertiesListPanel(
                      children: List.generate(_filteredProperties.length, (index) {
                        final property = _filteredProperties[index];
                        final client = _clientsById[property.clientId];

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == _filteredProperties.length - 1 ? 0 : 12,
                          ),
                          child: _PropertyCard(
                            property: property,
                            clientName: client?.fullName ?? 'No client',
                            onOpen: () => _openPropertyDetails(property),
                            onEdit: () => _editProperty(property),
                            onDelete: () => _deleteProperty(property),
                            onRestore: property.isArchived
                                ? () => _restoreProperty(property)
                                : null,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertiesTopBar extends StatelessWidget {
  final TextEditingController searchController;
  final bool showArchivedOnly;
  final int propertiesCount;
  final VoidCallback onBack;
  final VoidCallback onAddProperty;
  final Future<void> Function() onShowActive;
  final Future<void> Function() onShowArchived;

  const _PropertiesTopBar({
    required this.searchController,
    required this.showArchivedOnly,
    required this.propertiesCount,
    required this.onBack,
    required this.onAddProperty,
    required this.onShowActive,
    required this.onShowArchived,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = showArchivedOnly
        ? '$propertiesCount archived properties'
        : '$propertiesCount active properties';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: const Color(0xFF242730),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF343846)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.38),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.035),
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: onBack,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2D36),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF3A3E4B)),
                      ),
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Color(0xFFF3F6FC),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Properties',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFFF4F6FA),
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFA0A7B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _PremiumSearchField(
                      controller: searchController,
                      hintText: showArchivedOnly
                          ? 'Search archived...'
                          : 'Search property...',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PropertiesToolbarButton(
                    icon: CupertinoIcons.house_fill,
                    selected: !showArchivedOnly,
                    onTap: () => onShowActive(),
                  ),
                  const SizedBox(width: 8),
                  _PropertiesToolbarButton(
                    icon: CupertinoIcons.archivebox_fill,
                    selected: showArchivedOnly,
                    onTap: () => onShowArchived(),
                  ),
                  const SizedBox(width: 8),
                  _PropertiesToolbarButton(
                    icon: CupertinoIcons.plus,
                    selected: false,
                    accent: true,
                    onTap: onAddProperty,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertiesToolbarButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final bool accent;
  final VoidCallback onTap;

  const _PropertiesToolbarButton({
    required this.icon,
    required this.selected,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent || selected
        ? const Color(0xFF38BDF8)
        : const Color(0xFFB8C1D9);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFF202530),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF3A4050),
            width: 1.15,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.26),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.025),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: color,
          size: accent ? 22 : 20,
        ),
      ),
    );
  }
}

class _PropertiesListPanel extends StatelessWidget {
  final List<Widget> children;

  const _PropertiesListPanel({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF262C37),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF3D4555),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _PremiumSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;

  const _PremiumSearchField({
    required this.controller,
    required this.hintText,
  });

  @override
  State<_PremiumSearchField> createState() => _PremiumSearchFieldState();
}

class _PremiumSearchFieldState extends State<_PremiumSearchField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
      _focusNode.hasFocus && widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _PremiumSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearText() {
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF202530),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3A4050),
          width: 1.15,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: const TextStyle(
          color: Color(0xFFF3F6FC),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        cursorColor: const Color(0xFF38BDF8),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF9AA3B7),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            CupertinoIcons.search,
            color: Color(0xFFB8C1D9),
            size: 20,
          ),
          suffixIcon: _showClearButton
              ? GestureDetector(
            onTap: _clearText,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Color(0xFF9AA3B7),
              size: 18,
            ),
          )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  final PropertyModel property;
  final String clientName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpen;
  final VoidCallback? onRestore;

  const _PropertyCard({
    required this.property,
    required this.clientName,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final archived = property.isArchived;
    final type = (property.propertyType ?? '').trim();
    final sqft = property.squareFootage;
    final city = (property.city ?? '').trim();
    final province = (property.province ?? '').trim();
    final postal = (property.postalCode ?? '').trim();
    final address2 = (property.addressLine2 ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: archived
            ? const Color(0xFF1B2028)
            : const Color(0xFF1E2430),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: archived
              ? const Color(0xFF313847)
              : const Color(0xFF384152),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.38),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.035),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PropertyAvatar(archived: archived),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.addressLine1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA0A7B8),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _PropertyStateChip(archived: archived),
            ],
          ),

          if (address2.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PropertyInfoRow(
              icon: CupertinoIcons.location,
              text: address2,
            ),
          ],

          if (city.isNotEmpty || province.isNotEmpty || postal.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PropertyInfoRow(
              icon: CupertinoIcons.map,
              text: [
                if (city.isNotEmpty) city,
                if (province.isNotEmpty) province,
                if (postal.isNotEmpty) postal,
              ].join(', '),
            ),
          ],

          if (type.isNotEmpty || sqft > 0) ...[
            const SizedBox(height: 8),
            _PropertyInfoRow(
              icon: CupertinoIcons.square_grid_2x2,
              text: [
                if (type.isNotEmpty) type,
                if (sqft > 0) '${sqft.toStringAsFixed(0)} sqft',
              ].join(' • '),
            ),
          ],

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _CardActionButton(
                  icon: CupertinoIcons.eye,
                  label: 'Open',
                  tone: const Color(0xFF7EA7FF),
                  borderTone: const Color(0xFF3B5282),
                  backgroundTone: const Color(0xFF182235),
                  onTap: onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardActionButton(
                  icon: archived
                      ? CupertinoIcons.arrow_uturn_left
                      : CupertinoIcons.pencil,
                  label: archived ? 'Restore' : 'Edit',
                  tone: const Color(0xFFD6DCE8),
                  borderTone: const Color(0xFF444B59),
                  backgroundTone: const Color(0xFF202530),
                  onTap: archived ? (onRestore ?? onOpen) : onEdit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardActionButton(
                  icon: CupertinoIcons.trash,
                  label: 'Delete',
                  tone: const Color(0xFFFF6B6B),
                  borderTone: const Color(0xFF704047),
                  backgroundTone: const Color(0xFF2A1F25),
                  onTap: onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PropertyAvatar extends StatelessWidget {
  final bool archived;

  const _PropertyAvatar({
    required this.archived,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF202530),
        border: Border.all(
          color: archived
              ? const Color(0xFF353B49)
              : const Color(0xFF3A4050),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.035),
            blurRadius: 7,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Icon(
        archived ? CupertinoIcons.archivebox : CupertinoIcons.house_fill,
        color: archived
            ? const Color(0xFFA0A7B8)
            : const Color(0xFFD6DCE8),
        size: 22,
      ),
    );
  }
}

class _PropertyStateChip extends StatelessWidget {
  final bool archived;

  const _PropertyStateChip({
    required this.archived,
  });

  @override
  Widget build(BuildContext context) {
    final color = archived
        ? const Color(0xFFA0A7B8)
        : const Color(0xFF72D88A);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF20242D),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: archived
              ? const Color(0xFF3A4050)
              : const Color(0xFF315C3C),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            archived ? 'Archived' : 'Active',
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PropertyInfoRow({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF303645),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 7,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFFB8C1D9),
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE8ECF4),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Icon(
            CupertinoIcons.chevron_right,
            color: Color(0xFF8E93A6),
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tone;
  final Color borderTone;
  final Color backgroundTone;
  final VoidCallback onTap;

  const _CardActionButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.borderTone,
    required this.backgroundTone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: backgroundTone,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderTone,
            width: 1.15,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.32),
              blurRadius: 16,
              offset: const Offset(0, 9),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.028),
              blurRadius: 7,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: tone, size: 16),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientSelectionSheet extends StatelessWidget {
  final List<ClientModel> clients;

  const _ClientSelectionSheet({
    required this.clients,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3D49),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select client',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF262832), height: 1),
            Expanded(
              child: clients.isEmpty
                  ? const Center(
                child: Text(
                  'Empty',
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: clients.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final client = clients[index];
                  final company = (client.companyName ?? '').trim();

                  return Material(
                    color: const Color(0xFF101117),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(context, client),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF23252E),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              client.fullName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (company.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                company,
                                style: const TextStyle(
                                  color: Color(0xFF8E93A6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPropertiesState extends StatelessWidget {
  const _EmptyPropertiesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF15161C),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFF262832)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.location_solid,
                color: Colors.white,
                size: 32,
              ),
              SizedBox(height: 18),
              Text(
                'No properties yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Create the first property and addresses will start appearing.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}