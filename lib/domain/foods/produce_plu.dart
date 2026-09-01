import 'package:meta/meta.dart';

/// What a produce sticker's code names.
@immutable
class ProduceItem {
  const ProduceItem({
    required this.code,
    required this.name,
    required this.isOrganic,
  });

  /// The code as typed, organic prefix and all.
  final String code;

  /// The commodity, ready to be searched for: "Bananas", "Apple, Gala".
  final String name;

  final bool isOrganic;

  /// How it should read on a food: the name plus the one adjective the code
  /// itself carries. Nothing else is inferred — a sticker says what kind of
  /// apple and whether it was grown organically, and not one thing more.
  String get label => isOrganic ? 'Organic $name' : name;
}

/// Price Look-Up codes — the sticker on loose produce (spec §5.5).
///
/// The gap this fills is the one §5.5 leaves open. The chain begins at a
/// barcode and a loose apple does not have one, so the fallback was typing the
/// whole food in by hand. The sticker's number is the nearest thing produce
/// has to a scan, and it is the same number in every shop.
///
/// **A PLU never goes to a barcode lookup**, and that is the load-bearing
/// decision here. Open Food Facts' short-code space is a different, populated,
/// unrelated namespace, and it answers confidently in it: 4062 is cucumber and
/// OFF returns "Organic Raw Pumpkin Seeds, 600 kcal"; 4159 is a Vidalia onion
/// and it returns a chocolate mould; 4053 is a lemon and it returns honey.
/// Each of those is a wrong food with wrong macros, arriving with every
/// appearance of being right — the one failure a review screen cannot catch.
/// So the code is resolved here, offline, and only the *name* goes out to the
/// sources, where USDA's produce data is the best in the chain anyway.
///
/// The table below is a subset — the produce a household actually buys —
/// parsed from the IFPS PLU listing rather than typed from memory. That
/// distinction is not pedantry: the first draft of this file was written from
/// memory and was wrong about broccoli (4060, not 4082), about what 4083 is
/// (white potato, not green beans) and about half a dozen others. A code is a
/// fact, and facts are looked up.
///
/// Gaps are expected and they fail honestly: an unknown code says it is
/// unknown and offers manual entry, which is where this path started.
abstract final class ProducePlu {
  /// Whether [raw] could be a produce code at all.
  ///
  /// Four digits in the 3000–4999 band IFPS assigns to produce, or five
  /// beginning with 9 for the organic form of one. A leading 8 was once
  /// reserved for genetically engineered produce and was never used in the
  /// shops; it is retired, so it is refused rather than guessed at.
  static bool isPlu(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 4) return _inBand(digits);
    if (digits.length == 5 && digits.startsWith('9')) {
      return _inBand(digits.substring(1));
    }
    return false;
  }

  /// The produce [raw] names, or null when this table does not know it.
  static ProduceItem? lookup(String raw) {
    final String digits = raw.replaceAll(RegExp(r'\D'), '');
    if (!isPlu(digits)) return null;

    final bool organic = digits.length == 5;
    final String? name = _byCode[organic ? digits.substring(1) : digits];
    if (name == null) return null;

    return ProduceItem(code: digits, name: name, isOrganic: organic);
  }

  static bool _inBand(String four) {
    final int value = int.tryParse(four) ?? 0;
    return value >= 3000 && value <= 4999;
  }

  /// How many codes are known, for a screen that wants to be honest about the
  /// size of the table it is searching.
  static int get known => _byCode.length;

  /// Code to commodity, conventional four-digit form only: the organic code is
  /// the same one with a 9 in front, which [lookup] strips rather than
  /// doubling every row here.
  ///
  /// Sizes are deliberately not carried. A small Gala and a large Gala are
  /// different codes and the same food, and the size of an apple has no
  /// bearing on its macros per 100 g — which is the only thing this name is
  /// used to look up.
  static const Map<String, String> _byCode = <String, String>{
    '3283': 'Apple, Honeycrisp',
    '4015': 'Apple, Red Delicious',
    '4016': 'Apple, Red Delicious',
    '4017': 'Apple, Granny Smith',
    '4018': 'Apple, Granny Smith',
    '4020': 'Apple, Golden Delicious',
    '4021': 'Apple, Golden Delicious',
    '4128': 'Apple, Cripps Pink',
    '4129': 'Apple, Fuji',
    '4130': 'Apple, Cripps Pink',
    '4131': 'Apple, Fuji',
    '4132': 'Apple, Gala',
    '4133': 'Apple, Gala',
    '4134': 'Apple, Gala',
    '4135': 'Apple, Gala',
    '4138': 'Apple, Granny Smith',
    '4139': 'Apple, Granny Smith',
    '4144': 'Apple, Jonagold',
    '4146': 'Apple, Jonagold',
    '4152': 'Apple, McIntosh',
    '4154': 'Apple, McIntosh',
    '4167': 'Apple, Red Delicious',
    '4168': 'Apple, Red Delicious',
    '4169': 'Apple, Rome',
    '4171': 'Apple, Rome',
    '4173': 'Apple, Royal Gala',
    '4174': 'Apple, Royal Gala',
    '4884': 'Arugula',
    '4080': 'Asparagus, Green',
    '4521': 'Asparagus, Green',
    '4523': 'Asparagus, White',
    '4525': 'Asparagus',
    '4046': 'Avocado, Hass',
    '4221': 'Avocado, Green',
    '4223': 'Avocado, Green',
    '4225': 'Avocado, Hass',
    '4226': 'Avocado, Cocktail',
    '4227': 'Avocado',
    '4770': 'Avocado, Hass',
    '4011': 'Bananas',
    '4186': 'Bananas, small',
    '4233': 'Bananas, Manzano',
    '4236': 'Bananas, red',
    '4885': 'Basil',
    '4887': 'Basil, sweet',
    '4536': 'Bean sprouts',
    '4535': 'Beans',
    '4539': 'Beet',
    '4540': 'Beet',
    '4541': 'Beet',
    '4252': 'Berries',
    '4244': 'Black Raspberries',
    '4239': 'Blackberries',
    '4240': 'Blueberries',
    '3082': 'Broccoli, Crowns',
    '4060': 'Broccoli',
    '4548': 'Broccoli',
    '4549': 'Broccoli',
    '4547': 'Broccoli Rabe',
    '4550': 'Brussels Sprout',
    '4551': 'Brussels Sprout',
    '4069': 'Cabbage, Green',
    '4552': 'Cabbage, Chinese',
    '4554': 'Cabbage, Red',
    '4555': 'Cabbage, Savoy, green',
    '4556': 'Cabbage',
    '4094': 'Carrots, bunched',
    '4560': 'Carrots, baby',
    '4562': 'Carrots',
    '4564': 'Carrots',
    '4079': 'Cauliflower',
    '4566': 'Cauliflower',
    '4569': 'Cauliflower',
    '4070': 'Celery',
    '4575': 'Celery, Hearts',
    '4577': 'Celery',
    '4585': 'Celery Root',
    '4888': 'Chives',
    '4889': 'Cilantro',
    '4614': 'Collards',
    '4242': 'Cranberries',
    '4062': 'Cucumber, Green',
    '4592': 'Cucumber, Armenian',
    '4593': 'Cucumber, English',
    '4594': 'Cucumber, Japanese',
    '4596': 'Cucumber, Pickling',
    '4597': 'Cucumber',
    '4891': 'Dill',
    '4515': 'Fennel',
    '4608': 'Garlic',
    '4609': 'Garlic, Elephant',
    '4610': 'Garlic',
    '4613': 'Ginger',
    '4612': 'Ginger root',
    '4245': 'Golden Raspberries',
    '4027': 'Grapefruit, Ruby',
    '4047': 'Grapefruit, Ruby',
    '4280': 'Grapefruit, Ruby',
    '4281': 'Grapefruit, Ruby',
    '4284': 'Grapefruit, Deep Red',
    '4287': 'Grapefruit, Deep Red',
    '4290': 'Grapefruit, White',
    '4293': 'Grapefruit, White',
    '4296': 'Grapefruit',
    '4022': 'Grapes, white seedless',
    '4023': 'Grapes, red seedless',
    '4056': 'Grapes, blue seedless',
    '4270': 'Grapes, blue',
    '4272': 'Grapes, Concord',
    '4274': 'Grapes, white',
    '4275': 'Grapes',
    '4497': 'Grapes, Sugraone',
    '4498': 'Grapes, white seedless',
    '4499': 'Grapes, Crimson',
    '4635': 'Grapes, red seedless',
    '4636': 'Grapes, Red Globe',
    '4638': 'Grapes, Fantasy',
    '4066': 'Green beans',
    '4620': 'Greens',
    '4627': 'Kale',
    '4030': 'Kiwifruit',
    '4301': 'Kiwifruit',
    '4894': 'Lemon Grass',
    '4033': 'Lemons',
    '4053': 'Lemons',
    '4304': 'Lemons',
    '4958': 'Lemons',
    '4061': 'Lettuce, Iceberg',
    '4075': 'Lettuce, Red Leaf',
    '4076': 'Lettuce, Green Leaf',
    '4631': 'Lettuce, Bibb',
    '4632': 'Lettuce, Boston',
    '4634': 'Lettuce, Iceberg',
    '4639': 'Lettuce, Mache',
    '4640': 'Lettuce, Romaine',
    '4641': 'Lettuce',
    '4529': 'Lima beans',
    '4048': 'Limes',
    '4305': 'Limes, key',
    '4306': 'Limes',
    '4051': 'Mango, Red',
    '4311': 'Mango, Green',
    '4312': 'Mango, Yellow',
    '4313': 'Mango',
    '4959': 'Mango, Red',
    '4895': 'Marjoram',
    '4034': 'Melon, Honeydew',
    '4049': 'Melon, Cantaloupe',
    '4050': 'Melon, Cantaloupe',
    '4317': 'Melon, Canary',
    '4318': 'Melon, Cantaloupe',
    '4319': 'Melon, Cantaloupe',
    '4326': 'Melon, Galia',
    '4329': 'Melon, Honeydew',
    '4896': 'Mint',
    '4085': 'Mushroom',
    '4645': 'Mushroom, button',
    '4646': 'Mushroom, Black Forest',
    '4648': 'Mushroom, Cremini',
    '4649': 'Mushroom, Oyster',
    '4650': 'Mushroom, Portabella',
    '4651': 'Mushroom, Shiitake',
    '4653': 'Mushroom',
    '4616': 'Mustard',
    '4035': 'Nectarine, Yellow Flesh',
    '4036': 'Nectarine, Yellow Flesh',
    '4379': 'Nectarine',
    '4068': 'Onion, Green',
    '4082': 'Onion, Red',
    '4093': 'Onion, Yellow',
    '4159': 'Onion, Vidalia',
    '4658': 'Onion, Boiling',
    '4660': 'Onion, Pearl',
    '4662': 'Onion, Shallots',
    '4663': 'Onion, White',
    '4665': 'Onion, Yellow',
    '4666': 'Onion',
    '4012': 'Orange, Navel',
    '4013': 'Orange, Navel',
    '4014': 'Orange, Valencia',
    '4381': 'Orange, Blood',
    '4382': 'Orange, Juice',
    '4383': 'Orange, Tangelo Minneola',
    '4384': 'Orange, Navel',
    '4385': 'Orange, Navel',
    '4388': 'Orange, Valencia',
    '4897': 'Oregano',
    '4909': 'Other Herbs',
    '4052': 'Papaya',
    '4394': 'Papaya',
    '4396': 'Papaya',
    '4899': 'Parsley',
    '4901': 'Parsley, Italian',
    '4037': 'Peach, Yellow Flesh',
    '4038': 'Peach, Yellow Flesh',
    '4400': 'Peach, White Flesh',
    '4401': 'Peach, White Flesh',
    '4402': 'Peach, Yellow Flesh',
    '4403': 'Peach, Yellow Flesh',
    '4404': 'Peach',
    '4024': 'Pear, Bartlett',
    '4025': 'Pear, d\'Anjou',
    '4026': 'Pear, Bosc',
    '4406': 'Pear, Asian, white',
    '4408': 'Pear, Asian',
    '4409': 'Pear, Bartlett',
    '4411': 'Pear, Bosc',
    '4414': 'Pear, Comice',
    '4416': 'Pear, d\'Anjou',
    '4425': 'Pear',
    '4065': 'Pepper, Bell',
    '4681': 'Pepper, Bell, green',
    '4682': 'Pepper, Bell, orange',
    '4684': 'Pepper, Bell, white',
    '4686': 'Pepper, Chili, green',
    '4688': 'Pepper, Bell, red',
    '4689': 'Pepper, Bell, yellow',
    '4690': 'Pepper, Hot',
    '4692': 'Pepper, Hungarian Wax',
    '4693': 'Pepper, Jalapeno',
    '4694': 'Pepper, Jalapeno, red',
    '4705': 'Pepper, Poblano',
    '4709': 'Pepper, Serrano',
    '4710': 'Pepper',
    '4029': 'Pineapple',
    '4430': 'Pineapple',
    '4433': 'Pineapple',
    '4235': 'Plantains',
    '4039': 'Plum, Black',
    '4041': 'Plum, Red',
    '4443': 'Plum',
    '4530': 'Pole beans',
    '3128': 'Potato, purple',
    '4072': 'Potato, Russet',
    '4073': 'Potato, red',
    '4074': 'Potato, Sweet Potato, redflesh',
    '4083': 'Potato, white',
    '4091': 'Potato, Sweet Potato, white',
    '4723': 'Potato, Creamer, red',
    '4724': 'Potato, Creamer, white',
    '4725': 'Potato, Russet',
    '4727': 'Potato, yellow',
    '4728': 'Potato',
    '4816': 'Potato, Sweet Potato',
    '4817': 'Potato, Sweet Potato',
    '4818': 'Potato, Yam',
    '4089': 'Radish, Bunched, red',
    '4598': 'Radish, Daikon',
    '4742': 'Radish, Red',
    '4744': 'Radish',
    '4054': 'Raspberries, red',
    '4903': 'Rosemary',
    '4904': 'Sage',
    '3332': 'Spinach',
    '4090': 'Spinach',
    '4749': 'Spinach',
    '4067': 'Squash, Zucchini',
    '4086': 'Squash, Yellow Zucchini',
    '4750': 'Squash, Acorn',
    '4758': 'Squash, Buttercup',
    '4759': 'Squash, Butternut',
    '4761': 'Squash, Chayote',
    '4769': 'Squash, Kabocha',
    '4776': 'Squash, Spaghetti',
    '4785': 'Squash',
    '4077': 'Sweet corn, white',
    '4078': 'Sweet corn, yellow',
    '4589': 'Sweet corn, baby',
    '4590': 'Sweet corn, bicolour',
    '4591': 'Sweet corn',
    '4055': 'Tangerine',
    '4449': 'Tangerine, Sunburst',
    '4450': 'Tangerine, Clementine',
    '4451': 'Tangerine, Dancy',
    '4453': 'Tangerine, Honey',
    '4455': 'Tangerine, Mandarin',
    '4456': 'Tangerine, Tangelo',
    '4906': 'Tarragon',
    '4907': 'Thyme',
    '3061': 'Tomato, Beef',
    '3423': 'Tomato, Heirloom',
    '4063': 'Tomato, red',
    '4064': 'Tomato',
    '4087': 'Tomato, Plum',
    '4778': 'Tomato, yellow',
    '4796': 'Tomato, Cherry, red',
    '4797': 'Tomato, Cherry, yellow',
    '4798': 'Tomato, Greenhouse',
    '4799': 'Tomato, Greenhouse',
    '4801': 'Tomato, Tomatillos',
    '4803': 'Tomato, Teardrop',
    '4806': 'Tomato',
    '4664': 'Tomatoes, on the vine',
    '4805': 'Tomatoes, vine ripened',
    '4619': 'Turnip',
    '4031': 'Watermelon',
    '4032': 'Watermelon, seedless',
    '4340': 'Watermelon, yellow',
    '4533': 'Wax beans',
  };
}
