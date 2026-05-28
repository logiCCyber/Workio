import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';

import '../models/ai_estimate_result_model.dart';
import '../models/estimate_item_model.dart';
import '../models/ai_parsed_request_model.dart';
import '../services/company_settings_service.dart';
import '../services/smart_estimate_service.dart';
import '../utils/estimate_calculator.dart';
import '../utils/estimate_formatters.dart';
import '../utils/workio_icon_mapper.dart';

import '../models/client_model.dart';
import '../models/property_model.dart';
import '../models/estimate_model.dart';
import '../models/estimate_price_rule_model.dart';

import '../services/client_service.dart';
import '../services/property_service.dart';
import '../services/estimate_service.dart';
import '../services/parse_estimate_mini_service.dart';
import '../services/estimate_price_rules_service.dart';
import '../services/estimate_rule_resolution_service.dart';

import 'estimate_details_screen.dart';
import 'estimate_list_screen.dart';
import '../dialogs/add_client_dialog.dart';
import '../dialogs/add_property_dialog.dart';

class QuickQuoteScreen extends StatefulWidget {
  const QuickQuoteScreen({super.key});

  @override
  State<QuickQuoteScreen> createState() => _QuickQuoteScreenState();
}

class _QuickQuoteScreenState extends State<QuickQuoteScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _speechReady = false;
  bool _isListening = false;
  bool _voiceAppendMode = false;
  String _voiceLiveText = '';
  String? _speechLocaleId;

  bool _photoMode = false;
  final List<XFile> _selectedPhotos = [];
  static const int _maxPhotos = 5;

  bool _isLoading = true;
  bool _isGenerating = false;
  bool _isConverting = false;
  bool _isAnalyzingPhoto = false;
  double _discountValue = 0;
  bool _discountIsPercentage = false;
  String? _coachHint;
  Timer? _coachTimer;
  bool _photoWarningShown = false;
  String? _photoDetectedIssue;
  String? _photoWarning;
  String? _photoMatchedService;
  double? _photoConfidence;

  String? _forcedServiceType;
  String? _matchedServiceLabel;
  EstimatePriceRuleModel? _selectedPriceRule;

  // Photo detection selection state
  List<_PhotoDetection> _photoDetections = [];
  bool _photoRushEnabled = false;
  String _photoRushPrice = '';
  bool _photoMaterialsEnabled = false;
  Map<int, String> _photoMaterialPrices = {};
  List<EstimatePriceRuleModel> _suggestionRules = [];
  _PromptSuggestion? _promptSuggestion;

  List<ClientModel> _clients = [];
  List<PropertyModel> _properties = [];

  ClientModel? _selectedClient;
  PropertyModel? _selectedProperty;

  AiEstimateResultModel? _result;
  Map<int, String> _itemIconNames = {};

  double _taxRate = 0.13;
  String _taxLabel = 'Tax';
  String _currencyCode = 'CAD';

  @override
  void initState() {
    super.initState();
    _promptController.addListener(_onPromptChanged);

    _loadDefaults();
    _initSpeech();
  }

  @override
  void dispose() {
    _speech.stop();
    _coachTimer?.cancel();
    _promptController.removeListener(_onPromptChanged);
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    try {
      final settings = await CompanySettingsService.getSettings();
      final clients = await ClientService.getClients();
      final rules = await EstimatePriceRulesService.getRules();
      final activeRules = rules.where((rule) => rule.isActive).toList();

      if (!mounted) return;

      final taxLabel = settings?.taxLabel.trim() ?? '';
      final currencyCode = settings?.currencyCode.trim() ?? '';

      setState(() {
        _taxRate = settings?.defaultTaxRate ?? 0.13;
        _taxLabel = taxLabel.isEmpty ? 'Tax' : taxLabel;
        _currencyCode = currencyCode.isEmpty ? 'CAD' : currencyCode.toUpperCase();
        _clients = clients;
        _isLoading = false;
        _suggestionRules = activeRules;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Failed to load quick quote data');
    }
  }

  void _onPromptChanged() {
    _refreshWorkioSuggestion();

    _coachTimer?.cancel();
    _coachTimer = Timer(const Duration(milliseconds: 1500), () {
      _fetchCoachHint(_promptController.text);
    });
  }

  Future<void> _initSpeech() async {
    final ready = await _speech.initialize(
      onStatus: (status) {
        debugPrint('Speech status: $status');

        if (!mounted) return;

        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
            _voiceLiveText = '';
          });
        }
      },
      onError: (error) {
        debugPrint('Speech error: ${error.errorMsg} / permanent: ${error.permanent}');

        if (!mounted) return;

        final message = error.errorMsg.toLowerCase();

        // Это не критическая ошибка. Просто Android не понял речь.
        if (message.contains('no_match') ||
            message.contains('speech_timeout') ||
            message.contains('error_no_match')) {
          setState(() {
            _isListening = false;
            _voiceLiveText = '';
          });

          _showSnack('Did not catch that. Try speaking closer to the mic.');
          return;
        }

        setState(() {
          _isListening = false;
          _voiceLiveText = '';
        });

        if (message.contains('permission')) {
          _showSnack('Microphone permission is blocked. Enable it in settings.');
          return;
        }

        _showSnack('Voice input failed: ${error.errorMsg}');
      },
    );

    String? pickedLocaleId;

    if (ready) {
      final systemLocale = await _speech.systemLocale();
      final locales = await _speech.locales();

      debugPrint(
        'Speech available locales: ${locales.map((e) => e.localeId).take(20).join(', ')}',
      );

      pickedLocaleId = systemLocale?.localeId;

      final hasSystemLocale = locales.any(
            (locale) => locale.localeId == pickedLocaleId,
      );

      if (!hasSystemLocale) {
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('en')) {
            pickedLocaleId = locale.localeId;
            break;
          }
        }
      }

      pickedLocaleId ??= locales.isNotEmpty ? locales.first.localeId : null;
    }

    if (!mounted) return;

    setState(() {
      _speechReady = ready;
      _speechLocaleId = pickedLocaleId;
    });

    debugPrint('Speech ready: $ready, selected locale: $_speechLocaleId');
  }

  void _insertVoiceText(
      String spokenText, {
        required bool append,
      }) {
    final clean = spokenText.trim();
    if (clean.isEmpty) return;

    final current = _promptController.text.trim();

    final next = append
        ? (current.isEmpty ? clean : '$current $clean').trim()
        : clean;

    _promptController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  Future<void> _startVoiceInput({
    required bool append,
  }) async {
    if (!_speechReady) {
      _showSnack('Voice input is not available on this device');
      return;
    }

    if (_isListening) return;

    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await Future.delayed(const Duration(milliseconds: 180));

    setState(() {
      _voiceAppendMode = append;
      _isListening = true;
      _voiceLiveText = '';
    });

    try {
      await _speech.cancel();

      await _speech.listen(
        localeId: _speechLocaleId,
        onResult: (result) {
          if (!mounted) return;

          final live = result.recognizedWords.trim();

          setState(() {
            _voiceLiveText = live;
          });

          if (result.finalResult && live.isNotEmpty) {
            _insertVoiceText(
              live,
              append: _voiceAppendMode,
            );

            setState(() {
              _isListening = false;
              _voiceLiveText = '';
            });
          }
        },
        listenMode: stt.ListenMode.confirmation,
        partialResults: true,
        cancelOnError: false,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 8),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isListening = false;
        _voiceLiveText = '';
      });

      debugPrint('Voice listen failed: $e');
      _showSnack('Voice input failed: $e');
    }
  }

  Future<void> _stopVoiceInput() async {
    await _speech.stop();

    if (!mounted) return;

    setState(() {
      _isListening = false;
      _voiceLiveText = '';
    });
  }

  String _conditionalClean(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _hasConditionalInspectionSignal(String value) {
    final text = _conditionalClean(value);

    return RegExp(
      r'\b(if needed|as needed|if necessary|when needed|po neobhodimosti|po nado|as required)\b',
    ).hasMatch(text) &&
        RegExp(
          r'\b(inspect|inspection|diagnose|diagnostic|check|verify|proverit|diagnostika)\b',
        ).hasMatch(text);
  }

  bool _isInspectionLikeJob(String value) {
    final text = _conditionalClean(value);

    return RegExp(
      r'\b(inspect|inspection|diagnose|diagnostic|check|verify|troubleshoot|proverit|diagnostika)\b',
    ).hasMatch(text);
  }

  bool _hasDefiniteWorkAction(String value) {
    final text = _conditionalClean(value);

    return RegExp(
      r'\b(replace|replacement|repair|fix|install|installation|swap|change|zamenit|pochinit|ustanovit)\b',
    ).hasMatch(text);
  }

  Set<String> _conditionalObjectTokens(String value) {
    const ignore = {
      'if',
      'needed',
      'as',
      'necessary',
      'when',
      'po',
      'neobhodimosti',
      'nado',
      'inspect',
      'inspection',
      'diagnose',
      'diagnostic',
      'check',
      'verify',
      'repair',
      'replace',
      'install',
      'installation',
      'fix',
      'work',
      'job',
      'service',
      'the',
      'and',
      'or',
      'to',
      'for',
      'in',
      'on',
      'with',
    };

    return _conditionalClean(value)
        .split(' ')
        .where((e) => e.length >= 4)
        .where((e) => !ignore.contains(e))
        .toSet();
  }

  bool _isConditionalFollowupActionJob({
    required String job,
    required String fullPrompt,
  }) {
    if (!_hasConditionalInspectionSignal(fullPrompt)) return false;
    if (!_hasDefiniteWorkAction(job)) return false;
    if (_isInspectionLikeJob(job)) return false;

    final jobTokens = _conditionalObjectTokens(job);
    final fullTokens = _conditionalObjectTokens(fullPrompt);

    if (jobTokens.isEmpty || fullTokens.isEmpty) return false;

    return jobTokens.intersection(fullTokens).isNotEmpty;
  }

  bool _isInspectionDiagnosticRule(EstimatePriceRuleModel rule) {
    final text = _conditionalClean(
      '${rule.serviceType} ${rule.displayName ?? ''} '
          '${rule.aliases.join(' ')} ${rule.aiKeywords.join(' ')}',
    );

    return RegExp(
      r'\b(inspection|inspect|diagnostic|diagnose|troubleshoot|assessment|service call|check)\b',
    ).hasMatch(text);
  }

  bool _resultHasPositiveTotal(AiEstimateResultModel? result) {
    if (result == null || result.items.isEmpty) return false;

    for (final item in result.items) {
      final total = item.lineTotal > 0
          ? item.lineTotal
          : EstimateCalculator.calculateLineTotal(
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      );

      if (total > 0) return true;
    }

    return false;
  }

  Future<void> _openVoicePromptSheet() async {
    if (_isListening) {
      await _stopVoiceInput();
      return;
    }

    debugPrint('OPENING VOICE SHEET');

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2B2F38), Color(0xFF22252D)],
            ),
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xFF3A3F4B)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.mic_fill,
                        color: Color(0xFFF59E0B),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Voice Prompt',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          Text(
                            'Choose how to insert your voice text',
                            style: TextStyle(
                              color: Color(0xFFB7BCCB),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _VoiceSheetButton(
                    icon: CupertinoIcons.refresh,
                    label: 'Replace prompt',
                    onTap: () => Navigator.pop(context, 'replace'),
                  ),
                  const SizedBox(height: 10),
                  _VoiceSheetButton(
                    icon: CupertinoIcons.text_append,
                    label: 'Append to prompt',
                    onTap: () => Navigator.pop(context, 'append'),
                  ),
                  const SizedBox(height: 10),
                  _VoiceSheetButton(
                    icon: CupertinoIcons.xmark,
                    label: 'Cancel',
                    isCancel: true,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == 'replace') {
      await _startVoiceInput(append: false);
    } else if (action == 'append') {
      await _startVoiceInput(append: true);
    }
  }

  EstimateTotals get _totals {
    return EstimateCalculator.calculateTotals(
      items: _result?.items ?? const <EstimateItemModel>[],
      taxRate: _taxRate,
      discountValue: _discountValue,
      discountIsPercentage: _discountIsPercentage,
    );
  }

  void _showSnack(String message, {_SnackType type = _SnackType.info}) {
    if (!mounted) return;

    final isSuccess = message.toLowerCase().contains('created') ||
        message.toLowerCase().contains('updated') ||
        message.toLowerCase().contains('analyzed') ||
        message.toLowerCase().contains('converted');

    final isError = message.toLowerCase().contains('failed') ||
        message.toLowerCase().contains('error') ||
        message.toLowerCase().contains('not found') ||
        message.toLowerCase().contains('blocked') ||
        message.toLowerCase().contains('maximum');

    final resolvedType = type != _SnackType.info
        ? type
        : isSuccess
        ? _SnackType.success
        : isError
        ? _SnackType.error
        : _SnackType.info;

    final icon = resolvedType == _SnackType.success
        ? CupertinoIcons.checkmark_circle_fill
        : resolvedType == _SnackType.error
        ? CupertinoIcons.xmark_circle_fill
        : CupertinoIcons.info_circle_fill;

    final color = resolvedType == _SnackType.success
        ? const Color(0xFF22C55E)
        : resolvedType == _SnackType.error
        ? const Color(0xFFFF6B6B)
        : const Color(0xFFF59E0B);

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
            border: Border.all(color: color.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
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

  String _cleanEstimateText(String value) {
    var text = value.trim();

    if (text.isEmpty) return '';

    text = text
    // empty brackets
        .replaceAll(RegExp(r'\(\s*\)'), '')
        .replaceAll(RegExp(r'\[\s*\]'), '')
        .replaceAll(RegExp(r'\{\s*\}'), '')

    // empty placeholders / ugly punctuation
        .replaceAll(RegExp(r'\s+,\s*'), ', ')
        .replaceAll(RegExp(r'\s+;\s*'), '; ')
        .replaceAll(RegExp(r'\s+:\s*'), ': ')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'\s+\.'), '.')
        .replaceAll(RegExp(r'\s+,'), ',')

    // remove repeated generic AI opening
        .replaceAll(
      RegExp(
        r'^Complete the requested work for\s+[^:]+:\s*',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(
        r'^Complete the requested\s+',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(r'\bMaterials not included\.\s*Not\.', caseSensitive: false),
      'Materials not included.',
    )
        .replaceAll(
      RegExp(r'\bNot\.\s*On-site labor', caseSensitive: false),
      'On-site labor',
    )
        .replaceAll(
      RegExp(r'\bNot\.\s*Labor', caseSensitive: false),
      'Labor',
    )
        .replaceAll(
      RegExp(r'\bNot\.\s*Verify', caseSensitive: false),
      'Verify',
    )

    // cleanup wording
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    text = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');

    return text;
  }

  String _resultServiceTitle(AiEstimateResultModel result, int index) {
    String cleanTitle(String value) {
      var text = value.trim();

      text = text
          .replaceAll(
        RegExp(r'\s+estimate$', caseSensitive: false),
        '',
      )
          .replaceAll(
        RegExp(r'\s+quick quote$', caseSensitive: false),
        '',
      )
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      return text;
    }

    final title = cleanTitle(result.title ?? '');

    if (title.isNotEmpty &&
        title.toLowerCase() != 'quick quote' &&
        title.toLowerCase() != 'ai estimate') {
      return title;
    }

    final firstItemTitle = result.items.isNotEmpty
        ? cleanTitle(result.items.first.title)
        : '';

    if (firstItemTitle.isNotEmpty) {
      return firstItemTitle;
    }

    return 'Service ${index + 1}';
  }

  String _buildRichMultiScope(List<AiEstimateResultModel> results) {
    final sections = <String>[];

    for (var i = 0; i < results.length; i++) {
      final result = results[i];

      final title = _cleanEstimateText(_resultServiceTitle(result, i));
      final scope = _cleanEstimateText(result.scope ?? '');

      if (scope.isEmpty) continue;

      sections.add('$title\n$scope');
    }

    return sections.join('\n\n');
  }

  String _buildRichMultiNotes(List<AiEstimateResultModel> results) {
    final sections = <String>[];

    for (var i = 0; i < results.length; i++) {
      final result = results[i];

      final title = _cleanEstimateText(_resultServiceTitle(result, i));
      final notes = _cleanEstimateText(result.notes ?? '');

      if (notes.isEmpty) continue;

      sections.add('$title\n$notes');
    }

    return sections.join('\n\n');
  }

  Future<String?> _normalizeQuickQuotePrompt(String rawPrompt) async {
    final original = rawPrompt.trim();
    if (original.isEmpty) return null;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'normalize-quick-quote-prompt',
        body: {
          'prompt': original,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);

      final cleanPrompt = (data['cleanPrompt'] ?? original).toString().trim();

      // ВАЖНО:
      // Никаких popup. Admin не должен отвечать вручную.
      // Если AI сомневается по материалам — мы всё равно продолжаем.
      // Явные материалы потом отдельно парсит ParseEstimateMiniService.
      return cleanPrompt.isEmpty ? original : cleanPrompt;
    } catch (_) {
      return original;
    }
  }

  Map<String, dynamic> _ruleToCandidate(EstimatePriceRuleModel rule) {
    return {
      'ruleId': rule.id,
      'serviceType': rule.serviceType,
      'displayName': rule.displayName,
      'unit': rule.unit,
      'category': rule.category,
      'aliases': rule.aliases,
      'aiKeywords': rule.aiKeywords,
      'negativeKeywords': rule.negativeKeywords,
      'followupQuestions': rule.aiFollowupQuestions,
    };
  }

  String _intentClean(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _detectPromptIntent(String prompt) {
    final text = _intentClean(prompt);

    if (RegExp(r'\b(install|installation|mount|setup|put in|connect)\b').hasMatch(text)) {
      return 'installation';
    }

    if (RegExp(r'\b(replace|replacement|swap|change)\b').hasMatch(text)) {
      return 'replacement';
    }

    if (RegExp(r'\b(repair|fix|troubleshoot|leak|broken|not working)\b').hasMatch(text)) {
      return 'repair';
    }

    if (RegExp(r'\b(inspect|inspection|diagnose|check)\b').hasMatch(text)) {
      return 'inspection';
    }

    return 'broad';
  }

  String _detectRuleIntent(EstimatePriceRuleModel rule) {
    final text = _intentClean(
      '${rule.serviceType} ${rule.displayName ?? ''}',
    );

    if (RegExp(r'\b(install|installation|mount|setup)\b').hasMatch(text)) {
      return 'installation';
    }

    if (RegExp(r'\b(replace|replacement|swap)\b').hasMatch(text)) {
      return 'replacement';
    }

    if (RegExp(r'\b(repair|fix|troubleshoot|leak|broken)\b').hasMatch(text)) {
      return 'repair';
    }

    if (RegExp(r'\b(inspect|inspection|diagnose|diagnostic)\b').hasMatch(text)) {
      return 'inspection';
    }

    return 'broad';
  }

  bool _ruleIntentConflictsWithPrompt(
      String prompt,
      EstimatePriceRuleModel rule,
      ) {
    final promptIntent = _detectPromptIntent(prompt);
    final ruleIntent = _detectRuleIntent(rule);

    if (promptIntent == 'broad') return false;
    if (ruleIntent == 'broad') return false;

    return promptIntent != ruleIntent;
  }

  EstimatePriceRuleModel? _resolveRuleByLocalAliasFallback(
      String prompt,
      List<EstimatePriceRuleModel> rules,
      ) {
    String clean(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    String stem(String value) {
      var text = clean(value);

      if (text.endsWith('ies') && text.length > 4) {
        return '${text.substring(0, text.length - 3)}y';
      }

      if (text.endsWith('ches') && text.length > 5) {
        return text.substring(0, text.length - 2); // switches -> switch
      }

      if (text.endsWith('shes') && text.length > 5) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('es') && text.length > 4) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('s') && text.length > 3) {
        return text.substring(0, text.length - 1);
      }

      return text;
    }

    const genericWords = {
      'repair',
      'fix',
      'replace',
      'replacement',
      'install',
      'installation',
      'inspect',
      'inspection',
      'diagnose',
      'diagnostic',
      'service',
      'services',
      'work',
      'job',
      'labor',
      'labour',
      'urgent',
      'rush',
      'asap',
      'material',
      'materials',
      'included',
      'customer',
      'provided',
      'problem',
      'issue',
      'broken',
      'damaged',
      'burned',
      'check',
      'checking',
      'as',
      'needed',
    };

    List<String> tokens(String value) {
      return clean(value)
          .split(' ')
          .map((e) => stem(e))
          .where((e) => e.length >= 3)
          .where((e) => !genericWords.contains(e))
          .toList();
    }

    bool containsPhrase(String text, String phrase) {
      final cleanPhrase = clean(phrase);
      if (cleanPhrase.isEmpty) return false;

      return text.contains(RegExp(
        r'(^|\s)' + RegExp.escape(cleanPhrase) + r'(\s|$)',
      ));
    }

    final normalizedPrompt = clean(prompt);
    if (normalizedPrompt.isEmpty) return null;

    final promptTokens = tokens(normalizedPrompt).toSet();

    double bestScore = 0;
    EstimatePriceRuleModel? bestRule;

    for (final rule in rules) {
      double score = 0;

      final candidates = <({String text, double weight})>[
        (text: rule.serviceType, weight: 1.00),
        (text: rule.displayName ?? '', weight: 1.05),
        ...rule.aliases.map((e) => (text: e, weight: 1.35)),
        ...rule.aiKeywords.map((e) => (text: e, weight: 1.25)),
      ];

      int bestMatchedSpecificTokens = 0;

      for (final candidate in candidates) {
        final candidateText = clean(candidate.text);
        if (candidateText.isEmpty) continue;

        final candidateTokens = tokens(candidateText);
        if (candidateTokens.isEmpty) continue;

        int matchedTokens = 0;

        for (final token in candidateTokens) {
          if (promptTokens.contains(token)) {
            matchedTokens++;
          }
        }

        if (matchedTokens == 0) continue;

        bestMatchedSpecificTokens =
        matchedTokens > bestMatchedSpecificTokens
            ? matchedTokens
            : bestMatchedSpecificTokens;

        score += matchedTokens * 2.0 * candidate.weight;

        final allTokensMatched = candidateTokens.every(promptTokens.contains);
        if (allTokensMatched) {
          score += 3.0 * candidate.weight;
        }

        if (containsPhrase(normalizedPrompt, candidateText)) {
          score += 5.0 * candidate.weight;
        }

        // More specific object aliases should beat broad labor/category rules.
        if (candidateTokens.length <= 3 && allTokensMatched) {
          score += 2.0 * candidate.weight;
        }
      }

      for (final negative in rule.negativeKeywords) {
        final negativeText = clean(negative);
        if (negativeText.isEmpty) continue;

        final negativeTokens = tokens(negativeText);
        final negativeMatched =
            containsPhrase(normalizedPrompt, negativeText) ||
                negativeTokens.any(promptTokens.contains);

        if (negativeMatched) {
          score -= 8;
        }
      }

      if (bestMatchedSpecificTokens == 0) {
        score = 0;
      }

      if (_ruleIntentConflictsWithPrompt(prompt, rule)) {
        score -= 12;
      }

      if (score <= 0) {
        continue;
      }

      if (score > bestScore) {
        bestScore = score;
        bestRule = rule;
      }
    }

    return bestScore >= 2 ? bestRule : null;
  }

  Future<EstimatePriceRuleModel?> _resolveRuleForPrompt(String prompt) async {
    final rules = await EstimatePriceRulesService.getRules();
    final activeRules = rules.where((rule) => rule.isActive).toList();

    if (activeRules.isEmpty) return null;

    // Strong local fallback FIRST.
    // If prompt clearly contains a rule alias/keyword like "outlet",
    // do not let AI resolver reject inspection wording.
    final localFirst = _resolveRuleByLocalAliasFallback(prompt, activeRules);
    if (localFirst != null) {
      return localFirst;
    }

    final resolverResult = await EstimateRuleResolutionService.resolve(
      prompt: prompt,
      guidedAnswers: {
        'requested_work': prompt,
      },
      candidates: activeRules.map(_ruleToCandidate).toList(),
    );

    final selectedRuleId = resolverResult.selectedRuleId;

    if ((selectedRuleId ?? '').trim().isEmpty) {
      return _resolveRuleByLocalAliasFallback(prompt, activeRules);
    }

    final resolved = await EstimatePriceRulesService.getRuleById(
      selectedRuleId!.trim(),
    );

    if (resolved != null && _ruleIntentConflictsWithPrompt(prompt, resolved)) {
      return _resolveRuleByLocalAliasFallback(
        prompt,
        activeRules.where((rule) => rule.id != resolved.id).toList(),
      );
    }

    return resolved ?? _resolveRuleByLocalAliasFallback(prompt, activeRules);
  }

  Future<List<String>?> _splitQuickQuoteJobs(String prompt) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'split-quick-quote-jobs',
        body: {
          'prompt': prompt,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);

      final rawJobs = data['jobs'];
      if (rawJobs is! List) return [prompt];

      final jobs = rawJobs
          .whereType<Map>()
          .map((job) => (job['description'] ?? '').toString().trim())
          .where((text) => text.isNotEmpty)
          .toList();

      if (jobs.isEmpty) return [prompt];

      return jobs.length > 8 ? jobs.take(8).toList() : jobs;
    } catch (_) {
      return [prompt];
    }
  }

  String _fastClean(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(
      RegExp(
        r'[^a-zа-яё0-9\s$.,]+',
        caseSensitive: false,
        unicode: true,
      ),
      ' ',
    )
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _fastStem(String value) {
    var text = _fastClean(value);

    if (text.endsWith('ies') && text.length > 4) {
      return '${text.substring(0, text.length - 3)}y';
    }

    if (text.endsWith('ches') && text.length > 5) {
      return text.substring(0, text.length - 2);
    }

    if (text.endsWith('shes') && text.length > 5) {
      return text.substring(0, text.length - 2);
    }

    if (text.endsWith('es') && text.length > 4) {
      return text.substring(0, text.length - 2);
    }

    if (text.endsWith('s') && text.length > 3) {
      return text.substring(0, text.length - 1);
    }

    return text;
  }

  Set<String> _fastTokens(String value) {
    const ignored = {
      'install',
      'installation',
      'replace',
      'replacement',
      'repair',
      'fix',
      'inspect',
      'inspection',
      'diagnose',
      'diagnostic',
      'remove',
      'removal',
      'service',
      'work',
      'job',
      'the',
      'and',
      'or',
      'to',
      'for',
      'with',
      'in',
      'on',
      'at',
      'per',
      'each',
      'po',
      'za',
      'by',
      'of',
      'a',
      'an',
      'price',
      'cost',
      'total',
      'amount',
      'material',
      'materials',
      'part',
      'parts',
      'supply',
      'supplies',
      'included',
      'include',
    };

    return _fastClean(value)
        .split(' ')
        .map(_fastStem)
        .where((word) => word.length >= 2)
        .where((word) => double.tryParse(word) == null)
        .where((word) => !ignored.contains(word))
        .toSet();
  }

  double? _fastNumber(String value) {
    final clean = value
        .replaceAll('\$', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9\.]+'), '')
        .trim();

    if (clean.isEmpty) return null;

    return double.tryParse(clean);
  }

  bool _fastTokenClose(String a, String b) {
    final left = _fastStem(a);
    final right = _fastStem(b);

    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;

    final minLen = math.min(left.length, right.length);
    if (minLen < 3) return false;

    if (left.startsWith(right) || right.startsWith(left)) {
      return minLen >= 3;
    }

    final distance = _smallEditDistance(left, right);

    if (minLen >= 6) return distance <= 2;

    if (minLen >= 4) {
      final sameStart = left[0] == right[0];
      return sameStart && distance <= 2;
    }

    return false;
  }

  int _fastTokenMatchCount(Set<String> a, Set<String> b) {
    var count = 0;

    for (final left in a) {
      for (final right in b) {
        if (_fastTokenClose(left, right)) {
          count++;
          break;
        }
      }
    }

    return count;
  }

  bool _fastTokenSetHasMatch(Set<String> a, Set<String> b) {
    return _fastTokenMatchCount(a, b) > 0;
  }

  String _fastLaborOnlyPrompt(String prompt) {
    final parts = prompt.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return prompt;

    const materialMarkers = {
      'material',
      'materials',
      'part',
      'parts',
      'supply',
      'supplies',
    };

    for (var i = 0; i < parts.length; i++) {
      final token = _fastClean(parts[i]).replaceAll(RegExp(r'[^a-zа-яё0-9]+'), '');

      for (final marker in materialMarkers) {
        if (_fastTokenClose(token, marker)) {
          return parts.take(i).join(' ').trim();
        }
      }
    }

    return prompt.trim();
  }

  String _fastMaterialOnlyPrompt(String prompt) {
    final parts = prompt.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '';

    const materialMarkers = {
      'material',
      'materials',
      'part',
      'parts',
      'supply',
      'supplies',
    };

    for (var i = 0; i < parts.length; i++) {
      final token = _fastClean(parts[i]).replaceAll(RegExp(r'[^a-zа-яё0-9]+'), '');

      for (final marker in materialMarkers) {
        if (_fastTokenClose(token, marker)) {
          return parts.skip(i).join(' ').trim();
        }
      }
    }

    return '';
  }

  Set<String> _fastRuleTokens(EstimatePriceRuleModel rule) {
    return _fastTokens(
      [
        rule.serviceType,
        rule.displayName ?? '',
        rule.unit,
        ...rule.aliases,
        ...rule.aiKeywords,
      ].join(' '),
    );
  }

  Set<String> _fastStrongRuleTokens(EstimatePriceRuleModel rule) {
    return _fastTokens(
      [
        rule.serviceType,
        rule.displayName ?? '',
        ...rule.aliases,
      ].join(' '),
    );
  }

  bool _fastHasMaterialContext(String text, int index) {
    final start = math.max(0, index - 80);
    final prefix = text.substring(start, index).toLowerCase();

    return RegExp(
      r'\b(material|materials|materiali|part|parts|supply|supplies|included|vklyuch|включ|материал|материалы|labor price|labour price)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(prefix);
  }

  List<_FastPromptPriceOverride> _extractFastPriceOverrides(String prompt) {
    final text = prompt
        .trim()
        .toLowerCase()
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (text.isEmpty) return const [];

    final overrides = <_FastPromptPriceOverride>[];
    final seen = <String>{};

    void addOverride({
      required double quantity,
      required double unitPrice,
      required String objectText,
    }) {
      if (quantity <= 0 || unitPrice <= 0) return;

      final objectTokens = _fastTokens(objectText);
      if (objectTokens.isEmpty) return;

      final key =
          '${objectTokens.join('_')}_${quantity.toStringAsFixed(2)}_${unitPrice.toStringAsFixed(2)}';

      if (seen.contains(key)) return;
      seen.add(key);

      overrides.add(
        _FastPromptPriceOverride(
          quantity: quantity,
          unitPrice: double.parse(unitPrice.toStringAsFixed(2)),
          objectTokens: objectTokens,
        ),
      );
    }

    void addFromMatch(
        RegExpMatch match, {
          required int qtyGroup,
          required int objectGroup,
          required int priceGroup,
          bool priceIsTotal = false,
        }) {
      if (_fastHasMaterialContext(text, match.start)) return;

      final qty = _fastNumber(match.group(qtyGroup) ?? '');
      final rawPrice = _fastNumber(match.group(priceGroup) ?? '');
      final objectText = (match.group(objectGroup) ?? '').trim();

      if (qty == null || rawPrice == null || objectText.isEmpty) return;

      final unitPrice = priceIsTotal ? rawPrice / qty : rawPrice;

      addOverride(
        quantity: qty,
        unitPrice: unitPrice,
        objectText: objectText,
      );
    }

    final qtyObjectUnitPrice = RegExp(
      r'\b(\d+(?:[\.,]\d+)?)\s+'
      r'([a-zа-яё0-9][a-zа-яё0-9\s\/\.-]{0,70}?)\s+'
      r'(?:po|per|each|at|za|for|по|за|@|x|×)\s*'
      r'\$?\s*(\d+(?:[\.,]\d+)?)\s*\$?',
      caseSensitive: false,
      unicode: true,
    );

    for (final match in qtyObjectUnitPrice.allMatches(text)) {
      addFromMatch(
        match,
        qtyGroup: 1,
        objectGroup: 2,
        priceGroup: 3,
      );
    }

    final qtyObjectMoneyEach = RegExp(
      r'\b(\d+(?:[\.,]\d+)?)\s+'
      r'([a-zа-яё0-9][a-zа-яё0-9\s\/\.-]{0,70}?)\s+'
      r'\$+\s*(\d+(?:[\.,]\d+)?)\s*'
      r'(?:each|per|po|за|по)?\b',
      caseSensitive: false,
      unicode: true,
    );

    for (final match in qtyObjectMoneyEach.allMatches(text)) {
      addFromMatch(
        match,
        qtyGroup: 1,
        objectGroup: 2,
        priceGroup: 3,
      );
    }

    final qtyObjectTrailingMoney = RegExp(
      r'\b(\d+(?:[\.,]\d+)?)\s+'
      r'([a-zа-яё0-9][a-zа-яё0-9\s\/\.-]{0,70}?)\s+'
      r'\$?\s*(\d+(?:[\.,]\d+)?)\s*\$+\b',
      caseSensitive: false,
      unicode: true,
    );

    for (final match in qtyObjectTrailingMoney.allMatches(text)) {
      addFromMatch(
        match,
        qtyGroup: 1,
        objectGroup: 2,
        priceGroup: 3,
      );
    }

    final objectQtyUnitPrice = RegExp(
      r'\b([a-zа-яё][a-zа-яё0-9\s\/\.-]{0,70}?)\s+'
      r'(\d+(?:[\.,]\d+)?)\s+'
      r'(?:po|per|each|at|za|for|по|за|@|x|×)\s*'
      r'\$?\s*(\d+(?:[\.,]\d+)?)\s*\$?',
      caseSensitive: false,
      unicode: true,
    );

    for (final match in objectQtyUnitPrice.allMatches(text)) {
      addFromMatch(
        match,
        qtyGroup: 2,
        objectGroup: 1,
        priceGroup: 3,
      );
    }

    final qtyObjectTotalPrice = RegExp(
      r'\b(\d+(?:[\.,]\d+)?)\s+'
      r'([a-zа-яё0-9][a-zа-яё0-9\s\/\.-]{0,70}?)\s+'
      r'(?:total|all|итого|всего)\s*'
      r'\$?\s*(\d+(?:[\.,]\d+)?)\s*\$?',
      caseSensitive: false,
      unicode: true,
    );

    for (final match in qtyObjectTotalPrice.allMatches(text)) {
      addFromMatch(
        match,
        qtyGroup: 1,
        objectGroup: 2,
        priceGroup: 3,
        priceIsTotal: true,
      );
    }

    return overrides;
  }

  _FastPromptPriceOverride? _bestFastOverrideForRule({
    required String prompt,
    required EstimatePriceRuleModel rule,
  }) {
    final overrides = _extractFastPriceOverrides(prompt);
    if (overrides.isEmpty) return null;

    final strongRuleTokens = _fastStrongRuleTokens(rule);
    final allRuleTokens = _fastRuleTokens(rule);

    if (strongRuleTokens.isEmpty && allRuleTokens.isEmpty) return null;

    _FastPromptPriceOverride? best;
    var bestScore = 0.0;

    for (final override in overrides) {
      final strongScore = _fastTokenMatchCount(
        override.objectTokens,
        strongRuleTokens,
      ).toDouble();

      final weakScore = _fastTokenMatchCount(
        override.objectTokens,
        allRuleTokens,
      ).toDouble();

      final score = (strongScore * 10) + weakScore;

      if (score > bestScore) {
        bestScore = score;
        best = override;
      }
    }

    return bestScore > 0 ? best : null;
  }

  double? _extractFastQuantityForRule({
    required String prompt,
    required EstimatePriceRuleModel rule,
  }) {
    final override = _bestFastOverrideForRule(
      prompt: prompt,
      rule: rule,
    );

    if (override != null) {
      return override.quantity;
    }

    final ruleTokens = _fastRuleTokens(rule);
    if (ruleTokens.isEmpty) return null;

    final withoutMoney = prompt
        .replaceAll(RegExp(r'\$+\s*\d+(?:[\.,]\d+)?'), ' ')
        .replaceAll(RegExp(r'\d+(?:[\.,]\d+)?\s*\$+'), ' ')
        .replaceAll(
      RegExp(
        r'\b(?:po|per|each|at|za|for|по|за)\s+\d+(?:[\.,]\d+)?\b',
        caseSensitive: false,
        unicode: true,
      ),
      ' ',
    );

    final parts = _fastClean(withoutMoney)
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .toList();

    for (var i = 0; i < parts.length; i++) {
      final number = double.tryParse(parts[i]);
      if (number == null || number <= 0) continue;

      final start = math.max(0, i - 4);
      final end = math.min(parts.length - 1, i + 4);

      for (var j = start; j <= end; j++) {
        if (j == i) continue;

        final token = _fastStem(parts[j]);

        if (_fastTokenSetHasMatch({token}, ruleTokens)) {
          return number;
        }
      }
    }

    for (final part in parts) {
      final number = double.tryParse(part);
      if (number != null && number > 0 && number < 10000) {
        return number;
      }
    }

    return null;
  }

  double _fastRuleScore({
    required String prompt,
    required EstimatePriceRuleModel rule,
  }) {
    final promptClean = _fastClean(prompt);
    final promptTokens = _fastTokens(prompt);
    final ruleTokens = _fastRuleTokens(rule);

    if (promptTokens.isEmpty || ruleTokens.isEmpty) return 0;
    var score = _fastTokenMatchCount(promptTokens, ruleTokens) * 5.0;

    // Если в промпте есть сильный токен который точно совпадает
    // с другим rule — этот rule должен получить штраф
    final strongRuleTokens = _fastStrongRuleTokens(rule);
    final strongPromptMatch = _fastTokenMatchCount(promptTokens, strongRuleTokens);
    if (strongPromptMatch == 0) {
      return 0;
    }
    score += strongPromptMatch * 8.0;



    final candidates = <String>[
      rule.serviceType,
      rule.displayName ?? '',
      rule.unit,
      ...rule.aliases,
      ...rule.aiKeywords,
    ];

    for (final candidate in candidates) {
      final cleanCandidate = _fastClean(candidate);
      if (cleanCandidate.isEmpty) continue;

      if (promptClean.contains(
        RegExp(
          r'(^|\s)' + RegExp.escape(cleanCandidate) + r'(\s|$)',
          unicode: true,
        ),
      )) {
        score += 8;
      }
    }

    for (final negative in rule.negativeKeywords) {
      final negativeTokens = _fastTokens(negative);

      if (negativeTokens.isNotEmpty &&
          _fastTokenSetHasMatch(promptTokens, negativeTokens)) {
        score -= 8;
      }
    }

    if (_ruleIntentConflictsWithPrompt(prompt, rule)) {
      score -= 6;
    }

    debugPrint('RULE SCORE: ${rule.displayName} => $score');
    return score;
  }

  Future<EstimatePriceRuleModel?> _resolveFastQuickQuoteRule(
      String prompt, {
        List<EstimatePriceRuleModel>? candidates,
      }) async {
    final rules = candidates ??
        (_suggestionRules.isNotEmpty
            ? _suggestionRules
            : (await EstimatePriceRulesService.getRules())
            .where((rule) => rule.isActive)
            .toList());

    if (rules.isEmpty) return null;

    EstimatePriceRuleModel? bestRule;
    var bestScore = 0.0;

    for (final rule in rules) {
      final score = _fastRuleScore(
        prompt: prompt,
        rule: rule,
      );

      if (score > bestScore) {
        bestScore = score;
        bestRule = rule;
      }
    }

    return bestScore > 0 ? bestRule : null;
  }

  AiEstimateResultModel? _buildFastQuickQuoteResult({
    required String prompt,
    required EstimatePriceRuleModel rule,
  }) {
    final serviceLabel = rule.displayName?.trim().isNotEmpty == true
        ? rule.displayName!.trim()
        : rule.serviceType.trim();

    final override = _bestFastOverrideForRule(
      prompt: prompt,
      rule: rule,
    );

    final quantity = override?.quantity ??
        _extractFastQuantityForRule(
          prompt: prompt,
          rule: rule,
        ) ??
        1.0;

    final unitPrice = override?.unitPrice ?? rule.baseRate;

    if (quantity <= 0 || unitPrice <= 0) {
      return null;
    }

    final lineTotal = EstimateCalculator.calculateLineTotal(
      quantity: quantity,
      unitPrice: unitPrice,
    );

    final items = <EstimateItemModel>[
      EstimateItemModel(
        id: '',
        estimateId: '',
        title: serviceLabel,
        description: override == null
            ? 'Quick quote calculated from Price Rule.'
            : 'Quick quote calculated from explicit prompt price.',
        unit: rule.unit,
        quantity: double.parse(quantity.toStringAsFixed(2)),
        unitPrice: double.parse(unitPrice.toStringAsFixed(2)),
        lineTotal: lineTotal,
        sortOrder: 0,
        createdAt: null,
      ),
    ];

    final rushRate = rule.rushFixedRate ?? 0;
    if (_hasRushSignalInPrompt(prompt) && rushRate > 0) {
      items.add(
        EstimateItemModel(
          id: '',
          estimateId: '',
          title: '$serviceLabel Rush Fee',
          description: 'Rush fee from Price Rule.',
          unit: 'fixed',
          quantity: 1,
          unitPrice: double.parse(rushRate.toStringAsFixed(2)),
          lineTotal: double.parse(rushRate.toStringAsFixed(2)),
          sortOrder: items.length,
          createdAt: null,
        ),
      );
    }

    return AiEstimateResultModel(
      title: '$serviceLabel Quick Quote',
      scope: null,
      notes: null,
      items: items,
      parsedRequest: AiParsedRequestModel.empty(prompt),
      assumptions: const [],
      missingFields: const [],
      confidence: override == null ? 0.88 : 0.96,
    );
  }

  List<String> _splitFastQuickQuoteJobs(String prompt) {
    final parts = prompt
        .split(RegExp(r'[\n;]+|\s+\+\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return [prompt.trim()];

    return parts.length > 8 ? parts.take(8).toList() : parts;
  }

  Future<AiEstimateResultModel?> _generateSingleJobQuote(String jobPrompt) async {
    final rules = _suggestionRules.isNotEmpty
        ? _suggestionRules
        : (await EstimatePriceRulesService.getRules())
        .where((rule) => rule.isActive)
        .toList();

    if (rules.isEmpty) return null;

    // Парсим детали через AI
    final parsed = await ParseEstimateMiniService.parse(
      prompt: jobPrompt,
      localParsed: const {},
    );

    // Резолвим rule через AI
    final resolverResult = await EstimateRuleResolutionService.resolve(
      prompt: jobPrompt,
      guidedAnswers: {
        'requested_work': jobPrompt,
      },
      candidates: rules.map(_ruleToCandidate).toList(),
    );

    final selectedRuleId = resolverResult.selectedRuleId;
    if ((selectedRuleId ?? '').trim().isEmpty) return null;

    final selectedRule = await EstimatePriceRulesService.getRuleById(
      selectedRuleId!.trim(),
    );
    if (selectedRule == null) return null;

    final serviceLabel = selectedRule.displayName?.trim().isNotEmpty == true
        ? selectedRule.displayName!.trim()
        : selectedRule.serviceType.trim();

    // Берём quantity из AI парсера
    final overrides = _extractFastPriceOverrides(jobPrompt);
    final bestOverride = _bestFastOverrideForRule(
      prompt: jobPrompt,
      rule: selectedRule,
    );

    final quantity = bestOverride?.quantity
        ?? parsed.hours
        ?? parsed.sqft
        ?? parsed.rooms?.toDouble()
        ?? _extractFastQuantityForRule(prompt: jobPrompt, rule: selectedRule)
        ?? 1.0;

    final unitPrice = bestOverride?.unitPrice ?? selectedRule.baseRate;

    if (unitPrice <= 0) return null;

    final lineTotal = EstimateCalculator.calculateLineTotal(
      quantity: quantity,
      unitPrice: unitPrice,
    );

    final items = <EstimateItemModel>[
      EstimateItemModel(
        id: '',
        estimateId: '',
        title: serviceLabel,
        description: resolverResult.normalizedRequestedWork,
        unit: selectedRule.unit,
        quantity: double.parse(quantity.toStringAsFixed(2)),
        unitPrice: double.parse(unitPrice.toStringAsFixed(2)),
        lineTotal: lineTotal,
        sortOrder: 0,
        createdAt: null,
      ),
    ];

    final rushRate = selectedRule.rushFixedRate ?? 0;
    if (_hasRushSignalInPrompt(jobPrompt) && rushRate > 0) {
      items.add(
        EstimateItemModel(
          id: '',
          estimateId: '',
          title: '$serviceLabel Rush Fee',
          description: 'Rush fee from Price Rule.',
          unit: 'fixed',
          quantity: 1,
          unitPrice: double.parse(rushRate.toStringAsFixed(2)),
          lineTotal: double.parse(rushRate.toStringAsFixed(2)),
          sortOrder: items.length,
          createdAt: null,
        ),
      );
    }

    return AiEstimateResultModel(
      title: '$serviceLabel Quick Quote',
      scope: null,
      notes: null,
      items: items,
      parsedRequest: AiParsedRequestModel.empty(jobPrompt),
      assumptions: const [],
      missingFields: const [],
      confidence: resolverResult.confidence,
    );
  }

  Future<EstimatePriceRuleModel?> _resolveInspectionRuleForPrompt(
      String prompt,
      ) async {
    final rules = await EstimatePriceRulesService.getRules();

    final activeInspectionRules = rules
        .where((rule) => rule.isActive)
        .where(_isInspectionDiagnosticRule)
        .toList();

    if (activeInspectionRules.isEmpty) return null;

    final localFirst = _resolveRuleByLocalAliasFallback(
      prompt,
      activeInspectionRules,
    );

    if (localFirst != null) return localFirst;

    final resolverResult = await EstimateRuleResolutionService.resolve(
      prompt: prompt,
      guidedAnswers: {
        'requested_work': prompt,
      },
      candidates: activeInspectionRules.map(_ruleToCandidate).toList(),
    );

    final selectedRuleId = resolverResult.selectedRuleId;

    if ((selectedRuleId ?? '').trim().isEmpty) {
      return _resolveRuleByLocalAliasFallback(prompt, activeInspectionRules);
    }

    final resolved = await EstimatePriceRulesService.getRuleById(
      selectedRuleId!.trim(),
    );

    if (resolved != null && _isInspectionDiagnosticRule(resolved)) {
      return resolved;
    }

    return _resolveRuleByLocalAliasFallback(prompt, activeInspectionRules);
  }

  Future<AiEstimateResultModel?> _generateSingleInspectionJobQuote(
      String jobPrompt,
      ) async {
    final rules = await EstimatePriceRulesService.getRules();

    final activeInspectionRules = rules
        .where((rule) => rule.isActive)
        .where(_isInspectionDiagnosticRule)
        .toList();

    final selectedRule = await _resolveFastQuickQuoteRule(
      jobPrompt,
      candidates: activeInspectionRules,
    );

    if (selectedRule == null) return null;

    return _buildFastQuickQuoteResult(
      prompt: jobPrompt,
      rule: selectedRule,
    );
  }

  AiEstimateResultModel _mergeQuickQuoteResults({
    required String prompt,
    required List<AiEstimateResultModel> results,
  }) {
    final rawItems = <EstimateItemModel>[];

    for (final result in results) {
      rawItems.addAll(result.items);
    }

    final items = _dedupeRushItems(rawItems);

    final richScope = _buildRichMultiScope(results);
    final richNotes = _buildRichMultiNotes(results);

    final confidence = results.isEmpty
        ? 0.0
        : results
        .map((result) => result.confidence)
        .fold<double>(0, (sum, value) => sum + value) /
        results.length;

    return AiEstimateResultModel(
      title: results.length > 1 ? 'Multi-Service Quick Quote' : results.first.title,
      scope: richScope.trim().isEmpty ? null : richScope.trim(),
      notes: richNotes.trim().isEmpty ? null : richNotes.trim(),
      items: items,
      parsedRequest: results.first.parsedRequest,
      assumptions: results.expand((result) => result.assumptions).toList(),
      missingFields: results.expand((result) => result.missingFields).toList(),
      confidence: confidence,
    );
  }

  double? _promptNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final clean = value.toString().replaceAll(',', '.').trim();
    return double.tryParse(clean);
  }

  String _promptTitleCase(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  Future<List<EstimateItemModel>> _buildPromptMaterialItems(
      String prompt, {
        required int startSortOrder,
      }) async {
    try {
      final parsed = await ParseEstimateMiniService.parse(
        prompt: prompt,
        localParsed: const <String, dynamic>{},
      );

      final items = <EstimateItemModel>[];

      for (final material in parsed.parsedMaterials) {
        final rawName = (material['name'] ?? '').toString().trim();
        final rawText = (material['raw_text'] ?? '').toString().trim();

        final quantity = _promptNumber(material['quantity']) ?? 1;
        final unitPrice = _promptNumber(material['unit_price']);
        final lineTotal = _promptNumber(material['line_total']);

        double resolvedUnitPrice = unitPrice ?? 0;

        if (resolvedUnitPrice <= 0 && lineTotal != null && lineTotal > 0) {
          resolvedUnitPrice = quantity > 0 ? lineTotal / quantity : lineTotal;
        }

        if (resolvedUnitPrice <= 0) continue;

        final safeQty = quantity <= 0 ? 1.0 : quantity;
        final titleName = rawName.isEmpty ? 'Materials' : _promptTitleCase(rawName);
        final total = EstimateCalculator.calculateLineTotal(
          quantity: safeQty,
          unitPrice: resolvedUnitPrice,
        );

        items.add(
          EstimateItemModel(
            id: '',
            estimateId: '',
            title: '$titleName Materials',
            description: rawText.isEmpty
                ? 'Parsed from prompt material details.'
                : 'Parsed from prompt: $rawText',
            unit: 'item',
            quantity: safeQty,
            unitPrice: double.parse(resolvedUnitPrice.toStringAsFixed(2)),
            lineTotal: total,
            sortOrder: startSortOrder + items.length,
            createdAt: null,
          ),
        );
      }

      return items;
    } catch (_) {
      return const <EstimateItemModel>[];
    }
  }

  List<EstimateItemModel> _dedupeRushItems(List<EstimateItemModel> items) {
    final result = <EstimateItemModel>[];
    final seenRushKeys = <String>{};

    String clean(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    bool isRushItem(EstimateItemModel item) {
      final text = clean('${item.title} ${item.description} ${item.unit}');
      return RegExp(
        r'\b(rush|urgent|priority|expedited)\b',
      ).hasMatch(text);
    }

    for (final item in items) {
      if (!isRushItem(item)) {
        result.add(item);
        continue;
      }

      final key = '${clean(item.title)}_${item.unitPrice.toStringAsFixed(2)}';

      if (seenRushKeys.contains(key)) {
        continue;
      }

      seenRushKeys.add(key);
      result.add(item);
    }

    return result.asMap().entries.map((entry) {
      return entry.value.copyWith(sortOrder: entry.key);
    }).toList();
  }

  AiEstimateResultModel _appendPromptMaterialItems(
      AiEstimateResultModel result,
      List<EstimateItemModel> materialItems,
      ) {
    if (materialItems.isEmpty) return result;

    String clean(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    String stem(String value) {
      var text = clean(value);

      if (text.endsWith('ies') && text.length > 4) {
        return '${text.substring(0, text.length - 3)}y';
      }

      if (text.endsWith('ches') && text.length > 5) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('shes') && text.length > 5) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('es') && text.length > 4) {
        return text.substring(0, text.length - 2);
      }

      if (text.endsWith('s') && text.length > 3) {
        return text.substring(0, text.length - 1);
      }

      return text;
    }

    Set<String> objectTokens(String value) {
      const ignored = {
        'material',
        'materials',
        'item',
        'items',
        'part',
        'parts',
        'supply',
        'supplies',
        'each',
        'per',
        'total',
        'cost',
        'price',
        'parsed',
        'from',
        'prompt',
        'detail',
        'details',
        'included',
        'include',
        'with',
        'for',
        'and',
        'the',
      };

      return clean(value)
          .split(' ')
          .map(stem)
          .where((e) => e.length >= 3)
          .where((e) => !ignored.contains(e))
          .toSet();
    }

    bool closeMoney(double a, double b) {
      return (a - b).abs() < 0.01;
    }

    bool isDuplicatePromptMaterial(
        EstimateItemModel existing,
        EstimateItemModel material,
        ) {
      final sameQty = closeMoney(existing.quantity, material.quantity);
      final sameUnitPrice = closeMoney(existing.unitPrice, material.unitPrice);
      final sameLineTotal = closeMoney(existing.lineTotal, material.lineTotal);

      if (!sameQty || !sameUnitPrice || !sameLineTotal) {
        return false;
      }

      final existingTokens = objectTokens(
        '${existing.title} ${existing.description}',
      );

      final materialTokens = objectTokens(
        '${material.title} ${material.description}',
      );

      if (existingTokens.isEmpty || materialTokens.isEmpty) return false;

      final hasSameObject =
          existingTokens.intersection(materialTokens).isNotEmpty;

      if (!hasSameObject) return false;

      final existingTitle = clean(existing.title);

      final looksLikeRealWork = RegExp(
        r'\b(installation|install|repair|replace|replacement|service|removal|remove|inspection|inspect|diagnose|troubleshoot|mount|assembly|assemble)\b',
      ).hasMatch(existingTitle);

      // Example:
      // Keep: "Outlet Service" / "Dishwasher Installation"
      // Remove: "Outlets" when exact same qty + price + total exists as material.
      return !looksLikeRealWork;
    }

    final filteredExistingItems = result.items.where((existing) {
      for (final material in materialItems) {
        if (isDuplicatePromptMaterial(existing, material)) {
          return false;
        }
      }

      return true;
    }).toList();

    final normalizedMaterials = materialItems.asMap().entries.map((entry) {
      final index = filteredExistingItems.length + entry.key;
      final item = entry.value;

      return item.copyWith(
        sortOrder: index,
        lineTotal: EstimateCalculator.calculateLineTotal(
          quantity: item.quantity,
          unitPrice: item.unitPrice,
        ),
      );
    }).toList();

    return result.copyWith(
      items: [
        ...filteredExistingItems,
        ...normalizedMaterials,
      ],
      notes: (result.notes ?? '').trim(),
    );
  }


  bool _isMaterialOnlyJobPrompt(String value) {
    final text = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s$.,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) return false;

    final hasMoney = RegExp(
      r'(\$ ?\d+|\d+ ?\$|\b\d+(\.\d+)?\s*(each|per|total)\b)',
    ).hasMatch(text);

    final words = text
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .toSet();

    const materialWords = {
      'material',
      'materials',
      'part',
      'parts',
      'supply',
      'supplies',
      'included',
      'include',
      'cost',
      'price',
      'each',
      'per',
      'total',
    };

    const actionWords = {
      'replace',
      'replacement',
      'repair',
      'fix',
      'install',
      'installation',
      'mount',
      'remove',
      'clean',
      'paint',
      'inspect',
      'diagnose',
      'check',
      'service',
      'troubleshoot',
      'change',
      'swap',
      'assemble',
      'connect',
      'disconnect',
      'move',
      'build',
      'cut',
      'seal',
      'patch',
      'caulk',
    };

    bool hasCloseWord(Set<String> sourceWords, Set<String> targetWords) {
      for (final word in sourceWords) {
        for (final target in targetWords) {
          if (_fastTokenClose(word, target)) {
            return true;
          }
        }
      }

      return false;
    }

    final hasMaterialSignal = hasCloseWord(words, materialWords);
    final hasWorkAction = hasCloseWord(words, actionWords);

    return hasMaterialSignal && hasMoney && !hasWorkAction;
  }

  bool _hasRushSignalInPrompt(String value) {
    final text = value
        .trim()
        .toLowerCase()
        .replaceAll(
      RegExp(r'[^a-zа-яё0-9\s]+', unicode: true),
      ' ',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) return false;

    final noRush = RegExp(
      r'\b(no rush|not urgent|not rush|not priority|standard timing|normal schedule|normal service|not expedited|no expedited|ne srochnaya|nesrochnaya|rabota ne srochnaya|ne srochno|bez srochnosti|obychnaya rabota|regular schedule|не срочно|не срочная|без срочности|обычная работа)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);

    if (noRush) return false;

    return RegExp(
      r'\b(urgent|rush|asap|same day|emergency|priority|expedited|srochno|srochnaya|rabota srochnaya|shoshilinch|срочно|срочная|работа срочная|экстренно|приоритетно)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  bool _promptSaysMaterialsNotIncluded(String value) {
    final text = value
        .trim()
        .toLowerCase()
        .replaceAll(
      RegExp(r'[^a-zа-яё0-9\s]+', unicode: true),
      ' ',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (text.isEmpty) return false;

    return RegExp(
      r'\b(materials not included|material not included|without materials|labor only|labour only|customer provides|customer supplied|bez materialov|materiali ne vklyucheni|materialy ne vklyucheny|material ne vkluchen|материалы не включены|без материалов)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  String _suggestionClean(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _lastPromptToken(String value) {
    final clean = value.toLowerCase();
    final match = RegExp(r'([a-z0-9]+)$').firstMatch(clean);
    return match?.group(1)?.trim() ?? '';
  }

  bool _closeEnoughToken(String typed, String word) {
    if (typed.length < 2 || word.length < 2) return false;

    if (word.startsWith(typed)) return true;
    if (typed.length >= 4 && word.contains(typed)) return true;

    if (typed.length >= 4) {
      final head = word.substring(0, math.min(word.length, typed.length));
      return _smallEditDistance(typed, head) <= 1;
    }

    return false;
  }

  int _smallEditDistance(String a, String b) {
    final m = a.length;
    final n = b.length;

    final dp = List.generate(
      m + 1,
          (_) => List<int>.filled(n + 1, 0),
    );

    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }

    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;

        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce(math.min);
      }
    }

    return dp[m][n];
  }

  _PromptSuggestion? _buildWorkioSuggestion(String prompt) {
    final token = _lastPromptToken(prompt);

    final promptTokens = _suggestionClean(prompt)
        .split(' ')
        .where((word) => word.length >= 3)
        .toSet();

    if (token.length < 2) return null;

    final actionSuggestion = _buildActionSuggestion(token);
    if (actionSuggestion != null) return actionSuggestion;

    const ignore = {
      'the',
      'and',
      'for',
      'with',
      'need',
      'needs',
      'client',
      'material',
      'materials',
      'urgent',
      'rush',
      'replace',
      'repair',
      'install',
      'service',
    };

    if (ignore.contains(token)) return null;

    double bestScore = 0;
    EstimatePriceRuleModel? bestRule;
    String bestInsert = '';

    for (final rule in _suggestionRules) {
      final candidates = <String>[
        rule.serviceType,
        rule.displayName ?? '',
        ...rule.aliases,
        ...rule.aiKeywords,
      ];

      for (final candidate in candidates) {
        final cleanCandidate = _suggestionClean(candidate);
        if (cleanCandidate.isEmpty) continue;

        final words = cleanCandidate
            .split(' ')
            .where((word) => word.length >= 3)
            .toList();

        for (final word in words) {
          if (!_closeEnoughToken(token, word)) continue;

          var score = 10.0;

          if (word.startsWith(token)) score += 5;
          if (word == token) score += 8;
          if (candidate == rule.displayName) score += 2;
          if (rule.aliases.contains(candidate)) score += 4;

          if (score > bestScore) {
            bestScore = score;
            bestRule = rule;
            bestInsert = word;
          }
        }
      }
    }

    if (bestRule == null || bestInsert.trim().isEmpty) return null;

    final label = (bestRule.displayName ?? '').trim().isNotEmpty
        ? bestRule.displayName!.trim()
        : bestRule.serviceType.trim();

    return _PromptSuggestion(
      label: label,
      insertText: bestInsert.trim(),
    );
  }

  bool _isWeakSuggestionWord(String word) {
    const weak = {
      'bath',
      'bathroom',
      'kitchen',
      'basement',
      'garage',
      'room',
      'bedroom',
      'living',
      'hallway',
      'office',
      'laundry',
      'outside',
      'outdoor',
      'yard',
      'floor',
      'wall',
      'ceiling',
    };

    return weak.contains(word.trim().toLowerCase());
  }

  Set<String> _ruleStrongWords(EstimatePriceRuleModel rule) {
    const ignored = {
      'service',
      'install',
      'installation',
      'replace',
      'replacement',
      'repair',
      'fix',
      'inspect',
      'inspection',
      'diagnose',
      'diagnostic',
      'urgent',
      'rush',
      'material',
      'materials',
      'the',
      'and',
      'for',
      'with',
    };

    final candidates = <String>[
      rule.serviceType,
      rule.displayName ?? '',
      ...rule.aliases,
      ...rule.aiKeywords,
    ];

    return candidates
        .expand((value) => _suggestionClean(value).split(' '))
        .where((word) => word.length >= 3)
        .where((word) => !ignored.contains(word))
        .where((word) => !_isWeakSuggestionWord(word))
        .toSet();
  }

  _PromptSuggestion? _buildActionSuggestion(String token) {
    final actions = <({String label, String insert, List<String> words})>[
      (
      label: 'Install',
      insert: 'install',
      words: [
        'install',
        'installation',
        'instal',
        'setup',
        'mount',
        'connect',
        'ustanovit',
        'ustanovka',
        'postavit',
      ],
      ),
      (
      label: 'Replace',
      insert: 'replace',
      words: [
        'replace',
        'replacement',
        'replac',
        'swap',
        'change',
        'zamenit',
        'zamena',
        'pomenyat',
      ],
      ),
      (
      label: 'Repair',
      insert: 'repair',
      words: [
        'repair',
        'repa',
        'fix',
        'troubleshoot',
        'service',
        'pochinit',
        'remont',
        'otremontirovat',
      ],
      ),
      (
      label: 'Inspect',
      insert: 'inspect',
      words: [
        'inspect',
        'inspection',
        'diagnose',
        'diagnostic',
        'check',
        'verify',
        'proverit',
        'diagnostika',
      ],
      ),
    ];

    for (final action in actions) {
      for (final word in action.words) {
        if (_closeEnoughToken(token, word)) {
          return _PromptSuggestion(
            label: action.label,
            insertText: action.insert,
          );
        }
      }
    }

    return null;
  }

  void _refreshWorkioSuggestion() {
    final next = _buildWorkioSuggestion(_promptController.text);

    if (_promptSuggestion?.label == next?.label &&
        _promptSuggestion?.insertText == next?.insertText) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _promptSuggestion = next;
    });
  }

  Future<void> _fetchCoachHint(String prompt) async {
    if (prompt.trim().length < 3) {
      if (mounted) setState(() => _coachHint = null);
      return;
    }

    debugPrint('COACH HINT REQUEST: $prompt');

    try {
      final rules = _suggestionRules.isNotEmpty ? _suggestionRules : [];

      final response = await Supabase.instance.client.functions.invoke(
        'coach-quick-quote-prompt',
        body: {
          'prompt': prompt.trim(),
          'priceRules': rules.map((r) => {
            'displayName': r.displayName,
            'unit': r.unit,
            'aliases': r.aliases,
          }).toList(),
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);
      final hint = data['hint']?.toString().trim() ?? '';

      debugPrint('COACH HINT RESULT: $hint');

      if (!mounted) return;
      setState(() => _coachHint = hint.isEmpty ? null : hint);
    } catch (_) {
      if (mounted) setState(() => _coachHint = null);
    }
  }

  String get _workioTypingText {
    final prompt = _promptController.text.trim();

    if (prompt.isEmpty) {
      return 'write the job, quantity, materials, and urgency';
    }

    final suggestion = _promptSuggestion;

    if (suggestion != null) {
      return 'did you mean ${suggestion.label}? Tap to use';
    }

    if (_coachHint != null) {
      return '$_coachHint';
    }

    return 'keep typing so I can find the closest service';
  }

  void _useWorkioSuggestion() {
    final suggestion = _promptSuggestion;
    if (suggestion == null) return;

    final text = _promptController.text;
    final selection = _promptController.selection;
    final cursor = selection.baseOffset < 0 ? text.length : selection.baseOffset;

    final before = text.substring(0, cursor);
    final after = text.substring(cursor);

    final match = RegExp(r'([A-Za-z0-9]+)$').firstMatch(before);

    final insert = suggestion.insertText.toLowerCase();

    final newBefore = match == null
        ? '${before.trimRight()} $insert'
        : before.substring(0, match.start) + insert;

    final separator = after.isEmpty || after.startsWith(' ') ? '' : ' ';
    final nextText = '$newBefore$separator$after';

    _promptController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
  }

  bool _fastSaysMaterialsNotIncluded(String prompt) {
    final text = _fastClean(prompt);

    return RegExp(
      r'\b(materials? not included|materials? excluded|no materials|without materials|labor only|materiali ne vklyucheni|materialy ne vklyucheny|material ne vklyuchen|bez materialov|материалы не включены|без материалов)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  bool _fastSaysMaterialsIncluded(String prompt) {
    final text = _fastClean(prompt);

    if (_fastSaysMaterialsNotIncluded(prompt)) return false;

    return RegExp(
      r'\b(materials? included|materials? are included|with materials|materiali vklyucheni|materialy vklyucheny|material vklyuchen|материалы включены|с материалами)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  List<String> _splitQuickQuoteJobsLocal(String prompt) {
    final normalized = prompt
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s*,\s*'), '. ')
        .trim();

    final parts = normalized
        .split(
      RegExp(
        r'(?:\.\s+|;\s+|\n+|\s+\+\s+|\s+and\s+(?=install|replace|repair|remove|inspect|diagnose|service))',
        caseSensitive: false,
      ),
    )
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) => _hasDefiniteWorkAction(e))
        .toList();

    return parts.isEmpty ? [prompt.trim()] : parts.take(8).toList();
  }

  Future<void> _generateQuote() async {
    final rawPrompt = _promptController.text.trim();

    if (rawPrompt.isEmpty) {
      _showSnack('Describe the work first');
      return;
    }

    setState(() {
      _isGenerating = true;
      _result = null;
      _selectedPriceRule = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
    });

    setState(() => _coachHint = 'Calculating your quote...');

    try {
      final rules = _suggestionRules.isNotEmpty
          ? _suggestionRules
          : (await EstimatePriceRulesService.getRules())
          .where((rule) => rule.isActive)
          .toList();

      if (rules.isEmpty) {
        _showSnack('No active Price Rules found');
        return;
      }

      final priceRules = rules.map((rule) => {
        'ruleId': rule.id,
        'displayName': rule.displayName,
        'serviceType': rule.serviceType,
        'unit': rule.unit,
        'baseRate': rule.baseRate,
        'rushFixedRate': rule.rushFixedRate,
        'aliases': rule.aliases,
        'aiKeywords': rule.aiKeywords,
        'negativeKeywords': rule.negativeKeywords,
      }).toList();

      final response = await Supabase.instance.client.functions.invoke(
        'quick-quote-process',
        body: {
          'prompt': rawPrompt,
          'priceRules': priceRules,
        },
      );

      final data = Map<String, dynamic>.from(response.data as Map);

      if (data['error'] != null) {
        _showSnack('Error: ${data['error']}');
        return;
      }

      final rawJobs = data['jobs'] as List? ?? [];
      debugPrint('JOBS FROM AI: $rawJobs');

      final cleanPromptText = (data['cleanPrompt'] ?? '').toString();

      final globalRush =
          _hasRushSignalInPrompt(rawPrompt) ||
              _hasRushSignalInPrompt(cleanPromptText);

      final materialsBlocked =
          _promptSaysMaterialsNotIncluded(rawPrompt) ||
              _promptSaysMaterialsNotIncluded(cleanPromptText);

      // Проверяем есть ли глобальный rush price
// Если все jobs isUrgent=true но в промпте есть явная общая цена за визит
// то убираем individual rush fees и добавляем один общий
      final allUrgent = rawJobs.isNotEmpty && rawJobs.every((j) => j['isUrgent'] == true);

      final items = <EstimateItemModel>[];
      int sortOrder = 0;
      final iconNames = <int, String>{};

      // Определяем есть ли глобальный visit rush price
// Если AI вернул job с ruleId=null и description содержит "Visit Rush Fee"
      // Определяем есть ли глобальный visit rush price из cleanPrompt
      double? globalVisitRushPrice;
      final cleanPromptLower = (data['cleanPrompt'] ?? '').toString().toLowerCase();
      final visitRushMatch = RegExp(
        r'(?:single|one|overall|global|total|entire visit|all jobs?)[\s\S]{0,30}?rush[\s\S]{0,20}?\$(\d+(?:\.\d+)?)',
      ).firstMatch(cleanPromptLower) ?? RegExp(
        r'visit[\s\S]{0,20}?(?:rush|fee|charge)[\s\S]{0,20}?\$(\d+(?:\.\d+)?)',
      ).firstMatch(cleanPromptLower);
      if (visitRushMatch != null) {
        globalVisitRushPrice = double.tryParse(visitRushMatch.group(1) ?? '');
      }

// Проверяем если AI вернул job с Visit Rush Fee
      for (final job in rawJobs) {
        final ruleId = job['ruleId']?.toString().trim() ?? '';
        final desc = job['description']?.toString().toLowerCase() ?? '';
        final containsRushKeyword = desc.contains('visit rush fee') ||
            desc.contains('rush fee') ||
            desc.contains('visit fee');

        if (ruleId.isEmpty && containsRushKeyword) {
          final price = (job['laborUnitPrice'] as num?)?.toDouble() ?? 0.0;
          // Если AI вернул цену — используем её
          if (price > 0) {
            globalVisitRushPrice = price;
          }
          // Если AI вернул rush job без цены — fallback: суммируем rushFixedRate всех правил
          // которые помечены как isUrgent
          else if (globalVisitRushPrice == null) {
            double fallbackRush = 0;
            for (final j in rawJobs) {
              if (j['isUrgent'] != true) continue;
              final rId = j['ruleId']?.toString().trim() ?? '';
              if (rId.isEmpty) continue;
              final r = rules.firstWhere(
                    (e) => e.id == rId,
                orElse: () => rules.first,
              );
              fallbackRush += (r.rushFixedRate ?? 0);
            }
            // Если хоть у одного правила есть rush — используем максимальный
            if (fallbackRush > 0) {
              double maxRush = 0;
              for (final j in rawJobs) {
                if (j['isUrgent'] != true) continue;
                final rId = j['ruleId']?.toString().trim() ?? '';
                if (rId.isEmpty) continue;
                final r = rules.firstWhere(
                      (e) => e.id == rId,
                  orElse: () => rules.first,
                );
                final rushVal = r.rushFixedRate ?? 0;
                if (rushVal > maxRush) maxRush = rushVal;
              }
              if (maxRush > 0) {
                globalVisitRushPrice = maxRush;
              }
            }
          }
        }
      }

      for (final job in rawJobs) {
        final ruleId = job['ruleId']?.toString().trim() ?? '';
        final desc = job['description']?.toString().toLowerCase() ?? '';

        // Пропускаем Visit Rush Fee job — добавим его отдельно в конце
        if (ruleId.isEmpty && desc.contains('visit rush fee')) continue;
        if (ruleId.isEmpty) continue;

        final rule = rules.firstWhere(
              (r) => r.id == ruleId,
          orElse: () => rules.first,
        );

        final serviceLabel = (rule.displayName?.trim().isNotEmpty == true
            ? rule.displayName!.trim()
            : rule.serviceType.trim());

        final quantity = (job['quantity'] as num?)?.toDouble() ?? 1.0;
        final laborUnitPrice = (job['laborUnitPrice'] as num?)?.toDouble();
        final isUrgent = job['isUrgent'] == true || globalRush;
        final unitPrice = laborUnitPrice ?? rule.baseRate;

        if (unitPrice <= 0) continue;

        final lineTotal = EstimateCalculator.calculateLineTotal(
          quantity: quantity,
          unitPrice: unitPrice,
        );

        // === Smart title: используем description от AI как title, если он содержит action ===
        // Например: rule.displayName = "Dishwasher Service", AI вернул "Install Dishwasher"
        // → title должен быть "Install Dishwasher", а не "Dishwasher Service"
        final aiDescription = job['description']?.toString().trim() ?? '';
        final hasActionInDescription = RegExp(
          r'\b(install|installation|replace|replacement|repair|repaired|fix|inspect|inspection|diagnose|diagnostic|remove|removal)\b',
          caseSensitive: false,
        ).hasMatch(aiDescription);

        final finalTitle = hasActionInDescription && aiDescription.isNotEmpty
            ? _capitalize(aiDescription)
            : serviceLabel;

        iconNames[sortOrder] = rule.iconName ?? '';
        items.add(EstimateItemModel(
          id: '',
          estimateId: '',
          title: finalTitle,
          description: aiDescription,
          unit: rule.unit,
          quantity: quantity,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
          sortOrder: sortOrder++,
          createdAt: null,
        ));

        // Rush fee per job — только если нет глобального Visit Rush Fee
        // И только если у правила настроен rushFixedRate
        if (isUrgent && (rule.rushFixedRate ?? 0) > 0 && globalVisitRushPrice == null) {
          final rushRate = rule.rushFixedRate!;
          items.add(EstimateItemModel(
            id: '',
            estimateId: '',
            title: '$serviceLabel Rush Fee',
            description: 'Expedited scheduling fee',
            unit: 'fixed',
            quantity: 1,
            unitPrice: rushRate,
            lineTotal: rushRate,
            sortOrder: sortOrder++,
            createdAt: null,
          ));
        }

        // Materials
        final materials = materialsBlocked ? const [] : (job['materials'] as List? ?? []);
        for (final mat in materials) {
          final matName = mat['name']?.toString().trim() ?? 'Materials';
          final matQty = (mat['quantity'] as num?)?.toDouble() ?? 1.0;
          final matUnitPrice = (mat['unitPrice'] as num?)?.toDouble() ?? 0.0;
          final matLineTotal = EstimateCalculator.calculateLineTotal(
            quantity: matQty,
            unitPrice: matUnitPrice,
          );

          if (matUnitPrice <= 0) continue;

          items.add(EstimateItemModel(
            id: '',
            estimateId: '',
            title: '$matName Materials',
            description: 'Materials from prompt',
            unit: 'item',
            quantity: matQty,
            unitPrice: matUnitPrice,
            lineTotal: matLineTotal,
            sortOrder: sortOrder++,
            createdAt: null,
          ));
        }
      }

      // Добавляем один общий Visit Rush Fee если он есть
      if (globalVisitRushPrice != null && globalVisitRushPrice > 0) {
        items.add(EstimateItemModel(
          id: '',
          estimateId: '',
          title: 'Visit Rush Fee',
          description: 'Single rush fee for the entire visit',
          unit: 'fixed',
          quantity: 1,
          unitPrice: globalVisitRushPrice,
          lineTotal: globalVisitRushPrice,
          sortOrder: sortOrder++,
          createdAt: null,
        ));
      }

      if (!mounted) return;

      if (items.isEmpty) {
        _showSnack('No matching Price Rules found');
        return;
      }

      final matchedCount = rawJobs.where((j) =>
      (j['ruleId']?.toString().trim() ?? '').isNotEmpty
      ).length;
      final totalCount = rawJobs.length;
      final dynamicConfidence = totalCount > 0
          ? ((matchedCount / totalCount) * 0.85) + 0.10
          : 0.75;

      setState(() {
        _itemIconNames = iconNames;
        _result = AiEstimateResultModel(
          title: 'Quick Quote',
          scope: null,
          notes: null,
          items: items,
          parsedRequest: AiParsedRequestModel.empty(rawPrompt),
          assumptions: const [],
          missingFields: const [],
          confidence: dynamicConfidence,
        );
      });

    } catch (e) {
      debugPrint('Quick Quote failed: $e');
      if (!mounted) return;
      _showSnack('Failed to generate quick quote');
    } finally {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _coachHint = null;
      });
    }
  }

  void _clearQuote() {
    setState(() {
      _promptController.clear();
      _result = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
      _selectedPriceRule = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      if (_selectedPhotos.length >= _maxPhotos) {
        _showSnack('Maximum $_maxPhotos photos allowed');
        return;
      }

      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
      );

      if (picked == null) return;

      setState(() {
        _selectedPhotos.add(picked);
        _result = null;
        _forcedServiceType = null;
        _matchedServiceLabel = null;
        _selectedPriceRule = null;
      });
    } catch (_) {
      _showSnack('Failed to pick photo');
    }
  }

  String _capitalize(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return clean;
    return clean[0].toUpperCase() + clean.substring(1);
  }

  void _clearPhoto() {
    setState(() {
      _selectedPhotos.clear();
      _result = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
      _selectedPriceRule = null;
    });
  }

  void _removePhotoAt(int index) {
    if (index < 0 || index >= _selectedPhotos.length) return;

    setState(() {
      _selectedPhotos.removeAt(index);
      _result = null;
      _forcedServiceType = null;
      _matchedServiceLabel = null;
      _selectedPriceRule = null;
    });
  }

  double _priceForAction(String actionType, EstimatePriceRuleModel rule) {
    switch (actionType) {
      case 'inspect':  return rule.diagnosticFixedRate ?? 0;
      case 'repair':   return rule.repairFixedRate ?? rule.baseRate;
      case 'replace':  return rule.replaceFixedRate ?? rule.baseRate;
      case 'install':  return rule.installFixedRate ?? rule.baseRate;
      default:         return rule.baseRate;
    }
  }

  String _titleForAction(String actionType, String serviceLabel) {
    switch (actionType) {
      case 'inspect':  return 'Inspect $serviceLabel';
      case 'repair':   return 'Repair $serviceLabel';
      case 'replace':  return 'Replace $serviceLabel';
      case 'install':  return 'Install $serviceLabel';
      case 'remove':   return 'Remove $serviceLabel';
      default:         return serviceLabel;
    }
  }

  Future<void> _generateFromPhotoSelections() async {
    final selectedActions = <({_PhotoDetection detection, _PhotoAction action})>[];
    for (final detection in _photoDetections) {
      for (final action in detection.actions) {
        if (action.isSelected) {
          selectedActions.add((detection: detection, action: action));
        }
      }
    }

    if (selectedActions.isEmpty) {
      _showSnack('Select at least one action');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final rules = _suggestionRules.isNotEmpty
          ? _suggestionRules
          : (await EstimatePriceRulesService.getRules())
          .where((r) => r.isActive)
          .toList();

      final items = <EstimateItemModel>[];
      final iconNames = <int, String>{};
      int sortOrder = 0;

      for (final entry in selectedActions) {
        final action = entry.action;
        final detection = entry.detection;

        EstimatePriceRuleModel? rule;
        try {
          rule = rules.firstWhere((r) => r.id == action.ruleId);
        } catch (_) {
          continue;
        }

        final price = _priceForAction(action.actionType, rule);
        if (action.actionType == 'inspect' && price <= 0) continue;
        if (price <= 0) continue;

        final serviceLabel = (rule.displayName?.trim().isNotEmpty == true
            ? rule.displayName!.trim()
            : rule.serviceType.trim());

        iconNames[sortOrder] = rule.iconName ?? '';

        items.add(EstimateItemModel(
          id: '',
          estimateId: '',
          title: _titleForAction(action.actionType, serviceLabel),
          description: detection.objectLabel,
          unit: rule.unit,
          quantity: 1,
          unitPrice: price,
          lineTotal: price,
          sortOrder: sortOrder++,
          createdAt: null,
        ));
      }

      // Rush fee
      if (_photoRushEnabled) {
        final rushPrice = double.tryParse(
            _photoRushPrice.trim().replaceAll('\$', '').replaceAll(',', '.')) ?? 0;
        if (rushPrice > 0) {
          items.add(EstimateItemModel(
            id: '', estimateId: '',
            title: 'Visit Rush Fee',
            description: 'Single rush fee for entire visit',
            unit: 'fixed',
            quantity: 1,
            unitPrice: rushPrice,
            lineTotal: rushPrice,
            sortOrder: sortOrder++,
            createdAt: null,
          ));
        }
      }

      // Materials
      if (_photoMaterialsEnabled) {
        _photoMaterialPrices.forEach((index, priceStr) {
          final trimmed = priceStr.trim();
          if (trimmed.isEmpty) return;
          final amount = double.tryParse(
              trimmed.replaceAll('\$', '').replaceAll(',', '.'));
          if (amount == null || amount <= 0) return;
          if (index >= _photoDetections.length) return;
          final detection = _photoDetections[index];
          items.add(EstimateItemModel(
            id: '', estimateId: '',
            title: '${detection.objectLabel} parts Materials',
            description: 'Materials from photo quote',
            unit: 'item',
            quantity: 1,
            unitPrice: amount,
            lineTotal: amount,
            sortOrder: sortOrder++,
            createdAt: null,
          ));
        });
      }

      if (items.isEmpty) {
        _showSnack('No matching Price Rules found');
        return;
      }

      if (!mounted) return;

      // Формируем промпт для scope/notes при Convert to Estimate
      final summaryParts = selectedActions.map((e) {
        final rule = rules.cast<EstimatePriceRuleModel?>().firstWhere((r) => r?.id == e.action.ruleId, orElse: () => null);
        final label = rule?.displayName ?? e.detection.objectLabel;
        return '${e.action.actionType} $label';
      }).toList();
      if (_photoRushEnabled) summaryParts.add('rush job');
      if (_photoMaterialsEnabled) summaryParts.add('materials included');
      _promptController.text = summaryParts.join(', ');

      setState(() {
        _photoDetections = [];
        _photoMode = false;
        _itemIconNames = iconNames;
        _result = AiEstimateResultModel(
          title: 'Photo Quick Quote',
          scope: null,
          notes: null,
          items: items,
          parsedRequest: AiParsedRequestModel.empty('Photo Quick Quote'),
          assumptions: const [],
          missingFields: const [],
          confidence: 0.92,
        );
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to generate quote: $e');
    } finally {
      if (!mounted) return;
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _analyzePhotoQuote() async {
    if (_selectedPhotos.isEmpty) {
      _showSnack('Choose at least one photo first');
      return;
    }

    setState(() {
      _isAnalyzingPhoto = true;
      _photoDetections = [];
      _photoDetectedIssue = null;
      _photoWarning = null;
      _photoMatchedService = null;
      _photoConfidence = null;
      _result = null;
      _photoRushEnabled = false;
      _photoRushPrice = '';
      _photoMaterialsEnabled = false;
      _photoMaterialPrices = {};
    });

    try {
      final images = <Map<String, dynamic>>[];
      for (final photo in _selectedPhotos) {
        final bytes = await photo.readAsBytes();
        images.add({
          'imageBase64': base64Encode(bytes),
          'mimeType': photo.mimeType ?? 'image/jpeg',
        });
      }

      final rules = await EstimatePriceRulesService.getRules();
      final activeRules = rules
          .where((rule) => rule.isActive == true)
          .map((rule) => {
        'rule_id': rule.id,
        'service_type': rule.serviceType,
        'display_name': rule.displayName,
        'category': rule.category,
        'unit': rule.unit,
        'aliases': rule.aliases,
        'ai_keywords': rule.aiKeywords,
        'negative_keywords': rule.negativeKeywords,
      })
          .toList();

      final response = await Supabase.instance.client.functions.invoke(
        'analyze-quick-quote-photo',
        body: {'images': images, 'priceRules': activeRules},
      );

      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;

      final globalWarning = (data['global_warning'] ?? '').toString();
      final rawDetections = data['detections'];

      if (rawDetections == null || (rawDetections as List).isEmpty) {
        setState(() {
          _photoWarning = globalWarning.isNotEmpty
              ? globalWarning
              : 'No matching services found for these photos.';
        });
        _showSnack('No matching services found');
        return;
      }

      final detections = (rawDetections).map<_PhotoDetection>((d) {
        final rawActions = (d['possible_actions'] as List? ?? []);
        final actions = rawActions.map((a) => _PhotoAction(
          ruleId: a['rule_id']?.toString() ?? '',
          label: a['label']?.toString() ?? '',
          actionType: a['action_type']?.toString() ?? 'service',
        )).toList();
        return _PhotoDetection(
          imageIndex: (d['image_index'] as num?)?.toInt() ?? 0,
          objectLabel: d['object_label']?.toString() ?? 'Unknown',
          confidence: (d['confidence'] as num?)?.toDouble() ?? 0,
          actions: actions,
          warning: d['warning']?.toString() ?? '',
        );
      }).where((d) => d.actions.isNotEmpty).toList();

      if (detections.isEmpty) {
        setState(() {
          _photoWarning = 'No matching Price Rules found for these photos.';
        });
        _showSnack('No matching services found');
        return;
      }

      for (final detection in detections) {
        if (detection.actions.isNotEmpty) {
          detection.actions.first.isSelected = true;
        }
      }

      setState(() {
        _photoDetections = detections;
        _photoWarning = globalWarning;
      });

      _showSnack(
          '${detections.length} service${detections.length > 1 ? 's' : ''} detected.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to analyze photos: $e');
    } finally {
      if (!mounted) return;
      setState(() => _isAnalyzingPhoto = false);
    }
  }

  Future<void> _loadPropertiesForClient(ClientModel client) async {
    try {
      final properties = await PropertyService.getPropertiesByClient(client.id);

      if (!mounted) return;

      setState(() {
        _properties = properties;
      });
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to load client properties');
    }
  }

  Future<ClientModel?> _createClientFromQuickQuote() async {
    final created = await showAddClientDialog(context);

    if (created == null) return null;

    final clients = await ClientService.getClients();

    if (!mounted) return created;

    setState(() {
      _clients = clients;
      _selectedClient = created;
      _selectedProperty = null;
      _properties = [];
    });

    _showSnack('Client created');

    return created;
  }

  Future<PropertyModel?> _createPropertyFromQuickQuote(ClientModel client) async {
    final created = await showAddPropertyDialog(
      context,
      clientId: client.id,
    );

    if (created == null) return null;

    await _loadPropertiesForClient(client);

    if (!mounted) return created;

    setState(() {
      _selectedClient = client;
      _selectedProperty = created;
    });

    _showSnack('Property created');

    return created;
  }

  Future<ClientModel?> _pickClient() async {
    final clients = _clients;

    final selected = await showDialog<ClientModel>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.72,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF22252D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: const Color(0xFF3A3F4B),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Choose Client',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(dialogContext),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 28,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                GestureDetector(
                  onTap: () async {
                    Navigator.pop(dialogContext);

                    final created = await _createClientFromQuickQuote();
                    if (!mounted || created == null) return;

                    setState(() {
                      _selectedClient = created;
                      _selectedProperty = null;
                      _properties = [];
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF303440),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          '+ Add New Client',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: clients.isEmpty
                      ? const Center(
                    child: Text(
                      'No clients found',
                      style: TextStyle(
                        color: Color(0xFFB7BCCB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )
                      : ListView.separated(
                    itemCount: clients.length,
                    separatorBuilder: (_, __) {
                      return const SizedBox(height: 10);
                    },
                    itemBuilder: (context, index) {
                      final client = clients[index];
                      final company = (client.companyName ?? '').trim();

                      return _PickerItemTile(
                        icon: Icons.person_outline_rounded,
                        title: client.fullName,
                        subtitle: company,
                        onTap: () {
                          Navigator.pop(dialogContext, client);
                        },
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

    if (selected != null) {
      setState(() {
        _selectedClient = selected;
        _selectedProperty = null;
        _properties = [];
      });

      return selected;
    }

    if (_selectedClient != null) {
      return _selectedClient;
    }

    return null;
  }

  Future<PropertyModel?> _pickProperty(ClientModel client) async {
    await _loadPropertiesForClient(client);

    if (!mounted) return null;

    final selected = await showDialog<PropertyModel>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(dialogContext).size.height * 0.72,
            ),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF22252D),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: const Color(0xFF3A3F4B),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Choose Property',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(dialogContext),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 28,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                GestureDetector(
                  onTap: () async {
                    Navigator.pop(dialogContext);

                    final created = await _createPropertyFromQuickQuote(client);
                    if (!mounted || created == null) return;

                    setState(() {
                      _selectedClient = client;
                      _selectedProperty = created;
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF303440),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.add_home_work_outlined,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Text(
                          '+ Add New Property',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: _properties.isEmpty
                      ? const Center(
                    child: Text(
                      'No properties found',
                      style: TextStyle(
                        color: Color(0xFFB7BCCB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )
                      : ListView.separated(
                    itemCount: _properties.length,
                    separatorBuilder: (_, __) {
                      return const SizedBox(height: 10);
                    },
                    itemBuilder: (context, index) {
                      final property = _properties[index];

                      return _PickerItemTile(
                        icon: Icons.home_work_outlined,
                        title: property.addressLine1,
                        subtitle: property.city ?? '',
                        onTap: () {
                          Navigator.pop(dialogContext, property);
                        },
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

    if (selected != null) {
      setState(() {
        _selectedClient = client;
        _selectedProperty = selected;
      });

      return selected;
    }

    if (_selectedProperty != null) {
      return _selectedProperty;
    }

    return null;
  }

  Future<void> _openEstimateDetails(String estimateId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EstimateDetailsScreen(estimateId: estimateId),
      ),
    );
  }

  void _removeItem(int index) {
    final current = _result;
    if (current == null) return;

    final updated = List<EstimateItemModel>.from(current.items);
    updated.removeAt(index);

    setState(() {
      _result = current.copyWith(items: updated);
    });
  }

  Future<void> _convertToEstimate() async {
    final result = _result;

    if (result == null || result.items.isEmpty) {
      _showSnack('Generate a quick quote first');
      return;
    }

    final client = await _pickClient();
    if (client == null) return;

    final property = await _pickProperty(client);
    if (property == null) return;

    setState(() {
      _isConverting = true;
      _selectedClient = client;
      _selectedProperty = property;
    });

    try {
      var title = (result.title ?? '').trim().isEmpty
          ? 'Quick Quote Estimate'
          : result.title!.trim();

      var scopeText = (result.scope ?? '').trim();
      var notesText = (result.notes ?? '').trim();

      try {
        // === Определяем контекст для AI ===
        final originalPrompt = _promptController.text.trim();
        final lowerPrompt = originalPrompt.toLowerCase();

        // Rush detection
        final hasRush = RegExp(
          r'\b(rush|urgent|asap|emergency|priority|expedited|srochno|srochnaya)\b',
        ).hasMatch(lowerPrompt);

        // Materials mode (источник правды — items)
        final hasMaterialItem = result.items.any((i) {
          final t = '${i.title} ${i.description} ${i.unit}'.toLowerCase();
          return RegExp(r'\b(material|materials|part|parts|supply|supplies)\b').hasMatch(t);
        });

        final saidLaborOnly = RegExp(
          r'\b(labor only|labour only|materials not included|materiali ne vklyucheni|ne vklyucheni)\b',
        ).hasMatch(lowerPrompt);

        String materialsMode;
        if (hasMaterialItem) {
          materialsMode = 'included';
        } else if (saidLaborOnly) {
          materialsMode = 'labor_only';
        } else if (RegExp(r'\b(materials included|with materials)\b').hasMatch(lowerPrompt)) {
          materialsMode = 'included';
        } else {
          materialsMode = 'unknown';
        }

        // Intent
        String intent = 'service';
        if (RegExp(r'\b(install|installation|mount|ustanovit)\b').hasMatch(lowerPrompt)) {
          intent = 'install';
        } else if (RegExp(r'\b(replace|replacement|swap|zamenit)\b').hasMatch(lowerPrompt)) {
          intent = 'replace';
        } else if (RegExp(r'\b(repair|fix|broken|pochinit|remont)\b').hasMatch(lowerPrompt)) {
          intent = 'repair';
        } else if (RegExp(r'\b(inspect|diagnose|check|proverit)\b').hasMatch(lowerPrompt)) {
          intent = 'diagnostic';
        }

        // Service label из первого labor item
        String serviceLabel = '';
        for (final item in result.items) {
          final t = item.title.toLowerCase();
          if (RegExp(r'\b(material|rush|urgent)\b').hasMatch(t)) continue;
          serviceLabel = item.title;
          break;
        }
        if (serviceLabel.isEmpty && result.items.isNotEmpty) {
          serviceLabel = result.items.first.title;
        }

        // Trade category из selected rule
        final tradeCategory = _selectedPriceRule?.category ?? '';

        final response = await Supabase.instance.client.functions.invoke(
          'generate-estimate-content-v2',
          body: {
            'items': result.items.map((i) => {
              'title': i.title,
              'quantity': i.quantity,
              'unitPrice': i.unitPrice,
              'unit': i.unit,
              'description': i.description,
            }).toList(),
            'serviceLabel': serviceLabel,
            'tradeCategory': tradeCategory,
            'intent': intent,
            'hasRush': hasRush,
            'materialsMode': materialsMode,
            'originalPrompt': originalPrompt,
            'clientName': client.fullName,
            'propertyAddress': property.addressLine1,
            'propertyCity': property.city ?? '',
          },
        );

        final data = Map<String, dynamic>.from(response.data as Map);

        // === Правильный парсинг ответа v2 ===
        final aiTitle = (data['title'] ?? '').toString().trim();
        final aiScope = (data['scopeOfWork'] ?? '').toString().trim();
        final aiNotes = (data['notes'] ?? '').toString().trim();
        final aiTerms = (data['terms'] ?? '').toString().trim();

        final inclusions = (data['inclusions'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ?? [];

        final exclusions = (data['exclusions'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ?? [];

        final assumptions = (data['assumptions'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ?? [];

        if (aiTitle.isNotEmpty) title = aiTitle;
        if (aiScope.isNotEmpty) scopeText = aiScope;

        // === Notes объединяем: notes + inclusions + exclusions + assumptions + terms ===
        final notesParts = <String>[];

        if (aiNotes.isNotEmpty) notesParts.add(aiNotes);

        if (inclusions.isNotEmpty) {
          notesParts.add('What\'s Included:\n${inclusions.map((e) => '- $e').join('\n')}');
        }

        if (exclusions.isNotEmpty) {
          notesParts.add('What\'s Not Included:\n${exclusions.map((e) => '- $e').join('\n')}');
        }

        if (assumptions.isNotEmpty) {
          notesParts.add('Assumptions:\n${assumptions.map((e) => '- $e').join('\n')}');
        }

        if (aiTerms.isNotEmpty) {
          notesParts.add('Terms & Conditions:\n$aiTerms');
        }

        if (notesParts.isNotEmpty) {
          notesText = notesParts.join('\n\n');
        }
      } catch (e) {
        debugPrint('Convert AI text failed: $e');
      }

      final estimate = EstimateModel(
        id: '',
        adminAuthId: '',
        clientId: client.id,
        propertyId: property.id,
        estimateNumber: '',
        title: title,
        status: 'draft',
        scopeText: scopeText,
        notes: notesText,
        subtotal: 0,
        tax: 0,
        discount: 0,
        total: 0,
        validUntil: DateTime.now().add(const Duration(days: 14)),
        createdAt: null,
        updatedAt: null,
      );

      // Нормализуем unit под DB constraint (только item/sqft/fixed)
      final allowedUnits = {'item', 'sqft', 'fixed'};
      final normalizedItems = result.items.map((item) {
        final currentUnit = item.unit.trim().toLowerCase();
        // load/each/hour/room/loads → item (это всё счётные единицы)
        // всё остальное → fixed
        String safeUnit;
        if (allowedUnits.contains(currentUnit)) {
          safeUnit = currentUnit;
        } else if (currentUnit == 'load' || currentUnit == 'loads' ||
            currentUnit == 'each' || currentUnit == 'hour' ||
            currentUnit == 'hours' || currentUnit == 'room' ||
            currentUnit == 'rooms' || currentUnit == 'unit' ||
            currentUnit == 'units') {
          safeUnit = 'item';
        } else {
          safeUnit = 'fixed';
        }
        return item.copyWith(unit: safeUnit);
      }).toList();

      final created = await EstimateService.createEstimateWithItems(
        estimate: estimate,
        items: normalizedItems,
        taxRate: _taxRate,
        discountValue: 0,
        discountIsPercentage: false,
      );

      if (!mounted) return;

      _showSnack('Estimate ${created.estimateNumber} created');

      _clearQuote();

      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EstimateDetailsScreen(estimateId: created.id),
        ),
      );

    } catch (e, st) {
      debugPrint('🔴 CONVERT FAILED: $e');
      debugPrint('🔴 STACK: $st');
      if (!mounted) return;
      _showSnack('Failed to convert quote to estimate: $e');
    } finally {
      if (!mounted) return;

      setState(() {
        _isConverting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0B0F);
    final result = _result;
    final totals = _totals;

    return Scaffold(
      backgroundColor: background,
      body: _isLoading
          ? const Center(
        child: CupertinoActivityIndicator(radius: 16),
      )
          : SafeArea(
        top: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 30),
          children: [
            const _QuickQuoteGlassHeader(),
            const SizedBox(height: 12),
            _SectionCard(
              title: _photoMode ? 'Photo Quick Quote' : 'Text Quick Quote',
              subtitle: _photoMode
                  ? 'Upload a job photo and let Workio prepare a rough quote'
                  : 'Fast rough pricing using Price Rules',
              titleIcon: _photoMode
                  ? CupertinoIcons.camera_fill
                  : CupertinoIcons.text_alignleft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ModeSwitch(
                    photoMode: _photoMode,
                    onChanged: (value) {
                      setState(() {
                        _photoMode = value;
                        _result = null;
                      });
                      if (value && !_photoWarningShown) {
                        _photoWarningShown = true;
                        showCupertinoDialog(
                          context: context,
                          builder: (ctx) => CupertinoAlertDialog(
                            title: const Text('Photo AI Tips'),
                            content: const Text(
                              'Works best for visible problems — damage, leaks, broken items, junk, stains, burned parts.\n\nFor new installations or hidden issues, add a short text note after analyzing.',
                            ),
                            actions: [
                              CupertinoDialogAction(
                                isDefaultAction: true,
                                child: const Text('Got it'),
                                onPressed: () => Navigator.pop(ctx),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  if (!_photoMode) ...[
                    _PromptBoxWithMic(
                      controller: _promptController,
                      isListening: _isListening,
                      voiceLiveText: _voiceLiveText,
                      speechReady: _speechReady,
                      onMicTap: _isListening ? _stopVoiceInput : _openVoicePromptSheet,
                      onClearTap: _clearQuote,
                      workioText: _workioTypingText,
                      onWorkioTap: _promptSuggestion == null ? null : _useWorkioSuggestion,
                    ),
                    const SizedBox(height: 16),
                    _SwipeGenerateQuoteButton(
                      isLoading: _isGenerating,
                      onSubmit: _generateQuote,
                    ),
                  ] else ...[
                    if (_photoDetections.isEmpty) ...[
                      _PhotoPickerBlock(
                        photos: _selectedPhotos,
                        maxPhotos: _maxPhotos,
                        onCamera: () => _pickPhoto(ImageSource.camera),
                        onGallery: () => _pickPhoto(ImageSource.gallery),
                        onClearAll: _clearPhoto,
                        onRemoveAt: _removePhotoAt,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          color: _selectedPhotos.isEmpty
                              ? const Color(0xFF30333D)
                              : const Color(0xFF9A5A00),
                          borderRadius: BorderRadius.circular(18),
                          onPressed: _selectedPhotos.isEmpty || _isAnalyzingPhoto
                              ? null
                              : _analyzePhotoQuote,
                          child: _isAnalyzingPhoto
                              ? const CupertinoActivityIndicator(color: Colors.white)
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _selectedPhotos.isEmpty
                                  ? const Icon(CupertinoIcons.sparkles,
                                  color: Colors.white, size: 18)
                                  : const _PulsingSparkleIcon(),
                              const SizedBox(width: 9),
                              const Text(
                                'Analyze Photos',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // СТАЛО:
                      _PhotoDetectionSelectionView(
                        detections: _photoDetections,
                        rushEnabled: _photoRushEnabled,
                        rushPrice: _photoRushPrice,
                        materialsEnabled: _photoMaterialsEnabled,
                        onRushToggle: (val) =>
                            setState(() => _photoRushEnabled = val),
                        onRushPriceChanged: (val) =>
                            setState(() => _photoRushPrice = val),
                        onMaterialsToggle: (val) =>
                            setState(() => _photoMaterialsEnabled = val),
                        materialPrices: _photoMaterialPrices,                          // ← ДОБАВИТЬ
                        onMaterialPriceChanged: (index, value) =>                      // ← ДОБАВИТЬ
                        setState(() => _photoMaterialPrices[index] = value),       // ← ДОБАВИТЬ
                        onRetake: () => setState(() {
                          _photoDetections = [];
                          _selectedPhotos.clear();
                        }),
                        onGenerate: _generateFromPhotoSelections,
                        isGenerating: _isGenerating,
                      ),
                    ],
                  ],
                ],
              ),
            ),

            if (result != null) ...[
              const SizedBox(height: 14),

              _SectionCard(
                title: 'Price Breakdown',
                subtitle: 'Calculated from Price Rules',
                titleIcon: CupertinoIcons.list_bullet,
                child: result.items.isEmpty
                    ? const _InlineEmptyState(
                  text: 'No quote items generated.',
                )
                    : Column(
                  children: List.generate(result.items.length, (index) {
                    final item = result.items[index];

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == result.items.length - 1 ? 0 : 10,
                      ),
                      child: _QuickQuoteItemTile(
                        item: item,
                        iconName: _itemIconNames[item.sortOrder],
                        onDelete: () => _removeItem(index), // ← добавь это
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 14),

              _QuickQuoteHero(
                total: EstimateFormatters.formatCurrency(totals.total),
                subtotal: EstimateFormatters.formatCurrency(totals.subtotal),
                taxLabel: _taxLabel,
                tax: EstimateFormatters.formatCurrency(totals.tax),
                discount: '- ${EstimateFormatters.formatCurrency(totals.discount)}',
                currencyCode: _currencyCode,
                confidence: '${(result.confidence * 100).round()}%',
                canConvert: result.items.isNotEmpty,
                isConverting: _isConverting,
                onConvert: _convertToEstimate,
                discountValue: _discountValue,
                discountIsPercentage: _discountIsPercentage,
                onDiscountChanged: (value, isPercentage) {
                  setState(() {
                    _discountValue = value;
                    _discountIsPercentage = isPercentage;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _SnackType { success, error, info }

class _FastPromptPriceOverride {
  final double quantity;
  final double unitPrice;
  final Set<String> objectTokens;

  const _FastPromptPriceOverride({
    required this.quantity,
    required this.unitPrice,
    required this.objectTokens,
  });
}

class _PromptSuggestion {
  final String label;
  final String insertText;

  const _PromptSuggestion({
    required this.label,
    required this.insertText,
  });
}

class _SparkBoltIcon extends StatefulWidget {
  const _SparkBoltIcon();

  @override
  State<_SparkBoltIcon> createState() => _SparkBoltIconState();
}

class _SparkBoltIconState extends State<_SparkBoltIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(
    begin: 0.92,
    end: 1.12,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
  );

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.65,
    end: 1.0,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: const Icon(
          CupertinoIcons.bolt_fill,
          color: Colors.white,
          size: 17,
        ),
      ),
    );
  }
}

class _SwipeGenerateQuoteButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback onSubmit;

  const _SwipeGenerateQuoteButton({
    required this.isLoading,
    required this.onSubmit,
  });

  @override
  State<_SwipeGenerateQuoteButton> createState() => _SwipeGenerateQuoteButtonState();
}

class _SwipeGenerateQuoteButtonState extends State<_SwipeGenerateQuoteButton>
    with TickerProviderStateMixin {
  double _drag = 0;
  double _fillWidth = 0;

  static const double _knob = 50.0;

  late final AnimationController _glowFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addListener(() {
    setState(() {});
  })
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() { _fillWidth = 0; });
      }
    });

  double _snapStart = 0;

  late final AnimationController _snapBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..addListener(() {
    final t = Curves.easeOutCubic.transform(_snapBack.value);
    setState(() => _drag = _snapStart * (1.0 - t));
  });

  static const _orange = Color(0xFF9A5A00);
  static const _track = Color(0xFF171A22);

  @override
  void dispose() {
    _glowFade.dispose();
    _snapBack.dispose();
    super.dispose();
  }

  void _finish(double maxDrag) {
    final passed = _drag > maxDrag * 0.62;

    if (passed && !widget.isLoading) {
      setState(() {
        _drag = maxDrag;
        _fillWidth = maxDrag + _knob / 2;
      });
      _glowFade.value = 1.0;
      widget.onSubmit();
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _glowFade.reverse();
      });
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && !widget.isLoading) {
          _snapStart = _drag;
          _snapBack.forward(from: 0.0);
        }
      });
      return;
    }

    // Не дотянул — просто snap back
    _snapStart = _drag;
    _snapBack.forward(from: 0.0);
    _glowFade.reverse();
  }

  @override
  void didUpdateWidget(covariant _SwipeGenerateQuoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isLoading && !widget.isLoading) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (!mounted) return;
        _snapStart = _drag;
        _snapBack.forward(from: 0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const height = 58.0;
        const knob = _knob;
        final maxDrag = constraints.maxWidth - knob - 8;

        return GestureDetector(
          onHorizontalDragUpdate: widget.isLoading
              ? null
              : (details) {
            setState(() {
              _drag = (_drag + details.delta.dx).clamp(0.0, maxDrag);
              _fillWidth = _drag + knob / 2;
            });
            if (_drag > 0) _glowFade.value = 1.0;
          },
          onHorizontalDragEnd: widget.isLoading ? null : (_) => _finish(maxDrag),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1A1C24),
                  const Color(0xFF22252D),
                ],
              ),
              border: Border.all(
                color: const Color(0xFF2E3140),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Track fill (огненный fade)
                Positioned(
                  left: 4,
                  top: 4,
                  bottom: 4,
                  child: Opacity(
                    opacity: _glowFade.value,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: _fillWidth > 0 ? _fillWidth : 0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFD97706).withOpacity(0.5),
                            const Color(0xFF9A5A00).withOpacity(0.15),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Label
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: widget.isLoading ? 0.5 : 1.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.isLoading ? 'Generating...' : 'Swipe to generate',
                        style: const TextStyle(
                          color: Color(0xFFB7BCCB),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!widget.isLoading)
                        const Icon(
                          CupertinoIcons.arrow_right,
                          color: Color(0xFF9A5A00),
                          size: 15,
                        ),
                    ],
                  ),
                ),

                // Knob
                Positioned(
                  left: 4 + _drag,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFD97706), Color(0xFF9A5A00)],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF9A5A00).withOpacity(0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: widget.isLoading
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const _SparkBoltIcon(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? titleIcon;
  final IconData? subtitleIcon;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    this.titleIcon,
    this.subtitleIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2A2D35),
                Color(0xFF22252D),
              ],
            ),
            border: Border.all(
              color: Color(0xFF343846),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.42),
                blurRadius: 26,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.035),
                blurRadius: 8,
                offset: const Offset(-2, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (titleIcon != null) ...[
                    Icon(
                      titleIcon,
                      size: 18,
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),

              if ((subtitle ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (subtitleIcon != null) ...[
                      Icon(
                        subtitleIcon,
                        size: 14,
                        color: Color(0xFFB7BCCB),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB7BCCB),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PromptBoxWithMic extends StatelessWidget {
  final TextEditingController controller;
  final bool isListening;
  final bool speechReady;
  final VoidCallback onMicTap;
  final String voiceLiveText;
  final String workioText;
  final VoidCallback? onWorkioTap;
  final VoidCallback onClearTap;


  const _PromptBoxWithMic({
    required this.controller,
    required this.isListening,
    required this.speechReady,
    required this.onMicTap,
    required this.workioText,
    this.onWorkioTap,
    required this.onClearTap,
    required this.voiceLiveText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF161820),
            Color(0xFF111318),
          ],
        ),
        border: Border.all(
          color: Color(0xFF343846),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Workio label ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: _WorkioTypingLabel(
              text: workioText,
              onTap: onWorkioTap,
            ),
          ),

          // ── Divider 1 ──
          Container(
            height: 1,
            color: const Color(0xFF252936),
          ),

          // ── Prompt text field ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isListening) ...[
                  _VoiceListeningPanel(
                    liveText: voiceLiveText,
                  ),
                  const SizedBox(height: 12),
                ],
                Scrollbar(
                  thumbVisibility: true,
                  thickness: 3,
                  radius: const Radius.circular(99),
                  child: TextField(
                    controller: controller,
                    maxLines: 6,
                    minLines: 6,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    cursorColor: Color(0xFFF59E0B),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Replace 2 outlets, materials included, urgent',
                      hintStyle: TextStyle(
                        color: Color(0xFF697086),
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Divider 2 ──
          Container(
            height: 1,
            color: const Color(0xFF252936),
          ),

          // ── Mic + Clear row ──
          // ── Mic + Clear row ──
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E2028),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _PromptMicButton(
                  isListening: isListening,
                  enabled: speechReady,
                  onTap: onMicTap,
                ),
                const SizedBox(width: 8),
                _PromptClearButton(
                  onTap: onClearTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceListeningPanel extends StatelessWidget {
  final String liveText;

  const _VoiceListeningPanel({
    required this.liveText,
  });

  @override
  Widget build(BuildContext context) {
    final cleanLive = liveText.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.waveform,
                color: Color(0xFFF59E0B),
                size: 17,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Listening... speak now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF4D4D),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: const LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0xFF252936),
              valueColor: AlwaysStoppedAnimation<Color>(
                Color(0xFFF59E0B),
              ),
            ),
          ),
          if (cleanLive.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              cleanLive,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFB7BCCB),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromptMicButton extends StatelessWidget {
  final bool isListening;
  final bool enabled;
  final VoidCallback onTap;

  const _PromptMicButton({
    required this.isListening,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: enabled ? onTap : null,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isListening
              ? const Color(0xFF7A1F1F)
              : const Color(0xFF1A1B22),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isListening
                ? const Color(0xFFFF6B6B).withOpacity(0.35)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Icon(
          isListening ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill,
          color: isListening ? Colors.white : const Color(0xFFB6BCD0),
          size: 19,
        ),
      ),
    );
  }
}

class _PromptClearButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PromptClearButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1B22),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        child: const Icon(
          CupertinoIcons.clear_thick,
          color: Color(0xFFFF6B6B),
          size: 18,
        ),
      ),
    );
  }
}

class _WorkioTypingLabel extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const _WorkioTypingLabel({
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Static "Workio_" prefix — green monospace
          const Text(
            'Workio_',
            style: TextStyle(
              color: Color(0xFF39D353),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
              height: 1.25,
            ),
          ),
          // Animated message
          Expanded(
            child: TweenAnimationBuilder<int>(
              key: ValueKey(text),
              tween: IntTween(begin: 0, end: text.length),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                final visibleText = text.substring(0, math.min(value, text.length));
                return Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: visibleText,
                        style: TextStyle(
                          color: onTap == null
                              ? const Color(0xFFB7BCCB)
                              : const Color(0xFFFFC46B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                          height: 1.25,
                        ),
                      ),
                      const WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: _GreenBlinkCursor(),
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrangeBlinkCursor extends StatefulWidget {
  const _OrangeBlinkCursor();

  @override
  State<_OrangeBlinkCursor> createState() => _OrangeBlinkCursorState();
}

class _OrangeBlinkCursorState extends State<_OrangeBlinkCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.15,
    end: 1.0,
  ).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 2,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _GreenBlinkCursor extends StatefulWidget {
  const _GreenBlinkCursor();

  @override
  State<_GreenBlinkCursor> createState() => _GreenBlinkCursorState();
}

class _GreenBlinkCursorState extends State<_GreenBlinkCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.1,
    end: 1.0,
  ).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 2,
        height: 12,
        decoration: BoxDecoration(
          color: const Color(0xFF39D353),
          borderRadius: BorderRadius.circular(99),
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

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
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

class _BigTotalBlock extends StatelessWidget {
  final String total;
  final String currencyCode;

  const _BigTotalBlock({
    required this.total,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated Total',
            style: TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            currencyCode,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteHero extends StatefulWidget {
  final String total;
  final String subtotal;
  final String taxLabel;
  final String tax;
  final String discount;
  final String currencyCode;
  final String confidence;
  final bool canConvert;
  final bool isConverting;
  final VoidCallback onConvert;
  final double discountValue;
  final bool discountIsPercentage;
  final void Function(double value, bool isPercentage) onDiscountChanged;

  const _QuickQuoteHero({
    required this.total,
    required this.subtotal,
    required this.taxLabel,
    required this.tax,
    required this.discount,
    required this.currencyCode,
    required this.confidence,
    required this.canConvert,
    required this.isConverting,
    required this.onConvert,
    required this.discountValue,
    required this.discountIsPercentage,
    required this.onDiscountChanged,
  });

  @override
  State<_QuickQuoteHero> createState() => _QuickQuoteHeroState();
}

class _QuickQuoteHeroState extends State<_QuickQuoteHero> {
  void _openDiscountSheet() {
    double tempValue = widget.discountValue;
    bool tempIsPercentage = widget.discountIsPercentage;

    final controller = TextEditingController(
      text: widget.discountValue > 0
          ? widget.discountValue.toStringAsFixed(0)
          : '',
    );

    final discountFocusNode = FocusNode();
    bool isClosing = false;

    Future<void> closeDiscountDialog(
        BuildContext dialogContext, {
          bool clear = false,
          bool apply = false,
        }) async {
      if (isClosing) return;
      isClosing = true;

      discountFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();

      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 220));

      if (!dialogContext.mounted) return;

      if (clear) {
        widget.onDiscountChanged(0, false);
      }

      if (apply) {
        final value = double.tryParse(
          controller.text.trim().replaceAll(',', '.'),
        ) ??
            tempValue;

        widget.onDiscountChanged(
          value < 0 ? 0 : value,
          tempIsPercentage,
        );
      }

      Navigator.of(dialogContext).pop();
    }

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF22252D),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: const Color(0xFF3A3F4B),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.minus_circle_fill,
                          color: Color(0xFFF59E0B),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Discount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Apply discount to this quick quote',
                                style: TextStyle(
                                  color: Color(0xFFB7BCCB),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => closeDiscountDialog(dialogContext),
                          child: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Color(0xFF8E93A6),
                            size: 28,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF101117),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF303440),
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        focusNode: discountFocusNode,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        cursorColor: const Color(0xFFF59E0B),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: SizedBox(
                            width: 46,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: tempIsPercentage
                                  ? const SizedBox(
                                key: ValueKey('empty-prefix'),
                                width: 46,
                              )
                                  : const Center(
                                key: ValueKey('dollar-prefix'),
                                child: Icon(
                                  CupertinoIcons.money_dollar,
                                  color: Color(0xFFB7BCCB),
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                          suffixIcon: SizedBox(
                            width: 46,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: tempIsPercentage
                                  ? const Center(
                                key: ValueKey('percent-suffix'),
                                child: Icon(
                                  CupertinoIcons.percent,
                                  color: Color(0xFFB7BCCB),
                                  size: 20,
                                ),
                              )
                                  : const SizedBox(
                                key: ValueKey('empty-suffix'),
                                width: 46,
                              ),
                            ),
                          ),
                          hintText: '0',
                          hintStyle: const TextStyle(
                            color: Color(0xFF697086),
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 18,
                          ),
                        ),
                        onChanged: (value) {
                          tempValue = double.tryParse(
                            value.replaceAll(',', '.'),
                          ) ??
                              0;
                        },
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      height: 52,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171A22),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF303440),
                        ),
                      ),
                      child: Stack(
                        children: [
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            alignment: tempIsPercentage
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: 0.5,
                              heightFactor: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.28),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setDialogState(() {
                                      tempIsPercentage = false;
                                    });
                                  },
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 180),
                                      child: Icon(
                                        CupertinoIcons.money_dollar,
                                        key: ValueKey(tempIsPercentage ? 'dollar-off' : 'dollar-on'),
                                        color: tempIsPercentage
                                            ? const Color(0xFFB7BCCB)
                                            : Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setDialogState(() {
                                      tempIsPercentage = true;
                                    });
                                  },
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 180),
                                      child: Icon(
                                        CupertinoIcons.percent,
                                        key: ValueKey(tempIsPercentage ? 'percent-on' : 'percent-off'),
                                        color: tempIsPercentage
                                            ? Colors.white
                                            : const Color(0xFFB7BCCB),
                                        size: 21,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            color: const Color(0xFF3A3F4B),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: () {
                              closeDiscountDialog(dialogContext, clear: true);
                            },
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            color: const Color(0xFFD97706),
                            borderRadius: BorderRadius.circular(16),
                            onPressed: () {
                              closeDiscountDialog(dialogContext, apply: true);
                            },
                            child: const Text(
                              'Apply',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      controller.dispose();
      discountFocusNode.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFF9A5A00);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF272A32), Color(0xFF20232B)],
        ),
        border: Border.all(color: const Color(0xFF343846)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.bolt_fill, color: orange, size: 17),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Quick Quote Total',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  widget.confidence,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            widget.total,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w900, letterSpacing: -1.4, height: 1),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.money_dollar_circle_fill, color: Color(0xFFB7BCCB), size: 15),
              const SizedBox(width: 6),
              Text(
                '${widget.currencyCode} • rough price including tax',
                style: const TextStyle(color: Color(0xFFB7BCCB), fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _HeroSummaryRow(icon: CupertinoIcons.square_list_fill, label: 'Subtotal', value: widget.subtotal),
          const SizedBox(height: 10),
          _HeroSummaryRow(icon: CupertinoIcons.percent, label: widget.taxLabel, value: widget.tax),
          const SizedBox(height: 10),

          // Discount — тапабельный
          GestureDetector(
            onTap: _openDiscountSheet,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF2A2D35),
                    Color(0xFF22252D),
                  ],
                ),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: widget.discountValue > 0
                      ? const Color(0xFFF59E0B).withOpacity(0.4)
                      : const Color(0xFF343846),
                ),
              ),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.minus_circle_fill, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Discount',
                      style: TextStyle(color: Color(0xFFB7BCCB), fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    widget.discount,
                    style: TextStyle(
                      color: widget.discountValue > 0 ? const Color(0xFFF59E0B) : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(CupertinoIcons.chevron_right, size: 14, color: Color(0xFF697086)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: orange,
              borderRadius: BorderRadius.circular(16),
              onPressed: !widget.canConvert || widget.isConverting ? null : widget.onConvert,
              child: widget.isConverting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Convert to Estimate',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeroSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2A2D35),
            Color(0xFF22252D),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFF343846),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB7BCCB),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewInfoBlock extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _PreviewInfoBlock({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(16),
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
          Text(
            value,
            maxLines: multiline ? null : 2,
            overflow: multiline ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedQuoteItemsList extends StatelessWidget {
  final List<EstimateItemModel> items;

  const _ConnectedQuoteItemsList({
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF23252E),
        ),
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final isLast = index == items.length - 1;

          return Column(
            children: [
              _ConnectedQuoteItemRow(
                item: items[index],
              ),
              if (!isLast)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFF23252E),
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _ConnectedQuoteItemRow extends StatelessWidget {
  final EstimateItemModel item;

  const _ConnectedQuoteItemRow({
    required this.item,
  });

  bool get _isMaterial {
    final title = item.title.toLowerCase();
    final description = (item.description ?? '').toLowerCase();

    if (title.contains('labor') || title.contains('diagnostic')) {
      return false;
    }

    return title.contains('material') ||
        title.contains('parts') ||
        title.contains('consumables') ||
        description.contains('parsed from prompt');
  }

  bool get _isRush {
    final text = item.title.toLowerCase();

    return text.contains('rush') ||
        text.contains('expedited') ||
        text.contains('priority');
  }

  IconData get _icon {
    if (_isRush) return CupertinoIcons.bolt_fill;
    if (_isMaterial) return CupertinoIcons.cube_box_fill;
    return CupertinoIcons.hammer_fill;
  }

  String get _tag {
    if (_isRush) return 'Rush';
    if (_isMaterial) return 'Materials';
    return 'Labor';
  }

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    final qty = EstimateFormatters.formatQuantity(item.quantity);
    final unit = EstimateFormatters.formatUnit(item.unit);
    final unitPrice = EstimateFormatters.formatCurrency(item.unitPrice);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF171A22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF343846),
              ),
            ),
            child: Icon(
              _icon,
              color: const Color(0xFFF59E0B),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$_tag • $qty $unit × $unitPrice',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9EA4B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          Text(
            EstimateFormatters.formatCurrency(lineTotal),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteItemTile extends StatelessWidget {
  final EstimateItemModel item;
  final String? iconName;
  final VoidCallback? onDelete; // ← добавь

  const _QuickQuoteItemTile({
    required this.item,
    this.iconName,
    this.onDelete, // ← добавь
  });

  bool get _isMaterial {
    final title = item.title.toLowerCase();
    final description = (item.description ?? '').toLowerCase();

    if (title.contains('labor') || title.contains('diagnostic')) {
      return false;
    }

    return title.contains('material') ||
        title.contains('parts') ||
        title.contains('consumables') ||
        description.contains('parsed from prompt');
  }

  bool get _isRush {
    final text = item.title.toLowerCase();
    return text.contains('rush') ||
        text.contains('expedited') ||
        text.contains('priority');
  }

  IconData get _icon {
    if (_isRush) return CupertinoIcons.bolt_fill;
    if (_isMaterial) return CupertinoIcons.cube_box_fill;
    return WorkioIconMapper.resolveFromTitle(item.title, iconName: iconName);
  }

  String get _tag {
    if (_isRush) return 'Rush';
    if (_isMaterial) return 'Materials';
    return 'Labor';
  }

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

    final qty = EstimateFormatters.formatQuantity(item.quantity);
    final unit = EstimateFormatters.formatUnit(item.unit);
    final unitPrice = EstimateFormatters.formatCurrency(item.unitPrice);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2A2D35), Color(0xFF22252D)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF343846)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2D35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF3A3F4B)),
                ),
                child: Icon(_icon, color: const Color(0xFFF59E0B), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$_tag • $qty $unit × $unitPrice',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E93A6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                EstimateFormatters.formatCurrency(lineTotal),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),

        // X кнопка — top-right, немного вне карточки
        if (onDelete != null)
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E3140),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF3A3F4B),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: Color(0xFF8E93A6),
                  size: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EstimateItemTile extends StatelessWidget {
  final EstimateItemModel item;

  const _EstimateItemTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final lineTotal = item.lineTotal > 0
        ? item.lineTotal
        : EstimateCalculator.calculateLineTotal(
      quantity: item.quantity,
      unitPrice: item.unitPrice,
    );

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
            item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((item.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.description!,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
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

class _InlineEmptyState extends StatelessWidget {
  final String text;

  const _InlineEmptyState({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF23252E)),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.info,
            color: Color(0xFF8E93A6),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionSheet<T> extends StatelessWidget {
  final String title;
  final List<T> items;
  final String Function(T item) itemLabel;
  final String? emptyText;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.itemLabel,
    this.emptyText,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),

            if (actionLabel != null && onActionTap != null) ...[
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: onActionTap,
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101117),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF23252E)),
                ),
                child: Text(
                  emptyText ?? 'No items found',
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];

                    return GestureDetector(
                      onTap: () => Navigator.pop(context, item),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF23252E)),
                        ),
                        child: Text(
                          itemLabel(item),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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

class _ModeSwitch extends StatelessWidget {
  final bool photoMode;
  final ValueChanged<bool> onChanged;

  const _ModeSwitch({
    required this.photoMode,
    required this.onChanged,
  });

  static const _orange = Color(0xFF9A5A00);
  static const _bg = Color(0xFF1B1E26);
  static const _border = Color(0xFF343846);
  static const _inactive = Color(0xFFC6CBD8);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                left: photoMode ? segmentWidth : 0,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: _ModeTab(
                      label: 'Text',
                      icon: CupertinoIcons.text_alignleft,
                      active: !photoMode,
                      inactiveColor: _inactive,
                      onTap: () => onChanged(false),
                    ),
                  ),
                  Expanded(
                    child: _ModeTab(
                      label: 'Photo',
                      icon: CupertinoIcons.camera_fill,
                      active: photoMode,
                      inactiveColor: _inactive,
                      onTap: () => onChanged(true),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      pressedOpacity: 0.88,
      onPressed: onTap,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.05, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: active
              ? Row(
            key: ValueKey('active_$label'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          )
              : Text(
            label,
            key: ValueKey('inactive_$label'),
            style: TextStyle(
              color: inactiveColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteModeToggle extends StatelessWidget {
  final bool isPhoto;
  final ValueChanged<bool> onChanged;

  const _QuoteModeToggle({
    required this.isPhoto,
    required this.onChanged,
  });

  static const _orange = Color(0xFFF59E0B);
  static const _bg = Color(0xFF101117);
  static const _border = Color(0xFF23252E);
  static const _inactive = Color(0xFFC6CBD8);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOutCubic,
                left: isPhoto ? segmentWidth : 0,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: _orange,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: _QuoteModeTab(
                      label: 'Text',
                      icon: CupertinoIcons.text_alignleft,
                      active: !isPhoto,
                      inactiveColor: _inactive,
                      onTap: () => onChanged(false),
                    ),
                  ),
                  Expanded(
                    child: _QuoteModeTab(
                      label: 'Photo',
                      icon: CupertinoIcons.camera,
                      active: isPhoto,
                      inactiveColor: _inactive,
                      onTap: () => onChanged(true),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuoteModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _QuoteModeTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(14),
      pressedOpacity: 0.9,
      onPressed: onTap,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: active
              ? Row(
            key: ValueKey('active_$label'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          )
              : Text(
            label,
            key: ValueKey('inactive_$label'),
            style: TextStyle(
              color: inactiveColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPickerBlock extends StatelessWidget {
  final List<XFile> photos;
  final int maxPhotos;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onClearAll;
  final void Function(int index) onRemoveAt;

  const _PhotoPickerBlock({
    required this.photos,
    required this.maxPhotos,
    required this.onCamera,
    required this.onGallery,
    required this.onClearAll,
    required this.onRemoveAt,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhotos = photos.isNotEmpty;
    final canAddMore = photos.length < maxPhotos;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF151B27), // светлее
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF343B4D),
          width: 1.1,
        ),
      ),
      child: Column(
        children: [
          if (!hasPhotos) ...[
            const Icon(
              CupertinoIcons.camera_fill,
              color: Color(0xFFF59E0B),
              size: 38,
            ),
            const SizedBox(height: 12),
            const Text(
              'Add job photos',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add 1–$maxPhotos clear photos showing the problem, damaged area, or items to be serviced.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8E93A6),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${photos.length}/$maxPhotos photos ready',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF1C1D24),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: onClearAll,
                  child: const Icon(
                    CupertinoIcons.trash,
                    color: Color(0xFFFF6B6B),
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (photos.length == 1)
              SizedBox(
                width: double.infinity,
                height: 260,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(photos.first.path),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: CupertinoButton(
                        padding: EdgeInsets.zero,
                        minSize: 34,
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                        onPressed: () => onRemoveAt(0),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.2,
                ),
                itemBuilder: (context, index) {
                  final photo = photos[index];

                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(photo.path),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 30,
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                          onPressed: () => onRemoveAt(index),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _PhotoActionButton(
                  icon: CupertinoIcons.camera_fill,
                  label: 'Camera',
                  enabled: canAddMore,
                  onTap: onCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PhotoActionButton(
                  icon: CupertinoIcons.photo_fill_on_rectangle_fill,
                  label: 'Gallery',
                  enabled: canAddMore,
                  onTap: onGallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PhotoActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(17),
      onPressed: enabled ? onTap : null,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFF252830) : const Color(0xFF1A1D24),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: enabled ? const Color(0xFF454A5A) : const Color(0xFF2E3140),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: enabled
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF6F7482),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: enabled
                    ? Colors.white
                    : const Color(0xFF6F7482),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoAiWarningBlock extends StatelessWidget {
  const _PhotoAiWarningBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101117),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFC857).withOpacity(0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFC857).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: Color(0xFFFFC857),
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Text(
              'Photo AI works best for visible problems like damage, leaks, broken items, junk, stains, or burned parts. For new installation, upgrades, moving items, or hidden issues, add a short instruction. Always review the suggested prompt before generating a quote.',
              style: TextStyle(
                color: Color(0xFFB6BCD0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickQuoteGlassHeader extends StatelessWidget {
  const _QuickQuoteGlassHeader();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF2F3036),
                Color(0xFF24252B),
              ],
            ),
            border: Border.all(
              color: Color(0xFF3A3B42),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              _QuickQuoteHeaderBackButton(
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Quick Quote',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Color(0xFFEDEFF6),
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                CupertinoIcons.bolt_fill,
                size: 27,
                color: Color(0xFFF59E0B),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickQuoteHeaderBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickQuoteHeaderBackButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF31363E),
                Color(0xFF232830),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white.withOpacity(0.82),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerSheetScaffold extends StatelessWidget {
  final String title;
  final IconData titleIcon;
  final String addLabel;
  final IconData addIcon;
  final VoidCallback onAddTap;
  final List<Widget> children;

  const _PickerSheetScaffold({
    required this.title,
    required this.titleIcon,
    required this.addLabel,
    required this.addIcon,
    required this.onAddTap,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.68,
      child: Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2B2F38),
              Color(0xFF1E2028),
            ],
          ),
          border: Border(
            top: BorderSide(color: Color(0xFF3A3F4B)),
            left: BorderSide(color: Color(0xFF2F3440)),
            right: BorderSide(color: Color(0xFF2F3440)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0x19F59E0B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0x33F59E0B),
                        ),
                      ),
                      child: Icon(
                        titleIcon,
                        color: const Color(0xFFF59E0B),
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 28,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                GestureDetector(
                  onTap: onAddTap,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171A22),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF303440),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          addIcon,
                          color: const Color(0xFFF59E0B),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          addLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Expanded(
                  child: children.isEmpty
                      ? const Center(
                    child: Text(
                      'No items found',
                      style: TextStyle(
                        color: Color(0xFFB7BCCB),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  )
                      : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: children.length,
                    itemBuilder: (context, index) {
                      return children[index];
                    },
                    separatorBuilder: (_, __) {
                      return const SizedBox(height: 10);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerItemTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PickerItemTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF2C313C),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFF3A3F4B),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFFF59E0B),
                size: 24,
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB7BCCB),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 10),

              const Icon(
                CupertinoIcons.chevron_right,
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

class _VoiceSheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isCancel;

  const _VoiceSheetButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isCancel = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A2D35),
              Color(0xFF22252D),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isCancel
                ? const Color(0xFFFF6B6B).withOpacity(0.25)
                : const Color(0xFF343846),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2E3140),
                ),
              ),
              child: Icon(
                icon,
                color: isCancel
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFFB7BCCB),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isCancel
                    ? const Color(0xFFFF6B6B)
                    : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Photo Detection Data Classes ────────────────────────────────────────────

class _PhotoAction {
  final String ruleId;
  final String label;
  final String actionType;
  bool isSelected;

  _PhotoAction({
    required this.ruleId,
    required this.label,
    required this.actionType,
    this.isSelected = false,
  });
}

class _PhotoDetection {
  final int imageIndex;
  final String objectLabel;
  final double confidence;
  final List<_PhotoAction> actions;
  final String warning;

  _PhotoDetection({
    required this.imageIndex,
    required this.objectLabel,
    required this.confidence,
    required this.actions,
    required this.warning,
  });
}

// ─── Photo Detection Selection View ──────────────────────────────────────────

class _PhotoDetectionSelectionView extends StatefulWidget {
  final List<_PhotoDetection> detections;
  final bool rushEnabled;
  final String rushPrice;
  final bool materialsEnabled;
  final ValueChanged<bool> onRushToggle;
  final ValueChanged<String> onRushPriceChanged;
  final ValueChanged<bool> onMaterialsToggle;
  final VoidCallback onRetake;
  final VoidCallback onGenerate;
  final bool isGenerating;
  final Map<int, String> materialPrices;
  final void Function(int index, String value) onMaterialPriceChanged;

  const _PhotoDetectionSelectionView({
    required this.detections,
    required this.rushEnabled,
    required this.rushPrice,
    required this.materialsEnabled,
    required this.onRushToggle,
    required this.onRushPriceChanged,
    required this.onMaterialsToggle,
    required this.onRetake,
    required this.onGenerate,
    required this.isGenerating,
    required this.materialPrices,
    required this.onMaterialPriceChanged,
  });

  @override
  State<_PhotoDetectionSelectionView> createState() =>
      _PhotoDetectionSelectionViewState();
}

class _PhotoDetectionSelectionViewState
    extends State<_PhotoDetectionSelectionView> {
  late final TextEditingController _rushPriceController;

  @override
  void initState() {
    super.initState();
    _rushPriceController = TextEditingController(text: widget.rushPrice);
  }

  @override
  void dispose() {
    _rushPriceController.dispose();
    super.dispose();
  }

  IconData _iconForAction(String actionType) {
    switch (actionType) {
      case 'inspect': return CupertinoIcons.search;
      case 'repair': return CupertinoIcons.wrench;
      case 'replace': return CupertinoIcons.arrow_2_circlepath;
      case 'install': return CupertinoIcons.plus_circle;
      case 'remove': return CupertinoIcons.minus_circle;
      default: return CupertinoIcons.settings;
    }
  }

  Color _colorForAction(String actionType) {
    switch (actionType) {
      case 'inspect': return const Color(0xFF5B9BD5);
      case 'repair': return const Color(0xFFF59E0B);
      case 'replace': return const Color(0xFFE07B39);
      case 'install': return const Color(0xFF4CAF77);
      case 'remove': return const Color(0xFFE05C5C);
      default: return const Color(0xFF8E93A6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            GestureDetector(
              onTap: widget.onRetake,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2028),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF343846)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.camera,
                        color: Color(0xFF8E93A6), size: 13),
                    SizedBox(width: 6),
                    Text('Retake',
                        style: TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Detection cards
        ...widget.detections.map((detection) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: StatefulBuilder(
            builder: (context, setCardState) => Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2D3A), Color(0xFF22252F)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF3A3F52), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF252830),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            WorkioIconMapper.resolveFromTitle(detection.objectLabel),
                            color: const Color(0xFFF59E0B),
                            size: 15,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          detection.objectLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Photo ${detection.imageIndex}',
                          style: const TextStyle(
                            color: Color(0xFF5A5F70),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFF2A2E3A)),
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1F2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E3140)),
                    ),
                    child: Row(
                      children: detection.actions.asMap().entries.map((entry) {
                        final i = entry.key;
                        final action = entry.value;
                        final color = _colorForAction(action.actionType);
                        final isSelected = action.isSelected;
                        const exclusive = {'install', 'repair', 'replace', 'remove'};
                        final hasOtherExclusive = exclusive.contains(action.actionType) &&
                            detection.actions.any((a) =>
                            a != action && a.isSelected && exclusive.contains(a.actionType));
                        final isDisabled = hasOtherExclusive;
                        final isLast = i == detection.actions.length - 1;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setCardState(() {
                              if (exclusive.contains(action.actionType) && !action.isSelected) {
                                for (final a in detection.actions) {
                                  if (a != action && exclusive.contains(a.actionType)) {
                                    a.isSelected = false;
                                  }
                                }
                              }
                              action.isSelected = !action.isSelected;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.horizontal(
                                  left: i == 0 ? const Radius.circular(14) : Radius.zero,
                                  right: isLast ? const Radius.circular(14) : Radius.zero,
                                ),
                                border: isLast
                                    ? null
                                    : const Border(
                                  right: BorderSide(color: Color(0xFF2E3140)),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Icon(
                                      isSelected
                                          ? CupertinoIcons.checkmark_circle_fill
                                          : _iconForAction(action.actionType),
                                      key: ValueKey(isSelected),
                                      color: isSelected
                                          ? color
                                          : isDisabled
                                          ? const Color(0xFF2A2E3A)
                                          : const Color(0xFF4A4F60),
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    action.label.split(' ').first,
                                    style: TextStyle(
                                      color: isSelected
                                          ? color
                                          : isDisabled
                                          ? const Color(0xFF2A2E3A)
                                          : const Color(0xFF6A6F80),
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (detection.warning.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Text(
                        '⚠ ${detection.warning}',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        )),

        const SizedBox(height: 4),

        // Rush toggle
        _PhotoOptionToggle(
          icon: CupertinoIcons.bolt_fill,
          iconColor: const Color(0xFFF59E0B),
          label: 'Rush Job',
          isEnabled: widget.rushEnabled,
          onToggle: widget.onRushToggle,
          child: widget.rushEnabled
              ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: CupertinoTextField(
              controller: _rushPriceController,
              placeholder: 'Visit rush fee (optional)',
              placeholderStyle: const TextStyle(
                  color: Color(0xFF5A5F70), fontSize: 13),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              keyboardType: TextInputType.number,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 12),
                child: Text('\$',
                    style: TextStyle(
                        color: Color(0xFF8E93A6), fontSize: 14)),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF252830),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF343846)),
              ),
              onChanged: widget.onRushPriceChanged,
            ),
          )
              : null,
        ),

        const SizedBox(height: 8),

        // Materials toggle
        _PhotoOptionToggle(
          icon: CupertinoIcons.cube_box_fill,
          iconColor: const Color(0xFF8B7CF6),
          label: 'Materials Included',
          isEnabled: widget.materialsEnabled,
          onToggle: widget.onMaterialsToggle,
          child: widget.materialsEnabled
              ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: widget.detections.asMap().entries.map((entry) {
                final index = entry.key;
                final detection = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${detection.objectLabel} parts',
                          style: const TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 100,
                        child: CupertinoTextField(
                          placeholder: '\$0',
                          placeholderStyle: const TextStyle(
                              color: Color(0xFF5A5F70), fontSize: 13),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF252830),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF343846)),
                          ),
                          onChanged: (val) =>
                              widget.onMaterialPriceChanged(index, val),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          )
              : null,
        ),

        const SizedBox(height: 16),

        // Generate Quote button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            color: const Color(0xFF9A5A00),
            borderRadius: BorderRadius.circular(18),
            onPressed: widget.isGenerating ? null : widget.onGenerate,
            child: widget.isGenerating
                ? const CupertinoActivityIndicator(color: Colors.white)
                : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.bolt_fill,
                    color: Colors.white, size: 17),
                SizedBox(width: 8),
                Text(
                  'Generate Quote',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Photo Option Toggle ──────────────────────────────────────────────────────

class _PhotoOptionToggle extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isEnabled;
  final ValueChanged<bool> onToggle;
  final Widget? child;

  const _PhotoOptionToggle({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isEnabled,
    required this.onToggle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2D3A), Color(0xFF22252F)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isEnabled
              ? iconColor.withOpacity(0.4)
              : const Color(0xFF3A3F52),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                CupertinoSwitch(
                  value: isEnabled,
                  onChanged: onToggle,
                  activeColor: iconColor,
                ),
              ],
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

// ─── Fading Warning Block ─────────────────────────────────────────────────────

class _FadingPhotoWarning extends StatefulWidget {
  const _FadingPhotoWarning();

  @override
  State<_FadingPhotoWarning> createState() => _FadingPhotoWarningState();
}

class _FadingPhotoWarningState extends State<_FadingPhotoWarning> {
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted) return;
      setState(() => _opacity = 0.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(seconds: 2),
      child: const _PhotoAiWarningBlock(),
    );
  }
}

// ─── Pulsing Sparkle Icon ─────────────────────────────────────────────────────

class _PulsingSparkleIcon extends StatefulWidget {
  const _PulsingSparkleIcon();

  @override
  State<_PulsingSparkleIcon> createState() => _PulsingSparkleIconState();
}

class _PulsingSparkleIconState extends State<_PulsingSparkleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween<double>(
    begin: 0.85,
    end: 1.2,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic));

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.6,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: const Icon(
          CupertinoIcons.sparkles,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}