import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/estimate_price_rule_model.dart';
import '../services/estimate_price_rules_service.dart';
import '../services/rule_ai_metadata_service.dart';

class PriceRulesScreen extends StatefulWidget {
  const PriceRulesScreen({super.key});

  @override
  State<PriceRulesScreen> createState() => _PriceRulesScreenState();
}

class _PriceRulesScreenState extends State<PriceRulesScreen> {
  bool _isLoading = true;
  bool _isResetting = false;
  List<EstimatePriceRuleModel> _rules = [];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final rules = await EstimatePriceRulesService.getRules();

      if (!mounted) return;

      setState(() {
        _rules = rules;
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
    final displayNameController = TextEditingController(
      text: rule.displayName ?? '',
    );
    final aliasesController = TextEditingController(
      text: rule.aliases.join(', '),
    );
    final aiKeywordsController = TextEditingController(
      text: rule.aiKeywords.join(', '),
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
    final singleCoatRateController = TextEditingController(
      text: rule.singleCoatRate?.toStringAsFixed(2) ?? '',
    );
    final multiCoatRateController = TextEditingController(
      text: rule.multiCoatRate?.toStringAsFixed(2) ?? '',
    );

    bool isAiMetadataExpanded = false;
    bool isGeneratingAi = false;

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
                        '${rule.serviceType} • ${rule.category}',
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
                const SizedBox(height: 18),
                _RuleTextField(
                  controller: displayNameController,
                  label: 'Display Name',
                  hintText: 'Plumbing',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: aliasesController,
                  label: 'Aliases (comma separated)',
                  hintText: 'plumbing, toilet, sink, faucet, drain',
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
                if (isAiMetadataExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
                    child: Column(
                      children: [
                        _RuleTextField(
                          controller: aiKeywordsController,
                          label: 'AI Keywords (comma separated)',
                          hintText: 'toilet leak, drain, faucet, pipe leak',
                          maxLines: 2,
                          inputFormatters: [
                            AliasesAutoCommaFormatter(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiScopeTemplateController,
                          label: 'AI Scope Template',
                          hintText: 'Complete the requested plumbing work...',
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
                          hintText: 'Plumbing Work',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiLaborDescriptionController,
                          label: 'AI Labor Description',
                          hintText: 'Labor for requested plumbing work',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiMaterialsTitleController,
                          label: 'AI Materials Title',
                          hintText: 'Plumbing Materials',
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
                          unit: rule.unit,
                          aliases: _parseAliases(aliasesController.text),
                        );

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
                _RuleField(
                  controller: baseRateController,
                  label: 'Base Rate',
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
                const SizedBox(height: 12),
                _RuleField(
                  controller: singleCoatRateController,
                  label: 'Single Coat Rate',
                ),
                const SizedBox(height: 12),
                _RuleField(
                  controller: multiCoatRateController,
                  label: 'Multi Coat Rate',
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
                          baseRate: _parseDouble(baseRateController.text) ?? 0,
                          materialRatePerSqft:
                          _parseNullableDouble(materialRatePerSqftController.text),
                          materialFixedRate:
                          _parseNullableDouble(materialFixedRateController.text),
                          prepFixedRate:
                          _parseNullableDouble(prepFixedRateController.text),
                          rushFixedRate:
                          _parseNullableDouble(rushFixedRateController.text),
                          singleCoatRate:
                          _parseNullableDouble(singleCoatRateController.text),
                          multiCoatRate:
                          _parseNullableDouble(multiCoatRateController.text),
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
      await _loadRules();
      _showSnack('Rule updated');
    } catch (e) {
      _showSnack('Не удалось обновить rule');
    }
  }

  Future<void> _addRule() async {
    final serviceTypeController = TextEditingController();
    final categoryController = TextEditingController(text: 'main');
    final unitController = TextEditingController(text: 'fixed');

    final displayNameController = TextEditingController();
    final aliasesController = TextEditingController();

    final aiKeywordsController = TextEditingController();
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
    final singleCoatRateController = TextEditingController();
    final multiCoatRateController = TextEditingController();
    bool isAiMetadataExpanded = false;
    bool isGeneratingAi = false;
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
                    const Expanded(
                      child: Text(
                        'Add Service Type',
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
                  hintText: 'plumbing',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: displayNameController,
                  label: 'Display Name',
                  hintText: 'Plumbing',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: aliasesController,
                  label: 'Aliases (comma separated)',
                  hintText: 'plumbing, toilet, sink, faucet, drain',
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
                if (isAiMetadataExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 12, 0, 0),
                    child: Column(
                      children: [
                        _RuleTextField(
                          controller: aiKeywordsController,
                          label: 'AI Keywords (comma separated)',
                          hintText: 'toilet leak, drain, faucet, pipe leak',
                          maxLines: 2,
                          inputFormatters: [
                            AliasesAutoCommaFormatter(),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiScopeTemplateController,
                          label: 'AI Scope Template',
                          hintText: 'Complete the requested plumbing work...',
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
                          hintText: 'Plumbing Work',
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiLaborDescriptionController,
                          label: 'AI Labor Description',
                          hintText: 'Labor for requested plumbing work',
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        _RuleTextField(
                          controller: aiMaterialsTitleController,
                          label: 'AI Materials Title',
                          hintText: 'Plumbing Materials',
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
                _RuleTextField(
                  controller: categoryController,
                  label: 'Category',
                  hintText: 'main',
                ),
                const SizedBox(height: 12),
                _RuleTextField(
                  controller: unitController,
                  label: 'Unit',
                  hintText: 'fixed',
                ),
                _RuleField(
                  controller: baseRateController,
                  label: 'Base Rate',
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
                const SizedBox(height: 12),
                _RuleField(
                  controller: singleCoatRateController,
                  label: 'Single Coat Rate',
                ),
                const SizedBox(height: 12),
                _RuleField(
                  controller: multiCoatRateController,
                  label: 'Multi Coat Rate',
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
                          singleCoatRate: _parseNullableDouble(
                            singleCoatRateController.text,
                          ),
                          multiCoatRate: _parseNullableDouble(
                            multiCoatRateController.text,
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
      await _loadRules();
      _showSnack('Rule created');
    } catch (e) {
      _showSnack('Failed to create rule');
    }
  }

  Future<void> _resetDefaults() async {
    setState(() {
      _isResetting = true;
    });

    try {
      await EstimatePriceRulesService.resetDefaults();
      await _loadRules();
      _showSnack('Default rules restored');
    } catch (e) {
      _showSnack('Не удалось сбросить rules');
    } finally {
      if (!mounted) return;

      setState(() {
        _isResetting = false;
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
              onPressed: _addRule,
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
              onPressed: _isResetting ? null : _resetDefaults,
              child: _isResetting
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Text(
                'Reset',
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
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        itemCount: _rules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final rule = _rules[index];

          return _PriceRuleTile(
            rule: rule,
            onTap: () => _editRule(rule),
            onDelete: () => _deleteRule(rule),
          );
        },
      ),
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
                              ? '${rule.displayName} • ${rule.category}'
                              : '${rule.serviceType} • ${rule.category}',
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
              _RuleLine(
                label: 'Single Coat',
                value: _formatValue(rule.singleCoatRate),
              ),
              _RuleLine(
                label: 'Multi Coat',
                value: _formatValue(rule.multiCoatRate),
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