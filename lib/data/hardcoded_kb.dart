class KbEntry {
  final List<String> keywords;
  final String answer;
  final String source;
  const KbEntry({
    required this.keywords,
    required this.answer,
    required this.source,
  });
}

const List<KbEntry> kFaqsKnowledgeBase = [

  // ═══ HOME LOAN ═══

  KbEntry(
    keywords: ['home loan', 'purpose', 'avail', 'availed', 'purposes'],
    answer: 'A home loan can be availed for buying a New House, Home '
        'Renovation, Home Construction, buying a Plot, or Balance '
        'Transfer of an existing Home Loan.',
    source: 'FAQS_CFL.pdf — Home Loan, Q1',
  ),

  KbEntry(
    keywords: ['co-applicant', 'coapplicant', 'co applicant', 'joint'],
    answer: 'Yes. All co-owners of the property must sign up as '
        'co-applicants. For a sole owner, most banks require at least '
        'one adult family member as co-applicant. For partnership firms '
        'or companies, partners and promoter directors respectively must '
        'be co-applicants.',
    source: 'FAQS_CFL.pdf — Home Loan, Q2',
  ),

  KbEntry(
    keywords: ['who can avail home loan', 'eligible home loan',
               'home loan eligibility', 'qualify home loan'],
    answer: 'A home loan can be availed by: (1) Salaried Individuals, '
        '(2) Self Employed Professionals such as Chartered Accountants, '
        'Doctors, Architects, Cost Accountants, Company Secretaries, '
        'Management Consultants, (3) Self Employed Non-Professionals '
        'such as Traders, Distributors, Manufacturers, Service '
        'Providers, and (4) Non-Individual Entities such as '
        'Proprietorship Firms, Partnership Firms, Private Limited '
        'Companies, and Public Limited Companies.',
    source: 'FAQS_CFL.pdf — Home Loan, Q3',
  ),

  KbEntry(
    keywords: ['how much loan', 'loan eligible', 'loan amount',
               'eligibility', 'repayment capacity'],
    answer: 'Your bank assesses your repayment capacity to determine '
        'loan eligibility. Repayment capacity is based on your monthly '
        'disposable income — how much you can spend on repayment after '
        'deducting monthly expenses and obligations. The higher the '
        'monthly disposable income, the higher the loan amount you will '
        'be eligible for.',
    source: 'FAQS_CFL.pdf — Home Loan, Q4',
  ),

  KbEntry(
    keywords: ['emi', 'equated monthly', 'instalment', 'installment'],
    answer: 'EMI stands for Equated Monthly Instalment. You repay the '
        'loan in EMIs, which comprise both principal and interest.',
    source: 'FAQS_CFL.pdf — Home Loan, Q5',
  ),

  KbEntry(
    keywords: ['pre-emi', 'pre emi', 'pemi', 'partial disbursement',
               'interest only'],
    answer: 'Where only a part of the loan is disbursed, you pay only '
        'the interest on the disbursed amount until the full loan is '
        'availed. This interest is called Pre-EMI interest (PEMI) and '
        'is payable monthly until the final disbursement, after which '
        'regular EMIs commence.',
    source: 'FAQS_CFL.pdf — Home Loan, Q6',
  ),

  KbEntry(
    keywords: ['tenure', 'loan tenure', 'emi tenure', 'tenure affect',
               'longer tenure', 'shorter tenure'],
    answer: 'Higher loan tenure means lower EMI, as the repayment is '
        'amortized over a longer period. Most banks offer home loans '
        'for a maximum term of 15 or 20 years depending on the age '
        'of the applicants.',
    source: 'FAQS_CFL.pdf — Home Loan, Q7',
  ),

  KbEntry(
    keywords: ['sanction', 'disbursement', 'loan sanction',
               'loan disbursement', 'sanctioned', 'disbursed'],
    answer: 'Loan Sanction: Based on documentary proof of income, '
        'obligations, and credit rating, the bank decides whether to '
        'sanction the loan and issues a sanction letter with the loan '
        'amount, tenure, and interest rate. '
        'Loan Disbursement: The loan amount is handed over after the '
        'bank receives property papers and completes legal and '
        'technical evaluation. For fresh purchases, disbursement goes '
        'directly to the seller; for balance transfers, to the '
        'existing financer.',
    source: 'FAQS_CFL.pdf — Home Loan, Q8',
  ),

  KbEntry(
    keywords: ['ltv', 'loan to value', 'loan-to-value', 'property value',
               'mortgaged value'],
    answer: 'Loan to Value (LTV) is a term used to express the ratio '
        'of a loan to the value of the property mortgaged.',
    source: 'FAQS_CFL.pdf — Home Loan, Q9',
  ),

  KbEntry(
    keywords: ['amortization', 'amortisation', 'amortization schedule',
               'repayment schedule', 'principal interest schedule'],
    answer: 'An amortization schedule is a table that gives details of '
        'the periodic principal and interest payments on a loan and the '
        'amount outstanding at any point of time. It also shows the '
        'gradual decrease of the loan balance until it reaches zero.',
    source: 'FAQS_CFL.pdf — Home Loan, Q10',
  ),

  KbEntry(
    keywords: ['tax benefit', 'tax rebate', 'income tax', '80c',
               'tax deduction', 'section 80'],
    answer: 'Yes. Resident Indians are eligible for tax benefits on '
        'both Principal and Interest components of a Home Loan under '
        'the Income Tax Act, 1961. You are entitled to an income tax '
        'rebate for Interest repayment up to Rs. 2,00,000/- per annum '
        'and Principal Repayment up to INR 1,50,000/- under Section '
        '80C. If the loan is availed by two or more persons, each is '
        'eligible to claim deduction on interest up to INR 2 lakh and '
        'principal up to INR 1.5 lakh, provided all are also co-owners '
        'of the property.',
    source: 'FAQS_CFL.pdf — Home Loan, Q11',
  ),

  // ═══ WORKING CAPITAL LOAN ═══

  KbEntry(
    keywords: ['working capital', 'working capital loan',
               'what is working capital'],
    answer: 'A working capital loan is money borrowed to finance the '
        'day-to-day operations of a business. This includes fixed '
        'regular expenses such as rent, salaries and wages, office '
        'expenses, and security costs.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q1',
  ),

  KbEntry(
    keywords: ['who can avail working capital', 'working capital eligible',
               'working capital eligibility'],
    answer: 'A working capital loan can be availed by: Business Owners, '
        'Small & Medium Enterprises (SMEs), Manufacturers, Traders, '
        'and Service Providers.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q2',
  ),

  KbEntry(
    keywords: ['how working capital works', 'working capital work',
               'working capital unsecured', 'working capital 12 months'],
    answer: 'Working capital loans are offered by banks, NBFCs, and '
        'private financiers and are usually unsecured. The loan quantum '
        'depends on the working capital gap after accounting for liquid '
        'assets. It is generally sanctioned for a short-term period of '
        '12 months and is renewable.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q3',
  ),

  KbEntry(
    keywords: ['difference term loan working capital', 'term loan vs',
               'term loan difference'],
    answer: 'Term loans are used for purchasing long-term assets such '
        'as machinery or equipment and have a tenure of 3–10 years. '
        'Working capital loans finance day-to-day operations and are '
        'generally of shorter tenure up to 12 months.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q4',
  ),

  KbEntry(
    keywords: ['working capital interest rate', 'interest rate working',
               'rate of interest working capital'],
    answer: 'The rate of interest on a working capital loan depends on '
        'the lender, your business profile, financials, and loan '
        'amount. It typically varies between 12% p.a. to 21% p.a.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q7',
  ),

  KbEntry(
    keywords: ['working capital documents', 'documents working capital',
               'kyc working capital', 'required documents working'],
    answer: 'Documents generally required for a working capital loan: '
        'KYC documents of the business and promoters, Audited financial '
        'statements for the last 2–3 years, ITR of the business and '
        'promoters, Bank statements for the last 6–12 months, and other '
        'documents as per the lender\'s requirement.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q10',
  ),

  KbEntry(
    keywords: ['working capital disbursement time', 'how long working capital',
               'time disbursement working', 'days working capital'],
    answer: 'After submission of all required documents, a working '
        'capital loan can be sanctioned and disbursed within 5–7 '
        'working days depending on the lender\'s processing time.',
    source: 'FAQS_CFL.pdf — Working Capital Loan, Q11',
  ),

  // ═══ UNSECURED BUSINESS LOAN ═══

  KbEntry(
    keywords: ['unsecured business loan', 'unsecured loan',
               'what is unsecured'],
    answer: 'An unsecured business loan is a type of loan that does '
        'not require any collateral or security. It is availed on the '
        'basis of the borrower\'s creditworthiness, business financials, '
        'and income tax returns.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q1',
  ),

  KbEntry(
    keywords: ['who can avail unsecured', 'unsecured loan eligible',
               'unsecured business eligible'],
    answer: 'An unsecured business loan can be availed by: Business '
        'Owners, Self Employed Non-Professionals, and Self Employed '
        'Professionals.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q2',
  ),

  KbEntry(
    keywords: ['unsecured collateral', 'collateral unsecured',
               'security unsecured', 'no collateral'],
    answer: 'No collateral or security is required for an unsecured '
        'business loan. However, lenders may ask for a personal '
        'guarantee.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q4',
  ),

  KbEntry(
    keywords: ['startup unsecured', 'start-up unsecured', 'new business loan',
               'startup loan'],
    answer: 'Yes, a start-up can avail an unsecured business loan, '
        'provided it meets the lender\'s criteria in terms of turnover, '
        'business vintage, and profitability.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q5',
  ),

  KbEntry(
    keywords: ['unsecured tenure', 'tenure unsecured business',
               'unsecured loan period'],
    answer: 'The tenure for an unsecured business loan is generally '
        'between 12 months to 60 months, depending upon the lender '
        'and the loan amount.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q6',
  ),

  KbEntry(
    keywords: ['unsecured interest rate', 'interest rate unsecured',
               'rate unsecured business'],
    answer: 'The interest rate for an unsecured business loan varies '
        'based on your business profile, financials, credit score, and '
        'lender\'s policies. It typically ranges from 14% p.a. to '
        '24% p.a.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q7',
  ),

  KbEntry(
    keywords: ['unsecured documents', 'documents unsecured',
               'required documents unsecured business'],
    answer: 'Documents generally required for an unsecured business '
        'loan: KYC documents of the borrower and business, Business '
        'financials and audit reports for the last 2–3 years, Income '
        'Tax Returns, Bank statements for the last 6–12 months, and '
        'other documents as per the lender\'s requirement.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q10',
  ),

  KbEntry(
    keywords: ['unsecured disbursement time', 'how long unsecured',
               'days unsecured loan', 'time unsecured sanction'],
    answer: 'An unsecured business loan can be sanctioned and disbursed '
        'within 5–7 working days after submission of all required '
        'documents.',
    source: 'FAQS_CFL.pdf — Unsecured Business Loan, Q11',
  ),

  // ═══ LOAN AGAINST PROPERTY ═══

  KbEntry(
    keywords: ['difference home loan lap', 'home loan vs loan against',
               'lap vs home loan', 'loan against property difference'],
    answer: 'A home loan is availed for purchasing, constructing, '
        'renovating, or extending a house. A Loan Against Property '
        '(LAP) is availed by mortgaging an existing residential or '
        'commercial property, and the loan amount can be used for '
        'business expansion, working capital, marriage, medical '
        'emergency, or any personal needs other than speculative '
        'purposes.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q1',
  ),

  KbEntry(
    keywords: ['mortgage property', 'what property mortgaged', 'lap property',
               'kind of property', 'type of property'],
    answer: 'You can mortgage residential, commercial, or industrial '
        'property that is self-occupied or rented out, provided the '
        'title is clear and marketable.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q2',
  ),

  KbEntry(
    keywords: ['lap purpose', 'loan against property purpose',
               'avail lap for', 'lap availed'],
    answer: 'Loan Against Property (LAP) can be availed for business '
        'expansion, working capital requirement, debt consolidation, '
        'child\'s marriage, medical emergencies, or any other personal '
        'financial needs other than speculative purposes.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q3',
  ),

  KbEntry(
    keywords: ['lap vs top up', 'top up home loan', 'top-up',
               'difference lap top up'],
    answer: 'Loan Against Property is a separate loan taken by '
        'mortgaging your property. A Top-Up on a home loan is an '
        'additional loan that can be availed on your existing home '
        'loan if you have a good repayment track record and sufficient '
        'repayment capacity.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q4',
  ),

  KbEntry(
    keywords: ['prepay lap', 'foreclose lap', 'sell property lap',
               'prepay loan against property'],
    answer: 'Yes. You can prepay the Loan Against Property by selling '
        'the property, provided the proceeds are sufficient to repay '
        'the outstanding loan and all dues. The bank\'s consent is '
        'required for the sale, and the property documents will be '
        'released only after full repayment.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q5',
  ),

  KbEntry(
    keywords: ['nri lap', 'non resident indian lap', 'nri loan against',
               'nri property loan'],
    answer: 'Yes. Some banks and NBFCs offer Loan Against Property to '
        'Non-Resident Indians (NRIs) subject to terms and conditions. '
        'The property offered as collateral must be located in India.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q6',
  ),

  KbEntry(
    keywords: ['jointly owned property', 'joint property mortgage',
               'co-owned property', 'jointly owned lap'],
    answer: 'Yes. If a property is jointly owned, all co-owners of the '
        'property must be co-applicants for the Loan Against Property.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q7',
  ),

  KbEntry(
    keywords: ['insurance property', 'mandatory insurance',
               'property insurance lap', 'insure mortgaged'],
    answer: 'Yes. It is generally mandatory to take adequate insurance '
        'coverage for the property mortgaged against the loan to '
        'safeguard against unforeseen damages.',
    source: 'FAQS_CFL.pdf — Loan Against Property, Q8',
  ),

];
