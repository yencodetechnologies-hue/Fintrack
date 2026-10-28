import 'dart:convert';
import 'package:http/http.dart' as http;

class BrandModelService {
  // Comprehensive Indian & Global Motorcycle / Bike Brands & Models
  static final Map<String, List<String>> _bikeSeedData = {
    "Hero MotoCorp": [
      "Splendor Plus",
      "Splendor Xtec",
      "HF Deluxe",
      "Passion Pro",
      "Glamour",
      "Xpulse 200 4V",
      "Xtreme 160R",
      "Xtreme 200S",
      "Maestro Edge",
      "Pleasure Plus",
      "Vida V1 (EV)",
      "Karizma XMR",
    ],
    "Honda Motorcycles": [
      "Activa 6G",
      "Activa 125",
      "Shine 125",
      "SP 125",
      "Unicorn",
      "Dio",
      "CB350 H'ness",
      "CB350RS",
      "Hornet 2.0",
      "CB200X",
      "Livo",
      "Gold Wing",
    ],
    "Bajaj Auto": [
      "Pulsar 150",
      "Pulsar NS200",
      "Pulsar N160",
      "Pulsar N250",
      "Pulsar 220F",
      "Pulsar RS200",
      "Freedom 125 (CNG)",
      "Chetak (EV)",
      "Platina 110",
      "Dominar 400",
      "Dominar 250",
      "Avenger Cruise 220",
      "CT 110X",
    ],
    "TVS Motor": [
      "Jupiter 110",
      "Jupiter 125",
      "Apache RTR 160 4V",
      "Apache RTR 180",
      "Apache RTR 200 4V",
      "Apache RR 310",
      "Apache RTX 310",
      "iQube (EV)",
      "Raider 125",
      "Ntorq 125",
      "Radeon",
      "XL100",
      "Ronin 225",
    ],
    "Royal Enfield": [
      "Classic 350",
      "Hunter 350",
      "Bullet 350",
      "Meteor 350",
      "Himalayan 450",
      "Continental GT 650",
      "Interceptor 650",
      "Shotgun 650",
      "Super Meteor 650",
      "Scram 411",
    ],
    "Yamaha": [
      "FZ-S V4",
      "FZ-FI",
      "MT-15 V2",
      "YZF R15 V4",
      "R15M",
      "RayZR 125",
      "Fascino 125",
      "Aerox 155",
      "FZ-X",
    ],
    "Suzuki": [
      "Access 125",
      "Burgman Street",
      "Gixxer 150",
      "Gixxer SF 250",
      "V-Strom SX",
      "Hayabusa",
      "Avenis 125",
    ],
    "KTM": [
      "Duke 200",
      "Duke 250",
      "Duke 390",
      "RC 125",
      "RC 200",
      "RC 390",
      "Adventure 250",
      "Adventure 390",
    ],
    "Ather Energy": [
      "450X",
      "450S",
      "450 Apex",
      "Rizta",
    ],
    "Ola Electric": [
      "S1 Pro",
      "S1 Air",
      "S1 X",
      "S1 X+",
      "Roadster EV",
    ],
    "Revolt": [
      "RV400",
      "RV400 BRZ",
    ],
    "Kawasaki": [
      "Ninja 300",
      "Ninja 400",
      "Ninja 500",
      "Z900",
      "ZX-10R",
      "Versys 650",
    ],
    "BMW Motorrad": [
      "G 310 R",
      "G 310 GS",
      "G 310 RR",
      "S 1000 RR",
      "R 1250 GS",
    ],
  };

