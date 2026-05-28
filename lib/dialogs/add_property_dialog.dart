import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/property_model.dart';
import '../services/property_service.dart';

const _kPropertyAccent = Color(0xFF38BDF8);
const _kPropertySheet = Color(0xFF1F232C);
const _kPropertyInput = Color(0xFF1B2028);
const _kPropertyInputBorder = Color(0xFF3A4050);
const _kPropertyIcon = Color(0xFF38BDF8);

Future<PropertyModel?> showAddPropertyDialog(
    BuildContext context, {
      required String clientId,
      PropertyModel? existingProperty,
    }) {
  return showModalBottomSheet<PropertyModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _AddPropertyDialogContent(
      clientId: clientId,
      existingProperty: existingProperty,
    ),
  );
}

class _AddPropertyDialogContent extends StatefulWidget {
  final String clientId;
  final PropertyModel? existingProperty;

  const _AddPropertyDialogContent({
    required this.clientId,
    this.existingProperty,
  });

  @override
  State<_AddPropertyDialogContent> createState() =>
      _AddPropertyDialogContentState();
}

class _AddPropertyDialogContentState extends State<_AddPropertyDialogContent> {
  final TextEditingController _addressLine1Controller = TextEditingController();
  final TextEditingController _addressLine2Controller = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _provinceController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _squareFootageController = TextEditingController();
  final TextEditingController _propertyTypeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isSaving = false;

  @override
  void dispose() {
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    _squareFootageController.dispose();
    _propertyTypeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    final existing = widget.existingProperty;
    if (existing != null) {
      _addressLine1Controller.text = existing.addressLine1;
      _addressLine2Controller.text = existing.addressLine2 ?? '';
      _cityController.text = existing.city ?? '';
      _provinceController.text = existing.province ?? '';
      _postalCodeController.text = existing.postalCode ?? '';
      _squareFootageController.text =
      existing.squareFootage == 0 ? '' : existing.squareFootage.toString();
      _propertyTypeController.text = existing.propertyType ?? '';
      _notesController.text = existing.notes ?? '';
    }
  }

  Future<void> _saveProperty() async {
    final addressLine1 = _addressLine1Controller.text.trim();
    final addressLine2 = _addressLine2Controller.text.trim();
    final city = _cityController.text.trim();
    final province = _provinceController.text.trim();
    final postalCode = _postalCodeController.text.trim();
    final squareFootage = _parseDouble(_squareFootageController.text);
    final propertyType = _propertyTypeController.text.trim();
    final notes = _notesController.text.trim();

    if (addressLine1.isEmpty) {
      _showSnack('Enter address line 1');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final existing = widget.existingProperty;

      final payload = PropertyModel(
        id: existing?.id ?? '',
        adminAuthId: existing?.adminAuthId ?? '',
        clientId: widget.clientId,
        addressLine1: addressLine1,
        addressLine2: addressLine2.isEmpty ? null : addressLine2,
        city: city.isEmpty ? null : city,
        province: province.isEmpty ? null : province,
        postalCode: postalCode.isEmpty ? null : postalCode,
        squareFootage: squareFootage,
        propertyType: propertyType.isEmpty ? null : propertyType,
        notes: notes.isEmpty ? null : notes,
        createdAt: existing?.createdAt,
        updatedAt: existing?.updatedAt,
      );

      final saved = existing == null
          ? await PropertyService.createProperty(payload)
          : await PropertyService.updateProperty(payload);

      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save property');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
  }

  double _parseDouble(String value) {
    final cleaned = value
        .trim()
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existingProperty == null
        ? 'New Property'
        : 'Edit Property';

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
            color: _kPropertySheet,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: _kPropertyInputBorder),
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
                        border: Border.all(color: _kPropertyInputBorder),
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
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 42),
                ],
              ),

              const SizedBox(height: 18),

              _PremiumTextField(
                controller: _addressLine1Controller,
                icon: CupertinoIcons.location_solid,
                label: 'Address Line 1',
                hintText: '123 Main Street',
              ),
              const SizedBox(height: 12),

              _PremiumTextField(
                controller: _addressLine2Controller,
                icon: CupertinoIcons.location,
                label: 'Address Line 2',
                hintText: 'Unit, suite, floor...',
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _PremiumTextField(
                      controller: _cityController,
                      icon: CupertinoIcons.building_2_fill,
                      label: 'City',
                      hintText: 'Montreal',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PremiumTextField(
                      controller: _provinceController,
                      icon: CupertinoIcons.map,
                      label: 'Province',
                      hintText: 'QC',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _PremiumTextField(
                      controller: _postalCodeController,
                      icon: CupertinoIcons.number,
                      label: 'Postal Code',
                      hintText: 'H1H 1H1',
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 ]')),
                        CanadianPostalCodeFormatter(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PremiumTextField(
                      controller: _squareFootageController,
                      icon: CupertinoIcons.square_grid_2x2,
                      label: 'Sqft',
                      hintText: '1200',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _PremiumTextField(
                controller: _propertyTypeController,
                icon: CupertinoIcons.house_fill,
                label: 'Property Type',
                hintText: 'Condo / House / Basement',
              ),

              const SizedBox(height: 12),

              _PremiumTextField(
                controller: _notesController,
                icon: CupertinoIcons.doc_text,
                label: 'Notes',
                hintText: 'Parking details, access instructions...',
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
                  onPressed: _isSaving ? null : _saveProperty,
                  child: _isSaving
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                    widget.existingProperty == null
                        ? 'Save Property'
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
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  const _PremiumTextField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
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
    if (mounted) setState(() {});
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
      constraints: BoxConstraints(
        minHeight: isSingleLine ? 78 : 126,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _kPropertyInput,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _kPropertyInputBorder),
      ),
      child: Row(
        crossAxisAlignment:
        isSingleLine ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: isSingleLine ? 0 : 6),
            child: Icon(
              widget.icon,
              color: _kPropertyIcon,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
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
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.controller,
                  textCapitalization: widget.textCapitalization,
                  inputFormatters: widget.inputFormatters,
                  focusNode: _focusNode,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.maxLines,
                  minLines: isSingleLine ? 1 : widget.maxLines,
                  cursorColor: _kPropertyAccent,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF7D8496),
                      fontSize: 16,
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final upper = newValue.text.toUpperCase();

    return TextEditingValue(
      text: upper,
      selection: TextSelection.collapsed(offset: upper.length),
    );
  }
}

class CanadianPostalCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final raw = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');

    final limited = raw.length > 6 ? raw.substring(0, 6) : raw;

    String formatted;
    if (limited.length <= 3) {
      formatted = limited;
    } else {
      formatted = '${limited.substring(0, 3)} ${limited.substring(3)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}