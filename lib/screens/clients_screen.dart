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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(150),
        child: _ClientsTopBar(
          searchController: _searchController,
          showArchivedOnly: _showArchivedOnly,
          clientsCount: _filteredClients.length,
          onBack: () => Navigator.of(context).maybePop(),
          onAddClient: _addClient,
          onShowActive: () async {
            if (!_showArchivedOnly) return;

            setState(() {
              _showArchivedOnly = false;
            });

            await _loadClients();
          },
          onShowArchived: () async {
            if (_showArchivedOnly) return;

            setState(() {
              _showArchivedOnly = true;
            });

            await _loadClients();
          },
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
              Expanded(
                child: _isLoading
                    ? const Center(
                  child: CupertinoActivityIndicator(radius: 16),
                )
                    : _filteredClients.isEmpty
                    ? const _EmptyClientsState()
                    : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 120),
                  children: [
                    _ClientsListPanel(
                      children: List.generate(_filteredClients.length, (index) {
                        final client = _filteredClients[index];

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == _filteredClients.length - 1 ? 0 : 12,
                          ),
                          child: _ClientCard(
                            client: client,
                            onOpen: () => _openClientDetails(client),
                            onEdit: () => _editClient(client),
                            onDelete: () => _deleteClient(client),
                            onRestore: client.isArchived
                                ? () => _restoreClient(client)
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

class _ClientsTopBar extends StatelessWidget {
  final TextEditingController searchController;
  final bool showArchivedOnly;
  final int clientsCount;
  final VoidCallback onBack;
  final VoidCallback onAddClient;
  final Future<void> Function() onShowActive;
  final Future<void> Function() onShowArchived;

  const _ClientsTopBar({
    required this.searchController,
    required this.showArchivedOnly,
    required this.clientsCount,
    required this.onBack,
    required this.onAddClient,
    required this.onShowActive,
    required this.onShowArchived,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = showArchivedOnly
        ? '$clientsCount archived clients'
        : '$clientsCount active clients';

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: const Color(0xFF242730),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: const Color(0xFF343846),
              width: 1,
            ),
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
                        border: Border.all(
                          color: const Color(0xFF3A3E4B),
                          width: 1,
                        ),
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
                          'Clients',
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
                    child: _ClientsInlineSearchField(
                      controller: searchController,
                      hintText: showArchivedOnly
                          ? 'Search archived...'
                          : 'Search client...',
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ClientsToolbarButton(
                    icon: CupertinoIcons.person_2_fill,
                    selected: !showArchivedOnly,
                    onTap: () => onShowActive(),
                  ),
                  const SizedBox(width: 8),
                  _ClientsToolbarButton(
                    icon: CupertinoIcons.archivebox_fill,
                    selected: showArchivedOnly,
                    onTap: () => onShowArchived(),
                  ),
                  const SizedBox(width: 8),
                  _ClientsToolbarButton(
                    icon: CupertinoIcons.plus,
                    selected: false,
                    accent: true,
                    onTap: onAddClient,
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

class _ClientsListPanel extends StatelessWidget {
  final List<Widget> children;

  const _ClientsListPanel({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF262C37), // светлее родитель
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
      child: Column(
        children: children,
      ),
    );
  }
}

class _ClientsInlineSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;

  const _ClientsInlineSearchField({
    required this.controller,
    required this.hintText,
  });

  @override
  State<_ClientsInlineSearchField> createState() =>
      _ClientsInlineSearchFieldState();
}

class _ClientsInlineSearchFieldState extends State<_ClientsInlineSearchField> {
  late final FocusNode _focusNode;

  bool get _showClear =>
      _focusNode.hasFocus && widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
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
        color: const Color(0xFF202530), // НЕ чёрный
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF3A4050),
          width: 1.15,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        cursorColor: const Color(0xFF38BDF8),
        style: const TextStyle(
          color: Color(0xFFF3F6FC),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
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
          suffixIcon: _showClear
              ? GestureDetector(
            onTap: () {
              widget.controller.clear();
              _focusNode.requestFocus();
            },
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              color: Color(0xFF9AA3B7),
              size: 18,
            ),
          )
              : null,
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

class _ClientsToolbarButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final bool accent;
  final VoidCallback onTap;

  const _ClientsToolbarButton({
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
          color: const Color(0xFF202530), // НЕ чёрная кнопка
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
    final archived = client.isArchived;
    final company = (client.companyName ?? '').trim();
    final email = (client.email ?? '').trim();
    final phone = (client.phone ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: archived
            ? const Color(0xFF1B2028)
            : const Color(0xFF1E2430), // чуть темнее panel
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
              _ClientAvatar(
                name: client.fullName,
                archived: archived,
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (company.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        company,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFA0A7B8),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),
              _ClientStateChip(archived: archived),
            ],
          ),

          if (email.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ClientInfoRow(
              icon: CupertinoIcons.mail,
              text: email,
              archived: archived,
            ),
          ],

          if (phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ClientInfoRow(
              icon: CupertinoIcons.phone,
              text: phone,
              archived: archived,
            ),
          ],

          const SizedBox(height: 18),

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

class _ClientAvatar extends StatelessWidget {
  final String name;
  final bool archived;

  const _ClientAvatar({
    required this.name,
    required this.archived,
  });

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'CL';

    if (parts.length == 1) {
      final one = parts.first;
      return one.length >= 2
          ? one.substring(0, 2).toUpperCase()
          : one.toUpperCase();
    }

    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: archived
            ? const Color(0xFF222631)
            : const Color(0xFF202530),
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
      child: Text(
        _initials,
        style: TextStyle(
          color: archived
              ? const Color(0xFFA0A7B8)
              : const Color(0xFFD6DCE8),
          fontSize: 17,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ClientStateChip extends StatelessWidget {
  final bool archived;

  const _ClientStateChip({
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
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 12,
            offset: const Offset(0, 7),
          ),
        ],
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

class _ClientInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool archived;

  const _ClientInfoRow({
    required this.icon,
    required this.text,
    required this.archived,
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
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF222731),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF383F4D),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFB8C1D9),
              size: 15,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE8ECF4),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
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
            Icon(
              icon,
              color: tone,
              size: 16,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tone,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
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