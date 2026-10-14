import Foundation

struct FoodDatabase {
    static let all: [FoodItem] = protein + carbs + fats + vegetables + dairy + fruits + other + extras + additions

    // MARK: - Protein
    static let protein: [FoodItem] = [
        food("chicken_breast",   "Chicken Breast (raw)",      .protein,    120, 22.5, 0.0,  2.6),
        food("eggs_whole",       "Eggs (whole)",         .protein,    155, 13.0, 1.1, 11.0),
        food("egg_whites",       "Egg Whites",           .protein,     52, 11.0, 0.7,  0.2),
        food("tuna_canned",      "Tuna (canned)",        .protein,    116, 26.0, 0.0,  1.0),
        food("salmon",           "Salmon (raw)",               .protein,    208, 20.0, 0.0, 13.0),
        food("ground_beef_lean", "Ground Beef, lean (raw)",   .protein,    176, 20.0, 0.0, 10.0),
        food("turkey_breast",    "Turkey Breast (raw)",        .protein,    114, 23.7, 0.0,  1.5),
        food("shrimp",           "Shrimp",               .protein,     99, 24.0, 0.2,  0.3),
        food("whey_protein",     "Whey Protein",         .protein,    370, 75.0, 8.0,  4.0),
        food("tofu",             "Tofu",                 .protein,     76,  8.0, 1.9,  4.8),
    ]

    // MARK: - Carbs
    static let carbs: [FoodItem] = [
        food("white_rice",       "White Rice (cooked)",  .carbs,      130,  2.7, 28.0,  0.3),
        food("oats",             "Oats (dry)",                 .carbs,      389, 17.0, 66.0,  7.0),
        food("sweet_potato",     "Sweet Potato (baked)",         .carbs,       86,  1.6, 20.0,  0.1),
        food("whole_bread",      "Whole Wheat Bread",    .carbs,      247, 13.0, 41.0,  4.2),
        food("pasta_cooked",     "Pasta (cooked)",       .carbs,      158,  5.8, 31.0,  0.9),
        food("quinoa_cooked",    "Quinoa (cooked)",      .carbs,      120,  4.4, 21.0,  1.9),
        food("potato",           "Potato (boiled)",               .carbs,       77,  2.0, 17.0,  0.1),
        food("corn",             "Corn (cooked)",                 .carbs,       86,  3.3, 19.0,  1.4),
    ]

    // MARK: - Fats
    static let fats: [FoodItem] = [
        food("avocado",          "Avocado",              .fats,       160,  2.0,  9.0, 15.0),
        food("almonds",          "Almonds",              .fats,       579, 21.0, 22.0, 50.0),
        food("peanut_butter",    "Peanut Butter",        .fats,       588, 25.0, 20.0, 50.0),
        food("olive_oil",        "Olive Oil",            .fats,       884,  0.0,  0.0,100.0),
        food("walnuts",          "Walnuts",              .fats,       654, 15.0, 14.0, 65.0),
        food("cashews",          "Cashews",              .fats,       553, 18.0, 30.0, 44.0),
    ]

    // MARK: - Vegetables
    static let vegetables: [FoodItem] = [
        food("broccoli",         "Broccoli",             .vegetables,  34,  2.8,  7.0,  0.4),
        food("spinach",          "Spinach",              .vegetables,  23,  2.9,  3.6,  0.4),
        food("mixed_salad",      "Mixed Salad",          .vegetables,  20,  1.5,  3.0,  0.3),
        food("bell_pepper",      "Bell Pepper",          .vegetables,  31,  1.0,  6.0,  0.3),
        food("cucumber",         "Cucumber",             .vegetables,  16,  0.7,  3.6,  0.1),
        food("tomato",           "Tomato",               .vegetables,  18,  0.9,  3.9,  0.2),
        food("zucchini",         "Zucchini",             .vegetables,  17,  1.2,  3.1,  0.3),
    ]

