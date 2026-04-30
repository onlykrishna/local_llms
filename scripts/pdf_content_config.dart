// scripts/pdf_content_config.dart
// ============================================================
// ADD YOUR PDF CONTENT HERE
// To add a new PDF: add a new PdfContent entry to this list
// To update a PDF: change the content — the hash will change
//   and trigger re-indexing automatically on next app launch
// To remove a PDF: delete its PdfContent entry and re-run script
// ============================================================

class PdfContent {
  final String fileName;
  final String title;
  final String content;
  const PdfContent({
    required this.fileName,
    required this.title,
    required this.content,
  });
}

const List<PdfContent> pdfContents = [
  PdfContent(
    fileName: 'home_loan_faqs.pdf',
    title: 'Home Loan – FAQs & Details',
    content: '''
HOME LOAN – FAQs & Details

01. FOR WHAT PURPOSES CAN I AVAIL A HOME LOAN?
A home loan can be availed for buying a New House, Home Renovation, Home Construction, Buy a Plot or Balance transfer of existing Home Loan.

02. DO I NEED A CO-APPLICANT?
Yes. All the co-owners of your property will have to sign up as co-applicants. For a sole property owner or applicant also, most banks require one adult member in the family to sign up as a co-applicant. In case of partnership firm or a company, partners and promoter directors respectively need to be co-applicants.

03. WHO CAN AVAIL A HOME LOAN?
1. Salaried Individuals
2. Self Employed Professionals i.e Chartered Accountants, Doctors, Architects, Cost Accountants, Company Secretary, Management Consultants etc.
3. Self Employed Non Professional i.e Traders, Distributors, Manufacturers, Service Providers etc.
4. Non-Individual Entities i.e. Proprietorship Firms, Partnership Firms, Private Limited Companies, Public Limited companies.

04. HOW MUCH LOAN AM I ELIGIBLE FOR?
Your bank will assess your repayment capacity while deciding the home loan eligibility. Repayment capacity is based on your monthly disposable income, which basically means how much of your monthly income you can spend for repaying the loan after deducting monthly expenses and obligations. The higher the monthly disposable income, higher will be the amount you will be eligible for loan.

05. WHAT IS AN EMI?
EMI stands for Equated Monthly Instalment. You repay the loan in EMIs, which comprising both principal and interest.

06. WHAT IS A PRE-EMI?
Where you have availed only a part of the loan, you would be required to pay only the interest on the amount disbursed till the full loan is availed. This interest is called pre-EMI interest (PEMI) and is payable monthly till the final disbursement is made, after which the EMIs would commence.

07. HOW DOES THE LOAN TENURE AFFECT MY EMI?
Higher loan Tenure means lower EMI, as the loan repayment is amortized over the loan tenure. Most banks offer home loans for a maximum term of 15 or 20 years depending on the age of the applicants.

08. WHAT IS LOAN SANCTION AND DISBURSEMENT?
Based on the documentary proof pertaining to your income, obligations and credit rating, the bank decides whether or not the loan can be sanctioned to you. The bank will give you a sanction letter stating the loan amount, tenure and the interest rate, among other terms of the loan.
When the loan amount is actually handed over to you, it is called disbursement of the loan. This happens once the bank receives the required property papers. It conducts a legal and technical evaluation of the property. If everything is found in order the loan is disbursed. The disbursement of a home loan will happen directly to the person you are buying the property from in cases of fresh purchase. For Balance transfer cases, the loan will be disbursed to the financer from where it is being transferred.

09. WHAT IS LOAN TO VALUE (LTV)?
Loan to Value (LTV) is a term that is used to express the ratio of a Loan to the value of the Property Mortgaged.

10. WHAT IS AN AMORTIZATION SCHEDULE?
This is a table that gives details of the periodic principal and interest payments on a loan and the amount outstanding at any point of time. It also shows the gradual decrease of the loan balance until it reaches zero.

11. DO YOU GET A TAX BENEFIT ON THE LOAN?
Yes. Resident Indians are eligible for certain tax benefits on both Principal and Interest components of a Home Loan under the Income Tax Act, 1961. Under the current laws, you are entitled to an income tax rebate for Interest repayment up to Rs. 200,000/- per annum and Principal Repayment of INR 150,000/- under section 80C.
If the Housing Loan is availed by two or more persons, each of them is eligible to claim a deduction on the interest paid up to INR 2 lakh each. Tax can be deducted on the principal paid as well for an amount up to INR 1.5 lakh each. However, all the applicants should also be co-owners of the property in order to claim this deduction.
''',
  ),

  PdfContent(
    fileName: 'working_capital_loan_faqs.pdf',
    title: 'Working Capital Loan – FAQs & Details',
    content: '''
WORKING CAPITAL LOAN – FAQs & Details

01. WHAT IS A WORKING CAPITAL LOAN?
A working capital loan is money borrowed to finance the day-to-day operations of the business. This includes fixed, regular expenses such as rent for the factory shed and office, salaries and wages, office expenses, security costs, etc.

02. WHO CAN AVAIL A WORKING CAPITAL LOAN?
1. Business owners
2. Small & Medium Enterprises (SMEs)
3. Manufacturers
4. Traders
5. Service Providers

03. HOW DOES THE WORKING CAPITAL LOAN WORK?
Working capital loans are offered by banks, NBFCs and private financiers and are usually unsecured loans. The quantum of loan offered depends on the working capital gap that the business faces after taking into account all its liquid assets. The working capital loan will generally be sanctioned for a short-term period of 12 months and is renewable.

04. WHAT IS THE DIFFERENCE BETWEEN A TERM LOAN AND WORKING CAPITAL LOAN?
Term loans are used for purchasing long-term assets such as machinery or equipment and have a longer tenure of 3-10 years. On the other hand, working capital loans are used to finance day-to-day operations of the business and are generally of a shorter tenure of up to 12 months.

05. HOW MUCH LOAN AMOUNT CAN I AVAIL?
The amount of loan that can be sanctioned to you would be based on your requirement and the assessment of your business's working capital gap and repayment capacity by the lender.

06. WHAT IS THE SECURITY / COLLATERAL REQUIRED FOR A WORKING CAPITAL LOAN?
The working capital loan is generally offered without any collateral. However, depending upon the assessment of your financials and credit profile, the lender may ask for some form of security or personal guarantee.

07. WHAT ARE THE INTEREST RATES ON WORKING CAPITAL LOAN?
The rate of interest would be dependent on the lender, your business profile, financials, and the amount of loan availed. The rate of interest could vary between 12% p.a. to 21% p.a.

08. WHAT ARE THE OTHER CHARGES APPLICABLE?
Processing fees and documentation charges may be applicable depending upon the lender's policies.

09. CAN I PREPAY OR FORECLOSE THE WORKING CAPITAL LOAN?
Yes, you can prepay the loan. However, prepayment charges may be applicable based on the lender's policies.

10. WHAT DOCUMENTS ARE REQUIRED TO AVAIL A WORKING CAPITAL LOAN?
The following documents are generally required:
- KYC documents of the business and promoters
- Audited financial statements for the last 2-3 years
- ITR of the business and promoters
- Bank statements for the last 6-12 months
- Other documents as per the lender's requirement

11. HOW MUCH TIME DOES IT TAKE FOR LOAN DISBURSEMENT?
After submission of all required documents, the working capital loan can be sanctioned and disbursed within 5-7 working days depending upon the lender's processing time.
''',
  ),

  PdfContent(
    fileName: 'unsecured_business_loan_faqs.pdf',
    title: 'Unsecured Business Loan – FAQs & Details',
    content: '''
UNSECURED BUSINESS LOAN – FAQs & Details

01. WHAT IS AN UNSECURED BUSINESS LOAN?
An unsecured business loan is a type of loan that does not require any collateral or security. It is availed on the basis of the borrower's creditworthiness, business financials, and income tax returns.

02. WHO CAN AVAIL AN UNSECURED BUSINESS LOAN?
1. Business Owners
2. Self Employed Non-Professionals
3. Self Employed Professionals

03. HOW MUCH LOAN AMOUNT CAN I AVAIL?
The loan amount would depend on your financials, turnover, profit, existing obligations, and the assessment by the lending institution.

04. WHAT IS THE SECURITY / COLLATERAL REQUIRED?
No collateral or security is required for an unsecured business loan. However, lenders may ask for a personal guarantee.

05. CAN I AVAIL AN UNSECURED BUSINESS LOAN IF I AM A START-UP?
Yes, a start-up can avail an unsecured business loan, provided it meets the lender's criteria in terms of turnover, business vintage, and profitability.

06. WHAT IS THE TENURE FOR AN UNSECURED BUSINESS LOAN?
The tenure is generally between 12 months to 60 months, depending upon the lender and the loan amount.

07. WHAT IS THE INTEREST RATE FOR AN UNSECURED BUSINESS LOAN?
The interest rate varies based on your business profile, financials, credit score, and the lender's policies. Typically, the interest rate ranges from 14% p.a. to 24% p.a.

08. WHAT ARE THE OTHER CHARGES APPLICABLE?
Processing fees, documentation charges, and prepayment charges may be applicable depending on the lender's policies.

09. CAN I PREPAY OR FORECLOSE THE LOAN?
Yes, you can prepay or foreclose the loan, subject to the terms and conditions of the lending institution.

10. WHAT DOCUMENTS ARE REQUIRED TO AVAIL AN UNSECURED BUSINESS LOAN?
Generally, the following documents are required:
- KYC documents of the borrower and business
- Business financials and audit reports of last 2-3 years
- Income Tax Returns
- Bank statements of last 6-12 months
- Other documents as per the lender's requirement

11. HOW MUCH TIME DOES IT TAKE TO SANCTION AND DISBURSE THE LOAN?
The unsecured business loan can be sanctioned and disbursed within 5-7 working days after submission of all required documents.
''',
  ),

  PdfContent(
    fileName: 'loan_against_property_faqs.pdf',
    title: 'Loan Against Property – FAQs & Details',
    content: '''
LOAN AGAINST PROPERTY – FAQs & Details

01. WHAT IS THE DIFFERENCE BETWEEN A HOME LOAN AND LOAN AGAINST PROPERTY?
A home loan is a loan that is availed for purchasing a new house, construction of a house, renovation, or extension of a house. A loan against property (LAP) is a loan that is availed by mortgaging an existing residential or commercial property. The loan amount can be used for business expansion, working capital, marriage, medical emergency, or any personal needs other than speculative purposes.

02. WHAT KIND OF PROPERTY CAN BE MORTGAGED FOR LOAN AGAINST PROPERTY?
You can mortgage residential, commercial, or industrial property that is self-occupied or rented out, provided the title is clear and marketable.

03. WHAT ARE THE PURPOSES FOR WHICH I CAN AVAIL LOAN AGAINST PROPERTY?
Loan Against Property (LAP) can be availed for business expansion, working capital requirement, debt consolidation, child's marriage, medical emergencies, or any other personal financial needs other than speculative purposes.

04. WHAT IS THE DIFFERENCE BETWEEN LOAN AGAINST PROPERTY AND TOP-UP ON HOME LOAN?
Loan against property is a separate loan taken by mortgaging your property, whereas top-up on a home loan is an additional loan that can be availed on your existing home loan if you have a good repayment track record and sufficient repayment capacity.

05. CAN I PREPAY MY LOAN AGAINST PROPERTY BY SELLING THE PROPERTY?
Yes. You can prepay the loan against property by selling the property provided the proceeds are sufficient to repay the outstanding loan amount and all dues. The bank's consent is required for the sale, and the property documents will be released only after the full repayment of the loan.

06. CAN A NON-RESIDENT INDIAN (NRI) AVAIL LOAN AGAINST PROPERTY?
Yes. Some banks and NBFCs offer loan against property to Non-Resident Indians (NRIs) subject to terms and conditions. The property offered as collateral must be located in India.

07. CAN JOINTLY OWNED PROPERTY BE MORTGAGED FOR LOAN AGAINST PROPERTY?
Yes. If a property is jointly owned, all co-owners of the property have to be co-applicants for the loan against property.

08. IS IT MANDATORY TO TAKE INSURANCE FOR THE PROPERTY MORTGAGED?
Yes. Generally, it is mandatory to take adequate insurance coverage for the property that is mortgaged against the loan to safeguard against unforeseen damages.
''',
  ),
];