  // Comprehensive Indian & Global Car Brands & Models Database
  static final Map<String, List<String>> _carSeedData = {
    "Hyundai": [
      "Creta",
      "Creta N Line",
      "Venue",
      "Venue N Line",
      "i20",
      "i20 N Line",
      "Grand i10 Nios",
      "Verna",
      "Alcazar",
      "Exter",
      "Aura",
      "Tucson",
      "Ioniq 5 (EV)",
      "Kona Electric",
      "Santro",
      "Elantra",
    ],
    "Maruti Suzuki": [
      "Swift",
      "Baleno",
      "Brezza",
      "Dzire",
      "Ertiga",
      "Grand Vitara",
      "Fronx",
      "Jimny",
      "Alto K10",
      "WagonR",
      "Celerio",
      "Ignis",
      "XL6",
      "Invicto",
      "Ciaz",
      "S-Presso",
      "Eeco",
      "S-Cross",
    ],
    "Tata Motors": [
      "Nexon",
      "Nexon EV",
      "Punch",
      "Punch EV",
      "Harrier",
      "Safari",
      "Altroz",
      "Tiago",
      "Tiago EV",
      "Tigor",
      "Tigor EV",
      "Curvv",
      "Curvv EV",
      "Hexa",
    ],
    "Mahindra": [
      "Thar",
      "Thar Roxx",
      "XUV700",
      "Scorpio-N",
      "Scorpio Classic",
      "XUV3XO",
      "Bolero",
      "Bolero Neo",
      "XUV400 EV",
      "Marazzo",
      "XUV500",
      "Alturas G4",
    ],
    "Kia": [
      "Seltos",
      "Sonet",
      "Carens",
      "Carnival",
      "EV6 (Electric)",
      "EV9",
    ],
    "Toyota": [
      "Fortuner",
      "Fortuner Legender",
      "Innova Crysta",
      "Innova Hycross",
      "Urban Cruiser Hyryder",
      "Urban Cruiser Taisor",
      "Glanza",
      "Hilux",
      "Camry",
      "Vellfire",
      "Land Cruiser 300",
    ],
    "Honda": [
      "City",
      "City e:HEV (Hybrid)",
      "Elevate",
      "Amaze",
      "WR-V",
      "Jazz",
      "Civic",
      "CR-V",
    ],
    "Volkswagen": [
      "Virtus",
      "Taigun",
      "Tiguan",
      "Polo",
      "Vento",
      "Passat",
      "Golf",
    ],
    "Skoda": [
      "Slavia",
      "Kushaq",
      "Kodiaq",
      "Kylaq",
      "Octavia",
      "Superb",
    ],
    "MG Motor": [
      "Hector",
      "Hector Plus",
      "Astor",
      "ZS EV",
      "Comet EV",
      "Windsor EV",
      "Gloster",
    ],
    "Nissan": [
      "Magnite",
      "Kicks",
      "X-Trail",
      "Sunny",
      "GT-R",
    ],
    "Renault": [
      "Kiger",
      "Triber",
      "Kwid",
      "Duster",
    ],
    "Ford": [
      "Endeavour",
      "EcoSport",
      "Figo",
      "Aspire",
      "Freestyle",
      "Mustang",
    ],
    "Jeep": [
      "Compass",
      "Meridian",
      "Wrangler",
      "Grand Cherokee",
    ],
    "Citroen": [
      "C3",
      "C3 Aircross",
      "Basalt",
      "eC3 (EV)",
      "C5 Aircross",
    ],
    "BMW": [
      "3 Series (Gran Limousine)",
      "2 Series Gran Coupe",
      "5 Series",
      "7 Series",
      "X1",
      "X3",
      "X5",
      "X7",
      "M3",
      "M5",
      "i4 (EV)",
      "iX (EV)",
      "i7 (EV)",
    ],
    "Mercedes-Benz": [
      "C-Class",
      "E-Class",
      "S-Class",
      "GLA",
      "GLC",
      "GLE",
      "GLS",
      "G-Class (G63 AMG)",
      "A-Class Limousine",
      "EQE (EV)",
      "EQS (EV)",
    ],
    "Audi": [
      "A4",
      "A6",
      "A8L",
      "Q3",
      "Q5",
      "Q7",
      "Q8",
      "RS5",
      "e-tron (EV)",
    ],
    "Volvo": [
      "XC40 Recharge (EV)",
      "C40 Recharge (EV)",
      "XC60",
      "XC90",
      "S90",
    ],
    "Porsche": [
      "Macan",
      "Cayenne",
      "911",
      "Panamera",
      "Taycan (EV)",
      "718 Cayman",
    ],
    "Jaguar": [
      "F-PACE",
      "I-PACE (EV)",
      "F-TYPE",
    ],
    "Land Rover": [
      "Defender 90",
      "Defender 110",
      "Defender 130",
      "Range Rover Evoque",
      "Range Rover Velar",
      "Range Rover Sport",
      "Range Rover",
      "Discovery",
    ],
    "Tesla": [
      "Model 3",
      "Model Y",
      "Model S",
      "Model X",
      "Cybertruck",
    ],
    "Fiat": [
      "Punto",
      "Linea",
      "Abarth Punto",
      "Urban Cross",
    ],
    "Chevrolet": [
      "Beat",
      "Cruze",
      "Trailblazer",
      "Sail",
      "Enjoy",
    ],
    "Lexus": [
      "ES 300h",
      "NX 350h",
      "RX 350h",
      "LX 600",
      "LM 350h",
    ],
    "Aston Martin": ["DB12", "Vantage", "DBX 707"],
    "Ferrari": ["Roma", "296 GTB", "Purosangue", "SF90 Stradale"],
    "Lamborghini": ["Urus SE", "Revuelto", "Huracan Sterrato"],
    "Rolls-Royce": ["Ghost", "Phantom", "Spectre", "Cullinan"],
    "Bentley": ["Continental GT", "Flying Spur", "Bentayga"],
    "Maserati": ["Grecale", "Levante", "Ghibli", "GranTurismo"],
  };

