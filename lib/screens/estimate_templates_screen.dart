import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/estimate_template_model.dart';
import '../services/estimate_template_service.dart';
import '../utils/estimate_formatters.dart';

class EstimateTemplatesScreen extends StatefulWidget {
  const EstimateTemplatesScreen({super.key});

  @override
  State<EstimateTemplatesScreen> createState() => _EstimateTemplatesScreenState();
}

class _EstimateTemplatesScreenState extends State<EstimateTemplatesScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  List<EstimateTemplateModel> _allTemplates = [];
  List<EstimateTemplateModel> _filteredTemplates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilters);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final templates = await EstimateTemplateService.getTemplates();

      if (!mounted) return;

      setState(() {
        _allTemplates = templates;
        _filteredTemplates = templates;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load templates');
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _allTemplates.where((template) {
      final name = template.name.toLowerCase();
      final serviceType = (template.serviceType ?? '').toLowerCase();
      final scope = (template.defaultScopeText ?? '').toLowerCase();

      if (query.isEmpty) return true;

      return name.contains(query) ||
          serviceType.contains(query) ||
          scope.contains(query);
    }).toList();

    if (!mounted) return;

    setState(() {
      _filteredTemplates = filtered;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openTemplateEditor({EstimateTemplateModel? template}) async {
    final nameController = TextEditingController(text: template?.name ?? '');
    final serviceTypeController =
    TextEditingController(text: template?.serviceType ?? '');
    final scopeController =
    TextEditingController(text: template?.defaultScopeText ?? '');
    final notesController =
    TextEditingController(text: template?.defaultNotes ?? '');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  template == null ? 'New Template' : 'Edit Template',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                _PremiumTextField(
                  controller: nameController,
                  label: 'Template Name',
                  hintText: 'Basic Service Template',
                ),
                const SizedBox(height: 12),
                _PremiumTextField(
                  controller: serviceTypeController,
                  label: 'Service Type',
                  hintText: 'service_type',
                ),
                const SizedBox(height: 12),
                _PremiumTextField(
                  controller: scopeController,
                  label: 'Default Scope',
                  hintText: 'Describe the default work scope for this service...',
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                _PremiumTextField(
                  controller: notesController,
                  label: 'Default Notes',
                  hintText: 'Default notes, exclusions, materials, or conditions...',
                  maxLines: 4,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: const Color(0xFF5B8CFF),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: _isSaving
                        ? null
                        : () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;

                      Navigator.pop(context, true);
                    },
                    child: Text(
                      template == null ? 'Continue' : 'Save Changes',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == true) {
      setState(() {
        _isSaving = true;
      });

      try {
        final data = EstimateTemplateModel(
          id: template?.id ?? '',
          adminAuthId: '',
          name: nameController.text.trim(),
          serviceType: serviceTypeController.text.trim().isEmpty
              ? null
              : serviceTypeController.text.trim(),
          defaultScopeText: scopeController.text.trim().isEmpty
              ? null
              : scopeController.text.trim(),
          defaultNotes: notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          createdAt: template?.createdAt,
          updatedAt: template?.updatedAt,
        );

        if (template == null) {
          await EstimateTemplateService.createTemplate(data);
          _showSnack('Template created');
        } else {
          await EstimateTemplateService.updateTemplate(data);
          _showSnack('Template updated');
        }

        await _loadTemplates();
      } catch (e) {
        _showSnack('Failed to save template');
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
    }
  }

  Future<void> _deleteTemplate(EstimateTemplateModel template) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete template?'),
        content: Text(
          'Template "${template.name}" will be deleted.',
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
      await EstimateTemplateService.deleteTemplate(template.id);
      _showSnack('Template deleted');
      await _loadTemplates();
    } catch (e) {
      _showSnack('Failed to delete template');
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
          'Templates',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadTemplates,
            icon: const Icon(CupertinoIcons.refresh, color: Colors.white),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTemplateEditor(),
        backgroundColor: const Color(0xFF5B8CFF),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: const Icon(CupertinoIcons.add),
        label: const Text(
          'New Template',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _loadTemplates,
          color: const Color(0xFF5B8CFF),
          backgroundColor: const Color(0xFF15161C),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _PremiumSearchField(
                  controller: _searchController,
                  hintText: 'Search templates...',
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(
                  child: CupertinoActivityIndicator(radius: 16),
                )
                    : _filteredTemplates.isEmpty
                    ? const _EmptyTemplatesState()
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  itemCount: _filteredTemplates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final template = _filteredTemplates[index];

                    return _TemplateCard(
                      template: template,
                      onEdit: () => _openTemplateEditor(template: template),
                      onDelete: () => _deleteTemplate(template),
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

class _TemplateCard extends StatelessWidget {
  final EstimateTemplateModel template;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final serviceType = EstimateFormatters.safeText(
      template.serviceType,
      fallback: 'No service type',
    );

    final scope = EstimateFormatters.safeText(
      template.defaultScopeText,
      fallback: 'No default scope',
    );

    final notes = EstimateFormatters.safeText(
      template.defaultNotes,
      fallback: 'No notes',
    );

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
            template.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            serviceType,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _TemplateInfoBlock(
            label: 'Scope',
            value: scope,
          ),
          const SizedBox(height: 10),
          _TemplateInfoBlock(
            label: 'Notes',
            value: notes,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: CupertinoIcons.pencil,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
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

class _TemplateInfoBlock extends StatelessWidget {
  final String label;
  final String value;

  const _TemplateInfoBlock({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
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

class _PremiumTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  State<_PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<_PremiumTextField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
      widget.maxLines == 1 &&
          _focusNode.hasFocus &&
          widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _PremiumTextField oldWidget) {
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
    final isSingleLine = widget.maxLines == 1;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment:
              isSingleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    keyboardType: widget.keyboardType,
                    maxLines: widget.maxLines,
                    minLines: isSingleLine ? 1 : widget.maxLines,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    cursorColor: const Color(0xFF5B8CFF),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        color: Color(0xFF697086),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_showClearButton) ...[
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _clearText,
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Color(0xFF8E93A6),
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTemplatesState extends StatelessWidget {
  const _EmptyTemplatesState();

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFF1B1D25),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  CupertinoIcons.square_stack_3d_up,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No templates yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create your first reusable template for any service type.',
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