import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../models/client_model.dart';
import '../models/estimate_item_model.dart';
import '../models/estimate_model.dart';
import '../models/estimate_document_model.dart';
import '../models/property_model.dart';
import '../models/company_settings_model.dart';
import '../models/estimate_email_log_model.dart';

import '../services/client_service.dart';
import '../services/estimate_service.dart';
import '../services/property_service.dart';
import '../services/estimate_pdf_service.dart';
import '../services/estimate_document_service.dart';
import '../services/company_settings_service.dart';
import '../services/estimate_email_service.dart';
import '../services/invoice_service.dart';

import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';
import '../utils/company_logo_helper.dart';

import '../dialogs/send_estimate_dialog.dart';

import 'invoice_details_screen.dart';

class EstimateDetailsScreen extends StatefulWidget {
  final String estimateId;

  const EstimateDetailsScreen({
    super.key,
    required this.estimateId,
  });

  @override
  State<EstimateDetailsScreen> createState() => _EstimateDetailsScreenState();
}

class _EstimateDetailsScreenState extends State<EstimateDetailsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _scopeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDuplicating = false;
  bool _isPreviewingPdf = false;
  bool _isArchiving = false;
  bool _isDeleting = false;
  bool _isSharingPdf = false;
  bool _isSavingPdf = false;
  bool _isDocumentsLoading = false;
  bool _isSendingEmail = false;
  bool _isEmailLogsLoading = false;
  bool _isConvertingToInvoice = false;

  List<EstimateEmailLogModel> _emailLogs = [];

  CompanySettingsModel? _companySettings;

  EstimateModel? _estimate;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];
  List<EstimateItemModel> _items = [];
  List<EstimateDocumentModel> _documents = [];

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;

  DateTime? _validUntil;
  String _status = 'draft';

  double _taxRate = 0;
  double _discountValue = 0;
  bool _discountIsPercentage = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _scopeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  EstimateDocumentModel? get _latestSavedDocument {
    if (_documents.isEmpty) return null;
    return _documents.first;
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        EstimateService.getEstimateById(widget.estimateId),
        EstimateService.getEstimateItems(widget.estimateId),
        ClientService.getClients(),
        CompanySettingsService.getSettings(),
      ]);

      final estimate = results[0] as EstimateModel?;
      final items = results[1] as List<EstimateItemModel>;
      final clients = results[2] as List<ClientModel>;
      final companySettings = results[3] as CompanySettingsModel?;

      if (estimate == null) {
        if (!mounted) return;
        _showSnack('Estimate not found');
        Navigator.pop(context);
        return;
      }

      final selectedClient = clients.where((c) => c.id == estimate.clientId).cast<ClientModel?>().firstWhere(
            (c) => c != null,
        orElse: () => null,
      );

      List<PropertyModel> properties = [];
      PropertyModel? selectedProperty;

      if (selectedClient != null) {
        properties = await PropertyService.getPropertiesByClient(selectedClient.id);
        selectedProperty = properties.where((p) => p.id == estimate.propertyId).cast<PropertyModel?>().firstWhere(
              (p) => p != null,
          orElse: () => null,
        );
      }

      final subtotal = estimate.subtotal;
      final tax = estimate.tax;
      final discount = estimate.discount;

      double taxRate = 0;
      if (subtotal - discount > 0 && tax > 0) {
        taxRate = tax / (subtotal - discount);
      }

      setState(() {
        _estimate = estimate;
        _items = items;
        _clients = clients;
        _properties = properties;
        _selectedClient = selectedClient;
        _selectedProperty = selectedProperty;
        _validUntil = estimate.validUntil;
        _status = estimate.status;
        _companySettings = companySettings;

        _titleController.text = estimate.title;
        _scopeController.text = estimate.scopeText ?? '';
        _notesController.text = estimate.notes ?? '';

        _taxRate = taxRate.isNaN || taxRate.isInfinite ? 0 : taxRate;
        _discountValue = discount;
        _discountIsPercentage = false;

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load estimate');
    }
    await _loadDocuments();
    await _loadEmailLogs();
  }

  void _openEmailHistorySheet() {
    if (_emailLogs.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Email History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _emailLogs.length,
                      itemBuilder: (context, index) {
                        return _EmailLogTile(log: _emailLogs[index]);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  void _openSavedDocumentsSheet() {
    if (_documents.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Saved Documents',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _documents.length,
                      itemBuilder: (context, index) {
                        final document = _documents[index];
                        return _SavedDocumentTile(
                          document: document,
                          onOpen: () => _openSavedDocument(document),
                          onDelete: () => _deleteSavedDocument(document),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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

  Future<void> _convertToInvoice() async {
    final estimate = _estimate;

    if (estimate == null) {
      _showSnack('Estimate не найден');
      return;
    }

    if (estimate.id.trim().isEmpty) {
      _showSnack('Сначала сохрани estimate');
      return;
    }

    if (!estimate.isApproved) {
      _showSnack('Only approved estimates can be converted to invoice');
      return;
    }

    setState(() {
      _isConvertingToInvoice = true;
    });

    try {
      final invoice = await InvoiceService.createInvoiceFromEstimate(
        estimate: estimate,
        dueInDays: 14,
        terms: 'Payment due within 14 days.',
        paymentInstructions: (_companySettings?.companyPhone ?? '').trim().isNotEmpty
            ? 'For payment questions contact ${_companySettings!.companyPhone}'
            : null,
      );

      if (!mounted) return;

      _showSnack('Invoice ${invoice.invoiceNumber} создан');

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoiceDetailsScreen(invoiceId: invoice.id),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Ошибка при создании invoice');
    } finally {
      if (!mounted) return;

      setState(() {
        _isConvertingToInvoice = false;
      });
    }
  }

  Widget _buildCompanyInfoRow({
    required String label,
    required String value,
    int maxLines = 1,
  }) {
    final cleanValue = value.trim().isEmpty ? '—' : value.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232734)),
      ),
      child: Row(
        crossAxisAlignment:
        maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8E95A9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              cleanValue,
              textAlign: TextAlign.right,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.96),
                fontSize: maxLines > 1 ? 15 : 16,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLargeTextEditor({
    required String title,
    required TextEditingController controller,
    required IconData icon,
  }) async {
    final tempController = TextEditingController(text: controller.text.trim());
    final editorFocusNode = FocusNode();

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
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return WillPopScope(
          onWillPop: () async {
            await closeSheet(sheetContext);
            return false;
          },
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.88,
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
                          Icon(
                            icon,
                            color: const Color(0xFF8FB0FF),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              await closeSheet(sheetContext);
                            },
                            child: const Icon(
                              CupertinoIcons.xmark_circle_fill,
                              color: Color(0xFF8E93A6),
                              size: 28,
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
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101117),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFF23252E)),
                          ),
                          child: TextField(
                            controller: tempController,
                            focusNode: editorFocusNode,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            keyboardType: TextInputType.multiline,
                            textAlignVertical: TextAlignVertical.top,
                            cursorColor: const Color(0xFF5B8CFF),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Enter text...',
                              hintStyle: TextStyle(
                                color: Color(0xFF697086),
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              color: const Color(0xFF20232D),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () async {
                                await closeSheet(sheetContext);
                              },
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              color: const Color(0xFF5B8CFF),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () async {
                                final value = tempController.text.trim();
                                await closeSheet(sheetContext, value: value);
                              },
                              child: const Text(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
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

    final cleanResult = result?.trim();

    await Future.delayed(const Duration(milliseconds: 500));

    tempController.dispose();
    editorFocusNode.dispose();

    if (!mounted) return;
    if (cleanResult == null) return;

    setState(() {
      controller.text = cleanResult;
    });
  }

  Widget _buildScopeNotesRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final cleanValue = value.trim().isEmpty ? '—' : value.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  icon,
                  size: 18,
                  color: const Color(0xFF9AA3B2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          CupertinoIcons.arrow_up_left_arrow_down_right,
                          color: Color(0xFF8E93A6),
                          size: 15,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 150,
                      child: Scrollbar(
                        thumbVisibility: true,
                        radius: const Radius.circular(999),
                        thickness: 3,
                        child: SingleChildScrollView(
                          primary: false,
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            cleanValue,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.45,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
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

  Future<void> _openSavedDocument(EstimateDocumentModel document) async {
    try {
      final url = await EstimateDocumentService.createSignedUrl(document);

      final uri = Uri.parse(url);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showSnack('Failed to open document');
      }
    } catch (e) {
      _showSnack('Failed to open document');
    }
  }

  Future<void> _loadDocuments() async {
    final estimate = _estimate;
    if (estimate == null || estimate.id.trim().isEmpty) {
      setState(() {
        _documents = [];
      });
      return;
    }

    setState(() {
      _isDocumentsLoading = true;
    });

    try {
      final docs =
      await EstimateDocumentService.getDocumentsByEstimate(estimate.id);

      if (!mounted) return;

      setState(() {
        _documents = docs;
        _isDocumentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isDocumentsLoading = false;
        _documents = [];
      });

      _showSnack('Failed to load documents');
    }
  }

  Future<void> _loadPropertiesForClient(
      String clientId, {
        String? keepSelectedPropertyId,
      }) async {
    try {
      final properties = await PropertyService.getPropertiesByClient(clientId);

      if (!mounted) return;

      PropertyModel? selectedProperty;

      if (keepSelectedPropertyId != null) {
        selectedProperty = properties.where((p) => p.id == keepSelectedPropertyId).cast<PropertyModel?>().firstWhere(
              (p) => p != null,
          orElse: () => null,
        );
      }

      setState(() {
        _properties = properties;
        _selectedProperty = selectedProperty;
      });
    } catch (e) {
      _showSnack('Failed to load client properties');
    }
  }

  Future<void> _deleteSavedDocument(EstimateDocumentModel document) async {
    try {
      await EstimateDocumentService.deleteDocument(document);

      if (!mounted) return;

      _showSnack('Document deleted');
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to delete document');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _items,
      taxRate: _taxRate,
      discountValue: _discountValue,
      discountIsPercentage: _discountIsPercentage,
    );
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _workioMonthLabel(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  String _workioShortDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  Future<DateTime?> _pickDateWithWorkioSheet({
    required DateTime initialDate,
    required String title,
  }) async {
    DateTime selectedDate = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );

    DateTime visibleMonth = DateTime(
      selectedDate.year,
      selectedDate.month,
    );

    int monthDirection = 1;

    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final firstDayOfMonth = DateTime(
              visibleMonth.year,
              visibleMonth.month,
              1,
            );

            final daysInMonth = DateTime(
              visibleMonth.year,
              visibleMonth.month + 1,
              0,
            ).day;

            final leadingEmptyDays = firstDayOfMonth.weekday % 7;

            Widget buildCalendarBody() {
              return Column(
                key: ValueKey('${visibleMonth.year}-${visibleMonth.month}'),
                children: [
                  const Row(
                    children: [
                      _CalendarWeekDay('S'),
                      _CalendarWeekDay('M'),
                      _CalendarWeekDay('T'),
                      _CalendarWeekDay('W'),
                      _CalendarWeekDay('T'),
                      _CalendarWeekDay('F'),
                      _CalendarWeekDay('S'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF23252E), height: 1),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GridView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
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

                        final isSelected = _isSameDate(date, selectedDate);

                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              selectedDate = DateTime(
                                date.year,
                                date.month,
                                date.day,
                              );
                              visibleMonth = DateTime(date.year, date.month);
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF5B8CFF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              border: isSelected
                                  ? Border.all(
                                color: const Color(0xFF83A6FF),
                              )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${date.day}',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : isCurrentMonth
                                    ? Colors.white
                                    : const Color(0xFF4F5668),
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            }

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

                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.calendar,
                            color: Color(0xFFB8C1D9),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
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

                      const SizedBox(height: 16),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0E14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF23252E)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected date',
                              style: TextStyle(
                                color: Color(0xFF8E93A6),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _workioShortDate(selectedDate),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D0E14),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: const Color(0xFF23252E)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minSize: 42,
                                    onPressed: () {
                                      setModalState(() {
                                        monthDirection = -1;
                                        visibleMonth = DateTime(
                                          visibleMonth.year,
                                          visibleMonth.month - 1,
                                        );
                                      });
                                    },
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF15161C),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF23252E),
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.chevron_left,
                                        color: Color(0xFFB6BCD0),
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _workioMonthLabel(visibleMonth),
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
                                    minSize: 42,
                                    onPressed: () {
                                      setModalState(() {
                                        monthDirection = 1;
                                        visibleMonth = DateTime(
                                          visibleMonth.year,
                                          visibleMonth.month + 1,
                                        );
                                      });
                                    },
                                    child: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF15161C),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF23252E),
                                        ),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.chevron_right,
                                        color: Color(0xFFB6BCD0),
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    final slideAnimation = Tween<Offset>(
                                      begin: Offset(
                                        monthDirection > 0 ? 0.08 : -0.08,
                                        0,
                                      ),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    );

                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: slideAnimation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: buildCalendarBody(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              color: const Color(0xFF20232D),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              color: const Color(0xFF5B8CFF),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: () {
                                Navigator.pop(sheetContext, selectedDate);
                              },
                              child: const Text(
                                'OK',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
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
  }

  Future<void> _loadEmailLogs() async {
    final estimate = _estimate;

    if (estimate == null || estimate.id.trim().isEmpty) {
      setState(() {
        _emailLogs = [];
      });
      return;
    }

    setState(() {
      _isEmailLogsLoading = true;
    });

    try {
      final logs = await EstimateEmailService.getEmailLogsByEstimate(estimate.id);

      if (!mounted) return;

      setState(() {
        _emailLogs = logs;
        _isEmailLogsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _emailLogs = [];
        _isEmailLogsLoading = false;
      });

      _showSnack('Failed to load email history');
    }
  }

  Future<void> _pickValidUntil() async {
    final picked = await _pickDateWithWorkioSheet(
      initialDate: _validUntil ?? DateTime.now().add(const Duration(days: 14)),
      title: 'Select valid until',
    );

    if (picked == null) return;

    setState(() {
      _validUntil = picked;
    });
  }

  Future<void> _sendEstimate() async {
    final estimate = _estimate;

    if (estimate == null) {
      _showSnack('Estimate not found');
      return;
    }

    final dialogResult = await showSendEstimateDialog(
      context: context,
      estimate: estimate,
      client: _selectedClient,
      companySettings: _companySettings,
      latestDocument: _latestSavedDocument,
    );

    if (dialogResult == null) return;

    setState(() {
      _isSendingEmail = true;
    });

    try {
      final result = await EstimateEmailService.sendEstimate(
        estimate: estimate,
        items: _items,
        dialogResult: dialogResult,
        client: _selectedClient,
        property: _selectedProperty,
        companySettings: _companySettings,
      );

      if (!mounted) return;

      setState(() {
        _estimate = result.updatedEstimate;
        _status = result.updatedEstimate.status;
      });

      await _loadDocuments();
      await _loadEmailLogs();

      _showSnack('Estimate sent');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to send estimate');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSendingEmail = false;
      });
    }
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
  }

  Future<void> _pickStatus() async {
    final statuses = const [
      'draft',
      'sent',
      'approved',
      'rejected',
      'archived',
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 470,
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
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.tag_fill,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Change Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the current estimate status',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF262832), height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: statuses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final status = statuses[index];
                      final selectedNow = status == _status;

                      return Material(
                        color: const Color(0xFF101117),
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.pop(context, status),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selectedNow
                                    ? const Color(0xFF5B8CFF)
                                    : const Color(0xFF23252E),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _statusIcon(status),
                                  color: selectedNow
                                      ? const Color(0xFF5B8CFF)
                                      : const Color(0xFFB6BCD0),
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    EstimateFormatters.formatStatus(status),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (selectedNow)
                                  const Icon(
                                    CupertinoIcons.checkmark_circle_fill,
                                    color: Color(0xFF5B8CFF),
                                    size: 18,
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
        );
      },
    );

    if (selected == null) return;

    setState(() {
      _status = selected;
    });
  }

  Future<void> _showDiscountEditor() async {
    final valueController = TextEditingController(
      text: _discountValue == 0 ? '' : _discountValue.toString(),
    );

    bool isPercent = _discountIsPercentage;

    final result = await showModalBottomSheet<_DiscountResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
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
                      color: const Color(0xFF5B8CFF),
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
      backgroundColor: const Color(0xFF15161C),
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
                icon: CupertinoIcons.chart_pie,
                title: 'Tax Rate',
                subtitle: 'Set the tax percentage for this estimate',
              ),

              const SizedBox(height: 18),

              _sheetInputPanel(
                icon: CupertinoIcons.percent,
                label: 'Tax percent',
                controller: valueController,
                hintText: '13',
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  color: const Color(0xFF5B8CFF),
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

    final result = await showModalBottomSheet<EstimateItemModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget panel({
              required List<Widget> children,
            }) {
              return Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF23252E)),
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
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  crossAxisAlignment: maxLines > 1
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: maxLines > 1 ? 4 : 0),
                      child: Icon(
                        icon,
                        color: const Color(0xFF8E93A6),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
                          const SizedBox(height: 5),
                          TextField(
                            controller: controller,
                            keyboardType: keyboardType,
                            maxLines: maxLines,
                            minLines: maxLines > 1 ? 3 : 1,
                            cursorColor: const Color(0xFF5B8CFF),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
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
                        ],
                      ),
                    ),
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
                        Icon(
                          icon,
                          color: const Color(0xFF8E93A6),
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
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
                              const SizedBox(height: 5),
                              Text(
                                value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
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

            return Padding(
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
                          color: const Color(0xFFB8C1D9),
                          size: 22,
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
                          hintText: 'Service item title',
                        ),
                        const Divider(color: Color(0xFF23252E), height: 1),
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
                              backgroundColor: const Color(0xFF15161C),
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
                        const Divider(color: Color(0xFF23252E), height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          child: Row(
                            children: [
                              Expanded(
                                child: _CenteredMiniInput(
                                  icon: CupertinoIcons.number,
                                  label: 'Quantity',
                                  controller: quantityController,
                                  hintText: '1',
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _CenteredMiniInput(
                                  icon: CupertinoIcons.money_dollar_circle,
                                  label: 'Unit Price',
                                  controller: unitPriceController,
                                  hintText: '0.00',
                                  keyboardType: const TextInputType.numberWithOptions(
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
                        color: const Color(0xFF5B8CFF),
                        borderRadius: BorderRadius.circular(16),
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
                            estimateId:
                            existingItem?.estimateId ?? widget.estimateId,
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

                          FocusManager.instance.primaryFocus?.unfocus();
                          await SystemChannels.textInput
                              .invokeMethod<void>('TextInput.hide');

                          await Future.delayed(
                            const Duration(milliseconds: 250),
                          );

                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, item);
                          }
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
          },
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 400));

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
          .map((entry) => entry.value.copyWith(sortOrder: entry.key))
          .toList();
    });
  }

  Future<void> _saveChanges() async {
    final estimate = _estimate;

    if (estimate == null) return;

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
      final updatedEstimate = estimate.copyWith(
        clientId: _selectedClient!.id,
        propertyId: _selectedProperty!.id,
        title: _titleController.text.trim(),
        status: _status,
        scopeText: _scopeController.text.trim().isEmpty ? null : _scopeController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        validUntil: _validUntil,
      );

      final saved = await EstimateService.updateEstimateWithItems(
        estimate: updatedEstimate,
        items: _items,
        taxRate: _taxRate,
        discountValue: _discountValue,
        discountIsPercentage: _discountIsPercentage,
      );

      if (!mounted) return;

      setState(() {
        _estimate = saved;
      });

      _showSnack('Estimate updated');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save changes');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _archiveEstimate() async {
    final estimate = _estimate;
    if (estimate == null) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Archive estimate?'),
        content: Text(
          'Estimate "${estimate.title}" will be moved to archived.',
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

    if (confirmed != true) return;

    setState(() {
      _isArchiving = true;
    });

    try {
      await EstimateService.archiveEstimate(estimate.id);

      if (!mounted) return;

      setState(() {
        _status = 'archived';
        _estimate = estimate.copyWith(status: 'archived');
      });

      _showSnack('Estimate archived');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to archive estimate');
    } finally {
      if (!mounted) return;
      setState(() {
        _isArchiving = false;
      });
    }
  }

  Future<void> _deleteEstimatePermanently() async {
    final estimate = _estimate;
    if (estimate == null) return;

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text(
          'Only mistaken draft estimates should be deleted permanently. This action cannot be undone.',
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

    setState(() {
      _isDeleting = true;
    });

    try {
      await EstimateService.deleteEstimate(estimate.id);

      if (!mounted) return;

      _showSnack('Estimate deleted');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      final text = e.toString();

      if (text.contains('linked invoice') ||
          text.contains('Only draft estimates can be deleted')) {
        _showSnack(text.replaceFirst('Exception: ', ''));
      } else {
        _showSnack('Failed to delete estimate');
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
    }
  }

  Future<void> _duplicateEstimate() async {
    if (_estimate == null) return;

    setState(() {
      _isDuplicating = true;
    });

    try {
      final duplicated = await EstimateService.duplicateEstimate(_estimate!.id);

      if (!mounted) return;

      _showSnack('Estimate ${duplicated.estimateNumber} created');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to duplicate estimate');
    } finally {
      if (!mounted) return;

      setState(() {
        _isDuplicating = false;
      });
    }
  }

  Future<void> _previewPdf() async {
    final estimate = _estimate;

    if (estimate == null) {
      _showSnack('Estimate not found');
      return;
    }

    setState(() {
      _isPreviewingPdf = true;
    });

    try {
      await EstimatePdfService.previewEstimatePdf(
        estimate: estimate,
        items: _items,
        client: _selectedClient,
        property: _selectedProperty,
        companyName: _companyNameForPdf,
        companyEmail: _companyEmailForPdf,
        companyPhone: _companyPhoneForPdf,
        companyLogoUrl: _companyLogoUrlForPdf,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to open PDF');
    } finally {
      if (!mounted) return;

      setState(() {
        _isPreviewingPdf = false;
      });
    }
  }

  Future<void> _sharePdf() async {
    final estimate = _estimate;

    if (estimate == null) {
      _showSnack('Estimate not found');
      return;
    }

    setState(() {
      _isSharingPdf = true;
    });

    try {
      await EstimatePdfService.shareEstimatePdf(
        estimate: estimate,
        items: _items,
        client: _selectedClient,
        property: _selectedProperty,
        companyName: _companyNameForPdf,
        companyEmail: _companyEmailForPdf,
        companyPhone: _companyPhoneForPdf,
        companyLogoUrl: _companyLogoUrlForPdf,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to share PDF');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSharingPdf = false;
      });
    }
  }

  Future<void> _savePdfToStorage() async {
    final estimate = _estimate;

    if (estimate == null) {
      _showSnack('Estimate not found');
      return;
    }

    if (estimate.id.trim().isEmpty) {
      _showSnack('Save the estimate first');
      return;
    }

    setState(() {
      _isSavingPdf = true;
    });

    try {
      await EstimateDocumentService.saveEstimatePdf(
        estimate: estimate,
        items: _items,
        client: _selectedClient,
        property: _selectedProperty,
        companyName: _companyNameForPdf,
        companyEmail: _companyEmailForPdf,
        companyPhone: _companyPhoneForPdf,
        companyLogoUrl: _companyLogoUrlForPdf,
      );

      if (!mounted) return;

      _showSnack('PDF saved');
      await _loadDocuments();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to save PDF');
    } finally {
      if (!mounted) return;

      setState(() {
        _isSavingPdf = false;
      });
    }
  }

  String get _companyNameForPdf {
    final value = _companySettings?.companyName.trim() ?? '';
    return value.isEmpty ? 'Your Company Name' : value;
  }

  String? get _companyEmailForPdf {
    final value = _companySettings?.companyEmail?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get _companyPhoneForPdf {
    final value = _companySettings?.companyPhone?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String get _companyLogoUrlForPdf {
    return CompanyLogoHelper.resolvedLogoUrl(_companySettings);
  }

  Widget _buildCompanyLogoPreview() {
    return Container(
      width: 100,
      height: 75,
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      alignment: Alignment.center,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          CompanyLogoHelper.resolvedLogoUrl(_companySettings),
          width: 100,
          height: 75,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status.trim().toLowerCase()) {
      case 'draft':
        return CupertinoIcons.doc_text;
      case 'sent':
        return CupertinoIcons.paperplane_fill;
      case 'approved':
        return CupertinoIcons.checkmark_seal_fill;
      case 'rejected':
        return CupertinoIcons.xmark_circle_fill;
      case 'archived':
        return CupertinoIcons.archivebox_fill;
      default:
        return CupertinoIcons.tag;
    }
  }

  Widget _summaryDivider() {
    return const Divider(
      color: Color(0xFF23252E),
      height: 1,
    );
  }

  Widget _summaryPickerRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    int maxLines = 2,
  }) {
    final isPlaceholder = value.startsWith('Select');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
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
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaceholder
                            ? const Color(0xFF697086)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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

  Widget _summaryTitleRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.doc_text,
            color: Color(0xFF8E93A6),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Title',
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: _titleController,
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  cursorColor: const Color(0xFF5B8CFF),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Service Estimate • City',
                    hintStyle: TextStyle(
                      color: Color(0xFF697086),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCompactPicker({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
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
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_down,
                color: Color(0xFF8E93A6),
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryInfoRow({
    required IconData icon,
    required String label,
    required String value,
    int maxLines = 2,
  }) {
    final isPlaceholder = value.trim().isEmpty || value.trim().toLowerCase() == 'not set';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
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
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPlaceholder
                        ? const Color(0xFF697086)
                        : Colors.white,
                    fontSize: 15,
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

  Widget _historyGroup({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _actionGroup({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _summaryPanel({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        children: children,
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
        Icon(
          icon,
          color: const Color(0xFFB8C1D9),
          size: 22,
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
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
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
                const SizedBox(height: 5),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  cursorColor: const Color(0xFF5B8CFF),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
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
              ],
            ),
          ),
        ],
      ),
    );
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
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: FractionallySizedBox(
            heightFactor: 0.62,
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

                  Row(
                    children: [
                      Icon(
                        icon,
                        color: const Color(0xFFB8C1D9),
                        size: 22,
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
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFF8E93A6),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
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
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final itemTitle = titleBuilder(item);
                        final itemSubtitle = subtitleBuilder?.call(item) ?? '';
                        final itemIcon =
                            itemIconBuilder?.call(item) ?? CupertinoIcons.circle;

                        return Material(
                          color: const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pop(sheetContext, item),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF23252E),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    itemIcon,
                                    color: const Color(0xFF8E93A6),
                                    size: 19,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          itemTitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (itemSubtitle.trim().isNotEmpty) ...[
                                          const SizedBox(height: 5),
                                          Text(
                                            itemSubtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF8E93A6),
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    CupertinoIcons.chevron_right,
                                    color: Color(0xFF8E93A6),
                                    size: 16,
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

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
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
              if (trailing != null) trailing,
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

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(
          child: CupertinoActivityIndicator(radius: 16),
        ),
      );
    }

    final estimate = _estimate;
    final totals = _totals;

    if (estimate == null) {
      return const Scaffold(
        backgroundColor: background,
        body: Center(
          child: Text(
            'Estimate not found',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Container(
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF17181F), // темнее чем на скрине
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0xFF252832)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 46,
                    onPressed: () => Navigator.pop(context),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF20222B),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF2B2E38)),
                      ),
                      child: const Icon(
                        CupertinoIcons.chevron_left,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Estimate Details',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: _isArchiving ? null : _archiveEstimate,
                    icon: _isArchiving
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Icon(
                      CupertinoIcons.archivebox,
                      color: Color(0xFFB6BCD0),
                      size: 21,
                    ),
                    tooltip: 'Archive',
                  ),

                  if (_status == 'draft')
                    IconButton(
                      onPressed: _isDeleting ? null : _deleteEstimatePermanently,
                      icon: _isDeleting
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Icon(
                        CupertinoIcons.trash,
                        color: Color(0xFFFF7B7B),
                        size: 21,
                      ),
                      tooltip: 'Delete',
                    ),

                  IconButton(
                    onPressed: _isDuplicating ? null : _duplicateEstimate,
                    icon: _isDuplicating
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Icon(
                      CupertinoIcons.doc_on_doc,
                      color: Color(0xFFB6BCD0),
                      size: 21,
                    ),
                    tooltip: 'Duplicate',
                  ),

                  const SizedBox(width: 4),

                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minSize: 38,
                    color: const Color(0xFF5B8CFF),
                    borderRadius: BorderRadius.circular(14),
                    onPressed: _isSaving ? null : _saveChanges,
                    child: _isSaving
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          children: [
            _buildSectionCard(
              title: 'Estimate Summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.number,
                        color: Color(0xFF8E93A6),
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        estimate.estimateNumber,
                        style: const TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _summaryPanel(
                    children: [
                      _summaryPickerRow(
                        icon: CupertinoIcons.person,
                        label: 'Client',
                        value: _selectedClient == null
                            ? 'Select client'
                            : _selectedClient!.fullName,
                        onTap: _selectClient,
                      ),
                      _summaryDivider(),
                      _summaryPickerRow(
                        icon: CupertinoIcons.location_solid,
                        label: 'Property',
                        value: _selectedProperty == null
                            ? 'Select property'
                            : _selectedProperty!.fullAddress,
                        onTap: _selectProperty,
                      ),
                      _summaryDivider(),
                      _summaryTitleRow(),
                      _summaryDivider(),
                      Row(
                        children: [
                          Expanded(
                            child: _summaryCompactPicker(
                              icon: _statusIcon(_status),
                              label: 'Status',
                              value: EstimateFormatters.formatStatus(_status),
                              onTap: _pickStatus,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 62,
                            color: const Color(0xFF23252E),
                          ),
                          Expanded(
                            child: _summaryCompactPicker(
                              icon: CupertinoIcons.calendar,
                              label: 'Valid Until',
                              value: EstimateFormatters.formatDate(_validUntil),
                              onTap: _pickValidUntil,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Company Info',
              subtitle: 'These details are currently used in the PDF',
              child: _summaryPanel(
                children: [
                  _summaryInfoRow(
                    icon: CupertinoIcons.building_2_fill,
                    label: 'Company',
                    value: (_companySettings?.companyName.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyName
                        : 'Not set',
                    maxLines: 1,
                  ),
                  _summaryDivider(),
                  _summaryInfoRow(
                    icon: CupertinoIcons.mail_solid,
                    label: 'Email',
                    value: (_companySettings?.companyEmail?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyEmail!
                        : 'Not set',
                    maxLines: 2,
                  ),
                  _summaryDivider(),
                  _summaryInfoRow(
                    icon: CupertinoIcons.phone_fill,
                    label: 'Phone',
                    value: (_companySettings?.companyPhone?.trim().isNotEmpty ?? false)
                        ? _companySettings!.companyPhone!
                        : 'Not set',
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Scope & Notes',
              subtitle: 'Work description and additional notes',
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  children: [
                    _buildScopeNotesRow(
                      icon: CupertinoIcons.doc_text,
                      label: 'Scope',
                      value: _scopeController.text.trim(),
                      onTap: () => _openLargeTextEditor(
                        title: 'Edit Scope',
                        controller: _scopeController,
                        icon: CupertinoIcons.doc_text,
                      ),
                    ),
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                    _buildScopeNotesRow(
                      icon: CupertinoIcons.text_alignleft,
                      label: 'Notes',
                      value: _notesController.text.trim(),
                      onTap: () => _openLargeTextEditor(
                        title: 'Edit Notes',
                        controller: _notesController,
                        icon: CupertinoIcons.text_alignleft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Items',
              subtitle: 'Estimate line items',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _addOrEditItem(),
                child: const Icon(
                  CupertinoIcons.add_circled_solid,
                  color: Color(0xFF5B8CFF),
                  size: 24,
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
              subtitle: 'Tax, discount, and total',
              child: Column(
                children: [
                  _summaryPanel(
                    children: [
                      _TotalsActionRow(
                        icon: CupertinoIcons.percent,
                        label: 'Tax Rate',
                        value: '${(_taxRate * 100).toStringAsFixed(2)}%',
                        onTap: _showTaxEditor,
                        compact: true,
                      ),
                      _summaryDivider(),
                      _TotalsActionRow(
                        icon: CupertinoIcons.tag,
                        label: 'Discount',
                        value: _discountValue <= 0
                            ? 'None'
                            : _discountIsPercentage
                            ? '${_discountValue.toStringAsFixed(2)}%'
                            : EstimateFormatters.formatCurrency(_discountValue),
                        onTap: _showDiscountEditor,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _summaryPanel(
                    children: [
                      _totalInfoRow(
                        icon: CupertinoIcons.sum,
                        label: 'Subtotal',
                        value: EstimateFormatters.formatCurrency(totals.subtotal),
                      ),
                      _summaryDivider(),
                      _totalInfoRow(
                        icon: CupertinoIcons.percent,
                        label: 'Tax',
                        value: EstimateFormatters.formatCurrency(totals.tax),
                      ),
                      _totalInfoRow(
                        icon: CupertinoIcons.tag,
                        label: 'Discount',
                        value: '- ${EstimateFormatters.formatCurrency(totals.discount)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TotalGrandBar(
                    value: EstimateFormatters.formatCurrency(totals.total),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Actions',
              subtitle: 'Preview, send, save, or convert this estimate',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _actionGroup(
                    title: 'PDF',
                    subtitle: 'Preview, share, or save this estimate',
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _ActionButtonWide(
                                icon: CupertinoIcons.eye,
                                label: _isPreviewingPdf ? 'Opening...' : 'Preview PDF',
                                onTap: _isPreviewingPdf ? null : _previewPdf,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _ActionButtonWide(
                                icon: CupertinoIcons.share,
                                label: _isSharingPdf ? 'Sharing...' : 'Share PDF',
                                onTap: _isSharingPdf ? null : _sharePdf,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _ActionButtonWide(
                          icon: CupertinoIcons.arrow_down_doc,
                          label: _isSavingPdf ? 'Saving PDF...' : 'Save PDF',
                          onTap: _isSavingPdf ? null : _savePdfToStorage,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  _actionGroup(
                    title: 'Invoice',
                    subtitle: 'Convert approved estimate into invoice',
                    child: _estimate?.isApproved == true
                        ? _ActionButtonWide(
                      icon: CupertinoIcons.doc_on_clipboard,
                      label: _isConvertingToInvoice
                          ? 'Converting...'
                          : 'Convert to Invoice',
                      onTap: _isConvertingToInvoice ? null : _convertToInvoice,
                    )
                        : Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0E14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF23252E)),
                      ),
                      child: const Text(
                        'Available after estimate is approved.',
                        style: TextStyle(
                          color: Color(0xFFB8BCC8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  _actionGroup(
                    title: 'Client',
                    subtitle: 'Send estimate by email',
                    child: _ActionButtonWide(
                      icon: CupertinoIcons.paperplane,
                      label: _isSendingEmail ? 'Sending...' : 'Send Estimate',
                      onTap: _isSendingEmail ? null : _sendEstimate,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: 'Documents & History',
              subtitle: 'Saved PDFs and email activity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _historyGroup(
                    icon: CupertinoIcons.doc_text,
                    title: 'Saved Documents',
                    subtitle: _documents.isEmpty
                        ? 'No saved PDFs yet'
                        : '${_documents.length} saved PDF${_documents.length == 1 ? '' : 's'}',
                    child: _isDocumentsLoading
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CupertinoActivityIndicator(radius: 14),
                      ),
                    )
                        : _documents.isEmpty
                        ? const _EmptyDocumentsState()
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...List.generate(
                          _documents.length > 2 ? 2 : _documents.length,
                              (index) {
                            final document = _documents[index];
                            final visibleCount =
                            _documents.length > 2 ? 2 : _documents.length;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == visibleCount - 1 ? 0 : 10,
                              ),
                              child: _SavedDocumentTile(
                                document: document,
                                onOpen: () => _openSavedDocument(document),
                                onDelete: () => _deleteSavedDocument(document),
                              ),
                            );
                          },
                        ),
                        if (_documents.length > 2) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: const Color(0xFF0D0E14),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: _openSavedDocumentsSheet,
                              child: Text(
                                'View all documents (${_documents.length})',
                                style: const TextStyle(
                                  color: Color(0xFFB6BCD0),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  _historyGroup(
                    icon: CupertinoIcons.mail,
                    title: 'Email History',
                    subtitle: _emailLogs.isEmpty
                        ? 'No emails sent yet'
                        : '${_emailLogs.length} email${_emailLogs.length == 1 ? '' : 's'} sent',
                    child: _isEmailLogsLoading
                        ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CupertinoActivityIndicator(radius: 14),
                      ),
                    )
                        : _emailLogs.isEmpty
                        ? const _EmptyEmailLogsState()
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...List.generate(
                          _emailLogs.length > 2 ? 2 : _emailLogs.length,
                              (index) {
                            final log = _emailLogs[index];
                            final visibleCount =
                            _emailLogs.length > 2 ? 2 : _emailLogs.length;

                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == visibleCount - 1 ? 0 : 10,
                              ),
                              child: _EmailLogTile(log: log),
                            );
                          },
                        ),
                        if (_emailLogs.length > 2) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              color: const Color(0xFF0D0E14),
                              borderRadius: BorderRadius.circular(16),
                              onPressed: _openEmailHistorySheet,
                              child: Text(
                                'View all history (${_emailLogs.length})',
                                style: const TextStyle(
                                  color: Color(0xFFB6BCD0),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(vertical: 16),
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Save Changes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
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

class _PremiumPickerField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PremiumPickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaceholder = value.startsWith('Select');

    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            children: [
              Expanded(
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaceholder ? const Color(0xFF697086) : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.chevron_down,
                color: Color(0xFF8E93A6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final String Function(T item) itemLabel;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.itemLabel,
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
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: Color(0xFF262832), height: 1),
            Expanded(
              child: items.isEmpty
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
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];

                  return Material(
                    color: const Color(0xFF101117),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(context, item),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF23252E),
                          ),
                        ),
                        child: Text(
                          itemLabel(item),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
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

class _InlineEmptyItemsState extends StatelessWidget {
  const _InlineEmptyItemsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.square_list,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
                'No items yet. Add your first line item.',
              style: TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.hammer_fill,
                color: Color(0xFF8E93A6),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: onEdit,
                icon: const Icon(
                  CupertinoIcons.pencil,
                  color: Color(0xFFB6BCD0),
                  size: 17,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                onPressed: onDelete,
                icon: const Icon(
                  CupertinoIcons.trash,
                  color: Color(0xFFFF6B6B),
                  size: 17,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(
            color: Color(0xFF23252E),
            height: 1,
          ),
          if ((item.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    CupertinoIcons.exclamationmark_circle,
                    color: Color(0xFF8E93A6),
                    size: 17,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.description!,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
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
                  label: 'Unit Price',
                  value: EstimateFormatters.formatCurrency(item.unitPrice),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LineTotalBar(
            value: EstimateFormatters.formatCurrency(item.lineTotal),
          ),
        ],
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  const _SmallIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? const Color(0xFFB6BCD0);

    return Material(
      color: const Color(0xFF171922),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Icon(
            icon,
            size: 16,
            color: effectiveColor,
          ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F212A)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: emphasized ? 15 : 13,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalGrandBar extends StatelessWidget {
  final String value;

  const _TotalGrandBar({
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5B8CFF).withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.money_dollar_circle_fill,
            color: Color(0xFF8E93A6),
            size: 22,
          ),
          const SizedBox(width: 10),
          const Text(
            'Total',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTotalBar extends StatelessWidget {
  final String value;

  const _LineTotalBar({
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F212A)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.money_dollar_circle,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          const SizedBox(width: 10),
          const Text(
            'Line Total',
            style: TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsActionRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData icon;
  final bool compact;

  const _TotalsActionRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: compact ? 13 : 14,
          ),
          decoration: compact
              ? null
              : BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 18,
              ),
              const SizedBox(width: 10),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                CupertinoIcons.chevron_right,
                color: Color(0xFF8E93A6),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmphasized;

  const _SummaryLine({
    required this.label,
    required this.value,
    this.isEmphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: isEmphasized ? Colors.white : const Color(0xFF8E93A6),
            fontSize: isEmphasized ? 16 : 14,
            fontWeight: isEmphasized ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: isEmphasized ? 18 : 15,
            fontWeight: isEmphasized ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class _ActionButtonWide extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButtonWide({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;

    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDisabled
                  ? const Color(0xFF1A1C24)
                  : const Color(0xFF23252E),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isDisabled
                    ? const Color(0xFF5E6475)
                    : const Color(0xFFB6BCD0),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isDisabled
                      ? const Color(0xFF5E6475)
                      : Colors.white,
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
    return Material(
      color: selected ? const Color(0xFF5B8CFF) : const Color(0xFF101117),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF5B8CFF) : const Color(0xFF23252E),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFB6BCD0),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitDropdownField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String?> onChanged;

  const _UnitDropdownField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const units = [
      'fixed',
      'sqft',
      'room',
      'wall',
      'hour',
      'item',
      'day',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
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
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF15161C),
              icon: const Icon(
                CupertinoIcons.chevron_down,
                color: Color(0xFF8E93A6),
                size: 18,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              items: units.map((unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(
                    EstimateFormatters.formatUnit(unit),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
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

class _EmptyDocumentsState extends StatelessWidget {
  const _EmptyDocumentsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.doc,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No saved PDF documents yet.',
              style: TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedDocumentTile extends StatelessWidget {
  final EstimateDocumentModel document;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _SavedDocumentTile({
    required this.document,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            EstimateFormatters.formatDateTime(document.createdAt),
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HistoryActionButton(
                  icon: CupertinoIcons.eye,
                  label: 'Open',
                  onTap: onOpen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HistoryActionButton(
                  icon: CupertinoIcons.trash,
                  label: 'Delete',
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

class _HistoryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HistoryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0D0E14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1F212A)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: const Color(0xFFB6BCD0),
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
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

class _EmptyEmailLogsState extends StatelessWidget {
  const _EmptyEmailLogsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: const Row(
        children: [
          Icon(
            CupertinoIcons.mail,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No email history yet.',
              style: TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailLogTile extends StatelessWidget {
  final EstimateEmailLogModel log;

  const _EmailLogTile({
    required this.log,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'sent':
        return const Color(0xFF33C27F);
      case 'failed':
        return const Color(0xFFE05A5A);
      case 'pending':
        return const Color(0xFF4A90E2);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  String? _templateLabel(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'standard':
        return 'STANDARD';
      case 'updated':
        return 'UPDATED';
      case 'follow_up':
        return 'FOLLOW-UP';
      default:
        return null;
    }
  }

  Color _templateColor(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'standard':
        return const Color(0xFF5B8CFF);
      case 'updated':
        return const Color(0xFFFFB84D);
      case 'follow_up':
        return const Color(0xFFB07CFF);
      default:
        return const Color(0xFF8F96AB);
    }
  }

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: color.withOpacity(0.35),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(log.status);
    final templateLabel = _templateLabel(log.templateType);
    final templateColor = _templateColor(log.templateType);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.recipientEmail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            log.subject,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFB6BCD0),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTag(log.status.toUpperCase(), statusColor),
              if (templateLabel != null)
                _buildTag(templateLabel, templateColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            EstimateFormatters.formatDateTime(log.sentAt ?? log.createdAt),
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if ((log.providerName ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Provider: ${log.providerName}',
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
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
        heightFactor: 0.98,
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
                    CupertinoIcons.cube_box,
                    color: Color(0xFFB8C1D9),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Choose Unit',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Expanded(
                child: ListView.separated(
                  itemCount: units.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final unit = units[index];
                    final selected = unit == selectedUnit;

                    return Material(
                      color: selected
                          ? const Color(0xFF16233F)
                          : const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pop(context, unit),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF5B8CFF)
                                  : const Color(0xFF23252E),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _unitIcon(unit),
                                color: selected
                                    ? const Color(0xFF8FB0FF)
                                    : const Color(0xFF8E93A6),
                                size: 19,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  EstimateFormatters.formatUnit(unit),
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
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
                                    ? const Color(0xFF5B8CFF)
                                    : const Color(0xFF8E93A6),
                                size: selected ? 20 : 16,
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

class _CenteredMiniInput extends StatelessWidget {
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;

  const _CenteredMiniInput({
    required this.icon,
    required this.label,
    required this.controller,
    required this.hintText,
    required this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: const Color(0xFF8E93A6),
            size: 16,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            textAlign: TextAlign.center,
            cursorColor: const Color(0xFF5B8CFF),
            style: const TextStyle(
              color: Colors.white,
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
        ],
      ),
    );
  }
}

class _CalendarWeekDay extends StatelessWidget {
  final String label;

  const _CalendarWeekDay(this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8E93A6),
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AddEditEstimateItemPage extends StatefulWidget {
  final String estimateId;
  final EstimateItemModel? existingItem;
  final int? index;
  final int itemsLength;

  const _AddEditEstimateItemPage({
    required this.estimateId,
    this.existingItem,
    this.index,
    required this.itemsLength,
  });

  @override
  State<_AddEditEstimateItemPage> createState() =>
      _AddEditEstimateItemPageState();
}

class _AddEditEstimateItemPageState extends State<_AddEditEstimateItemPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitPriceController;

  late String _selectedUnit;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();

    final existingItem = widget.existingItem;

    _titleController = TextEditingController(
      text: existingItem?.title ?? '',
    );

    _descriptionController = TextEditingController(
      text: existingItem?.description ?? '',
    );

    _quantityController = TextEditingController(
      text: existingItem != null && existingItem.quantity != 0
          ? EstimateFormatters.formatQuantity(existingItem.quantity)
          : '',
    );

    _unitPriceController = TextEditingController(
      text: existingItem != null && existingItem.unitPrice != 0
          ? EstimateFormatters.formatNumber(existingItem.unitPrice)
          : '',
    );

    _selectedUnit = existingItem?.unit ?? 'fixed';
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isClosing) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final double quantity =
    EstimateCalculator.parseNumber(_quantityController.text).toDouble();

    final double unitPrice =
    EstimateCalculator.parseNumber(_unitPriceController.text).toDouble();

    final double normalizedQuantity = quantity <= 0 ? 1.0 : quantity;

    final item = EstimateItemModel(
      id: widget.existingItem?.id ?? '',
      estimateId: widget.existingItem?.estimateId ?? widget.estimateId,
      title: title,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      unit: _selectedUnit,
      quantity: normalizedQuantity,
      unitPrice: unitPrice,
      lineTotal: EstimateCalculator.calculateLineTotal(
        quantity: normalizedQuantity,
        unitPrice: unitPrice,
      ),
      sortOrder: widget.index ?? widget.itemsLength,
      createdAt: widget.existingItem?.createdAt,
    );

    _isClosing = true;

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 350));

    if (!mounted) return;

    Navigator.of(context).pop(item);
  }

  Widget _itemPanel({
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _itemInputRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment:
        maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 4 : 0),
            child: Icon(
              icon,
              color: const Color(0xFF8E93A6),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                const SizedBox(height: 5),
                TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  maxLines: maxLines,
                  minLines: maxLines > 1 ? 3 : 1,
                  cursorColor: const Color(0xFF5B8CFF),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemPickerRow({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF8E93A6),
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
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
                    const SizedBox(height: 5),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
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

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.existingItem == null ? 'Add Item' : 'Edit Item',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(14),
              onPressed: _submit,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF15161C),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF262832)),
              ),
              child: Column(
                children: [
                  _itemPanel(
                    children: [
                      _itemInputRow(
                        icon: CupertinoIcons.tag,
                        label: 'Title',
                        controller: _titleController,
                        hintText: 'Service item title',
                      ),
                      const Divider(color: Color(0xFF23252E), height: 1),
                      _itemInputRow(
                        icon: CupertinoIcons.text_alignleft,
                        label: 'Description',
                        controller: _descriptionController,
                        hintText: 'Optional description',
                        maxLines: 3,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _itemPanel(
                    children: [
                      _itemPickerRow(
                        icon: CupertinoIcons.cube_box,
                        label: 'Unit',
                        value: EstimateFormatters.formatUnit(_selectedUnit),
                        onTap: () async {
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
                            backgroundColor: const Color(0xFF15161C),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                            ),
                            builder: (_) {
                              return _UnitSelectionSheet(
                                units: units,
                                selectedUnit: _selectedUnit,
                              );
                            },
                          );

                          if (unit == null) return;

                          setState(() {
                            _selectedUnit = unit;
                          });
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _itemPanel(
                    children: [
                      _itemInputRow(
                        icon: CupertinoIcons.number,
                        label: 'Quantity',
                        controller: _quantityController,
                        hintText: '1',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const Divider(color: Color(0xFF23252E), height: 1),
                      _itemInputRow(
                        icon: CupertinoIcons.money_dollar_circle,
                        label: 'Unit Price',
                        controller: _unitPriceController,
                        hintText: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      color: const Color(0xFF5B8CFF),
                      borderRadius: BorderRadius.circular(16),
                      onPressed: _submit,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.existingItem == null
                                ? CupertinoIcons.plus_circle
                                : CupertinoIcons.checkmark_circle,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.existingItem == null
                                ? 'Add Item'
                                : 'Save Changes',
                            style: const TextStyle(
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
            ),
          ],
        ),
      ),
    );
  }
}