  // 1. Fetch Brands based on Vehicle Type
  static Future<List<String>> fetchBrands(String vehicleType) async {
    if (vehicleType == "bike") {
      final list = _bikeSeedData.keys.toList();
      list.sort();
      return list;
    } else {
      final list = _carSeedData.keys.toList();
      list.sort();
      return list;
    }
  }

  // 2. Fetch Models based on Vehicle Type and Selected Brand
  static Future<List<String>> fetchModels(String vehicleType, String brand) async {
    if (brand.isEmpty) return [];

    if (vehicleType == "bike") {
      if (_bikeSeedData.containsKey(brand)) {
        final list = List<String>.from(_bikeSeedData[brand]!);
        list.sort();
        return list;
      }
      return ["Standard 125cc", "Standard 150cc", "Standard 200cc"];
    } else {
      final List<String> seedModels = _carSeedData[brand] ?? [];

      // Try fetching NHTSA API models as well to merge US/Global variants
      try {
        final encodedBrand = Uri.encodeComponent(brand);
        final res = await http
            .get(Uri.parse("https://vpic.nhtsa.dot.gov/api/vehicles/getmodelsformake/$encodedBrand?format=json"))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final results = data["Results"] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final apiModels = results.map((e) => e["Model_Name"].toString().trim()).toList();
            final combinedSet = <String>{...seedModels, ...apiModels};
            final list = combinedSet.toList();
            list.sort();
            return list;
          }
        }
      } catch (_) {}

      if (seedModels.isNotEmpty) {
        final list = List<String>.from(seedModels);
        list.sort();
        return list;
      }

