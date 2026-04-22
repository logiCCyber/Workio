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

      _showSnack('Не удалось загрузить объекты');
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
      _showSnack('Объект восстановлен');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при восстановлении объекта');
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
      _showSnack('Сначала создай хотя бы одного клиента');
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
    _showSnack('Объект создан');
  }

  Future<void> _editProperty(PropertyModel property) async {
    final updated = await showAddPropertyDialog(
      context,
      clientId: property.clientId,
      existingProperty: property,
    );

    if (updated == null) return;

    await _loadData();
    _showSnack('Объект обновлён');
  }

  Future<void> _deleteProperty(PropertyModel property) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Удалить объект?'),
        content: Text(
          'Объект "${property.addressLine1}" будет удалён.',
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
      _showSnack('Объект удалён');
    } catch (e) {
      if (!mounted) return;

      final text = e.toString();

      if (text.contains('estimates_property_id_fkey') ||
          text.contains('invoices_property_id_fkey')) {
        if (property.isArchived) {
          _showSnack('Нельзя удалить объект: он используется в estimates или invoices');
          return;
        }

        final archive = await showCupertinoDialog<bool>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Удаление невозможно'),
            content: const Text(
              'Объект уже используется в estimates или invoices. Архивировать вместо удаления?',
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
          _showSnack('Объект архивирован');
        }

        return;
      }

      _showSnack('Ошибка при удалении объекта');
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
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Properties',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProperty,
        backgroundColor: const Color(0xFF5B8CFF),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(CupertinoIcons.add),
        label: const Text(
          'New Property',
          style: TextStyle(fontWeight: FontWeight.w600),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _PremiumSearchField(
                  controller: _searchController,
                  hintText: _showArchivedOnly
                      ? 'Поиск архивного объекта...'
                      : 'Поиск объекта...',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _PropertiesModeButton(
                        label: 'Active',
                        selected: !_showArchivedOnly,
                        onTap: () async {
                          if (!_showArchivedOnly) return;

                          setState(() {
                            _showArchivedOnly = false;
                          });

                          await _loadData();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PropertiesModeButton(
                        label: 'Archived',
                        selected: _showArchivedOnly,
                        onTap: () async {
                          if (_showArchivedOnly) return;

                          setState(() {
                            _showArchivedOnly = true;
                          });

                          await _loadData();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                  child: CupertinoActivityIndicator(radius: 16),
                )
                    : _filteredProperties.isEmpty
                    ? const _EmptyPropertiesState()
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: _filteredProperties.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final property = _filteredProperties[index];
                    final client = _clientsById[property.clientId];

                    return _PropertyCard(
                      property: property,
                      clientName: client?.fullName ?? 'Без клиента',
                      onOpen: () => _openPropertyDetails(property),
                      onEdit: () => _editProperty(property),
                      onDelete: () => _deleteProperty(property),
                      onRestore: property.isArchived
                          ? () => _restoreProperty(property)
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF262832),
          width: 1,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        cursorColor: const Color(0xFF5B8CFF),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF8E93A6),
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: const Icon(
            CupertinoIcons.search,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          suffixIcon: _showClearButton
              ? GestureDetector(
            onTap: _clearText,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Color(0xFF8E93A6),
              size: 18,
            ),
          )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
    final type = (property.propertyType ?? '').trim();
    final sqft = property.squareFootage;
    final city = (property.city ?? '').trim();
    final province = (property.province ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            property.addressLine1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (property.isArchived) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2D36),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF3A3D46)),
              ),
              child: const Text(
                'Archived',
                style: TextStyle(
                  color: Color(0xFFB6BCD0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if ((property.addressLine2 ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              property.addressLine2!,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _PropertyInfoRow(
            icon: CupertinoIcons.person,
            text: clientName,
          ),
          if (city.isNotEmpty || province.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PropertyInfoRow(
              icon: CupertinoIcons.location,
              text: [city, province]
                  .where((e) => e.trim().isNotEmpty)
                  .join(', '),
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
                  onTap: onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardActionButton(
                  icon: property.isArchived
                      ? CupertinoIcons.arrow_uturn_left
                      : CupertinoIcons.pencil,
                  label: property.isArchived ? 'Restore' : 'Edit',
                  onTap: property.isArchived ? (onRestore ?? onOpen) : onEdit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CardActionButton(
                  icon: CupertinoIcons.trash,
                  label: 'Delete',
                  onTap: onDelete,
                  color: const Color(0xFFE05A5A),
                ),
              ),
            ],
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
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xFFB6BCD0),
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _CardActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFFB6BCD0);

    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: effectiveColor, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: effectiveColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
              'Выбери клиента',
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
                  'Пусто',
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
                'Пока нет объектов',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Создай первый объект и адреса начнут заполняться.',
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

class _PropertiesModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PropertiesModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF5B8CFF)
          : const Color(0xFF15161C),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5B8CFF)
                  : const Color(0xFF262832),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}