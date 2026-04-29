import 'package:flutter/foundation.dart';

class DeterministicKbMatcher {

  /// Returns the KB entry ID that should win for this query,
  /// or null if no deterministic match is found.
  String? match(String rawQuery) {
    final q = _normalize(rawQuery);

    // Check each rule in priority order
    for (final rule in _rules) {
      if (rule.matches(q)) {
        debugPrint('[DKM] Deterministic match: ${rule.targetId} '
                   'via rule "${rule.name}"');
        return rule.targetId;
      }
    }
    return null;
  }

  String _normalize(String text) => text
    .toLowerCase()
    .replaceAll('-', ' ')
    .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

  static final List<_KbRule> _rules = [

    // ── PRE-EMI (must come BEFORE EMI rule) ──────────────────
    _KbRule(
      name: 'pre_emi_explicit',
      targetId: 'hl_06',
      requiredTerms: ['pre'],
      anyOf: ['emi', 'pemi', 'pre emi'],
    ),
    _KbRule(
      name: 'pemi_acronym',
      targetId: 'hl_06',
      requiredTerms: ['pemi'],
      anyOf: [],
    ),
    _KbRule(
      name: 'partial_disbursement',
      targetId: 'hl_06',
      requiredTerms: ['partial'],
      anyOf: ['disbursement', 'interest only'],
    ),

    // ── EMI (only if no "pre" prefix) ────────────────────────
    _KbRule(
      name: 'emi_definition',
      targetId: 'hl_05',
      requiredTerms: ['emi'],
      anyOf: [],
      blockedTerms: ['pre', 'pemi'],  // must NOT contain these
    ),
    _KbRule(
      name: 'equated_monthly',
      targetId: 'hl_05',
      requiredTerms: ['equated monthly'],
      anyOf: [],
    ),

    // ── LTV ──────────────────────────────────────────────────
    _KbRule(
      name: 'ltv_definition',
      targetId: 'hl_09',
      requiredTerms: [],
      anyOf: ['ltv', 'loan to value', 'loan-to-value'],
    ),

    // ── AMORTIZATION ─────────────────────────────────────────
    _KbRule(
      name: 'amortization',
      targetId: 'hl_10',
      requiredTerms: [],
      anyOf: ['amortization', 'amortisation', 'amortization schedule',
               'repayment schedule'],
    ),

    // ── TAX BENEFIT ──────────────────────────────────────────
    _KbRule(
      name: 'tax_benefit',
      targetId: 'hl_11',
      requiredTerms: [],
      anyOf: ['tax benefit', 'tax rebate', 'income tax', '80c',
               'section 80', 'tax deduction', 'tax saving'],
    ),

    // ── WHO CAN AVAIL — must disambiguate by loan type ───────
    _KbRule(
      name: 'who_avail_working_capital',
      targetId: 'wcl_02',
      requiredTerms: ['working capital'],
      anyOf: ['who', 'eligible', 'avail', 'can'],
    ),
    _KbRule(
      name: 'who_avail_unsecured',
      targetId: 'ubl_01',
      requiredTerms: ['unsecured'],
      anyOf: ['who', 'eligible', 'avail', 'can'],
    ),
    _KbRule(
      name: 'who_avail_home_loan',
      targetId: 'hl_03',
      requiredTerms: ['home loan'],
      anyOf: ['who', 'eligible', 'avail', 'can', 'qualify'],
    ),

    // ── HOME LOAN PURPOSE vs LAP PURPOSE ─────────────────────
    _KbRule(
      name: 'lap_purpose',
      targetId: 'lap_03',
      requiredTerms: ['loan against property'],
      anyOf: ['purpose', 'avail', 'for what', 'uses'],
    ),
    _KbRule(
      name: 'lap_purpose_acronym',
      targetId: 'lap_03',
      requiredTerms: ['lap'],
      anyOf: ['purpose', 'avail', 'for what', 'uses'],
    ),
    _KbRule(
      name: 'home_loan_purpose',
      targetId: 'hl_01',
      requiredTerms: ['home loan'],
      anyOf: ['purpose', 'avail', 'for what', 'uses'],
    ),

    // ── HOME LOAN vs LAP DIFFERENCE ──────────────────────────
    _KbRule(
      name: 'home_vs_lap_diff',
      targetId: 'lap_01',
      requiredTerms: [],
      anyOf: ['difference home loan lap', 'home loan vs lap',
               'lap vs home loan'],
    ),

    // ── LAP vs TOP-UP ─────────────────────────────────────────
    _KbRule(
      name: 'lap_vs_topup',
      targetId: 'lap_04',
      requiredTerms: [],
      anyOf: ['top up', 'top-up', 'topup'],
    ),

    // ── TERM LOAN vs WORKING CAPITAL ─────────────────────────
    _KbRule(
      name: 'term_vs_wcl',
      targetId: 'wcl_04',
      requiredTerms: [],
      anyOf: ['term loan vs', 'difference term loan',
               'term loan working capital'],
    ),

    // ── DISBURSEMENT TIME — disambiguate by loan type ─────────
    _KbRule(
      name: 'disbursement_unsecured',
      targetId: 'ubl_11',
      requiredTerms: ['unsecured'],
      anyOf: ['time', 'days', 'how long', 'disbursement'],
    ),
    _KbRule(
      name: 'disbursement_working_capital',
      targetId: 'wcl_11',
      requiredTerms: ['working capital'],
      anyOf: ['time', 'days', 'how long', 'disbursement'],
    ),
    _KbRule(
      name: 'disbursement_home_loan',
      targetId: 'hl_08',
      requiredTerms: ['home loan'],
      anyOf: ['sanction', 'disbursement', 'disburse', 'time'],
    ),

    // ── INTEREST RATE — disambiguate by loan type ─────────────
    _KbRule(
      name: 'interest_unsecured',
      targetId: 'ubl_07',
      requiredTerms: ['unsecured'],
      anyOf: ['interest', 'rate', 'percent'],
    ),
    _KbRule(
      name: 'interest_working_capital',
      targetId: 'wcl_07',
      requiredTerms: ['working capital'],
      anyOf: ['interest', 'rate', 'percent'],
    ),

    // ── DOCUMENTS — disambiguate by loan type ─────────────────
    _KbRule(
      name: 'documents_unsecured',
      targetId: 'ubl_10',
      requiredTerms: ['unsecured'],
      anyOf: ['document', 'documents', 'required', 'kyc'],
    ),
    _KbRule(
      name: 'documents_working_capital',
      targetId: 'wcl_10',
      requiredTerms: ['working capital'],
      anyOf: ['document', 'documents', 'required', 'kyc'],
    ),

    // ── TENURE — disambiguate by loan type ───────────────────
    _KbRule(
      name: 'tenure_unsecured',
      targetId: 'ubl_06',
      requiredTerms: ['unsecured'],
      anyOf: ['tenure', 'period', 'duration', 'months', 'years'],
    ),
    _KbRule(
      name: 'tenure_home_loan',
      targetId: 'hl_07',
      requiredTerms: ['home loan'],
      anyOf: ['tenure', 'emi tenure', 'affect'],
    ),

    // ── NRI ───────────────────────────────────────────────────
    _KbRule(
      name: 'nri_lap',
      targetId: 'lap_06',
      requiredTerms: ['nri'],
      anyOf: ['lap', 'loan against property', 'property'],
    ),

    // ── JOINTLY OWNED ─────────────────────────────────────────
    _KbRule(
      name: 'jointly_owned',
      targetId: 'lap_07',
      requiredTerms: [],
      anyOf: ['jointly owned', 'joint property', 'co owned',
               'co-owned property'],
    ),

    // ── STARTUP LOAN ─────────────────────────────────────────
    _KbRule(
      name: 'startup_loan',
      targetId: 'ubl_05',
      requiredTerms: [],
      anyOf: ['startup', 'start-up', 'start up', 'new business',
               'new company'],
    ),

    // ── INSURANCE / PROPERTY ─────────────────────────────────
    _KbRule(
      name: 'property_insurance',
      targetId: 'lap_08',
      requiredTerms: [],
      anyOf: ['insurance', 'insure', 'mandatory insurance',
               'property insurance'],
    ),

    // ── CO-APPLICANT ─────────────────────────────────────────
    _KbRule(
      name: 'co_applicant',
      targetId: 'hl_02',
      requiredTerms: [],
      anyOf: ['co-applicant', 'co applicant', 'coapplicant',
               'joint applicant'],
    ),

    // ── COLLATERAL / SECURITY ────────────────────────────────
    _KbRule(
      name: 'no_collateral',
      targetId: 'ubl_04',
      requiredTerms: ['unsecured'],
      anyOf: ['collateral', 'security', 'guarantee'],
    ),
  ];
}

class _KbRule {
  final String name;
  final String targetId;
  final List<String> requiredTerms;  // ALL must be present
  final List<String> anyOf;           // at least ONE must be present (if non-empty)
  final List<String> blockedTerms;    // NONE must be present

  const _KbRule({
    required this.name,
    required this.targetId,
    required this.requiredTerms,
    required this.anyOf,
    this.blockedTerms = const [],
  });

  bool matches(String normalizedQuery) {
    // Check blocked terms first — if any present, this rule fails
    for (final blocked in blockedTerms) {
      if (normalizedQuery.contains(blocked)) return false;
    }

    // Check all required terms are present
    for (final required in requiredTerms) {
      if (!normalizedQuery.contains(required)) return false;
    }

    // Check at least one anyOf term is present (if list is non-empty)
    if (anyOf.isNotEmpty) {
      final hasAny = anyOf.any((t) => normalizedQuery.contains(t));
      if (!hasAny) return false;
    }

    return true;
  }
}
