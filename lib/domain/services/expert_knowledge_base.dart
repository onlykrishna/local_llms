import 'package:get/get.dart';
import '../../domain/models/inference_domain.dart';

/// Neural Expert Knowledge Base — Zero-latency verified ground truth.
/// Bypasses on-device model for high-traffic entities to prevent hallucination.
class ExpertKnowledgeBase {
  static const Map<String, String> _entities = {

    // ── ACTORS ────────────────────────────────────────────────────────────
    'salman khan':
        'Salman Khan — Born: Dec 27, 1965, Indore. Son of screenwriter Salim Khan. '
        'Breakthrough: Maine Pyar Kiya (1989). Biggest hits: Dabangg (2010), Bajrangi Bhaijaan (2015), Sultan (2016). '
        'Hosts Bigg Boss. Founder: Being Human Foundation (education & healthcare). '
        'Over 10 Filmfare Awards. One of highest-grossing Bollywood actors.',

    'shah rukh khan':
        'Shah Rukh Khan (SRK) — Born: Nov 2, 1965, New Delhi. King of Bollywood. '
        'Breakthrough: Deewana (1992). Iconic films: DDLJ (1995), Kuch Kuch Hota Hai (1998), '
        'My Name is Khan (2010), Chennai Express (2013), Jawan (2023). '
        'Most Filmfare Awards by any actor (record). Co-owner: Kolkata Knight Riders (IPL).',

    'amitabh bachchan':
        'Amitabh Bachchan — Born: Oct 11, 1942, Prayagraj. The "Angry Young Man" of Bollywood. '
        'Iconic films: Zanjeer (1973), Deewar (1975), Sholay (1975), Agneepath (1990), '
        'Black (2005), Piku (2015). Host of Kaun Banega Crorepati (KBC). '
        'Padma Shri, Padma Bhushan, Padma Vibhushan, Dadasaheb Phalke Award recipient.',

    'ranveer singh':
        'Ranveer Singh — Born: Jul 6, 1985, Mumbai. Debut: Band Baaja Baaraat (2010). '
        'Major films: Bajirao Mastani (2015), Padmaavat (2018), Gully Boy (2019), '
        '83 (2021). Known for high energy performances and bold fashion. '
        'Married to Deepika Padukone (2018).',

    'deepika padukone':
        'Deepika Padukone — Born: Jan 5, 1986, Copenhagen. Debut: Om Shanti Om (2007). '
        'Major films: Cocktail (2012), Ram-Leela (2013), Piku (2015), Padmaavat (2018), '
        'Pathaan (2023). One of highest-paid Indian actresses globally. '
        'Mental health advocate. Married to Ranveer Singh (2018).',

    'aamir khan':
        'Aamir Khan — Born: Mar 14, 1965, Mumbai. Known as "Mr. Perfectionist". '
        'Debut: Qayamat Se Qayamat Tak (1988). Landmark films: Lagaan (2001, Oscar-nominated), '
        'Taare Zameen Par (2007), 3 Idiots (2009), Dangal (2016), PK (2014). '
        'Dangal is the highest-grossing Bollywood film in China (\$193M). '
        'Produces and directs. Padma Bhushan recipient.',

    'hrithik roshan':
        'Hrithik Roshan — Born: Jan 10, 1974, Mumbai. Debut: Kaho Naa Pyaar Hai (2000). '
        'Known for action and dance. Major films: Koi Mil Gaya (2003), Krrish (2006), '
        'Dhoom 2 (2006), Zindagi Na Milegi Dobara (2011), War (2019), Fighter (2024). '
        'Often called the "Greek God" of Bollywood.',

    'akshay kumar':
        'Akshay Kumar — Born: Sep 9, 1967, Amritsar. Also known as "Khiladi". '
        'Debut: Saugandh (1991). Known for patriotic and action films: '
        'Kesari (2019), Mission Mangal (2019), Sooryavanshi (2021), Skanda. '
        'Padma Shri recipient. One of the most prolific Bollywood actors.',

    // ── FILMS & BOX OFFICE ────────────────────────────────────────────────
    'dangal':
        'Dangal (2016) — Director: Nitesh Tiwari. Lead: Aamir Khan. '
        'Based on wrestler Mahavir Phogat and daughters Geeta & Babita Phogat. '
        'Box office: ₹2,024 crore worldwide — highest-grossing Indian film ever (as of 2024). '
        'China box office alone: ~\$193 million. National Award winner.',

    'baahubali':
        'Baahubali: The Beginning (2015) & Baahubali 2: The Conclusion (2017). '
        'Director: S.S. Rajamouli. Lead: Prabhas. Telugu film dubbed in Hindi. '
        'Baahubali 2 collected ₹1,810 crore worldwide — was highest-grossing Indian film before Dangal. '
        'Famous for "Why did Kattappa kill Baahubali?" suspense.',

    'ddlj':
        'Dilwale Dulhania Le Jayenge (DDLJ, 1995) — Director: Aditya Chopra. '
        'Cast: Shah Rukh Khan, Kajol. Produced by Yash Raj Films. '
        'Ran for 25+ years at Maratha Mandir, Mumbai — record for longest-running film. '
        'Won 10 Filmfare Awards. National Award for Best Film.',

    'sholay':
        'Sholay (1975) — Director: Ramesh Sippy. Cast: Amitabh Bachchan, Dharmendra, '
        'Sanjeev Kumar, Jaya Bachchan, Hema Malini. '
        'Considered the greatest Indian film ever made. Named "Film of the Millennium" by BBC India. '
        'Villain Gabbar Singh is one of Bollywood\'s most iconic characters.',

    '3 idiots':
        '3 Idiots (2009) — Director: Rajkumar Hirani. Lead: Aamir Khan, R. Madhavan, Sharman Joshi. '
        'Based on novel "Five Point Someone" by Chetan Bhagat. '
        'Box office: ₹460 crore worldwide — was highest-grossing Bollywood film at release. '
        'Famous dialogue: "All is well". Promoted engineering education reform.',

    'pathaan':
        'Pathaan (2023) — Director: Siddharth Anand. Cast: Shah Rukh Khan, Deepika Padukone, John Abraham. '
        'Box office: ₹1,050 crore worldwide. SRK\'s comeback film after 4-year gap. '
        'Part of YRF Spy Universe.',

    // ── AWARDS ────────────────────────────────────────────────────────────
    'filmfare awards':
        'Filmfare Awards — Annual Bollywood awards by The Times of India Group. '
        'Also called the "Black Lady" awards. First ceremony: March 21, 1954. '
        'First Best Actor: Dilip Kumar (Daag). First Best Actress: Meena Kumari (Parineeta). '
        'First Best Film: Do Bigha Zamin. First Best Director: Bimal Roy. '
        'Most Filmfare Awards: Shah Rukh Khan (Best Actor). '
        'Most female: Lata Mangeshkar (Playback).',

    'national film awards':
        'National Film Awards — Highest film honours in India, given by Government of India. '
        'Presented by the President of India. Categories: Best Film, Direction, Actor, Actress etc. '
        'Dadasaheb Phalke Award is the highest individual honour for lifetime contribution to cinema.',

    // ── GENERAL ───────────────────────────────────────────────────────────
    'bollywood':
        'Bollywood is the Mumbai-based Hindi-language film industry. '
        'Produces 1,500–2,000 films per year across all Indian languages (Indian cinema). '
        'Bollywood alone produces ~200 Hindi films annually. '
        'Revenue: \$2.1 billion (2019). Largest by number of films: Tamil & Telugu also major.',

    // ── HEALTH (kept for cross-domain short-circuit) ───────────────────────
    'diabetes':
        'Diabetes is a metabolic disease causing high blood sugar. '
        'Type 1: body does not make insulin. Type 2: body does not use insulin effectively. '
        'Management: diet, exercise, blood sugar monitoring, medication. '
        'Always consult a qualified doctor for treatment.',
  };

  /// Returns a verified answer if the query matches a known entity.
  /// Returns null if no match — model inference proceeds normally.
  static String? probe(String query, InferenceDomain domain) {
    final text = query.toLowerCase().trim();
    for (var entry in _entities.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}