      return [
        "Base Variant",
        "Mid Variant",
        "Top Variant (AT)",
        "EV Long Range",
      ];
    }
  }

  // 3. Smart Vehicle Specs & Fuel Filter Lookup
  static VehicleModelSpec getModelSpec(String vehicleType, String brand, String model) {
    final mLower = model.toLowerCase();
    final bLower = brand.toLowerCase();

    // A. Check Electric Vehicles (EVs): whole words only, so "Evoque", "Seven" or "Motorola" don't count
    bool word(String text, String w) => RegExp('(^|[^a-z0-9])${RegExp.escape(w)}(\$|[^a-z0-9])').hasMatch(text);
    const evModelWords = ["ev", "ev6", "ev9", "electric", "ioniq", "taycan", "e-tron", "etron", "ec3", "chetak", "iqube", "vida", "eqs", "eqb"];
    const evBrands = ["tesla", "ather", "ola", "ola electric", "revolt", "ultraviolette", "simple energy", "okinawa", "ampere", "byd"];
    final isEv = evModelWords.any((w) => word(mLower, w)) || evBrands.any((b) => word(bLower, b));

    if (isEv) {
      final isBikeEv = vehicleType == "bike" || ["ather", "ola", "revolt", "ultraviolette", "okinawa", "ampere"].any((b) => word(bLower, b));
      return VehicleModelSpec(
        capacity: isBikeEv ? 3.7 : 40.5,
        defaultMileage: isBikeEv ? 35.0 : 7.5,
        availableFuelTypes: ["electric"],
      );
    }

    // B. Check CNG Vehicles
    if (mLower.contains("cng") || mLower.contains("freedom")) {
      final isBikeCng = vehicleType == "bike" || mLower.contains("freedom");
      return VehicleModelSpec(
        capacity: isBikeCng ? 2.0 : 12.0,
        defaultMileage: isBikeCng ? 95.0 : 28.0,
        availableFuelTypes: ["cng", "petrol"],
      );
    }

    // C. Check Strong Hybrid Vehicles
    if (mLower.contains("hybrid") || mLower.contains("e:hev") || mLower.contains("hycross") || mLower.contains("hyryder") || mLower.contains("invicto")) {
      return const VehicleModelSpec(
        capacity: 45.0,
        defaultMileage: 23.5,
        availableFuelTypes: ["hybrid", "petrol"],
      );
    }

    // D. BIKES (Non-EV, Non-CNG) -> Petrol only (No Diesel)
    if (vehicleType == "bike") {
      double cap = 10.0;
      double mileage = 55.0;

      if (mLower.contains("activa") || mLower.contains("jupiter") || mLower.contains("dio") || mLower.contains("access") || mLower.contains("fascino") || mLower.contains("rayzr") || mLower.contains("pleasure") || mLower.contains("burgman")) {
        cap = 5.3;
        mileage = 48.0;
      } else if (mLower.contains("splendor") || mLower.contains("hf deluxe") || mLower.contains("shine") || mLower.contains("platina") || mLower.contains("passion")) {
        cap = 10.0;
        mileage = 65.0;
      } else if (mLower.contains("pulsar") || mLower.contains("apache") || mLower.contains("fz") || mLower.contains("mt-15") || mLower.contains("r15") || mLower.contains("gixxer")) {
        cap = 12.0;
        mileage = 42.0;
      } else if (bLower.contains("royal enfield") || mLower.contains("classic 350") || mLower.contains("dominar") || mLower.contains("himalayan") || bLower.contains("kawasaki") || bLower.contains("bmw")) {
        cap = 13.5;
        mileage = 32.0;
      }

      return VehicleModelSpec(
        capacity: cap,
        defaultMileage: mileage,
        availableFuelTypes: const ["petrol"],
      );
    }

    // E. CARS (Non-EV, Non-CNG, Non-Hybrid)
    double cap = 45.0;
    double mileage = 16.5;

    if (mLower.contains("fortuner")) {
      cap = 80.0;
      mileage = 12.0;
    } else if (mLower.contains("creta") || mLower.contains("seltos") || mLower.contains("alcazar")) {
      cap = 50.0;
      mileage = 16.0;
    } else if (mLower.contains("thar") || mLower.contains("xuv700") || mLower.contains("scorpio") || mLower.contains("safari") || mLower.contains("harrier") || mLower.contains("defender")) {
      cap = 60.0;
      mileage = 13.5;
    } else if (mLower.contains("swift") || mLower.contains("baleno") || mLower.contains("i20") || mLower.contains("altroz") || mLower.contains("tiago") || mLower.contains("wagonr") || mLower.contains("kwid") || mLower.contains("polo")) {
      cap = 37.0;
      mileage = 19.5;
    }

    return VehicleModelSpec(
      capacity: cap,
      defaultMileage: mileage,
      availableFuelTypes: const ["petrol", "diesel", "cng", "hybrid"],
    );
  }
}

class VehicleModelSpec {
  final double capacity; // Liters or kWh
  final double defaultMileage; // km/L or km/kWh
  final List<String> availableFuelTypes; // ["petrol", "diesel", "cng", "electric", "hybrid"]

  const VehicleModelSpec({
    required this.capacity,
    required this.defaultMileage,
    required this.availableFuelTypes,
  });
}

