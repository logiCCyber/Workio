import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:ui';

import '../models/client_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../models/property_model.dart';
import '../models/estimate_template_model.dart';
import '../models/company_settings_model.dart';

import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/property_service.dart';
import '../services/company_settings_service.dart';
import '../services/estimate_template_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';

import '../dialogs/add_client_dialog.dart';
import '../dialogs/add_property_dialog.dart';

const _kEstimateAccent = Color(0xFF38BDF8);
const _kEstimateAccentBlue = Color(0xFF5B8CFF);

class CreateEstimateScreen extends StatefulWidget {
  const CreateEstimateScreen({super.key});

  @override
  State<CreateEstimateScreen> createState() => _CreateEstimateScreenState();
}

class _CreateEstimateScreenState extends State<CreateEstimateScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _isListening = false;
  bool _voiceAppendMode = false;

  bool _isLoading = true;
  bool _isSaving = false;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];
  List<EstimateItemModel> _items = [];
  List<EstimateTemplateModel> _templates = [];

  EstimateTemplateModel? _selectedTemplate;
  CompanySettingsModel? _companySettings;

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;

  DateTime? _validUntil = DateTime.now().add(const Duration(days: 14));

  double _taxRate = 0.13;
  double _discountValue = 0;
  bool _discountIsPercentage = false;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    _titleController.dispose();
    _scopeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addNewProperty() async {
    final client = _selectedClient;

    if (client == null) {
      _showSnack('Select a client first');
      return;
    }

    final created = await showAddPropertyDialog(
      context,
      clientId: client.id,
    );

    if (created == null) return;

    await _loadPropertiesForClient(client.id);

    if (!mounted) return;

    setState(() {
      _selectedProperty = created;
    });

    _maybeAutoFillTitle();
    _showSnack('Property created');
  }

  Future<void> _addNewClient() async {
    final created = await showAddClientDialog(context);

    if (created == null) return;

    await _loadClients();

    if (!mounted) return;

    setState(() {
      _selectedClient = created;
      _selectedProperty = null;
      _properties = [];
    });

    await _loadPropertiesForClient(created.id);

    _showSnack('Client created');
  }

  Future<void> _loadClients() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        ClientService.getClients(),
        CompanySettingsService.getSettings(),
        EstimateTemplateService.getTemplates(),
      ]);

      final clients = results[0] as List<ClientModel>;
      final companySettings = results[1] as CompanySettingsModel?;
      final templates = results[2] as List<EstimateTemplateModel>;

      if (!mounted) return;

      setState(() {
        _clients = clients;
        _templates = templates;
        _companySettings = companySettings;
        _taxRate = companySettings?.defaultTaxRate ?? 0.13;
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

  Future<void> _loadPropertiesForClient(String clientId) async {
    setState(() {
      _isLoading = true;
      _properties = [];
      _selectedProperty = null;
    });

    try {
      final properties = await PropertyService.getPropertiesByClient(clientId);

      if (!mounted) return;

      setState(() {
        _properties = properties;
        _isLoading = false;
      });

      if (properties.isNotEmpty) {
        setState(() {
          _selectedProperty = properties.first;
        });
        _maybeAutoFillTitle();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load client properties');
    }
  }

  String get _taxLabel {
    final value = _companySettings?.taxLabel.trim() ?? '';
    return value.isEmpty ? 'Tax' : value;
  }

  String get _currencyCode {
    final value = _companySettings?.currencyCode.trim() ?? '';
    return value.isEmpty ? 'CAD' : value.toUpperCase();
  }

  void _maybeAutoFillTitle() {
    if (_titleController.text.trim().isNotEmpty) return;

    final property = _selectedProperty;
    if (property == null) return;

    _titleController.text = EstimateFormatters.buildEstimateTitle(
      serviceType: 'Estimate',
      city: property.city,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    final lower = message.toLowerCase();

    final isSuccess = lower.contains('created') ||
        lower.contains('saved') ||
        lower.contains('updated') ||
        lower.contains('uploaded') ||
        lower.contains('removed');

    final isError = lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('select') ||
        lower.contains('enter') ||
        lower.contains('add at least');

    final icon = isSuccess
        ? CupertinoIcons.checkmark_circle_fill
        : isError
        ? CupertinoIcons.xmark_circle_fill
        : CupertinoIcons.info_circle_fill;

    final color = isSuccess
        ? const Color(0xFF22C55E)
        : isError
        ? const Color(0xFFFF6B6B)
        : const Color(0xFF38BDF8);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF22252D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: color.withOpacity(0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.40),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initSpeech() async {
    final ready = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;

        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
      onError: (error) {
        if (!mounted) return;

        setState(() {
          _isListening = false;
        });

        _showSnack('Voice input failed: ${error.errorMsg}');
      },
    );

    if (!mounted) return;

    setState(() {
      _speechReady = ready;
    });
  }

  void _insertVoiceTextToController(
      TextEditingController controller,
      String spokenText, {
        required bool append,
      }) {
    final clean = spokenText.trim();
    if (clean.isEmpty) return;

    final current = controller.text.trim();

    final next = append
        ? (current.isEmpty ? clean : '$current $clean').trim()
        : clean;

    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _startVoiceInput({
    required TextEditingController controller,
    required bool append,
    ValueChanged<String>? onLiveText,
    VoidCallback? onDone,
  }) async {
    if (!_speechReady) {
      _showSnack('Voice input is not available on this device');
      return;
    }

    if (_isListening) return;

    setState(() {
      _voiceAppendMode = append;
      _isListening = true;
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;

        final spoken = result.recognizedWords.trim();

        if (spoken.isNotEmpty) {
          if (onLiveText != null) {
            onLiveText(spoken);
          } else if (result.finalResult) {
            _insertVoiceTextToController(
              controller,
              spoken,
              append: _voiceAppendMode,
            );
          }
        }

        if (result.finalResult) {
          setState(() {
            _isListening = false;
          });

          onDone?.call();
        }
      },
      listenMode: stt.ListenMode.dictation,
      partialResults: true,
      cancelOnError: true,
      listenFor: const Duration(seconds: 45),
      pauseFor: const Duration(seconds: 5),
    );
  }

  Future<void> _stopVoiceInput() async {
    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _isListening = false;
    });
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _items,
      taxRate: _taxRate,
      discountValue: _discountValue,
      discountIsPercentage: _discountIsPercentage,
    );
  }

  Future<void> _pickValidUntil() async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _SimpleDateSheet(
          initialDate: _validUntil ?? DateTime.now().add(const Duration(days: 14)),
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _validUntil = picked;
    });
  }

  Future<void> _selectClient() async {
    if (_clients.isEmpty) {
      _showSnack('Add at least one client first');
      return;
    }

    final selected = await _openWorkioPickerSheet<ClientModel>(
      title: 'Choose Client',
      subtitle: 'Select the customer for this estimate',
      icon: CupertinoIcons.person_2_fill,
      items: _clients,
      itemIconBuilder: (_) => CupertinoIcons.person_crop_circle,
      titleBuilder: (client) => client.fullName,
      subtitleBuilder: (client) {
        final company = (client.companyName ?? '').trim();
        return company.isEmpty ? 'No company' : company;
      },
    );

    if (selected == null) return;

    setState(() {
      _selectedClient = selected;
      _selectedProperty = null;
      _properties = [];
    });

    await _loadPropertiesForClient(selected.id);
  }

  Future<void> _selectProperty() async {
    if (_selectedClient == null) {
      _showSnack('Select a client first');
      return;
    }

    if (_properties.isEmpty) {
      _showSnack('This client has no properties yet');
      return;
    }

    final selected = await _openWorkioPickerSheet<PropertyModel>(
      title: 'Choose Property',
      subtitle: 'Select the job location',
      icon: CupertinoIcons.location_solid,
      items: _properties,
      itemIconBuilder: (_) => CupertinoIcons.house_fill,
      titleBuilder: (property) => property.fullAddress,
    );

    if (selected == null) return;

    setState(() {
      _selectedProperty = selected;
    });

    _maybeAutoFillTitle();
  }

  void _applyTemplate(EstimateTemplateModel template) {
    setState(() {
      _selectedTemplate = template;
      _titleController.text = template.name;
      _scopeController.text = template.defaultScopeText ?? '';
      _notesController.text = template.defaultNotes ?? '';
    });
  }

  Future<void> _selectTemplate() async {
    if (_templates.isEmpty) {
      _showSnack('No templates yet');
      return;
    }

    final selected = await _openWorkioPickerSheet<EstimateTemplateModel>(
      title: 'Choose Template',
      subtitle: 'Apply a saved estimate template',
      icon: CupertinoIcons.square_stack_3d_up,
      items: _templates,
      itemIconBuilder: (_) => CupertinoIcons.doc_text,
      titleBuilder: (template) => template.name,
      subtitleBuilder: (template) {
        final scope = (template.defaultScopeText ?? '').trim();
        return scope.isEmpty ? 'No default scope' : scope;
      },
    );

    if (selected == null) return;

    _applyTemplate(selected);
  }

  Future<void> _showDiscountEditor() async {
    final valueController = TextEditingController(
      text: _discountValue == 0 ? '' : _discountValue.toString(),
    );

    bool isPercent = _discountIsPercentage;

    final result = await showModalBottomSheet<_DiscountResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF242730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3D49),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),

                  _sheetHeader(
                    icon: CupertinoIcons.tag,
                    title: 'Discount',
                    subtitle: 'Set fixed or percentage discount',
                  ),

                  const SizedBox(height: 18),

                  _sheetInputPanel(
                    icon: CupertinoIcons.tag_circle,
                    label: 'Discount value',
                    controller: valueController,
                    hintText: '0',
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _ChoiceButton(
                          label: 'Fixed',
                          selected: !isPercent,
                          onTap: () {
                            setModalState(() {
                              isPercent = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ChoiceButton(
                          label: 'Percent',
                          selected: isPercent,
                          onTap: () {
                            setModalState(() {
                              isPercent = true;
                            });
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      color: const Color(0xFF38BDF8),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: () {
                        final value = EstimateCalculator.parseNumber(
                          valueController.text,
                        );

                        Navigator.pop(
                          context,
                          _DiscountResult(
                            value: value,
                            isPercentage: isPercent,
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.checkmark_circle,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Apply',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    valueController.dispose();

    if (result == null) return;

    setState(() {
      _discountValue = result.value;
      _discountIsPercentage = result.isPercentage;
    });
  }

  Future<void> _showTaxEditor() async {
    final valueController = TextEditingController(
      text: (_taxRate * 100).toStringAsFixed(2),
    );

    final value = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF242730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),

              _sheetHeader(
                icon: CupertinoIcons.percent,
                title: 'Tax Rate',
                subtitle: 'Set the tax percentage for this estimate',
              ),

              const SizedBox(height: 18),

              _sheetInputPanel(
                icon: CupertinoIcons.money_dollar_circle,
                label: 'Tax percent',
                controller: valueController,
                hintText: '13',
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  color: const Color(0xFF38BDF8),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    final percent = EstimateCalculator.parseNumber(
                      valueController.text,
                    );

                    Navigator.pop(context, percent / 100);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_circle,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    valueController.dispose();

    if (value == null) return;

    setState(() {
      _taxRate = value;
    });
  }

  Future<void> _addOrEditItem({
    EstimateItemModel? existingItem,
    int? index,
  }) async {
    final titleController = TextEditingController(
      text: existingItem?.title ?? '',
    );

    final descriptionController = TextEditingController(
      text: existingItem?.description ?? '',
    );

    final quantityController = TextEditingController(
      text: existingItem != null && existingItem.quantity != 0
          ? EstimateFormatters.formatQuantity(existingItem.quantity)
          : '',
    );

    final unitPriceController = TextEditingController(
      text: existingItem != null && existingItem.unitPrice != 0
          ? EstimateFormatters.formatNumber(existingItem.unitPrice)
          : '',
    );

    String selectedUnit = existingItem?.unit ?? 'fixed';

    bool itemSheetClosing = false;

    Future<void> closeItemSheet(
        BuildContext sheetContext, [
          EstimateItemModel? item,
        ]) async {
      if (itemSheetClosing) return;
      itemSheetClosing = true;

      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 300));

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext, item);
    }

    final result = await showModalBottomSheet<EstimateItemModel>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF242730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget panel({required List<Widget> children}) {
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF181B23),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF303442)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.025),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(children: children),
              );
            }

            Widget inputRow({
              required IconData icon,
              required String label,
              required TextEditingController controller,
              required String hintText,
              TextInputType keyboardType = TextInputType.text,
              int maxLines = 1,
            }) {
              final hasText = controller.text.trim().isNotEmpty;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  crossAxisAlignment: maxLines > 1
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(
                                  top: maxLines > 1 ? 2 : 0,
                                ),
                                child: _PremiumPickerLeadingIcon(
                                  icon: icon,
                                  tone: _PickerIconTone.softWhite,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: const TextStyle(
                                  color: Color(0xFF8E93A6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: TextField(
                              controller: controller,
                              keyboardType: keyboardType,
                              maxLines: maxLines,
                              minLines: maxLines > 1 ? 3 : 1,
                              cursorColor: const Color(0xFF38BDF8),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                              onChanged: (_) => setModalState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: hintText,
                                hintStyle: const TextStyle(
                                  color: Color(0xFF697086),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasText) ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          controller.clear();
                          setModalState(() {});
                        },
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

            Widget pickerRow({
              required IconData icon,
              required String label,
              required String value,
              required VoidCallback onTap,
            }) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _PremiumPickerLeadingIcon(
                                    icon: icon,
                                    tone: _PickerIconTone.propertyBlue,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Color(0xFF8E93A6),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Padding(
                                padding: const EdgeInsets.only(left: 24),
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          CupertinoIcons.chevron_down,
                          color: Color(0xFF8E93A6),
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            Widget centeredInput({
              required IconData icon,
              required String label,
              required TextEditingController controller,
              required String hintText,
              required TextInputType keyboardType,
            }) {
              return Container(
                constraints: const BoxConstraints(minHeight: 84),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF181B23),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF303442)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PremiumPickerLeadingIcon(
                      icon: icon,
                      tone: _PickerIconTone.softWhite,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFA1A7B8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TextField(
                      controller: controller,
                      keyboardType: keyboardType,
                      textAlign: TextAlign.center,
                      cursorColor: const Color(0xFF38BDF8),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '0',
                        hintStyle: TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              );
            }

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                await closeItemSheet(sheetContext);
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  14,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3D49),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),

                      const SizedBox(height: 18),

                      Row(
                        children: [
                          Icon(
                            existingItem == null
                                ? CupertinoIcons.add_circled
                                : CupertinoIcons.pencil_circle,
                            color: const Color(0xFF38BDF8),
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              existingItem == null ? 'Add Item' : 'Edit Item',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      panel(
                        children: [
                          inputRow(
                            icon: CupertinoIcons.tag,
                            label: 'Title',
                            controller: titleController,
                            hintText: 'Labor / Materials',
                          ),
                          const Divider(color: Color(0xFF303442), height: 1),
                          inputRow(
                            icon: CupertinoIcons.text_alignleft,
                            label: 'Description',
                            controller: descriptionController,
                            hintText: 'Optional description',
                            maxLines: 3,
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      panel(
                        children: [
                          pickerRow(
                            icon: CupertinoIcons.cube_box,
                            label: 'Unit',
                            value: EstimateFormatters.formatUnit(selectedUnit),
                            onTap: () async {
                              FocusManager.instance.primaryFocus?.unfocus();
                              await SystemChannels.textInput.invokeMethod<void>(
                                'TextInput.hide',
                              );
                              await Future.delayed(
                                const Duration(milliseconds: 250),
                              );

                              if (!sheetContext.mounted) return;

                              const units = [
                                'fixed',
                                'sqft',
                                'room',
                                'wall',
                                'hour',
                                'item',
                                'day',
                              ];

                              final unit = await showModalBottomSheet<String>(
                                context: context,
                                backgroundColor: const Color(0xFF242730),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(28),
                                  ),
                                ),
                                builder: (_) {
                                  return _UnitSelectionSheet(
                                    units: units,
                                    selectedUnit: selectedUnit,
                                  );
                                },
                              );

                              if (unit == null) return;

                              setModalState(() {
                                selectedUnit = unit;
                              });
                            },
                          ),
                          const Divider(color: Color(0xFF303442), height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: centeredInput(
                                    icon: CupertinoIcons.number,
                                    label: 'Quantity',
                                    controller: quantityController,
                                    hintText: '1',
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: centeredInput(
                                    icon: CupertinoIcons.money_dollar_circle,
                                    label: 'Unit Price',
                                    controller: unitPriceController,
                                    hintText: '0.00',
                                    keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          color: const Color(0xFF38BDF8),
                          borderRadius: BorderRadius.circular(18),
                          onPressed: () async {
                            final title = titleController.text.trim();
                            if (title.isEmpty) return;

                            final quantity = EstimateCalculator.parseNumber(
                              quantityController.text,
                            ).toDouble();

                            final unitPrice = EstimateCalculator.parseNumber(
                              unitPriceController.text,
                            ).toDouble();

                            final safeQuantity = quantity <= 0 ? 1.0 : quantity;

                            final item = EstimateItemModel(
                              id: existingItem?.id ?? '',
                              estimateId: existingItem?.estimateId ?? '',
                              title: title,
                              description:
                              descriptionController.text.trim().isEmpty
                                  ? null
                                  : descriptionController.text.trim(),
                              unit: selectedUnit,
                              quantity: safeQuantity,
                              unitPrice: unitPrice,
                              lineTotal: EstimateCalculator.calculateLineTotal(
                                quantity: safeQuantity,
                                unitPrice: unitPrice,
                              ),
                              sortOrder: index ?? _items.length,
                              createdAt: existingItem?.createdAt,
                            );

                            await closeItemSheet(sheetContext, item);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                existingItem == null
                                    ? CupertinoIcons.plus_circle
                                    : CupertinoIcons.checkmark_circle,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                existingItem == null
                                    ? 'Add Item'
                                    : 'Save Changes',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future.delayed(const Duration(milliseconds: 500));

    titleController.dispose();
    descriptionController.dispose();
    quantityController.dispose();
    unitPriceController.dispose();

    if (result == null) return;

    setState(() {
      if (index != null) {
        _items[index] = result;
      } else {
        _items.add(result);
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _items = _items
          .asMap()
          .entries
          .map(
            (entry) => entry.value.copyWith(sortOrder: entry.key),
      )
          .toList();
    });
  }

  Future<void> _saveEstimate() async {
    if (_selectedClient == null) {
      _showSnack('Select a client');
      return;
    }

    if (_selectedProperty == null) {
      _showSnack('Select a property');
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      _showSnack('Enter an estimate title');
      return;
    }

    if (_items.isEmpty) {
      _showSnack('Add at least one item');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final estimate = EstimateModel(
        id: '',
        adminAuthId: '',
        clientId: _selectedClient!.id,
        propertyId: _selectedProperty!.id,
        estimateNumber: '',
        title: _titleController.text.trim(),
        status: 'draft',
        scopeText: _scopeController.text.trim().isEmpty
            ? null
            : _scopeController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        subtotal: 0,
        tax: 0,
        discount: 0,
        total: 0,
        validUntil: _validUntil,
        createdAt: null,
        updatedAt: null,
      );

      final created = await EstimateService.createEstimateWithItems(
        estimate: estimate,
        items: _items,
        taxRate: _taxRate,
        discountValue: _discountValue,
        discountIsPercentage: _discountIsPercentage,
      );

      if (!mounted) return;

      _showSnack('Estimate ${created.estimateNumber} saved');

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save estimate');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<T?> _openWorkioPickerSheet<T>({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<T> items,
    required String Function(T item) titleBuilder,
    String Function(T item)? subtitleBuilder,
    IconData Function(T item)? itemIconBuilder,
  }) {
    final sheetHeight = items.length <= 1
        ? 0.42
        : items.length <= 3
        ? 0.56
        : 0.72;

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF242730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: sheetHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D4250),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: _PremiumPickerLeadingIcon(
                          icon: icon,
                          tone: _PickerIconTone.softWhite,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFFF1F4F8),
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFFA0A7B8),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];

                        final titleText = titleBuilder(item).trim();
                        final subtitleText =
                        (subtitleBuilder?.call(item) ?? '').trim();

                        final itemIcon =
                            itemIconBuilder?.call(item) ?? CupertinoIcons.circle;

                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.pop(context, item),
                            child: Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: const Color(0xFF181B23),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFF343A49),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: _PremiumPickerLeadingIcon(
                                      icon: itemIcon,
                                      tone: _PickerIconTone.propertyBlue,
                                    ),
                                  ),

                                  const SizedBox(width: 13),

                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          titleText.isEmpty
                                              ? 'Untitled'
                                              : titleText,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFF1F4F8),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (subtitleText.isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            subtitleText,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFA0A7B8),
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              height: 1.25,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      CupertinoIcons.chevron_right,
                                      color: Color(0xFF9AA3B7),
                                      size: 16,
                                    ),
                                  ),
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
          ),
        );
      },
    );
  }

  Future<void> _openLargeTextEditor({
    required String title,
    required TextEditingController controller,
    required IconData icon,
  }) async {
    final tempController = TextEditingController(text: controller.text.trim());
    final editorFocusNode = FocusNode();

    final listeningNotifier = ValueNotifier<bool>(false);
    final speechPreviewNotifier = ValueNotifier<String>('');
    String liveVoiceBaseText = '';

    bool isClosing = false;

    Future<void> closeSheet(
        BuildContext sheetContext, {
          String? value,
        }) async {
      if (isClosing) return;
      isClosing = true;

      editorFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 220));

      if (!sheetContext.mounted) return;

      Navigator.of(sheetContext).pop(value);
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: const Color(0xFF242730),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return WillPopScope(
          onWillPop: () async {
            if (_isListening) {
              await _stopVoiceInput();
            }
            return true;
          },
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.84,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3D49),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          _PremiumPickerLeadingIcon(
                            icon: icon,
                            tone: _PickerIconTone.softWhite,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Review and edit this text before saving.',
                          style: TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF151922),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFF343A49),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ValueListenableBuilder<bool>(
                                valueListenable: listeningNotifier,
                                builder: (context, isRecording, _) {
                                  return _LargeEditorActionButton(
                                    icon: isRecording
                                        ? CupertinoIcons.stop_fill
                                        : CupertinoIcons.mic_fill,
                                    color: isRecording
                                        ? const Color(0xFFFF6B6B)
                                        : _kEstimateAccent,
                                    onTap: () async {
                                      if (isRecording) {
                                        await _stopVoiceInput();
                                        listeningNotifier.value = false;
                                        speechPreviewNotifier.value = '';
                                      } else {
                                        listeningNotifier.value = true;
                                        speechPreviewNotifier.value = '';
                                        liveVoiceBaseText = tempController.text.trim();

                                        await _startVoiceInput(
                                          controller: tempController,
                                          append: true,
                                          onLiveText: (spokenText) {
                                            final clean = spokenText.trim();
                                            if (clean.isEmpty) return;

                                            speechPreviewNotifier.value = clean;

                                            final next = liveVoiceBaseText.isEmpty
                                                ? clean
                                                : '$liveVoiceBaseText $clean';

                                            tempController.value = TextEditingValue(
                                              text: next,
                                              selection: TextSelection.collapsed(
                                                offset: next.length,
                                              ),
                                            );
                                          },
                                          onDone: () {
                                            listeningNotifier.value = false;
                                            speechPreviewNotifier.value = '';
                                          },
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              _LargeEditorActionButton(
                                icon: Icons.select_all_rounded,
                                color: const Color(0xFFF3F6FC),
                                onTap: () {
                                  final text = tempController.text;
                                  if (text.isEmpty) return;

                                  editorFocusNode.requestFocus();
                                  tempController.selection = TextSelection(
                                    baseOffset: 0,
                                    extentOffset: text.length,
                                  );
                                },
                              ),
                              const SizedBox(width: 6),
                              _LargeEditorActionButton(
                                icon: CupertinoIcons.doc_on_doc,
                                color: const Color(0xFFF3F6FC),
                                onTap: () async {
                                  final text = tempController.text.trim();
                                  if (text.isEmpty) return;

                                  await Clipboard.setData(ClipboardData(text: text));
                                  _showSnack('Copied');
                                },
                              ),
                              const SizedBox(width: 6),
                              _LargeEditorActionButton(
                                icon: CupertinoIcons.xmark,
                                color: const Color(0xFFFF6B6B),
                                onTap: () {
                                  tempController.clear();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF181B23),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: const Color(0xFF303442),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.26),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: tempController,
                            focusNode: editorFocusNode,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            cursorColor: const Color(0xFF38BDF8),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Type here...',
                              hintStyle: TextStyle(
                                color: Color(0xFF697086),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              color: const Color(0xFF242730),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () async {
                                if (_isListening) {
                                  await _stopVoiceInput();
                                }
                                await closeSheet(sheetContext);
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFFD6DCE8),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              color: const Color(0xFF38BDF8),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () async {
                                if (_isListening) {
                                  await _stopVoiceInput();
                                }

                                await closeSheet(
                                  sheetContext,
                                  value: tempController.text.trim(),
                                );
                              },
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Save',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 300));

    listeningNotifier.dispose();
    speechPreviewNotifier.dispose();
    editorFocusNode.dispose();
    tempController.dispose();

    if (result == null) return;

    setState(() {
      controller.text = result;
    });
  }

  Widget _formPanel({
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF303442),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _largeTextRow({
    required IconData icon,
    _PickerIconTone iconTone = _PickerIconTone.softWhite,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final isEmpty = value.trim().isEmpty;
    final cleanValue = isEmpty ? 'Tap to add text' : value.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _PremiumPickerLeadingIcon(
                  icon: icon,
                  tone: isEmpty ? _PickerIconTone.neutral : iconTone,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFFA0A7B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          CupertinoIcons.arrow_up_left_arrow_down_right,
                          color: Color(0xFF8E93A6),
                          size: 14,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      cleanValue,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isEmpty
                            ? const Color(0xFF697086)
                            : const Color(0xFFF3F6FC),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                        letterSpacing: -0.1,
                      ),
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

  Widget _sheetHeader({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PremiumPickerLeadingIcon(
          icon: icon,
          tone: _PickerIconTone.softWhite,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
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
      ],
    );
  }

  Widget _sheetInputPanel({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF303442)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PremiumPickerLeadingIcon(
                icon: icon,
                tone: _PickerIconTone.softWhite,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFA0A7B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              cursorColor: _kEstimateAccent,
              style: const TextStyle(
                color: Color(0xFFF3F6FC),
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF697086),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    final cleanSubtitle = (subtitle ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF252934),
        borderRadius: BorderRadius.circular(24),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF4F6FA),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.25,
                      ),
                    ),
                    if (cleanSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        cleanSubtitle,
                        style: const TextStyle(
                          color: Color(0xFFA0A7B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final totals = _totals;

    return Scaffold(
      backgroundColor: background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
                  child: Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2D36),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF3A3E4B),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white.withOpacity(0.82),
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Create Estimate',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color(0xFFF4F6FA),
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Subtotal ${EstimateFormatters.formatCurrency(totals.subtotal)} • Total ${EstimateFormatters.formatCurrency(totals.total)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFA0A7B8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Icon(
                        Icons.calculate_rounded,
                        color: Color(0xFF38BDF8),
                        size: 25,
                      ),

                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: CupertinoActivityIndicator(radius: 16),
      )
          : SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _buildSectionCard(
              title: 'Client & Property',
              subtitle: 'Client and estimate property',
              child: _formPanel(
                children: [
                  _PremiumPickerField(
                    label: 'Client',
                    leadingIcon: CupertinoIcons.person_fill,
                    iconTone: _PickerIconTone.clientBlue,
                    value: _selectedClient == null ? '' : _selectedClient!.fullName,
                    onTap: _selectClient,
                    showClearButton: _selectedClient != null,
                    showChevron: false,
                    onClear: () {
                      setState(() {
                        _selectedClient = null;
                        _selectedProperty = null;
                        _properties = [];
                      });
                    },
                    emptyIcon: CupertinoIcons.add,
                    onEmptyIconTap: _addNewClient,
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),
                  _PremiumPickerField(
                    label: 'Property',
                    leadingIcon: CupertinoIcons.house_fill,
                    iconTone: _PickerIconTone.propertyBlue,
                    value: _selectedProperty == null ? '' : _selectedProperty!.fullAddress,
                    onTap: _selectProperty,
                    showClearButton: _selectedProperty != null,
                    showChevron: false,
                    onClear: () {
                      setState(() {
                        _selectedProperty = null;
                      });
                    },
                    emptyIcon: CupertinoIcons.add,
                    onEmptyIconTap: _addNewProperty,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Estimate Info',
              subtitle: 'Main estimate information',
              child: _formPanel(
                children: [
                  _PremiumPickerField(
                    label: 'Template',
                    leadingIcon: CupertinoIcons.square_stack_3d_up,
                    iconTone: _PickerIconTone.templateBlue,
                    value: _selectedTemplate == null ? '' : _selectedTemplate!.name,
                    onTap: _selectTemplate,
                    showClearButton: _selectedTemplate != null,
                    showChevron: true,
                    onClear: () {
                      setState(() {
                        _selectedTemplate = null;
                      });
                    },
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),
                  _PremiumTextField(
                    controller: _titleController,
                    label: 'Title',
                    leadingIcon: CupertinoIcons.doc_text,
                    hintText: 'Service Estimate • City',
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),
                  _PremiumPickerField(
                    label: 'Valid Until',
                    leadingIcon: CupertinoIcons.calendar,
                    iconTone: _PickerIconTone.calendarBlue,
                    value: EstimateFormatters.formatDate(_validUntil),
                    onTap: _pickValidUntil,
                    showClearButton: _validUntil != null,
                    showChevron: false,
                    onClear: () {
                      setState(() {
                        _validUntil = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Scope & Notes',
              subtitle: 'Work details and client notes',
              child: _formPanel(
                children: [
                  _largeTextRow(
                    icon: CupertinoIcons.doc_text_fill,
                    iconTone: _PickerIconTone.softWhite,
                    label: 'Scope',
                    value: _scopeController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Scope',
                        controller: _scopeController,
                        icon: CupertinoIcons.doc_text_fill,
                      );
                    },
                  ),
                  const Divider(color: Color(0xFF303442), height: 1),
                  _largeTextRow(
                    icon: CupertinoIcons.text_bubble_fill,
                    iconTone: _PickerIconTone.softWhite,
                    label: 'Notes',
                    value: _notesController.text,
                    onTap: () {
                      _openLargeTextEditor(
                        title: 'Edit Notes',
                        controller: _notesController,
                        icon: CupertinoIcons.text_bubble_fill,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Items',
              subtitle: 'Estimate line items',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                onPressed: () => _addOrEditItem(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181B23),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF303442),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _kEstimateAccent.withOpacity(0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.plus,
                    color: _kEstimateAccent,
                    size: 22,
                  ),
                ),
              ),
              child: _items.isEmpty
                  ? const _InlineEmptyItemsState()
                  : Column(
                children: List.generate(_items.length, (index) {
                  final item = _items[index];

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _items.length - 1 ? 0 : 10,
                    ),
                    child: _EstimateItemTile(
                      item: item,
                      onEdit: () => _addOrEditItem(
                        existingItem: item,
                        index: index,
                      ),
                      onDelete: () => _removeItem(index),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Totals',
              subtitle: 'Tax, discount, and total amount',
              child: Column(
                children: [
                  _TotalsPanel(
                    children: [
                      _TotalsEditRow(
                        icon: CupertinoIcons.percent,
                        iconTone: _PickerIconTone.softWhite,
                        label: 'Tax Rate',
                        value: '${(_taxRate * 100).toStringAsFixed(2)}%',
                        onTap: _showTaxEditor,
                      ),
                      const Divider(color: Color(0xFF303442), height: 1),
                      _TotalsEditRow(
                        icon: CupertinoIcons.tag,
                        iconTone: _PickerIconTone.softWhite,
                        label: 'Discount',
                        value: _discountValue <= 0
                            ? 'None'
                            : _discountIsPercentage
                            ? '${_discountValue.toStringAsFixed(2)}%'
                            : EstimateFormatters.formatCurrency(_discountValue),
                        onTap: _showDiscountEditor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  _TotalsPanel(
                    readOnly: true,
                    children: [
                      _TotalsValueRow(
                        icon: CupertinoIcons.sum,
                        iconTone: _PickerIconTone.propertyBlue,
                        label: 'Subtotal',
                        value: EstimateFormatters.formatCurrency(totals.subtotal),
                        muted: true,
                      ),
                      const Divider(color: Color(0xFF303442), height: 1),

                      _TotalsValueRow(
                        icon: CupertinoIcons.percent,
                        iconTone: _PickerIconTone.softWhite,
                        label: _taxLabel,
                        value: EstimateFormatters.formatCurrency(totals.tax),
                        muted: true,
                      ),
                      const Divider(color: Color(0xFF303442), height: 1),

                      _TotalsValueRow(
                        icon: CupertinoIcons.tag,
                        iconTone: _PickerIconTone.titleBlue,
                        label: 'Discount',
                        value: '- ${EstimateFormatters.formatCurrency(totals.discount)}',
                        muted: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  _TotalsGrandRow(
                    value: EstimateFormatters.formatCurrency(totals.total),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _kEstimateAccent.withOpacity(0.26),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.26),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: CupertinoButton(
                color: _isSaving
                    ? const Color(0xFF2A2D36)
                    : _kEstimateAccent,
                borderRadius: BorderRadius.circular(20),
                padding: const EdgeInsets.symmetric(vertical: 16),
                onPressed: _isSaving ? null : _saveEstimate,
                child: _isSaving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.arrow_drop_down_circle_outlined,
                      color: Colors.white,
                      size: 19,
                    ),
                    SizedBox(width: 9),
                    Text(
                      'Save Draft Estimate',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _estimateFieldIcon(
    IconData icon, {
      Color color = const Color(0xFFF3F6FC),
    }) {
  return SizedBox(
    width: 20,
    height: 20,
    child: Center(
      child: Icon(
        icon,
        color: color.withOpacity(0.90),
        size: 16.5,
      ),
    ),
  );
}

enum _PickerIconTone {
  neutral,
  clientBlue,
  propertyBlue,
  templateBlue,
  titleBlue,
  calendarBlue,
  softWhite,
}

class _PremiumPickerLeadingIcon extends StatelessWidget {
  final IconData icon;
  final _PickerIconTone tone;
  final Color? colorOverride;

  const _PremiumPickerLeadingIcon({
    required this.icon,
    required this.tone,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    Color iconColor;

    switch (tone) {
      case _PickerIconTone.clientBlue:
        iconColor = _kEstimateAccentBlue;
        break;
      case _PickerIconTone.propertyBlue:
        iconColor = _kEstimateAccent;
        break;
      case _PickerIconTone.templateBlue:
        iconColor = const Color(0xFF60A5FA);
        break;
      case _PickerIconTone.titleBlue:
        iconColor = const Color(0xFF7DD3FC);
        break;
      case _PickerIconTone.calendarBlue:
        iconColor = _kEstimateAccent;
        break;
      case _PickerIconTone.softWhite:
        iconColor = const Color(0xFFF3F6FC);
        break;
      case _PickerIconTone.neutral:
        iconColor = const Color(0xFF8E93A6);
        break;
    }

    return SizedBox(
      width: 19,
      height: 19,
      child: Center(
        child: Icon(
          icon,
          color: (colorOverride ?? iconColor).withOpacity(0.88),
          size: 15.5,
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
  final IconData? leadingIcon;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.keyboardType,
    this.leadingIcon,
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
    final hasIcon = widget.leadingIcon != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: widget.maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (hasIcon) ...[
            Padding(
              padding: EdgeInsets.only(top: widget.maxLines > 1 ? 2 : 0),
              child: _PremiumPickerLeadingIcon(
                icon: widget.leadingIcon!,
                tone: _PickerIconTone.titleBlue,
              ),
            ),
            const SizedBox(width: 10),
          ],

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Color(0xFFA0A7B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: widget.keyboardType,
                  maxLines: widget.maxLines,
                  minLines: widget.maxLines > 1 ? 3 : 1,
                  cursorColor: const Color(0xFF38BDF8),
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(
                      color: Color(0xFF697086),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),

          if (_showClearButton) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                widget.controller.clear();
                _focusNode.requestFocus();
              },
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

class _PremiumInitialTextField extends StatelessWidget {
  final String initialValue;
  final String label;
  final String hintText;
  final int maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  const _PremiumInitialTextField({
    required this.initialValue,
    required this.label,
    required this.hintText,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
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
              label,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: initialValue,
              keyboardType: keyboardType,
              maxLines: maxLines,
              minLines: maxLines == 1 ? 1 : maxLines,
              onChanged: onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
              cursorColor: const Color(0xFF38BDF8),
              decoration: InputDecoration(
                isDense: true,
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: Color(0xFF697086),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumPickerField extends StatelessWidget {
  final String label;
  final IconData leadingIcon;
  final _PickerIconTone iconTone;
  final String value;
  final VoidCallback onTap;
  final bool showClearButton;
  final VoidCallback? onClear;
  final IconData? emptyIcon;
  final VoidCallback? onEmptyIconTap;
  final int valueMaxLines;
  final bool showChevron;
  final Color? iconColor;

  const _PremiumPickerField({
    required this.label,
    required this.leadingIcon,
    required this.value,
    required this.onTap,
    this.iconTone = _PickerIconTone.neutral,
    this.showClearButton = false,
    this.onClear,
    this.emptyIcon,
    this.onEmptyIconTap,
    this.valueMaxLines = 2,
    this.showChevron = true,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    final isPlaceholder = value.trim().toLowerCase().startsWith('select');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            hasValue ? 12 : 0,
            14,
            hasValue ? 12 : 0,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: hasValue ? 58 : 68,
            ),
            child: Row(
              children: [
                Expanded(
                  child: hasValue
                      ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _PremiumPickerLeadingIcon(
                            icon: leadingIcon,
                            tone: iconTone,
                            colorOverride: iconColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Color(0xFF8E93A6),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          value,
                          maxLines: valueMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaceholder
                                ? const Color(0xFF697086)
                                : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  )
                      : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: 1.22,
                        child: _PremiumPickerLeadingIcon(
                          icon: leadingIcon,
                          tone: iconTone,
                          colorOverride: iconColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Color(0xFFA1A7B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (showClearButton && onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: const Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: Color(0xFF8E93A6),
                      size: 18,
                    ),
                  )
                else if (emptyIcon != null && onEmptyIconTap != null)
                  GestureDetector(
                    onTap: onEmptyIconTap,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: const Color(0xFF20232D),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: const Color(0xFF343846),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        CupertinoIcons.add,
                        color: _kEstimateAccent,
                        size: 20,
                      ),
                    ),
                  )
                else if (showChevron)
                    const Icon(
                      CupertinoIcons.chevron_right,
                      color: Color(0xFF8E93A6),
                      size: 18,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SimpleDateSheet extends StatefulWidget {
  final DateTime initialDate;

  const _SimpleDateSheet({
    required this.initialDate,
  });

  @override
  State<_SimpleDateSheet> createState() => _SimpleDateSheetState();
}

class _SimpleDateSheetState extends State<_SimpleDateSheet> {
  late DateTime selectedDate;
  late DateTime visibleMonth;

  @override
  void initState() {
    super.initState();
    selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    visibleMonth = DateTime(selectedDate.year, selectedDate.month);
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;

    final leadingEmptyDays = firstDay.weekday % 7;

    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              const SizedBox(height: 18),

              const Row(
                children: [
                  Icon(
                    CupertinoIcons.calendar,
                    color: Color(0xFFB8C1D9),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Select valid until',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF23252E)),
                ),
                child: Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          visibleMonth = DateTime(
                            visibleMonth.year,
                            visibleMonth.month - 1,
                          );
                        });
                      },
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Color(0xFFB6BCD0),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          _monthLabel(visibleMonth),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          visibleMonth = DateTime(
                            visibleMonth.year,
                            visibleMonth.month + 1,
                          );
                        });
                      },
                      child: const Icon(
                        CupertinoIcons.chevron_right,
                        color: Color(0xFFB6BCD0),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF101117),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF23252E)),
                  ),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: 42,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leadingEmptyDays + 1;
                      final isCurrentMonth =
                          dayNumber >= 1 && dayNumber <= daysInMonth;

                      final date = DateTime(
                        visibleMonth.year,
                        visibleMonth.month,
                        dayNumber,
                      );

                      final selected = _sameDay(date, selectedDate);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedDate = date;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF38BDF8)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : isCurrentMonth
                                  ? Colors.white
                                  : const Color(0xFF4F5668),
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  color: const Color(0xFF38BDF8),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () {
                    Navigator.pop(context, selectedDate);
                  },
                  child: const Text(
                    'Apply Date',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
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

class _UnitSelectionSheet extends StatelessWidget {
  final List<String> units;
  final String selectedUnit;

  const _UnitSelectionSheet({
    required this.units,
    required this.selectedUnit,
  });

  IconData _unitIcon(String unit) {
    switch (unit.trim().toLowerCase()) {
      case 'fixed':
        return CupertinoIcons.checkmark_seal;
      case 'sqft':
        return CupertinoIcons.square_grid_2x2;
      case 'room':
        return CupertinoIcons.house;
      case 'wall':
        return CupertinoIcons.rectangle;
      case 'hour':
        return CupertinoIcons.clock;
      case 'item':
        return CupertinoIcons.cube_box;
      case 'day':
        return CupertinoIcons.calendar;
      default:
        return CupertinoIcons.circle_grid_hex;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D4250),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              const SizedBox(height: 18),

              const Row(
                children: [
                  Icon(
                    CupertinoIcons.cube_box_fill,
                    color: Color(0xFFF3F6FC),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Choose Unit',
                      style: TextStyle(
                        color: Color(0xFFF1F4F8),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: units.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final unit = units[index];
                    final selected = unit == selectedUnit;

                    return Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.pop(context, unit),
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF102A36)
                                : const Color(0xFF151922),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF38BDF8)
                                  : const Color(0xFF343A49),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: selected
                                    ? const Color(0xFF38BDF8).withOpacity(0.14)
                                    : Colors.black.withOpacity(0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _unitIcon(unit),
                                color: selected
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF9AA3B7),
                                size: 20,
                              ),
                              const SizedBox(width: 13),

                              Expanded(
                                child: Text(
                                  EstimateFormatters.formatUnit(unit),
                                  style: TextStyle(
                                    color: selected
                                        ? const Color(0xFFF3F6FC)
                                        : const Color(0xFFE7EAF2),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),

                              Icon(
                                selected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.chevron_right,
                                color: selected
                                    ? const Color(0xFF38BDF8)
                                    : const Color(0xFF8E93A6),
                                size: selected ? 21 : 16,
                              ),
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
      ),
    );
  }
}

class _InlineEmptyItemsState extends StatelessWidget {
  const _InlineEmptyItemsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF303442),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kEstimateAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kEstimateAccent.withOpacity(0.24),
              ),
            ),
            child: const Icon(
              CupertinoIcons.square_list_fill,
              color: _kEstimateAccent,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No line items yet',
                  style: TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap the plus button to add labor, materials, or service items.',
                  style: TextStyle(
                    color: Color(0xFFA0A7B8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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

class _EstimateItemTile extends StatelessWidget {
  final EstimateItemModel item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EstimateItemTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  String _displayTitle() {
    final rawTitle = item.title.trim();
    if (rawTitle.isEmpty) return 'Untitled Item';

    final qty = item.quantity;
    if (qty <= 1) return rawTitle;

    final lower = rawTitle.toLowerCase();

    if (lower.endsWith('labor')) return rawTitle;
    if (lower.endsWith('s')) return rawTitle;

    if (lower.endsWith('y') &&
        lower.length > 1 &&
        !'aeiou'.contains(lower[lower.length - 2])) {
      return '${rawTitle.substring(0, rawTitle.length - 1)}ies';
    }

    if (lower.endsWith('ch') ||
        lower.endsWith('sh') ||
        lower.endsWith('x') ||
        lower.endsWith('z')) {
      return '${rawTitle}es';
    }

    return '${rawTitle}s';
  }

  @override
  Widget build(BuildContext context) {
    final description = (item.description ?? '').trim();

    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF303442),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PremiumPickerLeadingIcon(
                icon: CupertinoIcons.cube_box_fill,
                tone: _PickerIconTone.propertyBlue,
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Text(
                  _displayTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3F6FC),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.15,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              _SmallIconButton(
                icon: CupertinoIcons.pencil,
                onTap: onEdit,
              ),
              const SizedBox(width: 8),
              _SmallIconButton(
                icon: CupertinoIcons.trash,
                onTap: onDelete,
                color: const Color(0xFFFF6B6B),
              ),
            ],
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA0A7B8),
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],

          const SizedBox(height: 13),

          Row(
            children: [
              Expanded(
                child: _MiniInfo(
                  label: 'Qty',
                  value: EstimateFormatters.formatQuantity(item.quantity),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniInfo(
                  label: 'Unit',
                  value: EstimateFormatters.formatUnit(item.unit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniInfo(
                  label: 'Price',
                  value: EstimateFormatters.formatCurrency(item.unitPrice),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          _MiniInfo(
            label: 'Line Total',
            value: EstimateFormatters.formatCurrency(lineTotal),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _SmallIconButton({
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFFB8C1D9),
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFF222631),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF343846),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: color,
          size: 16,
        ),
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _MiniInfo({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: emphasized ? 14 : 10,
        vertical: emphasized ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: emphasized
            ? _kEstimateAccent.withOpacity(0.10)
            : const Color(0xFF222631),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: emphasized
              ? _kEstimateAccent.withOpacity(0.30)
              : const Color(0xFF343846),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: emphasized
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: emphasized ? 10 : 6),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: emphasized ? TextAlign.right : TextAlign.center,
              style: TextStyle(
                color: emphasized
                    ? const Color(0xFFF3F6FC)
                    : const Color(0xFFD6DCE8),
                fontSize: emphasized ? 15 : 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  final List<Widget> children;
  final bool readOnly;

  const _TotalsPanel({
    required this.children,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: readOnly
            ? const Color(0xFF242730)
            : const Color(0xFF181B23),
        borderRadius: BorderRadius.circular(20),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: readOnly
              ? const Color(0xFF343846)
              : const Color(0xFF303442),
          width: 1,
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _TotalsEditRow extends StatelessWidget {
  final IconData icon;
  final _PickerIconTone iconTone;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TotalsEditRow({
    required this.icon,
    required this.iconTone,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              _PremiumPickerLeadingIcon(
                icon: icon,
                tone: iconTone,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB8C1D9),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                color: Color(0xFF8E93A6),
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsValueRow extends StatelessWidget {
  final IconData icon;
  final _PickerIconTone iconTone;
  final String label;
  final String value;
  final bool muted;

  const _TotalsValueRow({
    required this.icon,
    required this.iconTone,
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          _PremiumPickerLeadingIcon(
            icon: icon,
            tone: iconTone,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted
                    ? const Color(0xFF8E93A6)
                    : const Color(0xFFF3F6FC),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF3F6FC),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsGrandRow extends StatelessWidget {
  final String value;

  const _TotalsGrandRow({
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      decoration: BoxDecoration(
        color: const Color(0xFF102A36),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _kEstimateAccent.withOpacity(0.52),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _kEstimateAccent.withOpacity(0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _kEstimateAccent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _kEstimateAccent.withOpacity(0.35),
              ),
            ),
            child: const Center(
              child: Icon(
                CupertinoIcons.money_dollar_circle_fill,
                color: _kEstimateAccent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Total',
              style: TextStyle(
                color: Color(0xFFF3F6FC),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF3F6FC),
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? _kEstimateAccent.withOpacity(0.16)
              : const Color(0xFF181B23),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? _kEstimateAccent.withOpacity(0.72)
                : const Color(0xFF303442),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _kEstimateAccent : const Color(0xFFA0A7B8),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _DiscountResult {
  final double value;
  final bool isPercentage;

  const _DiscountResult({
    required this.value,
    required this.isPercentage,
  });
}

class _PreviewInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewInfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LargeEditorActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _LargeEditorActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF242730),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: const Color(0xFF3A4150),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: color,
            size: 18,
          ),
        ),
      ),
    );
  }
}