    // MARK: - Dairy
    static let dairy: [FoodItem] = [
        food("greek_yogurt",     "Greek Yogurt (0%)",    .dairy,       59, 10.0,  3.6,  0.4),
        food("cottage_cheese",   "Cottage Cheese",       .dairy,       98, 11.0,  3.4,  4.3),
        food("milk_whole",       "Whole Milk",           .dairy,       61,  3.2,  4.8,  3.3),
        food("milk_skim",        "Skim Milk",            .dairy,       35,  3.4,  5.0,  0.1),
        food("mozzarella",       "Mozzarella",           .dairy,      280, 28.0,  2.2, 17.0),
        food("cheddar",          "Cheddar",              .dairy,      402, 25.0,  1.3, 33.0),
    ]

    // MARK: - Fruits
    static let fruits: [FoodItem] = [
        food("banana",           "Banana",               .fruits,      89,  1.1, 23.0,  0.3),
        food("apple",            "Apple",                .fruits,      52,  0.3, 14.0,  0.2),
        food("blueberries",      "Blueberries",          .fruits,      57,  0.7, 14.0,  0.3),
        food("orange",           "Orange",               .fruits,      47,  0.9, 12.0,  0.1),
        food("strawberries",     "Strawberries",         .fruits,      32,  0.7,  7.7,  0.3),
        food("mango",            "Mango",                .fruits,      60,  0.8, 15.0,  0.4),
    ]

    // MARK: - Other
    static let other: [FoodItem] = [
        food("protein_bar",      "Protein Bar",          .other,      340, 20.0, 40.0, 10.0),
        food("dark_chocolate",   "Dark Chocolate 70%",   .other,      598,  8.0, 46.0, 43.0),
        food("honey",            "Honey",                .other,      304,  0.3, 82.0,  0.0),
        food("granola",          "Granola",              .other,      489,  9.0, 64.0, 22.0),
    ]

    // MARK: - Extras (+40 foods)

    static let extras: [FoodItem] = [
        // More protein
        food("cod",               "Cod",                  .protein,     82, 18.0,  0.0,  0.7),
        food("tilapia",           "Tilapia",              .protein,    128, 26.0,  0.0,  2.7),
        food("pork_loin",         "Pork Loin (raw)",            .protein,    143, 26.0,  0.0,  4.0),
        food("edamame",           "Edamame",              .protein,    121, 11.0,  8.9,  5.2),
        food("tempeh",            "Tempeh",               .protein,    193, 19.0,  9.4, 11.0),
        food("sardines",          "Sardines (canned)",    .protein,    208, 25.0,  0.0, 11.0),
        // More carbs
        food("pasta_whole",       "Whole Wheat Pasta",    .carbs,      174,  7.5, 35.0,  1.4),
        food("cornmeal",          "Cornmeal (dry)",             .carbs,      362,  8.1, 77.0,  3.6),
        food("bagel",             "Bagel",                .carbs,      270, 10.0, 53.0,  1.7),
        food("pita_bread",        "Pita Bread",           .carbs,      275,  9.1, 55.0,  1.2),
        food("lentils",           "Lentils (cooked)",     .carbs,      116,  9.0, 20.0,  0.4),
        food("chickpeas",         "Chickpeas (cooked)",   .carbs,      164,  8.9, 27.0,  2.6),
        // More fats
        food("pumpkin_seeds",     "Pumpkin Seeds",        .fats,       446, 19.0, 54.0, 19.0),
        food("coconut_oil",       "Coconut Oil",          .fats,       862,  0.0,  0.0, 100.0),
        food("flaxseeds",         "Flaxseeds",            .fats,       534, 18.0, 29.0, 42.0),
        // More vegetables
        food("kale",              "Kale",                 .vegetables,  35,  2.9,  4.4,  0.5),
        food("mushrooms",         "Mushrooms",            .vegetables,  22,  3.1,  3.3,  0.3),
        food("asparagus",         "Asparagus",            .vegetables,  20,  2.2,  3.7,  0.1),
        food("peas",              "Green Peas (cooked)",           .vegetables,  81,  5.4, 14.0,  0.4),
        food("celery",            "Celery",               .vegetables,  16,  0.7,  3.0,  0.2),
        food("beets",             "Beets",                .vegetables,  43,  1.6,  9.6,  0.2),
        // More dairy
        food("butter",            "Butter",               .dairy,      717,  0.9,  0.1, 81.0),
        food("cream_cheese",      "Cream Cheese",         .dairy,      342,  6.0,  4.1, 34.0),
        // More fruits
        food("watermelon",        "Watermelon",           .fruits,      30,  0.6,  7.6,  0.2),
        food("grapes",            "Grapes",               .fruits,      67,  0.6, 17.0,  0.4),
        food("kiwi",              "Kiwi",                 .fruits,      61,  1.1, 15.0,  0.5),
        food("pineapple",         "Pineapple",            .fruits,      50,  0.5, 13.0,  0.1),
        food("peach",             "Peach",                .fruits,      39,  0.9,  9.5,  0.3),
        // More other
        food("rice_cakes",        "Rice Cakes",           .other,      387,  8.0, 81.0,  3.5),
        food("peanut_butter_pb",  "Peanut Butter",        .other,      588, 25.0, 20.0, 50.0),
        food("hummus",            "Hummus",               .other,      166,  8.0, 14.0,  9.6),
        food("tortilla_wrap",     "Tortilla Wrap",        .other,      300,  7.5, 54.0,  6.0),
        food("sports_drink",      "Sports Drink",         .other,       21,  0.0,  5.2,  0.0),
    ]

