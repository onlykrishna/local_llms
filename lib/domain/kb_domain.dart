enum KbDomain {
  health(label: 'Health', icon: 'assets/icons/health.svg'),
  education(label: 'Education', icon: 'assets/icons/education.svg'),
  banking(label: 'Banking', icon: 'assets/icons/banking.svg'),
  legal(label: 'Legal', icon: 'assets/icons/legal.svg'),
  government(label: 'Government', icon: 'assets/icons/govt.svg');

  const KbDomain({required this.label, required this.icon});
  final String label;
  final String icon;
}
