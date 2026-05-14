import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/estimate_price_rule_model.dart';
import '../services/estimate_price_rules_service.dart';
import '../services/rule_ai_metadata_service.dart';

class _WorkioUnitOption {
  final String value;
  final String title;
  final String subtitle;

  const _WorkioUnitOption({
    required this.value,
    required this.title,
    required this.subtitle,
  });
}

const List<_WorkioUnitOption> _workioUnitOptions = [
  _WorkioUnitOption(
    value: 'fixed',
    title: 'Fixed',
    subtitle: 'Flat price / one job',
  ),
  _WorkioUnitOption(
    value: 'item',
    title: 'Item',
    subtitle: 'Per item / each',
  ),
  _WorkioUnitOption(
    value: 'hour',
    title: 'Hour',
    subtitle: 'Per hour',
  ),
  _WorkioUnitOption(
    value: 'day',
    title: 'Day',
    subtitle: 'Per day',
  ),
  _WorkioUnitOption(
    value: 'visit',
    title: 'Visit',
    subtitle: 'Per visit',
  ),
  _WorkioUnitOption(
    value: 'trip',
    title: 'Trip',
    subtitle: 'Service call / travel trip',
  ),
  _WorkioUnitOption(
    value: 'load',
    title: 'Load',
    subtitle: 'Truck load / junk load',
  ),
  _WorkioUnitOption(
    value: 'yard',
    title: 'Yard',
    subtitle: 'Cubic yard / volume',
  ),
  _WorkioUnitOption(
    value: 'bag',
    title: 'Bag',
    subtitle: 'Per bag',
  ),
  _WorkioUnitOption(
    value: 'sqft',
    title: 'Sqft',
    subtitle: 'Per square foot',
  ),
  _WorkioUnitOption(
    value: 'linear_ft',
    title: 'Linear ft',
    subtitle: 'Per linear foot',
  ),
  _WorkioUnitOption(
    value: 'room',
    title: 'Room',
    subtitle: 'Per room',
  ),
  _WorkioUnitOption(
    value: 'wall',
    title: 'Wall',
    subtitle: 'Per wall',
  ),
  _WorkioUnitOption(
    value: 'floor',
    title: 'Floor',
    subtitle: 'Per floor',
  ),
  _WorkioUnitOption(
    value: 'door',
    title: 'Door',
    subtitle: 'Per door',
  ),
  _WorkioUnitOption(
    value: 'window',
    title: 'Window',
    subtitle: 'Per window',
  ),
  _WorkioUnitOption(
    value: 'fixture',
    title: 'Fixture',
    subtitle: 'Per fixture',
  ),
  _WorkioUnitOption(
    value: 'outlet',
    title: 'Outlet',
    subtitle: 'Per outlet',
  ),
  _WorkioUnitOption(
    value: 'switch',
    title: 'Switch',
    subtitle: 'Per switch',
  ),
  _WorkioUnitOption(
    value: 'appliance',
    title: 'Appliance',
    subtitle: 'Per appliance',
  ),
  _WorkioUnitOption(
    value: 'ton',
    title: 'Ton',
    subtitle: 'Per ton',
  ),
  _WorkioUnitOption(
    value: 'lb',
    title: 'Lb',
    subtitle: 'Per pound',
  ),
];

_WorkioUnitOption? _unitOptionFor(String value) {
  final clean = value.trim().toLowerCase();

  for (final option in _workioUnitOptions) {
    if (option.value == clean) return option;
  }

  return null;
}

