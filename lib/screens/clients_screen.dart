import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../dialogs/add_client_dialog.dart';
import '../models/client_model.dart';
import '../services/client_service.dart';
import 'client_details_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _showArchivedOnly = false;

  List<ClientModel> _allClients = [];
  List<ClientModel> _filteredClients = [];

  @override
  void initState() {
    super.initState();
    _loadClients();
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final clients = await ClientService.getClients(
        archivedOnly: _showArchivedOnly,
      );

      if (!mounted) return;

      setState(() {
        _allClients = clients;
        _filteredClients = clients;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load clients');
    }
  }

  Future<void> _restoreClient(ClientModel client) async {
    try {
      await ClientService.restoreClient(client.id);

      if (!mounted) return;

      await _loadClients();
      _showSnack('Client restored');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to restore client');
    }
  }

  Future<void> _openClientDetails(ClientModel client) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientDetailsScreen(client: client),
      ),
    );

    await _loadClients();
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _allClients.where((client) {
      final fullName = client.fullName.toLowerCase();
      final company = (client.companyName ?? '').toLowerCase();
      final email = (client.email ?? '').toLowerCase();
      final phone = (client.phone ?? '').toLowerCase();

      if (query.isEmpty) return true;

      return fullName.contains(query) ||
          company.contains(query) ||
          email.contains(query) ||
          phone.contains(query);
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredClients = filtered;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addClient() async {
    final created = await showAddClientDialog(context);

    if (created == null) return;

    await _loadClients();
    _showSnack('Client created');
  }

  Future<void> _editClient(ClientModel client) async {
    final updated = await showAddClientDialog(
      context,
      existingClient: client,
    );

    if (updated == null) return;

    await _loadClients();
    _showSnack('Client updated');
  }

  Future<void> _deleteClient(ClientModel client) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete client?'),
        content: Text(
          'Client "${client.fullName}" will be deleted.',
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
      await ClientService.deleteClient(client.id);

      if (!mounted) return;

      await _loadClients();
      _showSnack('Client deleted');
    } catch (e) {
      if (!mounted) return;

      final text = e.toString();

      if (text.contains('estimates_client_id_fkey')) {
        if (client.isArchived) {
          _showSnack('Cannot delete client: it is used in estimates');
          return;
        }

        final archive = await showCupertinoDialog<bool>(
          context: context,
          builder: (_) => CupertinoAlertDialog(
            title: const Text('Delete not available'),
            content: const Text(
              'This client is already used in estimates. Archive instead of deleting?',
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
          await ClientService.archiveClient(client.id);
          if (!mounted) return;
          await _loadClients();
          _showSnack('Client archived');
        }

        return;
      }

      _showSnack('Failed to delete client');
    }
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
          'Clients',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClient,
        backgroundColor: const Color(0xFF5B8CFF),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(CupertinoIcons.add),
        label: const Text(
          'New Client',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadClients,
          color: const Color(0xFF5B8CFF),
          backgroundColor: const Color(0xFF15161C),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _PremiumSearchField(
                  controller: _searchController,
                  hintText: _showArchivedOnly
                      ? 'Search archived client...'
                      : 'Search client...',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _ClientsModeButton(
                        label: 'Active',
                        selected: !_showArchivedOnly,
                        onTap: () async {
                          if (!_showArchivedOnly) return;
                          setState(() {
                            _showArchivedOnly = false;
                          });
                          await _loadClients();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ClientsModeButton(
                        label: 'Archived',
                        selected: _showArchivedOnly,
                        onTap: () async {
                          if (_showArchivedOnly) return;
                          setState(() {
                            _showArchivedOnly = true;
                          });
                          await _loadClients();
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
                    : _filteredClients.isEmpty
                    ? const _EmptyClientsState()
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: _filteredClients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final client = _filteredClients[index];

                    return _ClientCard(
                      client: client,
                      onOpen: () => _openClientDetails(client),
                      onEdit: () => _editClient(client),
                      onDelete: () => _deleteClient(client),
                      onRestore: client.isArchived
                          ? () => _restoreClient(client)
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

class _ClientCard extends StatelessWidget {
  final ClientModel client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onOpen;
  final VoidCallback? onRestore;

  const _ClientCard({
    required this.client,
    required this.onEdit,
    required this.onDelete,
    required this.onOpen,
    this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final company = (client.companyName ?? '').trim();
    final email = (client.email ?? '').trim();
    final phone = (client.phone ?? '').trim();

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
            client.fullName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (client.isArchived) ...[
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
          if (company.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              company,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (email.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ClientInfoRow(
              icon: CupertinoIcons.mail,
              text: email,
            ),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ClientInfoRow(
              icon: CupertinoIcons.phone,
              text: phone,
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
                  icon: client.isArchived
                      ? CupertinoIcons.arrow_uturn_left
                      : CupertinoIcons.pencil,
                  label: client.isArchived ? 'Restore' : 'Edit',
                  onTap: client.isArchived ? (onRestore ?? onOpen) : onEdit,
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

class _ClientInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ClientInfoRow({
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

class _EmptyClientsState extends StatelessWidget {
  const _EmptyClientsState();

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
                CupertinoIcons.person_2,
                color: Colors.white,
                size: 32,
              ),
              SizedBox(height: 18),
              Text(
                'No clients yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Create your first client and the database will start filling up.',
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

class _ClientsModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ClientsModeButton({
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