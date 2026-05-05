import '../models/guideline_model.dart';

/// Default hair care guidelines - always available offline
class GuidelinesData {
  static List<GuidelineModel> get defaultGuidelines => [
    GuidelineModel(
      id: '1',
      title: 'Daily Scalp Care',
      category: 'Care',
      content: 'Clean your scalp daily with a gentle shampoo. Avoid harsh chemicals and hot water which can strip natural oils. Over-washing can also damage your scalp\'s natural balance.',
      tips: ['Use lukewarm water', 'Massage gently in circular motions', 'Rinse thoroughly', 'Limit washing to 2-3 times per week for dry scalp'],
    ),
    GuidelineModel(
      id: '2',
      title: 'Nutrition for Hair Health',
      category: 'Nutrition',
      content: 'A balanced diet rich in protein, iron, zinc, and vitamins A, C, D, and E promotes healthy hair growth. Biotin and omega-3 fatty acids are especially beneficial for hair strength.',
      tips: ['Eat eggs, fish, and lean meats', 'Include leafy greens and nuts', 'Stay hydrated - drink 8+ glasses of water daily', 'Consider biotin supplements if deficient'],
    ),
    GuidelineModel(
      id: '3',
      title: 'Hair Loss Prevention',
      category: 'Prevention',
      content: 'Early intervention is key. Avoid tight hairstyles that pull on roots, reduce stress, and consult a specialist if you notice excessive shedding (more than 100 hairs per day).',
      tips: ['Avoid tight ponytails and braids', 'Manage stress through exercise and sleep', 'Get regular checkups with a dermatologist', 'Don\'t ignore sudden or patchy hair loss'],
    ),
    GuidelineModel(
      id: '4',
      title: 'Scalp Massage Benefits',
      category: 'Care',
      content: 'Spend 3-5 minutes every night massaging your scalp with your fingertips. This improves blood circulation, reduces tension, and can promote healthier hair growth.',
      tips: ['Use circular motions with light pressure', 'Focus on areas with thinning', 'Be consistent - do it daily', 'Use natural oils (coconut, argan) for extra nourishment'],
    ),
    GuidelineModel(
      id: '5',
      title: 'Choosing the Right Products',
      category: 'Products',
      content: 'Select products based on your scalp type: oily, dry, or sensitive. Look for pH-balanced (4.5-5.5) and sulfate-free options to maintain scalp health.',
      tips: ['Know your scalp type first', 'Read ingredients - avoid sulfates and parabens', 'Patch test new products before full use', 'Match shampoo to scalp, conditioner to hair ends'],
    ),
    GuidelineModel(
      id: '6',
      title: 'Protecting Hair from Heat & Sun',
      category: 'Protection',
      content: 'Excessive heat styling and UV exposure can damage hair cuticles and cause dryness. Use heat protectant sprays and cover your head when in direct sunlight for long periods.',
      tips: ['Use heat protectant before styling', 'Limit blow-drying and flat iron use', 'Wear a hat or scarf in strong sun', 'Rinse with cool water after washing'],
    ),
    GuidelineModel(
      id: '7',
      title: 'Managing Dandruff',
      category: 'Conditions',
      content: 'Dandruff is often caused by dry scalp or fungal overgrowth. Use anti-dandruff shampoos with zinc pyrithione or ketoconazole. Keep scalp moisturized but not oily.',
      tips: ['Use medicated shampoo 2-3 times weekly', 'Don\'t scratch - it worsens inflammation', 'Reduce stress and improve diet', 'See a doctor if severe or persistent'],
    ),
    GuidelineModel(
      id: '8',
      title: 'Hair Thinning: What to Do',
      category: 'Conditions',
      content: 'Hair thinning can result from genetics, stress, diet, or medical conditions. Early diagnosis helps. Minoxidil and finasteride may help; consult a specialist for personalized treatment.',
      tips: ['Identify the cause with a professional', 'Improve nutrition and reduce stress', 'Avoid harsh chemicals and heat', 'Consider PRP or other treatments if recommended'],
    ),
    GuidelineModel(
      id: '9',
      title: 'Natural Oils for Hair',
      category: 'Care',
      content: 'Coconut, argan, jojoba, and castor oils can nourish the scalp and strengthen hair. Apply 1-2 times per week, leave for 30 minutes, then shampoo. Warm the oil slightly for better absorption.',
      tips: ['Coconut oil: great for protein treatment', 'Argan oil: adds shine and moisture', 'Castor oil: may promote growth', 'Don\'t overuse - can clog follicles'],
    ),
    GuidelineModel(
      id: '10',
      title: 'When to See a Specialist',
      category: 'Prevention',
      content: 'Consult a dermatologist or trichologist if you experience: sudden hair loss, patchy bald spots, scalp pain, severe dandruff, or hair loss that doesn\'t improve with lifestyle changes.',
      tips: ['Don\'t delay - early treatment is best', 'Bring photos of hair progression', 'List medications and supplements', 'Be honest about stress and diet'],
    ),
  ];
}
