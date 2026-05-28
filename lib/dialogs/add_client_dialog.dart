import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import '../models/client_model.dart';
import '../services/client_service.dart';

const _kClientAccent = Color(0xFF38BDF8);
const _kClientSheet = Color(0xFF1F232C);
const _kClientInput = Color(0xFF1B2028);
const _kClientInputBorder = Color(0xFF3A4050);
const _kClientIcon = Color(0xFF3B82F6);

Future<ClientModel?> showAddClientDialog(
    BuildContext context, {
      ClientModel? existingClient,
    }) {
  return showModalBottomSheet<ClientModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _AddClientDialogContent(
      existingClient: existingClient,
    ),
  );
}

class _AddClientDialogContent extends StatefulWidget {
  final ClientModel? existingClient;

  const _AddClientDialogContent({
    this.existingClient,
  });

  @override
  State<_AddClientDialogContent> createState() => _AddClientDialogContentState();
}

class _AddClientDialogContentState extends State<_AddClientDialogContent> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSaving = false;
  bool _isPhoneValid = true;
  String? _normalizedPhoneNumber;

  @override
  void dispose() {
    _fullNameController.dispose();
    _companyNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    final existing = widget.existingClient;
    if (existing != null) {
      _fullNameController.text = existing.fullName;
      _companyNameController.text = existing.companyName ?? '';
      _emailController.text = existing.email ?? '';
      final existingPhone = existing.phone ?? '';
      _phoneController.text = _formatPhoneDisplay(existingPhone);
      _normalizedPhoneNumber = _normalizePhoneForSave(existingPhone);
      _notesController.text = existing.notes ?? '';
    }

    _normalizedPhoneNumber =
    _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();
  }

  Future<void> _handlePhoneChanged(String rawValue) async {
    final formatted = _formatPhoneDisplay(rawValue);

    if (_phoneController.text != formatted) {
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final normalized = _normalizePhoneForSave(formatted);
    final digits = normalized.replaceAll(RegExp(r'[^0-9]'), '');

    setState(() {
      _normalizedPhoneNumber = normalized.isEmpty ? null : normalized;
      _isPhoneValid = digits.isEmpty || digits.length >= 10;
    });
  }

  String _normalizePhoneForSave(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';

    if (digits.length == 10) {
      return '+1$digits';
    }

    if (digits.length == 11 && digits.startsWith('1')) {
      return '+$digits';
    }

    if (raw.trim().startsWith('+')) {
      return '+$digits';
    }

    return '+1$digits';
  }

  String _formatPhoneDisplay(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return '';

    // Canada / USA format
    final local = digits.length == 11 && digits.startsWith('1')
        ? digits.substring(1)
        : digits;

    if (local.length <= 3) {
      return '+1 $local';
    }

    if (local.length <= 6) {
      return '+1 ${local.substring(0, 3)}-${local.substring(3)}';
    }

    if (local.length <= 10) {
      return '+1 ${local.substring(0, 3)}-${local.substring(3, 6)}-${local.substring(6)}';
    }

    // other countries typed with +
    if (trimmed.startsWith('+')) {
      return '+$digits';
    }

    return '+$digits';
  }

  Future<void> _saveClient() async {
    final fullName = _fullNameController.text.trim();
    final companyName = _companyNameController.text.trim();
    final email = _emailController.text.trim();
    final phone = (_normalizedPhoneNumber ?? _phoneController.text).trim();
    final notes = _notesController.text.trim();

    if (phone.isNotEmpty && !_isPhoneValid) {
      _showSnack('Enter valid phone number');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final existing = widget.existingClient;

    final payload = ClientModel(
      id: existing?.id ?? '',
      adminAuthId: existing?.adminAuthId ?? '',
      fullName: fullName,
      companyName: companyName.isEmpty ? null : companyName,
      email: email.isEmpty ? null : email,
      phone: phone.isEmpty ? null : phone,
      notes: notes.isEmpty ? null : notes,
      createdAt: existing?.createdAt,
      updatedAt: existing?.updatedAt,
    );

    final saved = existing == null
        ? await ClientService.createClient(payload)
        : await ClientService.updateClient(payload);

    if (!mounted) return;
    Navigator.pop(context, saved);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existingClient == null ? 'New Client' : 'Edit Client';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            color: _kClientSheet,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _kClientInputBorder,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.42),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.025),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
                    onPressed: () => Navigator.pop(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF202530),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _kClientInputBorder),
                      ),
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Color(0xFFF3F6FC),
                        size: 24,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),

              const SizedBox(height: 18),

              _PremiumTextField(
                controller: _fullNameController,
                icon: CupertinoIcons.person,
                label: 'Full Name',
                hintText: 'John Smith',
              ),
              const SizedBox(height: 12),

              _PremiumTextField(
                controller: _companyNameController,
                icon: CupertinoIcons.building_2_fill,
                label: 'Company Name',
                hintText: 'Smith Renovation',
              ),
              const SizedBox(height: 12),

              _PremiumTextField(
                controller: _emailController,
                icon: CupertinoIcons.envelope,
                label: 'Email',
                hintText: 'client@email.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              _PhoneInputCard(
                phoneController: _phoneController,
                isValid: _isPhoneValid,
                onChanged: _handlePhoneChanged,
                onClear: () {
                  setState(() {
                    _phoneController.clear();
                    _normalizedPhoneNumber = null;
                    _isPhoneValid = true;
                  });
                },
              ),

              const SizedBox(height: 12),

              _PremiumTextField(
                controller: _notesController,
                icon: CupertinoIcons.doc_text,
                label: 'Notes',
                hintText: 'Preferred contact by email...',
                maxLines: 4,
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: const Color(0xFF3B82F6),
                  borderRadius: BorderRadius.circular(18),
                  onPressed: _isSaving ? null : _saveClient,
                  child: _isSaving
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                    widget.existingClient == null
                        ? 'Save Client'
                        : 'Save Changes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
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
  final IconData icon;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;

  const _PremiumTextField({
    required this.controller,
    required this.icon,
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
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _focusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _clearText() {
    widget.controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isSingleLine = widget.maxLines == 1;

    return Container(
      constraints: BoxConstraints(
        minHeight: isSingleLine ? 78 : 126,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kClientInput,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _kClientInputBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment:
        isSingleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: isSingleLine ? 0 : 6),
            child: Icon(
              widget.icon,
              color: _kClientIcon,
              size: 24,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Color(0xFFA0A7B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.maxLines,
                  minLines: isSingleLine ? 1 : widget.maxLines,
                  cursorColor: _kClientAccent,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF7D8496),
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          if (_showClearButton) ...[
            const SizedBox(width: 8),
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
    );
  }
}

class _PhoneInputCard extends StatelessWidget {
  final TextEditingController phoneController;
  final bool isValid;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _PhoneInputCard({
    required this.phoneController,
    required this.isValid,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 78,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kClientInput,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isValid ? _kClientInputBorder : const Color(0xFFFF6B6B),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.phone_fill,
            color: _kClientIcon,
            size: 24,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phone',
                  style: TextStyle(
                    color: Color(0xFFA0A7B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: false,
                  ),
                  cursorColor: _kClientAccent,
                  onChanged: onChanged,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Phone number',
                    hintStyle: const TextStyle(
                      color: Color(0xFF7D8496),
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: phoneController.text.trim().isNotEmpty
                        ? GestureDetector(
                      onTap: onClear,
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
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}