String _fallbackUnitTitle(String value) {
  final clean = value.trim().isEmpty ? 'fixed' : value.trim();

  return clean
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

class PriceRulesScreen extends StatefulWidget {
  const PriceRulesScreen({super.key});

  @override
  State<PriceRulesScreen> createState() => _PriceRulesScreenState();
}

class _PriceRulesScreenState extends State<PriceRulesScreen> {
  bool _isLoading = true;
  bool _isDeletingAll = false;
  List<EstimatePriceRuleModel> _rules = [];
  String? _expandedCategory;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      final value = _searchController.text.trim().toLowerCase();

      if (_searchQuery == value) return;

      setState(() {
        _searchQuery = value;
      });
    });

    _loadRules();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final rules = await EstimatePriceRulesService.getRules();

      if (!mounted) return;

      final availableCategories = rules
          .map((rule) => rule.category.trim().isEmpty
          ? 'main'
          : rule.category.trim().toLowerCase())
          .toSet()
          .toList();

      setState(() {
        _rules = rules;

        if (availableCategories.isEmpty) {
          _expandedCategory = null;
        } else if (_expandedCategory != null &&
            !availableCategories.contains(_expandedCategory)) {
          _expandedCategory = null;
        }

        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showSnack('Не удалось загрузить price rules');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickRuleUnit({
    required TextEditingController controller,
    required StateSetter setModalState,
  }) async {
    final currentUnit = controller.text.trim().isEmpty
        ? 'fixed'
        : controller.text.trim().toLowerCase();

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF15161C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return _RuleUnitPickerSheet(
          currentUnit: currentUnit,
        );
      },
    );

    if (selected == null) return;

    setModalState(() {
      controller.text = selected;
    });
  }

  Future<void> _deleteRule(EstimatePriceRuleModel rule) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Delete Rule'),
          content: Text(
            'Delete ${rule.displayName?.trim().isNotEmpty == true ? rule.displayName : rule.serviceType}?',
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
        );
      },
    );

    if (confirmed != true) return;

    try {
      await EstimatePriceRulesService.deleteRule(rule.id);
      await _loadRules();
      _showSnack('Rule deleted');
    } catch (e) {
      _showSnack('Failed to delete rule');
    }
  }

  Future<void> _editRule(EstimatePriceRuleModel rule) async {
    final baseRateController = TextEditingController(
      text: rule.baseRate.toStringAsFixed(2),
    );
    final unitController = TextEditingController(text: rule.unit);
    final displayNameController = TextEditingController(
      text: rule.displayName ?? '',
    );
    final aliasesController = TextEditingController(
      text: rule.aliases.join(', '),
    );
    final aiKeywordsController = TextEditingController(
      text: rule.aiKeywords.join(', '),
    );
    final negativeKeywordsController = TextEditingController(
      text: rule.negativeKeywords.join(', '),
    );
    final aiScopeTemplateController = TextEditingController(
      text: rule.aiScopeTemplate ?? '',
    );
    final aiNotesTemplateController = TextEditingController(
      text: rule.aiNotesTemplate ?? '',
    );
    final aiLaborTitleController = TextEditingController(
      text: rule.aiLaborTitle ?? '',
    );
    final aiLaborDescriptionController = TextEditingController(
      text: rule.aiLaborDescription ?? '',
    );
    final aiMaterialsTitleController = TextEditingController(
      text: rule.aiMaterialsTitle ?? '',
    );
    final aiMaterialsDescriptionController = TextEditingController(
      text: rule.aiMaterialsDescription ?? '',
    );
    final aiPrepTitleController = TextEditingController(
      text: rule.aiPrepTitle ?? '',
    );
    final aiPrepDescriptionController = TextEditingController(
      text: rule.aiPrepDescription ?? '',
    );
    final aiRushTitleController = TextEditingController(
      text: rule.aiRushTitle ?? '',
    );
    final aiRushDescriptionController = TextEditingController(
      text: rule.aiRushDescription ?? '',
    );
    final materialRatePerSqftController = TextEditingController(
      text: rule.materialRatePerSqft?.toStringAsFixed(2) ?? '',
    );
    final materialFixedRateController = TextEditingController(
      text: rule.materialFixedRate?.toStringAsFixed(2) ?? '',
    );
    final prepFixedRateController = TextEditingController(
      text: rule.prepFixedRate?.toStringAsFixed(2) ?? '',
    );
    final rushFixedRateController = TextEditingController(
      text: rule.rushFixedRate?.toStringAsFixed(2) ?? '',
    );
    final installFixedRateController = TextEditingController(
      text: rule.installFixedRate?.toStringAsFixed(2) ?? '',
    );
    final replaceFixedRateController = TextEditingController(
      text: rule.replaceFixedRate?.toStringAsFixed(2) ?? '',
    );
    final repairFixedRateController = TextEditingController(
      text: rule.repairFixedRate?.toStringAsFixed(2) ?? '',
    );
    final diagnosticFixedRateController = TextEditingController(
      text: rule.diagnosticFixedRate?.toStringAsFixed(2) ?? '',
    );

    bool isAiMetadataExpanded = false;
    bool isGeneratingAi = false;
    bool isAdvancedPricingExpanded = false;

    List<Map<String, dynamic>> generatedFollowupQuestions =
    List<Map<String, dynamic>>.from(rule.aiFollowupQuestions);

    final updatedRule = await showModalBottomSheet<EstimatePriceRuleModel>(
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
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Edit ${_formatCategoryTitle(rule.category)} Service',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 32,
                      onPressed: () => Navigator.pop(context),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    rule.displayName?.trim().isNotEmpty == true
                        ? rule.displayName!.trim()
                        : rule.serviceType,
                    style: const TextStyle(
                      color: Color(0xFF8E93A6),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _LockedCategoryInfo(
                  title: 'Category',
                  value: _formatCategoryTitle(rule.category),
                ),
                const SizedBox(height: 12),
                _RuleUnitPickerField(
                  controller: unitController,
                  label: 'Unit',
                  onTap: () => _pickRuleUnit(
                    controller: unitController,
                    setModalState: setModalState,
                  ),
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: displayNameController,
                  label: 'Display Name',
                  hintText: 'Service display name',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: aliasesController,
                  label: 'Aliases (comma separated)',
                  hintText: 'main name, short name, common client words',
                  maxLines: 2,
                  inputFormatters: [
                    AliasesAutoCommaFormatter(),
                  ],
                ),
                const SizedBox(height: 12),
                _CollapsibleSectionHeader(
                  title: 'AI Metadata',
                  subtitle: 'Optional • only for smarter AI output',
                  isExpanded: isAiMetadataExpanded,
                  onTap: () {
                    setModalState(() {
                      isAiMetadataExpanded = !isAiMetadataExpanded;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: negativeKeywordsController,
                  label: 'Negative Keywords (comma separated)',
                  hintText: 'words that should NOT match this service',
                  maxLines: 2,
                  inputFormatters: [
                    AliasesAutoCommaFormatter(),
                  ],
                ),
                if (isAiMetadataExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
                    child: Column(
                      children: [
                        _RuleTextField(
                          controller: aiKeywordsController,
                          label: 'AI Keywords (comma separated)',
                          hintText: 'common request, problem words, client phrases',
                          maxLines: 2,
                          inputFormatters: [
                            AliasesAutoCommaFormatter(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiScopeTemplateController,
                          label: 'AI Scope Template',
                          hintText: 'Complete the requested {service_label} work...',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiNotesTemplateController,
                          label: 'AI Notes Template',
                          hintText: 'Final price may change if hidden issues are found...',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiLaborTitleController,
                          label: 'AI Labor Title',
                          hintText: 'Main Service Work',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiLaborDescriptionController,
                          label: 'AI Labor Description',
                          hintText: 'Labor for the requested service',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiMaterialsTitleController,
                          label: 'AI Materials Title',
                          hintText: 'Service Materials',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiMaterialsDescriptionController,
                          label: 'AI Materials Description',
                          hintText: 'Materials and consumables',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiPrepTitleController,
                          label: 'AI Prep Title',
                          hintText: 'Prep Work',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiPrepDescriptionController,
                          label: 'AI Prep Description',
                          hintText: 'Preparation before main work begins',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiRushTitleController,
                          label: 'AI Rush Title',
                          hintText: 'Rush Service',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiRushDescriptionController,
                          label: 'AI Rush Description',
                          hintText: 'Priority scheduling and rush handling',
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: const Color(0xFF1E212B),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: isGeneratingAi
                        ? null
                        : () async {
                      final serviceType = rule.serviceType.trim();
                      if (serviceType.isEmpty) return;

                      setModalState(() {
                        isGeneratingAi = true;
                      });

                      try {
                        final result = await RuleAiMetadataService.generate(
                          serviceType: serviceType,
                          displayName: displayNameController.text.trim(),
                          category: rule.category,
                          unit: unitController.text.trim().isEmpty
                              ? rule.unit
                              : unitController.text.trim().toLowerCase(),
                          aliases: _parseAliases(aliasesController.text),
                        );

                        displayNameController.text =
                        result.suggestedDisplayName.trim().isEmpty
                            ? displayNameController.text.trim()
                            : result.suggestedDisplayName.trim();

                        aiKeywordsController.text = result.aiKeywords.join(', ');
                        negativeKeywordsController.text = result.negativeKeywords.join(', ');
                        aiScopeTemplateController.text = result.aiScopeTemplate;
                        aiNotesTemplateController.text = result.aiNotesTemplate;
                        aiLaborTitleController.text = result.aiLaborTitle;
                        aiLaborDescriptionController.text =
                            result.aiLaborDescription;
                        aiMaterialsTitleController.text = result.aiMaterialsTitle;
                        aiMaterialsDescriptionController.text =
                            result.aiMaterialsDescription;
                        aiPrepTitleController.text = result.aiPrepTitle;
                        aiPrepDescriptionController.text = result.aiPrepDescription;
                        aiRushTitleController.text = result.aiRushTitle;
                        aiRushDescriptionController.text = result.aiRushDescription;
                        generatedFollowupQuestions =
                        List<Map<String, dynamic>>.from(result.aiFollowupQuestions);

                        final mergedAliases = <String>{
                          ..._parseAliases(aliasesController.text),
                          ...result.aliases,
                        }.toList();

                        aliasesController.text = mergedAliases.join(', ');

                        _showSnack('AI metadata generated');
                      } catch (e) {
                        _showSnack('Failed to generate AI metadata: $e');
                        debugPrint('Failed to generate AI metadata: $e');
                      } finally {
                        setModalState(() {
                          isGeneratingAi = false;
                        });
                      }
                    },
                    child: isGeneratingAi
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                      'Generate AI Metadata',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _RuleField(
                  controller: baseRateController,
                  label: 'Base Rate',
                ),
                const SizedBox(height: 12),
                _CollapsibleSectionHeader(
                  title: 'Advanced Pricing',
                  subtitle: 'Optional • install / replace / repair / diagnostic',
                  isExpanded: isAdvancedPricingExpanded,
                  onTap: () {
                    setModalState(() {
                      isAdvancedPricingExpanded = !isAdvancedPricingExpanded;
                    });
                  },
                ),
                if (isAdvancedPricingExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
                    child: Column(
                      children: [
                        _RuleField(
                          controller: installFixedRateController,
                          label: 'Install Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: replaceFixedRateController,
                          label: 'Replace Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: repairFixedRateController,
                          label: 'Repair Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: diagnosticFixedRateController,
                          label: 'Diagnostic / Inspection Fee',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: materialRatePerSqftController,
                          label: 'Material Rate / Sqft',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: materialFixedRateController,
                          label: 'Material Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: prepFixedRateController,
                          label: 'Prep Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: rushFixedRateController,
                          label: 'Rush Fixed Rate',
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
                    onPressed: () {
                      Navigator.pop(
                        context,
                        rule.copyWith(
                          displayName: displayNameController.text.trim().isEmpty
                              ? null
                              : displayNameController.text.trim(),
                          aliases: _parseAliases(aliasesController.text),
                          aiKeywords: _parseAliases(aiKeywordsController.text),
                          negativeKeywords: _parseAliases(negativeKeywordsController.text),
                          aiScopeTemplate: aiScopeTemplateController.text.trim().isEmpty
                              ? null
                              : aiScopeTemplateController.text.trim(),
                          aiNotesTemplate: aiNotesTemplateController.text.trim().isEmpty
                              ? null
                              : aiNotesTemplateController.text.trim(),
                          aiLaborTitle: aiLaborTitleController.text.trim().isEmpty
                              ? null
                              : aiLaborTitleController.text.trim(),
                          aiLaborDescription: aiLaborDescriptionController.text.trim().isEmpty
                              ? null
                              : aiLaborDescriptionController.text.trim(),
                          aiMaterialsTitle: aiMaterialsTitleController.text.trim().isEmpty
                              ? null
                              : aiMaterialsTitleController.text.trim(),
                          aiMaterialsDescription: aiMaterialsDescriptionController.text.trim().isEmpty
                              ? null
                              : aiMaterialsDescriptionController.text.trim(),
                          aiPrepTitle: aiPrepTitleController.text.trim().isEmpty
                              ? null
                              : aiPrepTitleController.text.trim(),
                          aiPrepDescription: aiPrepDescriptionController.text.trim().isEmpty
                              ? null
                              : aiPrepDescriptionController.text.trim(),
                          aiRushTitle: aiRushTitleController.text.trim().isEmpty
                              ? null
                              : aiRushTitleController.text.trim(),
                          aiRushDescription: aiRushDescriptionController.text.trim().isEmpty
                              ? null
                              : aiRushDescriptionController.text.trim(),
                          unit: unitController.text.trim().isEmpty
                              ? rule.unit
                              : unitController.text.trim().toLowerCase(),
                          baseRate: _parseDouble(baseRateController.text) ?? 0,
                          installFixedRate:
                          _parseNullableDouble(installFixedRateController.text),
                          replaceFixedRate:
                          _parseNullableDouble(replaceFixedRateController.text),
                          repairFixedRate:
                          _parseNullableDouble(repairFixedRateController.text),
                          diagnosticFixedRate:
                          _parseNullableDouble(diagnosticFixedRateController.text),
                          materialRatePerSqft:
                          _parseNullableDouble(materialRatePerSqftController.text),
                          materialFixedRate:
                          _parseNullableDouble(materialFixedRateController.text),
                          prepFixedRate:
                          _parseNullableDouble(prepFixedRateController.text),
                          rushFixedRate:
                          _parseNullableDouble(rushFixedRateController.text),
                          aiFollowupQuestions: generatedFollowupQuestions,
                        ),
                      );
                    },
                    child: const Text(
                      'Save Rule',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

    if (updatedRule == null) return;

    try {
      await EstimatePriceRulesService.updateRule(updatedRule);
      await EstimatePriceRulesService.suggestAndSaveIcon(updatedRule);
      await _loadRules();
      _showSnack('Rule updated');
    } catch (e) {
      _showSnack('Не удалось обновить rule');
    }
  }

  Future<void> _addRule({String? initialCategory}) async {
    final serviceTypeController = TextEditingController();

    final lockedCategory = initialCategory?.trim().isNotEmpty == true
        ? initialCategory!.trim().toLowerCase()
        : null;

    final categoryController = TextEditingController(
      text: lockedCategory ?? '',
    );
    final unitController = TextEditingController(text: 'fixed');

    final displayNameController = TextEditingController();
    final aliasesController = TextEditingController();

    final aiKeywordsController = TextEditingController();
    final negativeKeywordsController = TextEditingController();
    final aiScopeTemplateController = TextEditingController();
    final aiNotesTemplateController = TextEditingController();
    final aiLaborTitleController = TextEditingController();
    final aiLaborDescriptionController = TextEditingController();
    final aiMaterialsTitleController = TextEditingController();
    final aiMaterialsDescriptionController = TextEditingController();
    final aiPrepTitleController = TextEditingController();
    final aiPrepDescriptionController = TextEditingController();
    final aiRushTitleController = TextEditingController();
    final aiRushDescriptionController = TextEditingController();

    final baseRateController = TextEditingController();
    final materialRatePerSqftController = TextEditingController();
    final materialFixedRateController = TextEditingController();
    final prepFixedRateController = TextEditingController();
    final rushFixedRateController = TextEditingController();
    final installFixedRateController = TextEditingController();
    final replaceFixedRateController = TextEditingController();
    final repairFixedRateController = TextEditingController();
    final diagnosticFixedRateController = TextEditingController();

    bool isAiMetadataExpanded = false;
    bool isGeneratingAi = false;
    bool isAdvancedPricingExpanded = false;

    List<Map<String, dynamic>> generatedFollowupQuestions = [];

    final newRule = await showModalBottomSheet<EstimatePriceRuleModel>(
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
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lockedCategory == null
                            ? 'Add Service Type'
                            : 'Add ${_formatCategoryTitle(lockedCategory)} Service',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minSize: 32,
                      onPressed: () => Navigator.pop(context),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: Color(0xFF8E93A6),
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _RuleTextField(
                  controller: serviceTypeController,
                  label: 'Service Type',
                  hintText: 'service_type',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: displayNameController,
                  label: 'Display Name',
                  hintText: 'Service display name',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: aliasesController,
                  label: 'Aliases (comma separated)',
                  hintText: 'main name, short name, common client words',
                  maxLines: 2,
                  inputFormatters: [
                    AliasesAutoCommaFormatter(),
                  ],
                ),
                const SizedBox(height: 12),
                _CollapsibleSectionHeader(
                  title: 'AI Metadata',
                  subtitle: 'Optional • only for smarter AI output',
                  isExpanded: isAiMetadataExpanded,
                  onTap: () {
                    setModalState(() {
                      isAiMetadataExpanded = !isAiMetadataExpanded;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: negativeKeywordsController,
                  label: 'Negative Keywords (comma separated)',
                  hintText: 'do not match: demolition, wall removal, furniture pickup',
                  maxLines: 2,
                  inputFormatters: [
                    AliasesAutoCommaFormatter(),
                  ],
                ),
                if (isAiMetadataExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
                    child: Column(
                      children: [
                        _RuleTextField(
                          controller: aiKeywordsController,
                          label: 'AI Keywords (comma separated)',
                          hintText: 'common request, problem words, client phrases',
                          maxLines: 2,
                          inputFormatters: [
                            AliasesAutoCommaFormatter(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiScopeTemplateController,
                          label: 'AI Scope Template',
                          hintText: 'Complete the requested {service_label} work...',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiNotesTemplateController,
                          label: 'AI Notes Template',
                          hintText: 'Final price may change if hidden issues are found...',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiLaborTitleController,
                          label: 'AI Labor Title',
                          hintText: 'Main Service Work',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiLaborDescriptionController,
                          label: 'AI Labor Description',
                          hintText: 'Labor for the requested service',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiMaterialsTitleController,
                          label: 'AI Materials Title',
                          hintText: 'Service Materials',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiMaterialsDescriptionController,
                          label: 'AI Materials Description',
                          hintText: 'Materials and consumables',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiPrepTitleController,
                          label: 'AI Prep Title',
                          hintText: 'Prep Work',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiPrepDescriptionController,
                          label: 'AI Prep Description',
                          hintText: 'Preparation before main work begins',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiRushTitleController,
                          label: 'AI Rush Title',
                          hintText: 'Rush Service',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiRushDescriptionController,
                          label: 'AI Rush Description',
                          hintText: 'Priority scheduling and rush handling',
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: const Color(0xFF1E212B),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: isGeneratingAi
                        ? null
                        : () async {
                      final serviceType = serviceTypeController.text.trim();
                      final category = categoryController.text.trim();
                      final unit = unitController.text.trim();

                      if (serviceType.isEmpty) return;

                      setModalState(() {
                        isGeneratingAi = true;
                      });

                      try {
                        final result = await RuleAiMetadataService.generate(
                          serviceType: serviceType,
                          displayName: displayNameController.text.trim(),
                          category: category,
                          unit: unit,
                          aliases: _parseAliases(aliasesController.text),
                        );

                        serviceTypeController.text =
                        result.normalizedServiceType.trim().isEmpty
                            ? serviceTypeController.text.trim().toLowerCase()
                            : result.normalizedServiceType.trim().toLowerCase();

                        displayNameController.text =
                        result.suggestedDisplayName.trim().isEmpty
                            ? displayNameController.text.trim()
                            : result.suggestedDisplayName.trim();

                        aiKeywordsController.text = result.aiKeywords.join(', ');
                        aiScopeTemplateController.text = result.aiScopeTemplate;
                        aiNotesTemplateController.text = result.aiNotesTemplate;
                        aiLaborTitleController.text = result.aiLaborTitle;
                        aiLaborDescriptionController.text =
                            result.aiLaborDescription;
                        aiMaterialsTitleController.text = result.aiMaterialsTitle;
                        aiMaterialsDescriptionController.text =
                            result.aiMaterialsDescription;
                        aiPrepTitleController.text = result.aiPrepTitle;
                        aiPrepDescriptionController.text = result.aiPrepDescription;
                        aiRushTitleController.text = result.aiRushTitle;
                        aiRushDescriptionController.text = result.aiRushDescription;
                        generatedFollowupQuestions =
                        List<Map<String, dynamic>>.from(result.aiFollowupQuestions);

                        final mergedAliases = <String>{
                          ..._parseAliases(aliasesController.text),
                          ...result.aliases,
                        }.toList();

                        aliasesController.text = mergedAliases.join(', ');

                        _showSnack('AI metadata generated');
                      } catch (e) {
                        _showSnack('Failed to generate AI metadata: $e');
                        debugPrint('Failed to generate AI metadata: $e');
                      } finally {
                        setModalState(() {
                          isGeneratingAi = false;
                        });
                      }
                    },
                    child: isGeneratingAi
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text(
                      'Generate AI Metadata',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (lockedCategory == null) ...[
                  _RuleTextField(
                    controller: categoryController,
                    label: 'Category',
                    hintText: 'plumbing, electrical, roofing',
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  _LockedCategoryInfo(
                    title: 'Category',
                    value: _formatCategoryTitle(lockedCategory),
                  ),
                  const SizedBox(height: 12),
                ],
                _RuleUnitPickerField(
                  controller: unitController,
                  label: 'Unit',
                  onTap: () => _pickRuleUnit(
                    controller: unitController,
                    setModalState: setModalState,
                  ),
                ),
                const SizedBox(height: 12),
                _RuleField(
                  controller: baseRateController,
                  label: 'Base Rate',
                ),
                const SizedBox(height: 12),
                _CollapsibleSectionHeader(
                  title: 'Advanced Pricing',
                  subtitle: 'Optional • install / replace / repair / diagnostic',
                  isExpanded: isAdvancedPricingExpanded,
                  onTap: () {
                    setModalState(() {
                      isAdvancedPricingExpanded = !isAdvancedPricingExpanded;
                    });
                  },
                ),
                if (isAdvancedPricingExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
                    child: Column(
                      children: [
                        _RuleField(
                          controller: installFixedRateController,
                          label: 'Install Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: replaceFixedRateController,
                          label: 'Replace Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: repairFixedRateController,
                          label: 'Repair Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: diagnosticFixedRateController,
                          label: 'Diagnostic / Inspection Fee',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: materialRatePerSqftController,
                          label: 'Material Rate / Sqft',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: materialFixedRateController,
                          label: 'Material Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: prepFixedRateController,
                          label: 'Prep Fixed Rate',
                        ),
                        const SizedBox(height: 12),
                        _RuleField(
                          controller: rushFixedRateController,
                          label: 'Rush Fixed Rate',
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
                    onPressed: () {
                      final serviceType = serviceTypeController.text.trim();
                      final category = categoryController.text.trim();
                      final unit = unitController.text.trim();
                      final baseRate = _parseDouble(baseRateController.text);

                      if (serviceType.isEmpty ||
                          category.isEmpty ||
                          unit.isEmpty ||
                          baseRate == null) {
                        return;
                      }

                      Navigator.pop(
                        context,
                        EstimatePriceRuleModel(
                          id: _buildRuleId(
                            serviceType: serviceType,
                            category: category,
                          ),
                          aiFollowupQuestions: generatedFollowupQuestions,
                          negativeKeywords: _parseAliases(negativeKeywordsController.text),
                          serviceType: serviceType.toLowerCase(),
                          category: category.toLowerCase(),
                          unit: unit.toLowerCase(),
                          displayName: displayNameController.text.trim().isEmpty
                              ? null
                              : displayNameController.text.trim(),
                          aliases: _parseAliases(aliasesController.text),
                          aiKeywords: _parseAliases(aiKeywordsController.text),
                          aiScopeTemplate: aiScopeTemplateController.text.trim().isEmpty
                              ? null
                              : aiScopeTemplateController.text.trim(),
                          aiNotesTemplate: aiNotesTemplateController.text.trim().isEmpty
                              ? null
                              : aiNotesTemplateController.text.trim(),
                          aiLaborTitle: aiLaborTitleController.text.trim().isEmpty
                              ? null
                              : aiLaborTitleController.text.trim(),
                          aiLaborDescription: aiLaborDescriptionController.text.trim().isEmpty
                              ? null
                              : aiLaborDescriptionController.text.trim(),
                          aiMaterialsTitle: aiMaterialsTitleController.text.trim().isEmpty
                              ? null
                              : aiMaterialsTitleController.text.trim(),
                          aiMaterialsDescription: aiMaterialsDescriptionController.text.trim().isEmpty
                              ? null
                              : aiMaterialsDescriptionController.text.trim(),
                          aiPrepTitle: aiPrepTitleController.text.trim().isEmpty
                              ? null
                              : aiPrepTitleController.text.trim(),
                          aiPrepDescription: aiPrepDescriptionController.text.trim().isEmpty
                              ? null
                              : aiPrepDescriptionController.text.trim(),
                          aiRushTitle: aiRushTitleController.text.trim().isEmpty
                              ? null
                              : aiRushTitleController.text.trim(),
                          aiRushDescription: aiRushDescriptionController.text.trim().isEmpty
                              ? null
                              : aiRushDescriptionController.text.trim(),
                          baseRate: baseRate,
                          installFixedRate: _parseNullableDouble(
                            installFixedRateController.text,
                          ),
                          replaceFixedRate: _parseNullableDouble(
                            replaceFixedRateController.text,
                          ),
                          repairFixedRate: _parseNullableDouble(
                            repairFixedRateController.text,
                          ),
                          diagnosticFixedRate: _parseNullableDouble(
                            diagnosticFixedRateController.text,
                          ),
                          materialRatePerSqft: _parseNullableDouble(
                            materialRatePerSqftController.text,
                          ),
                          materialFixedRate: _parseNullableDouble(
                            materialFixedRateController.text,
                          ),
                          prepFixedRate: _parseNullableDouble(
                            prepFixedRateController.text,
                          ),
                          rushFixedRate: _parseNullableDouble(
                            rushFixedRateController.text,
                          ),
                          isActive: true,
                        ),
                      );
                    },
                    child: const Text(
                      'Create Rule',
                      style: TextStyle(fontWeight: FontWeight.w700),
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

    if (newRule == null) return;

    try {
      await EstimatePriceRulesService.createRule(newRule);
      await EstimatePriceRulesService.suggestAndSaveIcon(newRule);
      await _loadRules();
      _showSnack('Rule created');
    } catch (e) {
      _showSnack('Failed to create rule');
    }
  }

  Future<void> _deleteAllRules() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Delete All Rules'),
          content: const Text(
            'This will remove all your Price Rules. AI Estimate will not generate prices until you add rules again.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isDeletingAll = true;
    });

    try {
      await EstimatePriceRulesService.deleteAllRules();
      await _loadRules();
      _showSnack('All rules deleted');
    } catch (e) {
      _showSnack('Failed to delete all rules');
    } finally {
      if (!mounted) return;

      setState(() {
        _isDeletingAll = false;
      });
    }
  }

  double? _parseDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  double? _parseNullableDouble(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    return _parseDouble(normalized);
  }

  List<String> _parseAliases(String value) {
    return value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _buildRuleId({
    required String serviceType,
    required String category,
  }) {
    final normalizedServiceType = serviceType
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    final normalizedCategory = category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    return '${normalizedServiceType}_$normalizedCategory';
  }

  Map<String, List<EstimatePriceRuleModel>> get _rulesByCategory {
    final map = <String, List<EstimatePriceRuleModel>>{};

    for (final rule in _rules) {
      final category = rule.category.trim().isEmpty
          ? 'main'
          : rule.category.trim().toLowerCase();

      map.putIfAbsent(category, () => []);
      map[category]!.add(rule);
    }

    for (final entry in map.entries) {
      entry.value.sort((a, b) {
        final aName = (a.displayName?.trim().isNotEmpty == true)
            ? a.displayName!.trim()
            : a.serviceType.trim();
        final bName = (b.displayName?.trim().isNotEmpty == true)
            ? b.displayName!.trim()
            : b.serviceType.trim();

        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
    }

    return map;
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  bool _matchesSearch(EstimatePriceRuleModel rule) {
    final query = _searchQuery.trim().toLowerCase().replaceAll('_', ' ');
    if (query.isEmpty) return true;

    final searchableText = [
      rule.displayName ?? '',
      rule.serviceType,
      rule.category,
      rule.unit,
      ...rule.aliases,
      ...rule.aiKeywords,
      ...rule.negativeKeywords,
    ].join(' ').toLowerCase().replaceAll('_', ' ');

    return searchableText.contains(query);
  }

  Map<String, List<EstimatePriceRuleModel>> get _visibleRulesByCategory {
    final source = _rulesByCategory;

    if (!_isSearching) return source;

    final filtered = <String, List<EstimatePriceRuleModel>>{};

    for (final entry in source.entries) {
      final matches = entry.value.where(_matchesSearch).toList();

      if (matches.isNotEmpty) {
        filtered[entry.key] = matches;
      }
    }

    return filtered;
  }

  String _formatCategoryTitle(String value) {
    final clean = value.trim().isEmpty ? 'all_services' : value.trim();

    if (clean.toLowerCase() == 'main') {
      return 'All Services';
    }

    return clean
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
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
        centerTitle: false,
        titleSpacing: 20,
        title: const Text(
          'Price Rules',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF1E212B),
              borderRadius: BorderRadius.circular(14),
              onPressed: () => _addRule(),
              child: const Text(
                'Add',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF5B8CFF),
              borderRadius: BorderRadius.circular(14),
              onPressed: _isDeletingAll ? null : _deleteAllRules,
              child: _isDeletingAll
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Delete All',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: CupertinoActivityIndicator(radius: 16),
      )
          : _rules.isEmpty
          ? _EmptyPriceRulesState(onAdd: () => _addRule())
          : Builder(
        builder: (context) {
      final visibleRulesByCategory = _visibleRulesByCategory;

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _PriceRulesSearchField(
            controller: _searchController,
            onClear: () => _searchController.clear(),
          ),
          const SizedBox(height: 14),

          if (visibleRulesByCategory.isEmpty)
            const _NoSearchResultsState()
          else
            ...visibleRulesByCategory.entries.map((entry) {
              final category = entry.key;
              final rules = entry.value;
              final isExpanded = _isSearching || _expandedCategory == category;

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _PriceRuleCategoryCard(
                  title: _formatCategoryTitle(category),
                  subtitle:
                  '${rules.length} service${rules.length == 1 ? '' : 's'}',
                  onAdd: () => _addRule(initialCategory: category),
                  isExpanded: isExpanded,
                  onToggle: () {
                    if (_isSearching) return;

                    setState(() {
                      _expandedCategory = isExpanded ? null : category;
                    });
                  },
                  children: rules.map((rule) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _PriceRuleTile(
                        rule: rule,
                        onTap: () => _editRule(rule),
                        onDelete: () => _deleteRule(rule),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
        ],
      );
    },
    )
    );
  }
}

class _PriceRuleTile extends StatelessWidget {
  final EstimatePriceRuleModel rule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PriceRuleTile({
    required this.rule,
    required this.onTap,
    required this.onDelete,
  });

  String _formatValue(double? value) {
    if (value == null) return '—';
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF101117),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF23252E)),
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
                          rule.displayName?.trim().isNotEmpty == true
                              ? rule.displayName!
                              : rule.serviceType
                              .split(RegExp(r'[_\s-]+'))
                              .where((part) => part.isNotEmpty)
                              .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
                              .join(' '),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Type: ${rule.serviceType} • Unit: ${rule.unit}',
                          style: const TextStyle(
                            color: Color(0xFF8E93A6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171922),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2D37)),
                      ),
                      child: const Icon(
                        CupertinoIcons.trash,
                        color: Color(0xFFFF7B7B),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
              if (rule.aliases.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Aliases: ${rule.aliases.join(', ')}',
                  style: const TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _RuleLine(label: 'Base Rate', value: _formatValue(rule.baseRate)),
              _RuleLine(
                label: 'Material / Sqft',
                value: _formatValue(rule.materialRatePerSqft),
              ),
              _RuleLine(
                label: 'Material Fixed',
                value: _formatValue(rule.materialFixedRate),
              ),
              _RuleLine(
                label: 'Prep Fixed',
                value: _formatValue(rule.prepFixedRate),
              ),
              _RuleLine(
                label: 'Rush Fixed',
                value: _formatValue(rule.rushFixedRate),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  final String label;
  final String value;

  const _RuleLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
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
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}



class _RuleField extends StatefulWidget {
  final TextEditingController controller;
  final String label;

  const _RuleField({
    required this.controller,
    required this.label,
  });

  @override
  State<_RuleField> createState() => _RuleFieldState();
}

class _RuleFieldState extends State<_RuleField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
      _focusNode.hasFocus && widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _RuleField oldWidget) {
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
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: const Color(0xFF5B8CFF),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '0.00',
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

class _RuleTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  const _RuleTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.maxLines = 1,
    this.inputFormatters,
  });

  @override
  State<_RuleTextField> createState() => _RuleTextFieldState();
}

class _RuleTextFieldState extends State<_RuleTextField> {
  late final FocusNode _focusNode;

  bool get _showClearButton =>
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
  void didUpdateWidget(covariant _RuleTextField oldWidget) {
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
                    keyboardType: TextInputType.text,
                    maxLines: widget.maxLines,
                    minLines: isSingleLine ? 1 : widget.maxLines,
                    inputFormatters: widget.inputFormatters,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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

class AliasesAutoCommaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    var text = newValue.text;

    // Разрешаем разделять элементы только запятой / новой строкой / ;
    text = text.replaceAll('\n', ', ');
    text = text.replaceAll(';', ', ');

    // Нормализуем пробелы вокруг запятых
    text = text.replaceAll(RegExp(r'\s*,\s*'), ', ');

    // Убираем повторные запятые
    text = text.replaceAll(RegExp(r'(,\s*){2,}'), ', ');

    // Схлопываем лишние пробелы, НО не режем фразы по словам
    text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');

    // Чистим запятые в начале
    text = text.replaceAll(RegExp(r'^(,\s*)+'), '');

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CollapsibleSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool isExpanded;
  final VoidCallback onTap;

  const _CollapsibleSectionHeader({
    required this.title,
    required this.isExpanded,
    required this.onTap,
    this.subtitle,
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
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF23252E)),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Color(0xFF8E93A6),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                isExpanded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                color: const Color(0xFF8E93A6),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceRuleCategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onAdd;
  final VoidCallback onToggle;
  final bool isExpanded;
  final List<Widget> children;

  const _PriceRuleCategoryCard({
    required this.title,
    required this.subtitle,
    required this.onAdd,
    required this.onToggle,
    required this.isExpanded,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: onToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B8CFF).withOpacity(0.14),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: const Color(0xFF5B8CFF).withOpacity(0.22),
                              ),
                            ),
                            child: const Icon(
                              CupertinoIcons.square_grid_2x2_fill,
                              color: Color(0xFF8FB0FF),
                              size: 20,
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
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFF8E93A6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isExpanded
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            color: const Color(0xFF8E93A6),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: const Color(0xFF1E212B),
                borderRadius: BorderRadius.circular(14),
                onPressed: onAdd,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.add,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 14),
            ...children,
          ],
        ],
      ),
    );
  }
}

class _EmptyPriceRulesState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyPriceRulesState({
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF15161C),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF262832)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFF5B8CFF).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF5B8CFF).withOpacity(0.22),
                  ),
                ),
                child: const Icon(
                  CupertinoIcons.money_dollar_circle_fill,
                  color: Color(0xFF8FB0FF),
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'No Price Rules Yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create service-specific rules so Workio can price estimates accurately.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8E93A6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: const Color(0xFF5B8CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: onAdd,
                  child: const Text(
                    'Add First Rule',
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

class _LockedCategoryInfo extends StatelessWidget {
  final String title;
  final String value;

  const _LockedCategoryInfo({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
            title,
            style: const TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRulesSearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClear;

  const _PriceRulesSearchField({
    required this.controller,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.search,
              color: Color(0xFF8E93A6),
              size: 19,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: const Color(0xFF5B8CFF),
                decoration: const InputDecoration(
                  hintText: 'Search services, aliases, keywords...',
                  hintStyle: TextStyle(
                    color: Color(0xFF697086),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) {
                if (value.text.trim().isEmpty) {
                  return const SizedBox.shrink();
                }

                return GestureDetector(
                  onTap: onClear,
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: Color(0xFF8E93A6),
                    size: 20,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResultsState extends StatelessWidget {
  const _NoSearchResultsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15161C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF262832)),
      ),
      child: const Column(
        children: [
          Icon(
            CupertinoIcons.search,
            color: Color(0xFF8E93A6),
            size: 28,
          ),
          SizedBox(height: 10),
          Text(
            'No services found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Try another service name, alias, or keyword.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF8E93A6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleUnitPickerField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onTap;

  const _RuleUnitPickerField({
    required this.controller,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final unit = value.text.trim().isEmpty
            ? 'fixed'
            : value.text.trim().toLowerCase();

        final option = _unitOptionFor(unit);

        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
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
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option?.title ?? _fallbackUnitTitle(unit),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            option?.subtitle ?? 'Custom unit',
                            style: const TextStyle(
                              color: Color(0xFF8E93A6),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      CupertinoIcons.chevron_down,
                      color: Color(0xFF8E93A6),
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RuleUnitPickerSheet extends StatelessWidget {
  final String currentUnit;

  const _RuleUnitPickerSheet({
    required this.currentUnit,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            children: [
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3D49),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose Unit',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Most popular units are listed first.',
                  style: TextStyle(
                    color: Color(0xFF8E93A6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: _workioUnitOptions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final option = _workioUnitOptions[index];
                    final selected = option.value == currentUnit;

                    return GestureDetector(
                      onTap: () => Navigator.pop(context, option.value),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF1E2A4A)
                              : const Color(0xFF101117),
                          borderRadius: BorderRadius.circular(18),
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
                                    option.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    option.subtitle,
                                    style: const TextStyle(
                                      color: Color(0xFF8E93A6),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selected)
                              const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                color: Color(0xFF5B8CFF),
                                size: 22,
                              ),
                          ],
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