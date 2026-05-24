import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/invoice_document_model.dart';
import '../models/invoice_model.dart';

class SendInvoiceDialogResult {
  final String recipientEmail;
  final String subject;
  final String messageBody;
  final bool useLatestSavedPdf;
  final bool generateNewPdfIfMissing;
  final String? selectedDocumentId;
  final String templateType;

  const SendInvoiceDialogResult({
    required this.recipientEmail,
    required this.subject,
    required this.messageBody,
    required this.useLatestSavedPdf,
    required this.generateNewPdfIfMissing,
    this.selectedDocumentId,
    required this.templateType,
  });
}

enum InvoiceEmailTemplate {
  standard,
  updated,
  reminder,
  overdue,
}

Future<SendInvoiceDialogResult?> showSendInvoiceDialog({
  required BuildContext context,
  required InvoiceModel invoice,
  ClientModel? client,
  CompanySettingsModel? companySettings,
  InvoiceDocumentModel? latestDocument,
}) {
  return showModalBottomSheet<SendInvoiceDialogResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF1B1F28),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.86,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => _SendInvoiceDialogContent(
      invoice: invoice,
      client: client,
      companySettings: companySettings,
      latestDocument: latestDocument,
    ),
  );
}

class _SendInvoiceDialogContent extends StatefulWidget {
  final InvoiceModel invoice;
  final ClientModel? client;
  final CompanySettingsModel? companySettings;
  final InvoiceDocumentModel? latestDocument;

  const _SendInvoiceDialogContent({
    required this.invoice,
    this.client,
    this.companySettings,
    this.latestDocument,
  });

  @override
  State<_SendInvoiceDialogContent> createState() =>
      _SendInvoiceDialogContentState();
}

class _SendInvoiceDialogContentState extends State<_SendInvoiceDialogContent> {
  late final TextEditingController _toController;
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  late final ScrollController _messageScrollController;

  late bool _useLatestSavedPdf;
  bool _generateNewPdfIfMissing = true;

  late InvoiceEmailTemplate _selectedTemplate;

