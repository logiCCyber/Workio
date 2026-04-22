class InvoiceEmailLogModel {
  final String id;
  final String invoiceId;
  final String adminAuthId;
  final String recipientEmail;
  final String subject;
  final String? messageBody;
  final String? pdfDocumentId;
  final String status;
  final String? providerName;
  final String? providerMessageId;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final String? templateType;

  const InvoiceEmailLogModel({
    required this.id,
    required this.invoiceId,
    required this.adminAuthId,
    required this.recipientEmail,
    required this.subject,
    this.messageBody,
    this.pdfDocumentId,
    required this.status,
    this.providerName,
    this.providerMessageId,
    this.sentAt,
    this.createdAt,
    this.templateType,
  });

  factory InvoiceEmailLogModel.fromMap(Map<String, dynamic> map) {
    return InvoiceEmailLogModel(
      id: map['id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      adminAuthId: map['admin_auth_id']?.toString() ?? '',
      recipientEmail: map['recipient_email']?.toString() ?? '',
      subject: map['subject']?.toString() ?? '',
      messageBody: map['message_body']?.toString(),
      pdfDocumentId: map['pdf_document_id']?.toString(),
      status: map['status']?.toString() ?? 'sent',
      providerName: map['provider_name']?.toString(),
      providerMessageId: map['provider_message_id']?.toString(),
      templateType: map['template_type']?.toString(),
      sentAt: map['sent_at'] != null
          ? DateTime.tryParse(map['sent_at'].toString())
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'admin_auth_id': adminAuthId,
      'recipient_email': recipientEmail,
      'subject': subject,
      'message_body': messageBody,
      'pdf_document_id': pdfDocumentId,
      'status': status,
      'provider_name': providerName,
      'provider_message_id': providerMessageId,
      'sent_at': sentAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'template_type': templateType,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'invoice_id': invoiceId,
      'admin_auth_id': adminAuthId,
      'recipient_email': recipientEmail,
      'subject': subject,
      'message_body': messageBody,
      'pdf_document_id': pdfDocumentId,
      'status': status,
      'provider_name': providerName,
      'provider_message_id': providerMessageId,
      'sent_at': sentAt?.toIso8601String(),
      'template_type': templateType,
    };
  }

  InvoiceEmailLogModel copyWith({
    String? id,
    String? invoiceId,
    String? adminAuthId,
    String? recipientEmail,
    String? subject,
    String? messageBody,
    String? pdfDocumentId,
    String? status,
    String? providerName,
    String? providerMessageId,
    DateTime? sentAt,
    DateTime? createdAt,
    String? templateType,
  }) {
    return InvoiceEmailLogModel(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      adminAuthId: adminAuthId ?? this.adminAuthId,
      recipientEmail: recipientEmail ?? this.recipientEmail,
      subject: subject ?? this.subject,
      messageBody: messageBody ?? this.messageBody,
      pdfDocumentId: pdfDocumentId ?? this.pdfDocumentId,
      status: status ?? this.status,
      providerName: providerName ?? this.providerName,
      providerMessageId: providerMessageId ?? this.providerMessageId,
      sentAt: sentAt ?? this.sentAt,
      createdAt: createdAt ?? this.createdAt,
      templateType: templateType ?? this.templateType,
    );
  }

  bool get isPending => status == 'pending';
  bool get isSent => status == 'sent';
  bool get isFailed => status == 'failed';
}