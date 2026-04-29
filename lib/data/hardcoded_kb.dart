class KbEntry {
  final String id;
  final String question;
  final String answer;
  final List<String> keywords;
  final String category;
  const KbEntry({
    required this.id,
    required this.question,
    required this.answer,
    required this.keywords,
    required this.category,
  });

  /// The text that gets embedded into the vector store.
  /// Combines question + answer for richer semantic representation.
  String get embeddingText => '$question\n$answer\nKeywords: ${keywords.join(', ')}';
}

const String kKbVersion = 'v1.4';

const List<KbEntry> kKnowledgeBase = [

  KbEntry(
    id: 'hl_01',
    question: 'For what purposes can I avail a home loan?',
    answer: 'A home loan can be availed for buying a New House, Home '
        'Renovation, Home Construction, buying a Plot, or Balance '
        'Transfer of an existing Home Loan.',
    keywords: ['home loan purpose', 'avail home loan', 'home loan uses',
                'home loan for', 'buy house', 'renovation loan',
                'construction loan', 'plot loan'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_02',
    question: 'Do I need a co-applicant for a home loan?',
    answer: 'Yes. All co-owners of the property must sign up as '
        'co-applicants. For a sole owner, most banks require at least '
        'one adult family member as co-applicant. For partnership firms '
        'or companies, partners and promoter directors must be '
        'co-applicants.',
    keywords: ['co-applicant', 'co applicant', 'joint applicant',
                'need co applicant', 'home loan applicant'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_03',
    question: 'Who can avail a home loan?',
    answer: 'A home loan can be availed by: (1) Salaried Individuals, '
        '(2) Self Employed Professionals such as Chartered Accountants, '
        'Doctors, Architects, Cost Accountants, Company Secretaries, '
        'Management Consultants, (3) Self Employed Non-Professionals '
        'such as Traders, Distributors, Manufacturers, Service '
        'Providers, and (4) Non-Individual Entities such as '
        'Proprietorship Firms, Partnership Firms, Private Limited '
        'and Public Limited Companies.',
    keywords: ['who can home loan', 'home loan eligible', 'eligible home loan',
                'qualify home loan', 'salaried home loan',
                'self employed home loan'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_04',
    question: 'How much loan am I eligible for?',
    answer: 'Your bank assesses your repayment capacity to decide '
        'eligibility. Repayment capacity is based on monthly disposable '
        'income — how much you can spend on repayment after deducting '
        'expenses and obligations. Higher monthly disposable income '
        'means higher eligible loan amount.',
    keywords: ['how much loan', 'loan amount eligible', 'eligibility amount',
                'repayment capacity', 'monthly income loan',
                'disposable income'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_05',
    question: 'What is an EMI?',
    answer: 'EMI stands for Equated Monthly Instalment. You repay the '
        'loan in EMIs, which comprise both principal and interest.',
    keywords: [
      'what is emi',
      'emi meaning',
      'emi full form',
      'emi stand for',
      'equated monthly instalment',
      'equated monthly installment',
    ],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_06',
    question: 'What is a Pre-EMI?',
    answer: 'Where only a part of the loan is disbursed, you pay only '
        'the interest on the disbursed amount until the full loan is '
        'availed. This interest is called Pre-EMI interest (PEMI) and '
        'is payable monthly until the final disbursement, after which '
        'regular EMIs commence.',
    keywords: [
      'pre-emi',
      'pre emi',
      'pemi',
      'pre emi interest',
      'pre-emi interest',
      'partial disbursement interest',
      'interest before full disbursement',
      'what is pre emi',
      'what is a pre emi',
      'pre emi meaning',
      'pre emi definition',
      'pre emi full form',
    ],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_07',
    question: 'How does loan tenure affect my EMI?',
    answer: 'Higher loan tenure means lower EMI, as repayment is '
        'amortized over a longer period. Most banks offer home loans '
        'for a maximum term of 15 or 20 years depending on the age '
        'of the applicants.',
    keywords: ['tenure emi', 'loan tenure', 'tenure affect emi',
                'higher tenure lower emi', '15 years 20 years loan',
                'maximum tenure'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_08',
    question: 'What is loan sanction and disbursement?',
    answer: 'Loan Sanction: Based on documentary proof of income, '
        'obligations, and credit rating, the bank decides to sanction '
        'and issues a sanction letter with amount, tenure, and rate. '
        'Loan Disbursement: The loan amount is handed over after the '
        'bank receives property papers and completes legal and technical '
        'evaluation. For fresh purchases, disbursement goes to the '
        'seller; for balance transfers, to the existing financer.',
    keywords: ['loan sanction', 'loan disbursement', 'sanction letter',
                'sanctioned', 'disbursed', 'property papers',
                'legal evaluation'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_09',
    question: 'What is Loan to Value (LTV)?',
    answer: 'Loan to Value (LTV) is a term used to express the ratio '
        'of a loan to the value of the property mortgaged.',
    keywords: ['ltv', 'loan to value', 'loan-to-value', 'ltv meaning',
                'ltv ratio', 'property value ratio', 'what is ltv'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_10',
    question: 'What is an amortization schedule?',
    answer: 'An amortization schedule is a table giving details of '
        'periodic principal and interest payments on a loan and the '
        'amount outstanding at any point of time. It also shows the '
        'gradual decrease of the loan balance until it reaches zero.',
    keywords: ['amortization', 'amortisation', 'amortization schedule',
                'repayment schedule table', 'principal interest table'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'hl_11',
    question: 'Do you get a tax benefit on a home loan?',
    answer: 'Yes. Resident Indians are eligible for tax benefits on '
        'both Principal and Interest of a Home Loan under the Income '
        'Tax Act, 1961. Interest repayment rebate up to Rs. 2,00,000/- '
        'per annum and Principal Repayment up to INR 1,50,000/- under '
        'Section 80C. Joint borrowers can each claim up to INR 2 lakh '
        'on interest and INR 1.5 lakh on principal, provided all are '
        'co-owners.',
    keywords: ['tax benefit', 'tax rebate home loan', 'income tax home loan',
                '80c', 'section 80c', 'tax deduction loan',
                'tax saving home loan'],
    category: 'Home Loan',
  ),

  KbEntry(
    id: 'wcl_01',
    question: 'What is a working capital loan?',
    answer: 'A working capital loan is money borrowed to finance the '
        'day-to-day operations of a business, including fixed regular '
        'expenses such as rent, salaries and wages, office expenses, '
        'and security costs.',
    keywords: ['working capital loan', 'what is working capital',
                'working capital meaning', 'working capital definition'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'wcl_02',
    question: 'Who can avail a working capital loan?',
    answer: 'A working capital loan can be availed by Business Owners, '
        'Small & Medium Enterprises (SMEs), Manufacturers, Traders, '
        'and Service Providers.',
    keywords: ['who working capital', 'working capital eligible',
                'working capital eligibility', 'sme working capital'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'wcl_03',
    question: 'How does a working capital loan work?',
    answer: 'Working capital loans are offered by banks, NBFCs, and '
        'private financiers and are usually unsecured. The quantum '
        'depends on the working capital gap after accounting for liquid '
        'assets. It is sanctioned for a short-term period of 12 months '
        'and is renewable.',
    keywords: ['working capital work', 'how working capital', 'nbfc loan',
                'unsecured working capital', '12 months working capital'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'wcl_04',
    question: 'What is the difference between a term loan and working '
        'capital loan?',
    answer: 'Term loans are for purchasing long-term assets like '
        'machinery or equipment, with tenure of 3–10 years. Working '
        'capital loans finance day-to-day operations with a shorter '
        'tenure of up to 12 months.',
    keywords: ['term loan vs working capital', 'difference term loan',
                'term loan working capital difference'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'wcl_07',
    question: 'What are the interest rates on a working capital loan?',
    answer: 'The interest rate depends on the lender, your business '
        'profile, financials, and loan amount, typically varying '
        'between 12% p.a. to 21% p.a.',
    keywords: ['working capital interest', 'rate working capital',
                'interest rate working capital loan', '12 percent 21 percent'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'wcl_10',
    question: 'What documents are required for a working capital loan?',
    answer: 'Documents required: KYC documents of the business and '
        'promoters, Audited financial statements for the last 2–3 years, '
        'ITR of business and promoters, Bank statements for the last '
        '6–12 months, and other documents per lender\'s requirement.',
    keywords: ['working capital documents', 'documents for working capital',
                'kyc working capital', 'itr working capital'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'wcl_11',
    question: 'How much time does it take for working capital loan '
        'disbursement?',
    answer: 'After submission of all required documents, a working '
        'capital loan can be sanctioned and disbursed within 5–7 '
        'working days.',
    keywords: ['working capital time', 'disbursement time working capital',
                'how long working capital', 'days working capital loan'],
    category: 'Working Capital Loan',
  ),

  KbEntry(
    id: 'ubl_01',
    question: 'What is an unsecured business loan?',
    answer: 'An unsecured business loan does not require any collateral '
        'or security. It is availed based on the borrower\'s '
        'creditworthiness, business financials, and income tax returns.',
    keywords: ['unsecured business loan', 'what is unsecured loan',
                'unsecured loan meaning', 'no collateral loan'],
    category: 'Unsecured Business Loan',
  ),

  KbEntry(
    id: 'ubl_04',
    question: 'What security or collateral is required for an unsecured '
        'business loan?',
    answer: 'No collateral or security is required. However, lenders '
        'may ask for a personal guarantee.',
    keywords: ['unsecured collateral', 'collateral unsecured business',
                'security unsecured', 'personal guarantee unsecured'],
    category: 'Unsecured Business Loan',
  ),

  KbEntry(
    id: 'ubl_05',
    question: 'Can a start-up avail an unsecured business loan?',
    answer: 'Yes, a start-up can avail an unsecured business loan '
        'provided it meets the lender\'s criteria in terms of turnover, '
        'business vintage, and profitability.',
    keywords: ['startup loan', 'start-up loan', 'startup business loan',
                'new business loan', 'startup unsecured', 
                'can startup get loan', 'startup get business loan',
                'new company loan', 'startup eligible'],
    category: 'Unsecured Business Loan',
  ),

  KbEntry(
    id: 'ubl_06',
    question: 'What is the tenure for an unsecured business loan?',
    answer: 'The tenure is generally between 12 months to 60 months, '
        'depending upon the lender and the loan amount.',
    keywords: ['unsecured tenure', 'tenure unsecured loan',
                '12 months 60 months', 'unsecured loan period'],
    category: 'Unsecured Business Loan',
  ),

  KbEntry(
    id: 'ubl_07',
    question: 'What is the interest rate for an unsecured business loan?',
    answer: 'The interest rate varies based on business profile, '
        'financials, credit score, and lender\'s policies, typically '
        'ranging from 14% p.a. to 24% p.a.',
    keywords: ['unsecured interest rate', 'rate unsecured business',
                '14 percent 24 percent', 'interest unsecured loan'],
    category: 'Unsecured Business Loan',
  ),

  KbEntry(
    id: 'ubl_11',
    question: 'How long does it take to sanction an unsecured business '
        'loan?',
    answer: 'An unsecured business loan can be sanctioned and disbursed '
        'within 5–7 working days after submission of all required '
        'documents.',
    keywords: ['unsecured disbursement time', 'time unsecured loan',
                'how long unsecured', 'days unsecured business loan'],
    category: 'Unsecured Business Loan',
  ),

  KbEntry(
    id: 'lap_01',
    question: 'What is the difference between a home loan and loan '
        'against property?',
    answer: 'A home loan is for purchasing, constructing, renovating, '
        'or extending a house. A Loan Against Property (LAP) is availed '
        'by mortgaging an existing residential or commercial property '
        'for purposes like business expansion, working capital, marriage, '
        'or medical emergency.',
    keywords: ['home loan vs lap', 'difference home loan lap',
                'lap vs home loan', 'loan against property difference'],
    category: 'Loan Against Property',
  ),

  KbEntry(
    id: 'lap_02',
    question: 'What kind of property can be mortgaged for LAP?',
    answer: 'You can mortgage residential, commercial, or industrial '
        'property that is self-occupied or rented out, provided the '
        'title is clear and marketable.',
    keywords: ['lap property type', 'mortgage property type',
                'commercial residential mortgage', 'which property lap'],
    category: 'Loan Against Property',
  ),

  KbEntry(
    id: 'lap_03',
    question: 'For what purposes can I avail a Loan Against Property?',
    answer: 'LAP can be availed for business expansion, working capital '
        'requirement, debt consolidation, child\'s marriage, medical '
        'emergencies, or any personal financial needs other than '
        'speculative purposes.',
    keywords: ['lap purpose', 'loan against property purpose',
                'lap uses', 'avail lap for', 'lap availed for'],
    category: 'Loan Against Property',
  ),

  KbEntry(
    id: 'lap_04',
    question: 'What is the difference between LAP and top-up on home '
        'loan?',
    answer: 'LAP is a separate loan taken by mortgaging your property. '
        'A Top-Up on a home loan is an additional loan on your existing '
        'home loan if you have a good repayment track record and '
        'sufficient repayment capacity.',
    keywords: ['lap top up', 'top up home loan', 'lap vs top up',
                'difference lap top up home loan'],
    category: 'Loan Against Property',
  ),

  KbEntry(
    id: 'lap_06',
    question: 'Can a Non-Resident Indian (NRI) avail Loan Against '
        'Property?',
    answer: 'Yes. Some banks and NBFCs offer LAP to Non-Resident '
        'Indians (NRIs) subject to terms and conditions. The property '
        'offered as collateral must be located in India.',
    keywords: ['nri lap', 'nri loan against property', 'non resident indian lap',
                'nri property mortgage'],
    category: 'Loan Against Property',
  ),

  KbEntry(
    id: 'lap_07',
    question: 'Can jointly owned property be mortgaged for LAP?',
    answer: 'Yes. If a property is jointly owned, all co-owners must '
        'be co-applicants for the Loan Against Property.',
    keywords: ['jointly owned property lap', 'joint property mortgage',
                'co-owned lap', 'joint owners lap'],
    category: 'Loan Against Property',
  ),

  KbEntry(
    id: 'lap_08',
    question: 'Is it mandatory to take insurance for the mortgaged '
        'property?',
    answer: 'Yes. It is generally mandatory to take adequate insurance '
        'coverage for the property mortgaged against the loan to '
        'safeguard against unforeseen damages.',
    keywords: ['property insurance lap', 'mandatory insurance',
                'insure mortgaged property', 'insurance lap'],
    category: 'Loan Against Property',
  ),

];