    // MARK: - Additions (missing common foods)

    static let additions: [FoodItem] = [
        // protein
        food("beef_steak", "Beef Steak (raw)", .protein, 190, 21, 0, 12),
        food("chicken_thigh", "Chicken Thigh (raw)", .protein, 121, 19.7, 0, 4.1),
        food("bacon", "Bacon", .protein, 541, 37, 1.4, 42),
        food("ham", "Ham", .protein, 145, 21, 1.5, 6),
        food("cured_ham", "Cured Ham", .protein, 241, 31, 0.3, 13),
        food("sausage", "Sausage", .protein, 301, 15, 2, 27),
        food("ground_turkey", "Ground Turkey", .protein, 203, 27, 0, 10),
        food("pork_chop", "Pork Chop", .protein, 231, 26, 0, 14),
        food("mackerel", "Mackerel", .protein, 205, 19, 0, 14),
        food("crab", "Crab", .protein, 97, 19, 0, 1.5),
        food("octopus", "Octopus", .protein, 82, 15, 2.2, 1),
        food("lamb", "Lamb", .protein, 258, 25, 0, 17),
        food("black_beans", "Black Beans (cooked)", .protein, 132, 8.9, 24, 0.5),
        food("kidney_beans", "Kidney Beans (cooked)", .protein, 127, 8.7, 23, 0.5),
        food("pinto_beans", "Pinto Beans (cooked)", .protein, 143, 9, 26, 0.7),
        food("seitan", "Seitan", .protein, 141, 25, 6, 2),
        food("pea_protein", "Pea Protein", .protein, 380, 80, 3, 6),
        food("casein_protein", "Casein Protein", .protein, 360, 78, 5, 1.5),
        food("ricotta", "Ricotta", .protein, 174, 11, 3, 13),
        food("deli_turkey", "Deli Turkey", .protein, 104, 17, 4, 2),
        // carbs
        food("brown_rice", "Brown Rice (cooked)", .carbs, 123, 2.7, 26, 1),
        food("basmati_rice", "Basmati Rice (cooked)", .carbs, 121, 3.5, 25, 0.4),
        food("couscous", "Couscous (cooked)", .carbs, 112, 3.8, 23, 0.2),
        food("bulgur", "Bulgur (cooked)", .carbs, 83, 3.1, 19, 0.2),
        food("white_bread", "White Bread", .carbs, 265, 9, 49, 3.2),
        food("english_muffin", "English Muffin", .carbs, 227, 8, 44, 1.8),
        food("corn_tortilla", "Corn Tortilla", .carbs, 218, 5.7, 45, 2.9),
        food("flour_tortilla", "Flour Tortilla", .carbs, 304, 8, 51, 7.5),
        food("ramen_instant", "Ramen (instant)", .carbs, 448, 10, 63, 17),
        food("rice_noodles", "Rice Noodles (cooked)", .carbs, 108, 1.8, 25, 0.2),
        food("corn_flakes", "Corn Flakes", .carbs, 357, 7, 84, 0.4),
        food("crackers", "Crackers", .carbs, 439, 9, 71, 13),
        food("pretzels", "Pretzels", .carbs, 380, 10, 80, 3),
        food("popcorn", "Popcorn", .carbs, 387, 13, 78, 4.5),
        food("plantain", "Plantain", .carbs, 122, 1.3, 32, 0.4),
        food("cassava", "Cassava (yuca)", .carbs, 160, 1.4, 38, 0.3),
        food("yam", "Yam", .carbs, 118, 1.5, 28, 0.2),
        food("barley", "Barley (cooked)", .carbs, 123, 2.3, 28, 0.4),
        food("rye_bread", "Rye Bread", .carbs, 259, 8.5, 48, 3.3),
        food("sourdough", "Sourdough Bread", .carbs, 289, 12, 56, 1.9),
        food("naan", "Naan", .carbs, 310, 9, 52, 6.5),
        food("french_fries", "French Fries", .carbs, 312, 3.4, 41, 15),
        food("gnocchi", "Gnocchi", .carbs, 133, 3.5, 27, 1.2),
        food("farro", "Farro (cooked)", .carbs, 130, 3.5, 26, 0.9),
        // fats
        food("peanuts", "Peanuts", .fats, 567, 26, 16, 49),
        food("pistachios", "Pistachios", .fats, 560, 20, 28, 45),
        food("pecans", "Pecans", .fats, 691, 9, 14, 72),
        food("macadamia", "Macadamia Nuts", .fats, 718, 8, 14, 76),
        food("hazelnuts", "Hazelnuts", .fats, 628, 15, 17, 61),
        food("chia_seeds", "Chia Seeds", .fats, 486, 17, 42, 31),
        food("sunflower_seeds", "Sunflower Seeds", .fats, 584, 21, 20, 51),
        food("tahini", "Tahini", .fats, 595, 17, 21, 54),
        food("almond_butter", "Almond Butter", .fats, 614, 21, 19, 56),
        food("sesame_seeds", "Sesame Seeds", .fats, 573, 18, 23, 50),
        food("egg_yolk", "Egg Yolk", .fats, 322, 16, 3.6, 27),
        food("ghee", "Ghee", .fats, 900, 0, 0, 100),
        food("avocado_oil", "Avocado Oil", .fats, 884, 0, 0, 100),
        food("sunflower_oil", "Sunflower Oil", .fats, 884, 0, 0, 100),
        // vegetables
        food("carrot", "Carrot", .vegetables, 41, 0.9, 10, 0.2),
        food("green_beans", "Green Beans", .vegetables, 31, 1.8, 7, 0.2),
        food("cauliflower", "Cauliflower", .vegetables, 25, 1.9, 5, 0.3),
        food("brussels_sprouts", "Brussels Sprouts", .vegetables, 43, 3.4, 9, 0.3),
        food("cabbage", "Cabbage", .vegetables, 25, 1.3, 6, 0.1),
        food("lettuce", "Lettuce", .vegetables, 15, 1.4, 2.9, 0.2),
        food("onion", "Onion", .vegetables, 40, 1.1, 9, 0.1),
        food("garlic", "Garlic", .vegetables, 149, 6.4, 33, 0.5),
        food("eggplant", "Eggplant", .vegetables, 25, 1, 6, 0.2),
        food("pumpkin", "Pumpkin", .vegetables, 26, 1, 6.5, 0.1),
        food("radish", "Radish", .vegetables, 16, 0.7, 3.4, 0.1),
        food("leek", "Leek", .vegetables, 61, 1.5, 14, 0.3),
        food("artichoke", "Artichoke", .vegetables, 47, 3.3, 11, 0.2),
        food("okra", "Okra", .vegetables, 33, 1.9, 7, 0.2),
        food("arugula", "Arugula", .vegetables, 25, 2.6, 3.7, 0.7),
        food("swiss_chard", "Swiss Chard", .vegetables, 19, 1.8, 3.7, 0.2),
        food("green_onion", "Green Onion", .vegetables, 32, 1.8, 7.3, 0.2),
        food("turnip", "Turnip", .vegetables, 28, 0.9, 6.4, 0.1),
        // fruits
        food("pear", "Pear", .fruits, 57, 0.4, 15, 0.1),
        food("cherries", "Cherries", .fruits, 63, 1.1, 16, 0.2),
        food("raspberries", "Raspberries", .fruits, 52, 1.2, 12, 0.7),
        food("blackberries", "Blackberries", .fruits, 43, 1.4, 10, 0.5),
        food("plum", "Plum", .fruits, 46, 0.7, 11, 0.3),
        food("apricot", "Apricot", .fruits, 48, 1.4, 11, 0.4),
        food("pomegranate", "Pomegranate", .fruits, 83, 1.7, 19, 1.2),
        food("grapefruit", "Grapefruit", .fruits, 42, 0.8, 11, 0.1),
        food("lemon", "Lemon", .fruits, 29, 1.1, 9, 0.3),
        food("lime", "Lime", .fruits, 30, 0.7, 11, 0.2),
        food("cantaloupe", "Cantaloupe", .fruits, 34, 0.8, 8, 0.2),
        food("papaya", "Papaya", .fruits, 43, 0.5, 11, 0.3),
        food("guava", "Guava", .fruits, 68, 2.6, 14, 1),
        food("fig", "Fig", .fruits, 74, 0.8, 19, 0.3),
        food("dates", "Dates", .fruits, 282, 2.5, 75, 0.4),
        food("raisins", "Raisins", .fruits, 299, 3.1, 79, 0.5),
        food("cranberries", "Cranberries", .fruits, 46, 0.4, 12, 0.1),
        food("mandarin", "Mandarin", .fruits, 53, 0.8, 13, 0.3),
        food("nectarine", "Nectarine", .fruits, 44, 1.1, 11, 0.3),
        food("passion_fruit", "Passion Fruit", .fruits, 97, 2.2, 23, 0.7),
        // dairy
        food("plain_yogurt", "Plain Yogurt", .dairy, 61, 3.5, 4.7, 3.3),
        food("greek_yogurt_whole", "Greek Yogurt (whole)", .dairy, 97, 9, 4, 5),
        food("kefir", "Kefir", .dairy, 41, 3.3, 4.5, 1),
        food("parmesan", "Parmesan", .dairy, 431, 38, 4.1, 29),
        food("feta", "Feta", .dairy, 264, 14, 4.1, 21),
        food("swiss_cheese", "Swiss Cheese", .dairy, 393, 27, 5, 31),
        food("provolone", "Provolone", .dairy, 351, 26, 2.1, 27),
        food("gouda", "Gouda", .dairy, 356, 25, 2.2, 27),
        food("sour_cream", "Sour Cream", .dairy, 198, 2.4, 4.6, 19),
        food("heavy_cream", "Heavy Cream", .dairy, 340, 2.8, 2.8, 36),
        food("almond_milk", "Almond Milk", .dairy, 15, 0.6, 0.6, 1.2),
        food("soy_milk", "Soy Milk", .dairy, 43, 3.3, 3, 1.8),
        food("oat_milk", "Oat Milk", .dairy, 47, 1, 7, 1.5),
        food("ice_cream", "Ice Cream", .dairy, 207, 3.5, 24, 11),
        food("goat_cheese", "Goat Cheese", .dairy, 364, 22, 0.1, 30),
        food("blue_cheese", "Blue Cheese", .dairy, 353, 21, 2.3, 29),
        // other
        food("coffee", "Coffee (black)", .other, 1, 0.1, 0, 0),
        food("espresso", "Espresso", .other, 9, 0.1, 1.7, 0.2),
        food("tea", "Tea (unsweetened)", .other, 1, 0, 0.3, 0),
        food("latte", "Latte", .other, 56, 3, 5, 3),
        food("orange_juice", "Orange Juice", .other, 45, 0.7, 10, 0.2),
        food("apple_juice", "Apple Juice", .other, 46, 0.1, 11, 0.1),
        food("cola", "Cola", .other, 42, 0, 11, 0),
        food("coconut_water", "Coconut Water", .other, 19, 0.7, 3.7, 0.2),
        food("beer", "Beer", .other, 43, 0.5, 3.6, 0),
        food("wine_red", "Red Wine", .other, 85, 0.1, 2.6, 0),
        food("energy_drink", "Energy Drink", .other, 45, 0, 11, 0),
        food("water", "Water", .other, 0, 0, 0, 0),
        food("ketchup", "Ketchup", .other, 112, 1.3, 26, 0.4),
        food("mustard", "Mustard", .other, 66, 4.4, 5, 4),
        food("mayonnaise", "Mayonnaise", .other, 680, 1, 0.6, 75),
        food("soy_sauce", "Soy Sauce", .other, 53, 8, 4.9, 0.1),
        food("sriracha", "Sriracha", .other, 93, 1.9, 19, 0.9),
        food("bbq_sauce", "BBQ Sauce", .other, 172, 0.8, 41, 0.6),
        food("salsa", "Salsa", .other, 36, 1.5, 7, 0.2),
        food("ranch_dressing", "Ranch Dressing", .other, 430, 1, 6, 45),
        food("jam", "Jam", .other, 278, 0.4, 69, 0.1),
        food("maple_syrup", "Maple Syrup", .other, 260, 0, 67, 0.1),
        food("sugar", "Sugar", .other, 387, 0, 100, 0),
        food("brown_sugar", "Brown Sugar", .other, 380, 0, 98, 0),
        food("olives", "Olives", .other, 115, 0.8, 6, 11),
        food("pickles", "Pickles", .other, 11, 0.3, 2.3, 0.2),
        food("potato_chips", "Potato Chips", .other, 536, 7, 53, 35),
        food("cookies", "Cookies", .other, 480, 5, 64, 24),
        food("nutella", "Choc-Hazelnut Spread", .other, 539, 6, 58, 31),
        // Fresh variants & common extras
        food("fresh_tuna", "Tuna Steak (raw)", .protein, 144, 23, 0, 5),
        food("hake", "Hake", .protein, 90, 18, 0, 1.3),
        food("sea_bass", "Sea Bass", .protein, 97, 18, 0, 2),
        food("trout", "Trout", .protein, 148, 21, 0, 7),
        food("anchovies", "Anchovies", .protein, 131, 20, 0, 5),
        food("chorizo", "Chorizo", .protein, 455, 24, 2, 38),
        food("meatballs", "Meatballs", .protein, 240, 18, 6, 16),
        food("liver", "Liver", .protein, 175, 27, 4, 5),
        food("rabbit", "Rabbit", .protein, 173, 33, 0, 3.5),
        food("duck", "Duck", .protein, 337, 19, 0, 28),
        food("chicken_whole", "Chicken (whole)", .protein, 239, 27, 0, 14),
        food("chicken_wings", "Chicken Wings", .protein, 203, 30, 0, 8),
        food("queso_fresco", "Fresh Cheese", .dairy, 140, 12, 3, 9),
        food("manchego", "Manchego", .dairy, 464, 26, 0.1, 39),
        food("flavored_yogurt", "Flavored Yogurt", .dairy, 95, 3.5, 15, 2),
        food("arepa", "Arepa", .carbs, 219, 4, 45, 2),
        food("fried_plantain", "Fried Plantain", .carbs, 152, 1, 28, 4),
        food("empanada", "Empanada", .carbs, 280, 8, 30, 14),
        food("coconut", "Coconut", .fruits, 354, 3.3, 15, 33),
        food("tamarind", "Tamarind", .fruits, 239, 2.8, 63, 0.6),
        food("chili_pepper", "Chili Pepper", .vegetables, 40, 1.9, 9, 0.4),
        food("pizza", "Pizza", .other, 266, 11, 33, 10),
        food("hamburger", "Hamburger", .other, 295, 17, 24, 14),
        food("hot_dog", "Hot Dog", .other, 290, 10, 4, 26),
        // Preparation forms (raw/cooked/fried) so macros are accurate
        food("egg_boiled", "Egg (boiled)", .protein, 155, 13, 1.1, 11),
        food("egg_fried", "Egg (fried)", .protein, 196, 14, 0.8, 15),
        food("egg_scrambled", "Eggs (scrambled)", .protein, 149, 10, 1.6, 11),
        food("chicken_grilled", "Chicken Breast (grilled)", .protein, 195, 30, 0, 4.3),
        food("chicken_fried", "Chicken (fried, breaded)", .protein, 274, 23, 10, 16),
        food("chicken_roasted", "Chicken (roasted)", .protein, 190, 29, 0, 7.4),
        food("oats_cooked", "Oats (cooked)", .carbs, 71, 2.5, 12, 1.4),
        food("smoked_salmon", "Smoked Salmon", .protein, 117, 18, 0, 4.3),
        food("salmon_cooked", "Salmon (cooked)", .protein, 206, 22, 0, 12),
        food("tuna_steak_cooked", "Tuna Steak (cooked)", .protein, 184, 30, 0, 6.3),
        food("fish_breaded", "Fish (breaded, fried)", .protein, 232, 13, 17, 12),
        food("beef_steak_cooked", "Beef Steak (cooked)", .protein, 271, 31, 0, 16),
        food("ground_beef_cooked", "Ground Beef (cooked)", .protein, 250, 26, 0, 15),
        food("pork_cooked", "Pork Loin (cooked)", .protein, 242, 28, 0, 14),
        food("potato_baked", "Potato (baked)", .carbs, 93, 2.5, 21, 0.1),
        food("mashed_potato", "Mashed Potato", .carbs, 113, 2, 17, 4.2),
        food("potato_raw", "Potato (raw)", .carbs, 77, 2, 17, 0.1),
        food("sweet_potato_boiled", "Sweet Potato (boiled)", .carbs, 76, 1.4, 18, 0.1),
        food("white_rice_dry", "White Rice (dry)", .carbs, 365, 7, 80, 0.7),
        food("pasta_dry", "Pasta (dry)", .carbs, 371, 13, 75, 1.5),
        food("toast", "Toast", .carbs, 313, 10, 58, 4),
        food("baguette", "Baguette", .carbs, 274, 9, 53, 2.6),
        food("croissant", "Croissant", .carbs, 406, 8, 46, 21),
        food("cappuccino", "Cappuccino", .other, 37, 2, 3, 1.8),
        food("coffee_milk_skim", "Coffee w/ Skim Milk", .other, 22, 1.9, 2.8, 0.2),
        food("milk_semi", "Semi-Skimmed Milk", .dairy, 47, 3.4, 4.8, 1.6),
        food("lactose_free_milk", "Lactose-Free Milk", .dairy, 42, 3.4, 4.8, 1.5),
        food("broccoli_cooked", "Broccoli (cooked)", .vegetables, 35, 2.4, 7.2, 0.4),
        food("spinach_cooked", "Spinach (cooked)", .vegetables, 23, 3, 3.8, 0.3),
        food("carrot_cooked", "Carrot (cooked)", .vegetables, 35, 0.8, 8.2, 0.2),
        food("lentils_dry", "Lentils (dry)", .carbs, 352, 25, 63, 1.1),
        food("black_beans_dry", "Black Beans (dry)", .protein, 341, 21, 62, 1.4),
    ]
    // MARK: - Helper

    private static func food(_ id: String, _ name: String, _ cat: FoodCategory,
                              _ kcal: Double, _ p: Double, _ c: Double, _ f: Double) -> FoodItem {
        FoodItem(id: id, name: name, category: cat,
                 per100g: NutritionInfo(calories: kcal, protein: p, carbs: c, fat: f))
    }

    static func search(_ query: String) -> [FoodItem] {
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || NSLocalizedString($0.name, comment: "")
                .range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