  @override
  void initState() {
    super.initState();

    _toController = TextEditingController(
      text: widget.client?.email?.trim() ?? '',
    );
    _subjectController = TextEditingController();
    _messageController = TextEditingController();
    _messageScrollController = ScrollController();

    _selectedTemplate = _resolveDefaultTemplate();
    _applyTemplate(_selectedTemplate);

    _useLatestSavedPdf = widget.latestDocument != null;
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  InvoiceEmailTemplate _resolveDefaultTemplate() {
    final status = widget.invoice.status.trim().toLowerCase();

    if (status == 'overdue') {
      return InvoiceEmailTemplate.overdue;
    }

    if (status == 'sent') {
      return InvoiceEmailTemplate.reminder;
    }

    return InvoiceEmailTemplate.standard;
  }

  String get _clientName {
    final value = widget.client?.fullName.trim() ?? '';
    return value.isEmpty ? 'Client' : value;
  }

  String get _companyName {
    final value = widget.companySettings?.companyName.trim() ?? '';
    return value.isEmpty ? 'Your Company' : value;
  }

  String get _invoiceNumber {
    final value = widget.invoice.invoiceNumber.trim();
    return value.isEmpty ? 'INVOICE' : value;
  }

  String get _templateTitle {
    switch (_selectedTemplate) {
      case InvoiceEmailTemplate.standard:
        return 'Standard Invoice';
      case InvoiceEmailTemplate.updated:
        return 'Updated Invoice';
      case InvoiceEmailTemplate.reminder:
        return 'Payment Reminder';
      case InvoiceEmailTemplate.overdue:
        return 'Overdue Invoice';
    }
  }

  String get _templateSubtitle {
    switch (_selectedTemplate) {
      case InvoiceEmailTemplate.standard:
        return 'Default invoice email';
      case InvoiceEmailTemplate.updated:
        return 'Use when invoice was revised';
      case InvoiceEmailTemplate.reminder:
        return 'Friendly reminder about payment';
      case InvoiceEmailTemplate.overdue:
        return 'Use when invoice is overdue';
    }
  }

  String get _templateKey {
    switch (_selectedTemplate) {
      case InvoiceEmailTemplate.standard:
        return 'standard';
      case InvoiceEmailTemplate.updated:
        return 'updated';
      case InvoiceEmailTemplate.reminder:
        return 'reminder';
      case InvoiceEmailTemplate.overdue:
        return 'overdue';
    }
  }

  void _applyTemplate(InvoiceEmailTemplate template) {
    _selectedTemplate = template;
    _subjectController.text = _buildSubject(template);
    _messageController.text = _buildMessage(template);
  }

  String _buildSubject(InvoiceEmailTemplate template) {
    switch (template) {
      case InvoiceEmailTemplate.standard:
        return 'Invoice $_invoiceNumber';
      case InvoiceEmailTemplate.updated:
        return 'Updated Invoice $_invoiceNumber';
      case InvoiceEmailTemplate.reminder:
        return 'Payment Reminder — Invoice $_invoiceNumber';
      case InvoiceEmailTemplate.overdue:
        return 'Overdue Invoice $_invoiceNumber';
    }
  }

  String _buildMessage(InvoiceEmailTemplate template) {
    switch (template) {
      case InvoiceEmailTemplate.standard:
        return '''
Hello $_clientName,

Please find attached your invoice $_invoiceNumber.

Thank you for your business.

Best regards,
$_companyName
''';

      case InvoiceEmailTemplate.updated:
        return '''
Hello $_clientName,

Please find attached the updated invoice $_invoiceNumber.

Best regards,
$_companyName
''';

      case InvoiceEmailTemplate.reminder:
        return '''
Hello $_clientName,

This is a friendly reminder regarding invoice $_invoiceNumber.

Please review the attached invoice and let us know if you have any questions.

Best regards,
$_companyName
''';

      case InvoiceEmailTemplate.overdue:
        return '''
Hello $_clientName,

This is a reminder that invoice $_invoiceNumber is overdue.

Please review the attached invoice and contact us if anything needs clarification.

Best regards,
$_companyName
''';
    }
  }

  Future<void> _pickTemplate() async {
    final selected = await showModalBottomSheet<InvoiceEmailTemplate>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF1B1F28),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) {
        final scrollController = ScrollController();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A4F5E),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),

                const Row(
                  children: [
                    Icon(
                      CupertinoIcons.mail_solid,
                      color: Color(0xFFF3F6FC),
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose Email Template',
                            style: TextStyle(
                              color: Color(0xFFF1F4F8),
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Pick the best email style for this invoice',
                            style: TextStyle(
                              color: Color(0xFFA0A7B8),
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

            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                        _TemplatePickerTile(
                          icon: CupertinoIcons.doc_text,
                          title: 'Standard Invoice',
                          subtitle: 'Default invoice email',
                          selected:
                          _selectedTemplate == InvoiceEmailTemplate.standard,
                          onTap: () => Navigator.pop(
                            context,
                            InvoiceEmailTemplate.standard,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _TemplatePickerTile(
                          icon: CupertinoIcons.doc_append,
                          title: 'Updated Invoice',
                          subtitle: 'Use when invoice was revised',
                          selected:
                          _selectedTemplate == InvoiceEmailTemplate.updated,
                          onTap: () => Navigator.pop(
                            context,
                            InvoiceEmailTemplate.updated,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _TemplatePickerTile(
                          icon: CupertinoIcons.bell,
                          title: 'Payment Reminder',
                          subtitle: 'Friendly reminder about payment',
                          selected:
                          _selectedTemplate == InvoiceEmailTemplate.reminder,
                          onTap: () => Navigator.pop(
                            context,
                            InvoiceEmailTemplate.reminder,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _TemplatePickerTile(
                          icon: CupertinoIcons.exclamationmark_circle,
                          title: 'Overdue Invoice',
                          subtitle: 'Use when invoice is overdue',
                          selected:
                          _selectedTemplate == InvoiceEmailTemplate.overdue,
                          onTap: () => Navigator.pop(
                            context,
                            InvoiceEmailTemplate.overdue,
                          ),
                        ),
                ],
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
      _applyTemplate(selected);
    });
  }

  void _submit() {
    final recipient = _toController.text.trim();
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (recipient.isEmpty) return;
    if (subject.isEmpty) return;
    if (message.isEmpty) return;

    Navigator.pop(
      context,
      SendInvoiceDialogResult(
        recipientEmail: recipient,
        subject: subject,
        templateType: _templateKey,
        messageBody: message,
        useLatestSavedPdf: _useLatestSavedPdf,
        generateNewPdfIfMissing: _generateNewPdfIfMissing,
        selectedDocumentId:
        _useLatestSavedPdf ? widget.latestDocument?.id : null,
      ),
    );
  }

  Widget _sendDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: const Color(0xFF3A4150),
    );
  }

  Widget _sendPanel({
    required List<Widget> children,
    bool light = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: light
            ? const Color(0xFF242730)
            : const Color(0xFF151922),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: light
              ? const Color(0xFF343846)
              : const Color(0xFF343A49),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.018),
            blurRadius: 10,
            spreadRadius: -5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _sendInputRow({
    required IconData icon,
    Color iconColor = const Color(0xFFF3F6FC),
    required String label,
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    ScrollController? scrollController,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              icon,
              color: iconColor,
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
                    color: Color(0xFFF3F6FC),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                RawScrollbar(
                  controller: scrollController,
                  thumbColor: const Color(0xFFE9EDF6).withValues(alpha: 0.42),
                  radius: const Radius.circular(999),
                  thickness: scrollController == null ? 0 : 3,
                  thumbVisibility: scrollController != null,
                  child: TextField(
                    controller: controller,
                    scrollController: scrollController,
                    keyboardType: keyboardType,
                    maxLines: maxLines,
                    minLines: maxLines > 1 ? 5 : 1,
                    cursorColor: const Color(0xFF7C5CFF),
                    style: const TextStyle(
                      color: Color(0xFFF1F4F8),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sendPickerRow({
    required IconData icon,
    Color iconColor = const Color(0xFFF3F6FC),
    required String label,
    required String title,
    required String subtitle,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  icon,
                  color: iconColor,
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
                    Text(
                      title,
                      style: const TextStyle(
                        color: const Color(0xFFF1F4F8),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFFA0A7B8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_right,
                color: Color(0xFFF3F6FC),
                size: 16,
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sendSwitchRow({
    required IconData icon,
    Color iconColor = const Color(0xFFF3F6FC),
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final disabled = onChanged == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(
              icon,
              color: disabled ? const Color(0xFF60697A) : iconColor,
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
                  style: TextStyle(
                    color: disabled
                        ? const Color(0xFF72798A)
                        : const Color(0xFFF1F4F8),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: disabled
                        ? const Color(0xFF60697A)
                        : const Color(0xFFA0A7B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF7C5CFF),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestDocument = widget.latestDocument;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(
                    CupertinoIcons.paperplane_fill,
                    color: Color(0xFFF3F6FC),
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Invoice',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Review email details before sending',
                        style: TextStyle(
                          color: Color(0xFFA1A7B8),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            _sendPanel(
              children: [
                _sendInputRow(
                  icon: CupertinoIcons.mail,
                  iconColor: const Color(0xFFF3F6FC),
                  label: 'To',
                  controller: _toController,
                  hintText: 'client@email.com',
                  keyboardType: TextInputType.emailAddress,
                ),
                _sendDivider(),
                _sendPickerRow(
                  icon: CupertinoIcons.square_stack_3d_up,
                  iconColor: const Color(0xFFFFC107),
                  label: 'Email Template',
                  title: _templateTitle,
                  subtitle: _templateSubtitle,
                  onTap: _pickTemplate,
                ),
              ],
            ),

            const SizedBox(height: 14),

            _sendPanel(
              children: [
                _sendInputRow(
                  icon: CupertinoIcons.textformat,
                  iconColor: const Color(0xFF0EA5E9),
                  label: 'Subject',
                  controller: _subjectController,
                  hintText: 'Invoice INV-...',
                ),
                _sendDivider(),
                _sendInputRow(
                  icon: CupertinoIcons.text_bubble_fill,
                  iconColor: const Color(0xFFF3F6FC),
                  label: 'Message',
                  controller: _messageController,
                  hintText: 'Write your message...',
                  maxLines: 8,
                  scrollController: _messageScrollController,
                ),
              ],
            ),

            const SizedBox(height: 14),

            _sendPanel(
              light: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(
                          CupertinoIcons.paperclip,
                          color: Color(0xFFF3F6FC),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Attachment Source',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              latestDocument != null
                                  ? 'Latest PDF: ${latestDocument.fileName}'
                                  : 'No saved PDF found yet',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF8E93A6),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _sendDivider(),
                _sendSwitchRow(
                  icon: CupertinoIcons.doc_text,
                  iconColor: const Color(0xFFF3F6FC),
                  label: 'Use latest saved PDF',
                  subtitle: latestDocument == null
                      ? 'Save a PDF first to use this option'
                      : 'Attach the latest saved invoice PDF',
                  value: _useLatestSavedPdf,
                  onChanged: latestDocument == null
                      ? null
                      : (value) {
                    setState(() {
                      _useLatestSavedPdf = value;
                    });
                  },
                ),
                _sendDivider(),
                _sendSwitchRow(
                  icon: CupertinoIcons.arrow_clockwise,
                  iconColor: const Color(0xFFD94A4A),
                  label: 'Generate new PDF if needed',
                  subtitle: 'Create a fresh PDF if no saved file is available',
                  value: _generateNewPdfIfMissing,
                  onChanged: (value) {
                    setState(() {
                      _generateNewPdfIfMissing = value;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 15),
                color: const Color(0xFF7C5CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: _submit,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.paperplane_fill,
                      color: Colors.white,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Continue',
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
      ),
    );
  }
}

class _PremiumTextField extends StatelessWidget {
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
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              maxLines: maxLines,
              minLines: maxLines == 1 ? 1 : maxLines,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
              cursorColor: const Color(0xFF5B8CFF),
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

class _ChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
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
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String label;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF101117),
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
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFF8E93A6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplatePickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TemplatePickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF7C5CFF).withValues(alpha: 0.16)
              : const Color(0xFF1A1E27),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFF927BFF)
                : const Color(0xFF323847),
            width: 1.1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.16 : 0.10),
              blurRadius: selected ? 18 : 12,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFFF3F6FC),
              size: 20,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFFA0A7B8),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? const Color(0xFF8D74FF)
                  : const Color(0xFF697086),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F212A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: disabled ? const Color(0xFF5E6475) : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF7C5CFF),
          ),
        ],
      ),
    );
  }
}