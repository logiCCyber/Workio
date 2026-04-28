import 'package:supabase_flutter/supabase_flutter.dart';

class ParseEstimateMiniResult {
  final String? serviceType;
  final double? sqft;
  final int? rooms;
  final double? hours;
  final bool? materialsIncluded;
  final bool? laborOnly;
  final bool projectSizeRequired;
  final List<Map<String, dynamic>> parsedMaterials;
  final List<String> reasoningHints;
  final List<String> followupHints;

  const ParseEstimateMiniResult({
    required this.serviceType,
    required this.sqft,
    required this.rooms,
    required this.hours,
    required this.materialsIncluded,
    required this.laborOnly,
    required this.projectSizeRequired,
    required this.parsedMaterials,
    required this.reasoningHints,
    required this.followupHints,
  });

  factory ParseEstimateMiniResult.fromMap(Map<String, dynamic> map) {
    double? toDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString().replaceAll(',', '.'));
    }

    int? toInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    bool? toBool(dynamic value) {
      if (value == null) return null;
      if (value is bool) return value;
      final text = value.toString().trim().toLowerCase();
      if (text == 'true' || text == '1' || text == 'yes') return true;
      if (text == 'false' || text == '0' || text == 'no') return false;
      return null;
    }

    List<String> toStringList(dynamic value) {
      if (value is! List) return const [];
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<Map<String, dynamic>> toMapList(dynamic value) {
      if (value is! List) return const [];
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    final rawServiceType =
    (map['serviceType'] ?? map['service_type'])?.toString().trim();

    return ParseEstimateMiniResult(
      serviceType: (rawServiceType == null || rawServiceType.isEmpty)
          ? null
          : rawServiceType.toLowerCase(),
      sqft: toDouble(map['sqft']),
      rooms: toInt(map['rooms']),
      hours: toDouble(map['hours']),
      materialsIncluded: toBool(
        map['materialsIncluded'] ?? map['materials_included'],
      ),
      laborOnly: toBool(
        map['laborOnly'] ?? map['labor_only'],
      ),
      projectSizeRequired: toBool(
        map['projectSizeRequired'] ?? map['project_size_required'],
      ) ??
          false,
      parsedMaterials: toMapList(
        map['parsedMaterials'] ?? map['parsed_materials'],
      ),
      reasoningHints: toStringList(
        map['reasoningHints'] ?? map['reasoning_hints'],
      ),
      followupHints: toStringList(
        map['followupHints'] ?? map['followup_hints'],
      ),
    );
  }
}

class ParseEstimateMiniService {
  ParseEstimateMiniService._();

  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<ParseEstimateMiniResult> parse({
    required String prompt,
    required Map<String, dynamic> localParsed,
  }) async {
    final response = await _supabase.functions.invoke(
      'parse-estimate-mini',
      body: {
        'prompt': prompt,
        'localParsed': localParsed,
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception('Invalid parse-estimate-mini response');
    }

    final map = Map<String, dynamic>.from(data as Map);

    final error = map['error']?.toString().trim() ?? '';
    if (error.isNotEmpty) {
      throw Exception(error);
    }

    return ParseEstimateMiniResult.fromMap(map);
  }
}