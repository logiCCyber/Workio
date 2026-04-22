import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl_phone_number_input/intl_phone_number_input.dart';

import '../models/client_model.dart';
import '../services/client_service.dart';

Future<ClientModel?> showAddClientDialog(
    BuildContext context, {
      ClientModel? existingClient,
    }) {
  return showModalBottomSheet<ClientModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF15161C),
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
  PhoneNumber _initialPhoneNumber = PhoneNumber(isoCode: 'CA');
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
      _phoneController.text = existing.phone ?? '';
      _notesController.text = existing.notes ?? '';
    }

    _hydrateInitialPhoneNumber();
  }

  Future<void> _hydrateInitialPhoneNumber() async {
    final savedPhone = widget.existingClient?.phone?.trim() ?? '';
    _normalizedPhoneNumber = savedPhone.isEmpty ? null : savedPhone;

    if (savedPhone.isEmpty) return;

    try {
      final parsed = await PhoneNumber.getRegionInfoFromPhoneNumber(
        savedPhone,
        'CA',
      );

      if (!mounted) return;

      setState(() {
        _initialPhoneNumber = parsed;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _initialPhoneNumber = PhoneNumber(
          phoneNumber: savedPhone,
          isoCode: 'CA',
        );
      });
    }
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
              widget.existingClient == null ? 'New Client' : 'Edit Client',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _PremiumTextField(
              controller: _fullNameController,
              label: 'Full Name',
              hintText: 'John Smith',
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _companyNameController,
              label: 'Company Name',
              hintText: 'Smith Renovation',
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _emailController,
              label: 'Email',
              hintText: 'client@email.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            Container(
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
                    const Text(
                      'Phone',
                      style: TextStyle(
                        color: Color(0xFF8E93A6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InternationalPhoneNumberInput(
                      initialValue: _initialPhoneNumber,
                      textFieldController: _phoneController,
                      selectorConfig: const SelectorConfig(
                        selectorType: PhoneInputSelectorType.BOTTOM_SHEET,
                        useEmoji: true,
                        setSelectorButtonAsPrefixIcon: true,
                      ),
                      onInputChanged: (PhoneNumber number) {
                        setState(() {
                          _initialPhoneNumber = number;
                          _normalizedPhoneNumber = number.phoneNumber;
                        });
                      },
                      onInputValidated: (bool value) {
                        if (!mounted) return;
                        setState(() {
                          _isPhoneValid = value;
                        });
                      },
                      ignoreBlank: true,
                      autoValidateMode: AutovalidateMode.disabled,
                      formatInput: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: false,
                      ),
                      cursorColor: const Color(0xFF5B8CFF),
                      selectorTextStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                      inputBorder: InputBorder.none,
                      inputDecoration: InputDecoration(
                        isDense: true,
                        hintText: 'Phone number',
                        hintStyle: const TextStyle(
                          color: Color(0xFF697086),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        suffixIcon: _phoneController.text.trim().isNotEmpty
                            ? GestureDetector(
                          onTap: () {
                            setState(() {
                              _phoneController.clear();
                              _normalizedPhoneNumber = null;
                              _isPhoneValid = true;
                              _initialPhoneNumber = PhoneNumber(isoCode: 'CA');
                            });
                          },
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
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _notesController,
              label: 'Notes',
              hintText: 'Preferred contact by email...',
              maxLines: 4,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: const Color(0xFF5B8CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: _isSaving ? null : _saveClient,
                child: _isSaving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Text(
                  widget.existingClient == null ? 'Save Client' : 'Save Changes',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
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