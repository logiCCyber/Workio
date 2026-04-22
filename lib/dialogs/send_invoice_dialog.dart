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
    backgroundColor: const Color(0xFF15161C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
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

    _selectedTemplate = _resolveDefaultTemplate();
    _applyTemplate(_selectedTemplate);

    _useLatestSavedPdf = widget.latestDocument != null;
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
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
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choose Email Template',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _TemplatePickerTile(
                  title: 'Standard Invoice',
                  subtitle: 'Default invoice email',
                  selected: _selectedTemplate == InvoiceEmailTemplate.standard,
                  onTap: () => Navigator.pop(
                    context,
                    InvoiceEmailTemplate.standard,
                  ),
                ),
                const SizedBox(height: 10),
                _TemplatePickerTile(
                  title: 'Updated Invoice',
                  subtitle: 'Use when invoice was revised',
                  selected: _selectedTemplate == InvoiceEmailTemplate.updated,
                  onTap: () => Navigator.pop(
                    context,
                    InvoiceEmailTemplate.updated,
                  ),
                ),
                const SizedBox(height: 10),
                _TemplatePickerTile(
                  title: 'Payment Reminder',
                  subtitle: 'Friendly reminder about payment',
                  selected: _selectedTemplate == InvoiceEmailTemplate.reminder,
                  onTap: () => Navigator.pop(
                    context,
                    InvoiceEmailTemplate.reminder,
                  ),
                ),
                const SizedBox(height: 10),
                _TemplatePickerTile(
                  title: 'Overdue Invoice',
                  subtitle: 'Use when invoice is overdue',
                  selected: _selectedTemplate == InvoiceEmailTemplate.overdue,
                  onTap: () => Navigator.pop(
                    context,
                    InvoiceEmailTemplate.overdue,
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

  @override
  Widget build(BuildContext context) {
    final latestDocument = widget.latestDocument;

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
            const Text(
              'Send Invoice',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            _PremiumTextField(
              controller: _toController,
              label: 'To',
              hintText: 'client@email.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _SelectionCard(
              label: 'Email Template',
              title: _templateTitle,
              subtitle: _templateSubtitle,
              onTap: _pickTemplate,
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _subjectController,
              label: 'Subject',
              hintText: 'Invoice INV-...',
            ),
            const SizedBox(height: 12),
            _PremiumTextField(
              controller: _messageController,
              label: 'Message',
              hintText: 'Write your message...',
              maxLines: 8,
            ),
            const SizedBox(height: 14),
            _ChoiceCard(
              title: 'Attachment Source',
              subtitle: latestDocument != null
                  ? 'Latest PDF: ${latestDocument.fileName}'
                  : 'No saved PDF found yet',
              child: Column(
                children: [
                  _SwitchRow(
                    label: 'Use latest saved PDF',
                    value: _useLatestSavedPdf,
                    onChanged: latestDocument == null
                        ? null
                        : (value) {
                      setState(() {
                        _useLatestSavedPdf = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _SwitchRow(
                    label: 'Generate new PDF if needed',
                    value: _generateNewPdfIfMissing,
                    onChanged: (value) {
                      setState(() {
                        _generateNewPdfIfMissing = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: const Color(0xFF5B8CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: _submit,
                child: const Text(
                  'Continue',
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
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _TemplatePickerTile({
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF16233F) : const Color(0xFF101117),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF5B8CFF)
                : const Color(0xFF23252E),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 12,
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
                  ? const Color(0xFF5B8CFF)
                  : const Color(0xFF5E6475),
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
            activeColor: const Color(0xFF5B8CFF),
          ),
        ],
      ),
    );
  }
}