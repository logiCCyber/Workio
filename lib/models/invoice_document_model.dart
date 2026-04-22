class InvoiceDocumentModel {
  final String id;
  final String invoiceId;
  final String fileName;
  final String filePath;
  final String? fileUrl;
  final DateTime? createdAt;

  const InvoiceDocumentModel({
    required this.id,
    required this.invoiceId,
    required this.fileName,
    required this.filePath,
    this.fileUrl,
    this.createdAt,
  });

  factory InvoiceDocumentModel.fromMap(Map<String, dynamic> map) {
    return InvoiceDocumentModel(
      id: map['id']?.toString() ?? '',
      invoiceId: map['invoice_id']?.toString() ?? '',
      fileName: map['file_name']?.toString() ?? '',
      filePath: map['file_path']?.toString() ?? '',
      fileUrl: map['file_url']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'file_name': fileName,
      'file_path': filePath,
      'file_url': fileUrl,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'invoice_id': invoiceId,
      'file_name': fileName,
      'file_path': filePath,
      'file_url': fileUrl,
    };
  }

  InvoiceDocumentModel copyWith({
    String? id,
    String? invoiceId,
    String? fileName,
    String? filePath,
    String? fileUrl,
    DateTime? createdAt,
  }) {
    return InvoiceDocumentModel(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      fileUrl: fileUrl ?? this.fileUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}