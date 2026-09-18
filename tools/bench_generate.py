#!/usr/bin/env python3
"""tools/bench_generate.py -- the V4.3 deep-bench generator.

Committed tool (the register's instrument, the plan's own call): grows
data/people/ from 213 to ~1600 (the signed 1500-2000 band, ~55/nation) with
invented names on the fictionalisation rules, a kind mix, wants resolved
against each nation's own registers, ids on the <NATION>_<surname> convention,
and a sidecar auto-seed (tools/portraits_traits.json) for every new id.

DETERMINISTIC: one RNG (seed fixed below), sorted iteration everywhere. Two
runs on the same tree produce byte-identical files; the register is content
and content does not get a different world because the clock ticked.

RETROFIT MODE (default on): the existing 213 gain kind/traits/ambition/wants
and a `bench: false` marker, so the political cast and the generated bench
are distinguishable at a glance and the portrait tiering (Task 6) can split
met cast from bench singles off the register alone. The regnal monarchs get
kind regional_figure and no wants -- a monarch has no register to read.

Usage:
  python tools/bench_generate.py            # generate + retrofit, write files
  python tools/bench_generate.py --check    # verify only, no writes
"""

import json
import random
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from curated_names.extra_surnames import EXTRA_SURNAMES

ROOT = Path(__file__).resolve().parent.parent
PEOPLE_DIR = ROOT / "data" / "people"
SIDECAR_PATH = ROOT / "tools" / "portraits_traits.json"

SEED = 434003  # fixed; the tree's content must not depend on when it was made

# --- The kind mix (plan 3.7: politicians ~60% incl. regional figures, unions
# --- ~10%, press ~8%, judges ~10%, activists ~12%) ---------------------------
KIND_PLAN = [
    ("politician", 0.50),
    ("regional_figure", 0.10),
    ("union_leader", 0.10),
    ("press_owner", 0.08),
    ("judge", 0.10),
    ("activist", 0.12),
]

TRAITS = ["ambitious", "loyal", "principled", "pragmatic", "vain", "stubborn",
          "networked", "fervent"]

# Trait affinities by kind: a judge is more often principled, a press owner
# more often networked, an activist fervent. Affinity doubles the draw weight.
TRAIT_AFFINITY = {
    "politician": {"ambitious", "pragmatic", "networked"},
    "regional_figure": {"pragmatic", "stubborn"},
    "union_leader": {"principled", "fervent", "stubborn"},
    "press_owner": {"networked", "vain", "pragmatic"},
    "judge": {"principled", "stubborn"},
    "activist": {"fervent", "principled"},
}

# Meter want thresholds per meter key, authored bands (below/above read the
# same ranges the meters live in: grievance 0-100, press_freedom -1..1,
# judicial independence deviation, typically within +-0.4).
METER_BANDS = {
    "grievance": ("below", [30.0, 45.0]),
    "press_freedom": ("above", [-0.2, 0.3]),
    "judicial_independence": ("above", [0.05, 0.3]),
}

# Want odds per person: politicians carry 1-3, others 0-2.
WANT_COUNTS = {
    "politician": (1, 3),
    "regional_figure": (1, 2),
    "union_leader": (0, 2),
    "press_owner": (0, 2),
    "judge": (1, 2),
    "activist": (1, 2),
}

# --- Per-nation curated name lists -------------------------------------------
# ~40 surnames and ~24 given names per nation, all invented (no real
# officeholders, no famous figures), each nation's own phonology. Enough for
# ~55 people without repeats; surnames never collide with the existing 213.
NAMES = {
    "FRA": {
        "given_f": ["Adèle", "Solène", "Manon", "Clarisse", "Ombeline", "Margaux",
                    "Sidonie", "Anaëlle", "Romane", "Élise", "Apolline", "Diane"],
        "given_m": ["Émeric", "Thibault", "Quentin", "Aurélien", "Gaspard", "Loïc",
                    "Fabrice", "Sylvain", "Rémi", "Bastien", "Corentin", "Étienne"],
        "surnames": ["Verchère", "Tassigny", "Moulinet", "Beaumanoir", "Rivalland",
                     "Chassignol", "Pérecourt", "Vaugelas", "Delcour", "Briandais",
                     "Montcharvin", "Sauvageot", "Larivière", "Poncharal", "Fermont",
                     "Griveau", "Chalandre", "Ollivier", "Marchenay", "Trébosc",
                     "Aubarède", "Clapiers", "Nogaret", "Bésombes", "Vairon",
                     "Madelaine", "Rochecotte", "Sarrand", "Villedieu", "Périer",
                     "Ambroise", "Chauviré", "Forgues", "Lantier", "Morlaix",
                     "Saint-Léger", "Turcy", "Vincendon", "Yvrard", "Zuber"],
    },
    "DEU": {
        "given_f": ["Annelie", "Sophie", "Katharina", "Franka", "Johanna", "Lena",
                    "Marlies", "Wiebke", "Silke", "Heide", "Antje", "Greta"],
        "given_m": ["Dietlinde", "Achim", "Bertram", "Cornelius", "Eckhard", "Falk",
                    "Gernot", "Hauke", "Jörn", "Konrad", "Ludger", "Meinolf"],
        "surnames": ["Ahrendts", "Bergmann", "Claussen", "Diekmann", "Eilers",
                     "Feuerbach", "Groenewold", "Hartung", "Isenberg", "Kastner",
                     "Lindhorst", "Mertens", "Nolte", "Osterkamp", "Pfeiffer",
                     "Quast", "Ricken", "Schwarzkopf", "Tiefensee", "Uhlig",
                     "Vollbrecht", "Wenzel", "Ziegenhals", "Brinkmann", "Drolshagen",
                     "Ehlers", "Fischbach", "Gerlach", "Hülsbusch", "Iserlohe",
                     "Kesselring", "Löbbert", "Mummert", "Nienhaus", "Overbeck",
                     "Pötter", "Rolfes", "Suhren", "Tschirner", "Waldmann"],
    },
    "ITA": {
        "given_f": ["Bianca", "Chiara", "Eugenia", "Fiorella", "Giulietta", "Ilaria",
                    "Lavinia", "Mariangela", "Nunzia", "Ottavia", "Raffaella", "Selvaggia"],
        "given_m": ["Amerigo", "Bruno", "Cesare", "Dario", "Emilio", "Fabrizio",
                    "Gianluca", "Ludovico", "Marcello", "Nanni", "Oreste", "Piero"],
        "surnames": ["Albinetti", "Barbagallo", "Carafa", "Dell'Orto", "Ferretti",
                     "Gargiulo", "Imperiali", "Lombrosio", "Mancuso", "Nesci",
                     "Oliverio", "Petroselli", "Quarta", "Ravagnani", "Sconfienza",
                     "Taddei", "Ughi", "Vismara", "Zaccagnini", "Bandello",
                     "Cimabue", "Dossena", "Ermenegildo", "Ferradini", "Gentileschi",
                     "Laudomi", "Marchionni", "Natalicchio", "Orsini", "Pischedda",
                     "Reali", "Sferrazza", "Tirabassi", "Valguarnera", "Zingaretti",
                     "Aloisio", "Brancadoro", "Cuccurullo", "Diotallevi", "Fogliano"],
    },
    "ESP": {
        "given_f": ["Almudena", "Belén", "Carlota", "Esperanza", "Gloria", "Inés",
                    "Lourdes", "Marisol", "Nuria", "Paloma", "Rocío", "Silvia"],
        "given_m": ["Andrés", "Borja", "César", "Eduardo", "Fermín", "Gonzalo",
                    "Isidro", "Javier", "Lucas", "Mateo", "Nicolás", "Rodrigo"],
        "surnames": ["Aguirrecha", "Bembibre", "Cadalso", "Delgado", "Escalante",
                     "Figueroa", "Grijalba", "Herranz", "Iturbe", "Jaramillo",
                     "Lacalle", "Montalbán", "Navarrete", "Olivencia", "Palazuelos",
                     "Querol", "Rentero", "Sanchidrián", "Tejedor", "Uribarri",
                     "Vallespín", "Yagüe", "Zamorano", "Aranda", "Berrocal",
                     "Castejón", "Dueñas", "Estrada", "Fuentenebro", "Galíndez",
                     "Higuera", "Ibáñez", "Jové", "Larrauri", "Mendive", "Otxoa",
                     "Peláez", "Quintanilla", "Sáenz", "Villalobos"],
    },
    "BEL": {
        "given_f": ["Godelieve", "Marijke", "Nele", "Sofie", "Elke", "Hilde",
                    "Fien", "Lien", "Rosa", "Tine", "Amber", "Loes"],
        "given_m": ["Bavo", "Dries", "Gerben", "Gillain", "Joos", "Koen",
                    "Lode", "Maarten", "Nand", "Pim", "Rien", "Wout"],
        "surnames": ["Baelden", "Claes", "Debruyn", "Ectors", "Fransen",
                     "Goossens", "Hendrickx", "Janssens", "Kerkhofs", "Luyten",
                     "Mannaerts", "Nys", "Peeters", "Ryckx", "Seghers",
                     "Timmermans", "Vanassche", "Willems", "Zegers", "Aelbrecht",
                     "Boonen", "Coolsaet", "De Backer", "Elst", "Floor",
                     "Grillaert", "Hoet", "Ionkheere", "Keppens", "Labiau",
                     "Mortelmans", "Noppe", "Olyslagers", "Puelinckx", "Raskin",
                     "Swerts", "Tanghe", "Verhulst", "Weyts", "Zion"],
    },
    "NLD": {
        "given_f": ["Anneke", "Bregje", "Doortje", "Eefje", "Femke", "Greet",
                    "Heleen", "Iris", "Jolanda", "Karin", "Lidewij", "Maartje"],
        "given_m": ["Aart", "Bas", "Cornelis", "Dirk", "Egbert", "Frits",
                    "Gerben", "Hidde", "Jelle", "Klaas", "Lodewijk", "Menno"],
        "surnames": ["Aalders", "Bakhuis", "Coenen", "Doornbos", "Everts",
                     "Franken", "Grootveld", "Hofland", "IJpelaar", "Jansink",
                     "Kuiper", "Linthorst", "Meulenkamp", "Nieuwenhuis", "Ophof",
                     "Pronk", "Quist", "Rensink", "Sloots", "Tuinstra",
                     "Veerman", "Wolters", "Zandbergen", "Bergkamp", "Creemers",
                     "Dekkers", "Eerden", "Fiers", "Gerritsen", "Hofstede",
                     "IJsselmuiden", "Klaver", "Lammers", "Manders", "Notten",
                     "Oldenkamp", "Poelstra", "Rietdijk", "Scholten", "Vissers"],
    },
    "LUX": {
        "given_f": ["Angèle", "Claire", "Elise", "Genviève", "Josiane", "Léonie",
                    "Mireille", "Nadine", "Odile", "Serge", "Tessy", "Yvette"],
        "given_m": ["Alain", "Benoît", "Camille", "Désiré", "Émile", "Félix",
                    "Gaston", "Henri", "Lucien", "Marc", "Nicolas", "Victor"],
        "surnames": ["Ahnen", "Bintner", "Claus", "Diederich", "Elschner",
                     "Fabritius", "Greisch", "Hansen", "Jungblut", "Krier",
                     "Lamesch", "Majerus", "Nickels", "Oestreicher", "Pulver",
                     "Reiffers", "Schmit", "Thiel", "Wagner", "Weber",
                     "Zeimet", "Backes", "Caspary", "Dellé", "Engel",
                     "Frantz", "Glaesener", "Herrmann", "Jacoby", "Kirpach",
                     "Lentz", "Mertens", "Neumann", "Origer", "Pfeffer",
                     "Rippinger", "Schwartz", "Theisen", "Waringo", "Zenner"],
    },
    "CHE": {
        "given_f": ["Adelheid", "Beatrice", "Christa", "Elsbeth", "Franziska", "Gerda",
                    "Heidi", "Irene", "Karin", "Liselotte", "Marta", "Nathalie"],
        "given_m": ["Albrecht", "Beat", "Christian", "Ernst", "Fritz", "Gerhard",
                    "Hansjörg", "Kaspar", "Lorenz", "Martin", "Niklaus", "Peter"],
        "surnames": ["Aeberhardt", "Brunner", "Christen", "Däppen", "Egger",
                     "Fasnacht", "Grubenmann", "Hoffmann", "Imfeld", "Jenni",
                     "Kägi", "Lüthi", "Meier", "Nussbaumer", "Ottiger",
                     " Pfister", "Quaderer", "Rickenbach", "Stucki", "Thönen",
                     "Uehlinger", "Vollenweider", "Wyss", "Amstutz", "Bosshart",
                     "Caduff", "Dütsch", "Eugster", "Fuchs", "Giezendanner",
                     "Honegger", "Isler", "Kohler", "Lorz", "Meile", "Niederer",
                     "Osterwalder", "Rickenbacher", "Schürch", "Zbinden"],
    },
    "GBR": {
        "given_f": ["Agnes", "Beatrice", "Cecily", "Dorothy", "Edith", "Florence",
                    "Gwendolen", "Harriet", "Imogen", "Jessamy", "Kitty", "Letitia"],
        "given_m": ["Algernon", "Bertram", "Cuthbert", "Desmond", "Edmund", "Frederick",
                    "Giles", "Humphrey", "Ivor", "Jasper", "Kenneth", "Montague"],
        "surnames": ["Acheson-Lowndes", "Beckwith", "Carradine", "Deverell", "Eastcote",
                     "Ffoulkes", "Greenaway", "Harrington", "Inglethorpe", "Jessel",
                     "Kingscote", "Lambourne", "Marlowe", "Naughton", "Orlebar",
                     "Pentreath", "Quennell", "Ravensworth", "Scarthwaite", "Thirlwall",
                     "Urquhart", "Vane-Tempest", "Wetherby", "Yarborough", "Aldwyn",
                     "Blackwood", "Cholmondley", "Danvers", "Escott", "Fairweather",
                     "Granville", "Hawtrey", "Inskip", "Jarvis", "Kelsall", "Lubbock",
                     "Massingham", "Nethercott", "Pobjoy", "Selwyn-French"],
    },
    "AUT": {
        "given_f": ["Aloisia", "Barbara", "Christine", "Elisabeth", "Franziska", "Gerti",
                    "Hanna", "Ingrid", "Johanna", "Karin", "Lotte", "Mitzi"],
        "given_m": ["Augustin", "Balthasar", "Christoph", "Eduard", "Florian", "Gottfried",
                    "Hubert", "Ignaz", "Jakob", "Klemens", "Leopold", "Severin"],
        "surnames": ["Adlmannseder", "Berghammer", "Czerny", "Dienstl", "Ebner",
                     "Frauscher", "Gruber", "Haidinger", "Innerhofer", "Jagsch",
                     "Kienast", "Lettner", "Moser", "Neumayer", "Oberhauser",
                     "Puntigam", "Quendler", "Reiterer", "Schwarzenberger", "Trimmel",
                     "Unterberger", "Vollnhofer", "Wiesner", "Zauner", "Aschauer",
                     "Birngruber", "Dannecker", "Ederer", "Felbermair", "Gstrein",
                     "Hafner", "Iro", "Kaltenbrunner", "Loidl", "Matischek", "Nagler",
                     "Omann", "Piribauer", "Steinbauer", "Windbichler"],
    },
    "BGR": {
        "given_f": ["Bogdana", "Dilyana", "Emiliya", "Gergana", "Ivayla", "Kalina",
                    "Liliya", "Maya", "Nadezhda", "Polina", "Silviya", "Vanya"],
        "given_m": ["Asen", "Boris", "Deyan", "Filip", "Georgi", "Hristo",
                    "Ivan", "Kiril", "Lyubomir", "Martin", "Nikolay", "Stoyan"],
        "surnames": ["Aleksiev", "Bodurov", "Chervenkov", "Dimov", "Elenkov",
                     "Georgiev", "Hristov", "Ivanov", "Kolarov", "Lazarov",
                     "Minev", "Neykov", "Petrov", "Radanov", "Stefanov",
                     "Tomov", "Uzunov", "Videv", "Yanev", "Zlatarov",
                     "Andonov", "Banev", "Donev", "Enchev", "Ganev",
                     "Hinkov", "Ilarionov", "Kojuharov", "Lozanov", "Mihov",
                     "Naydenov", "Penev", "Rusinov", "Simeonov", "Todorov",
                     "Valchanov", "Vulkov", "Zografski", "Boikov", "Cholakov"],
    },
    "HRV": {
        "given_f": ["Ana", "Davorka", "Ivana", "Jasenka", "Lidija", "Marija",
                    "Nada", "Petra", "Sanja", "Tihana", "Vesna", "Zlata"],
        "given_m": ["Andrija", "Božidar", "Domagoj", "Filip", "Goran", "Hrvoje",
                    "Ivan", "Josip", "Krešimir", "Luka", "Miroslav", "Zvonimir"],
        "surnames": ["Babić", "Cindrić", "Dujella", "Erić", "Frkanović",
                     "Grgić", "Horvat", "Ivančić", "Jurišić", "Kovačić",
                     "Lukić", "Marić", "Novosel", "Ostojić", "Pavković",
                     "Radić", "Srakočić", "Tomljanović", "Vukasović", "Zorić",
                     "Anđelić", "Bartulović", "Cvitković", "Draženović", "Filipović",
                     "Grubišić", "Hrženjak", "Ille", "Jelavić", "Katić",
                     "Lucić", "Matošević", "Nikolić", "Oreski", "Perišić",
                     "Roglić", "Šimić", "Tomić", "Vlašić", "Župan"],
    },
    "CYP": {
        "given_f": ["Androula", "Chrysanthi", "Despo", "Eleni", "Fotini", "Georgia",
                    "Ioanna", "Kyriaki", "Loukia", "Maria", "Niovi", "Sofia"],
        "given_m": ["Andreas", "Charalambos", "Demetris", "Evagoras", "Fotos", "Georgios",
                    "Ioannis", "Kyriacos", "Loizos", "Marios", "Nikos", "Panayiotis"],
        "surnames": ["Adamou", "Charalambous", "Dimitriou", "Efstathiou", "Georgiou",
                     "Hadjigeorgiou", "Ioannou", "Kyprianou", "Loizou", "Mavrommatis",
                     "Nicolaou", "Oikonomou", "Papadopoulos", "Stefanou", "Vassiliou",
                     "Zachariou", "Andreou", "Christodoulou", "Eleftheriou", "Flouris",
                     "Griva", "Hadjiantoni", "Ktorides", "Liasides", "Mouskos",
                     "Neophytou", "Panayi", "Pilavakis", "Rossides", "Soteriou",
                     "Theocharous", "Tsiakkouris", "Vrahimi", "Zambas", "Argyrou",
                     "Chrysostomou", "Drousiotis", "Katsaros", "Miltiades", "Servas"],
    },
    "CZE": {
        "given_f": ["Anežka", "Božena", "Dana", "Eva", "Hana", "Jitka",
                    "Klára", "Lucie", "Markéta", "Naďa", "Petra", "Věra"],
        "given_m": ["Bohumil", "Ctirad", "Dobroslav", "Eduard", "František", "Jaromír",
                    "Karel", "Luboš", "Milan", "Oldřich", "Radim", "Vojtěch"],
        "surnames": ["Bartoš", "Caha", "Doležal", "Eliáš", "Fišer",
                     "Gregor", "Hájek", "Chalupa", "Janda", "Kroupa",
                     "Lukeš", "Marek", "Novotný", "Odehnal", "Petr",
                     "Rychtář", "Sedláček", "Toman", "Uhlíř", "Vávra",
                     "Záruba", "Beneš", "Chmelař", "Dvořáček", "Fojtík",
                     "Hrubý", "Jílek", "Kopecký", "Musil", "Němec",
                     "Přibyl", "Sova", "Šimek", "Tesař", "Vaněk",
                     "Zemek", "Beran", "Císař", "Duda", "Havlíček"],
    },
    "DNK": {
        "given_f": ["Astrid", "Bodil", "Ditte", "Elly", "Freja", "Grete",
                    "Inge", "Karen", "Lone", "Rigmor", "Sigrid", "Thyra"],
        "given_m": ["Aksel", "Bendt", "Carl", "Ejvind", "Flemming", "Gunnar",
                    "Holger", "Jesper", "Kjeld", "Laurids", "Mogens", "Søren"],
        "surnames": ["Abildgaard", "Brorson", "Clemmensen", "Damgaard", "Egholm",
                     "Friisberg", "Grønbæk", "Holst", "Iversen", "Jerndorff",
                     "Kjeldgaard", "Lindqvist", "Møller", "Nørregaard", "Olesen",
                     "Poulsen", "Quist", "Ravn", "Skytte", "Thygesen",
                     "Ulstrup", "Vestergaard", "Wiborg", "Østergaard", "Aaskov",
                     "Birkerød", "Clitgas", "Dyrholm", "Enevoldsen", "Fabricius",
                     "Gisl", "Hammelsvang", "Ingemann", "Juhl", "Kirkegaard",
                     "Laursen", "Månsson", "Nordenhof", "Paludan", "Schrøder"],
    },
    "EST": {
        "given_f": ["Aino", "Eve", "Kadri", "Liis", "Maie", "Piret",
                    "Riina", "Sirje", "Tiina", "Ülle", "Anneli", "Kristi"],
        "given_m": ["Aarne", "Endel", "Ivo", "Jaan", "Kalju", "Lembit",
                    "Mati", "Olev", "Peeter", "Rein", "Tõnu", "Vello"],
        "surnames": ["Aare", "Blomfeldt", "Claudt", "Deemant", "Eensoo",
                     "Freiberg", "Grünberg", "Halliste", "Ilves", "Jõgi",
                     "Kask", "Lillemäe", "Mändmaa", "Nurmsalu", "Oja",
                     "Pärn", "Rand", "Salu", "Tammeorg", "Uibo",
                     "Välbe", "Ööpik", "Allik", "Böckler", "Dittmer",
                     "Ehala", "Fjodorov", "Grents", "Härma", "Ikkonen",
                     "Jürgens", "Kütt", "Laurits", "Mets", "Nõmmik",
                     "Orav", "Parts", "Raudsepp", "Sirel", "Teder"],
    },
    "FIN": {
        "given_f": ["Aila", "Eija", "Helinä", "Irmeli", "Kirsti", "Liisa",
                    "Marjatta", "Niina", "Päivi", "Raili", "Sinikka", "Tuulikki"],
        "given_m": ["Aarne", "Eino", "Heikki", "Ilmari", "Juha", "Kalevi",
                    "Lasse", "Martti", "Niilo", "Paavo", "Seppo", "Tapio"],
        "surnames": ["Aaltonen", "Blomqvist", "Corander", "Degerholm", "Eskola",
                     "Fagerlund", "Grönholm", "Hakulinen", "Ikonen", "Järvinen",
                     "Karppinen", "Lindström", "Mäkinen", "Nieminen", "Ojala",
                     "Partanen", "Rautavaara", "Salonen", "Tolvanen", "Uusitalo",
                     "Virtanen", "Yrjänä", "Ahonen", "Berg", "Cederström",
                     "Dahlström", "Erkinjuntti", "Forsman", "Grell", "Heikkilä",
                     "Ilves", "Jokinen", "Kallio", "Lahtinen", "Moisio",
                     "Nurmi", "Peltomaa", "Räsänen", "Silvennoinen", "Väisänen"],
    },
    "GRC": {
        "given_f": ["Anthoula", "Christina", "Despoina", "Eleni", "Fotini", "Giota",
                    "Ioanna", "Konstantina", "Lambrini", "Maria", "Nikoletta", "Sofia"],
        "given_m": ["Anargyros", "Christos", "Dimitris", "Evangelos", " Fotios", "Georgios",
                    "Ioannis", "Kostas", "Leonidas", "Manolis", "Nikolaos", "Panagiotis"],
        "surnames": ["Agapitou", "Bamichas", "Chrysafis", "Dendrinos", "Eleftheriadis",
                     "Fotopoulos", "Galanis", "Hatzis", "Ioannidis", "Kanellos",
                     "Lambrakis", "Manousakis", "Nikolaidis", "Oikonomakis", "Papazoglou",
                     "Rallis", "Sifneos", "Tsakonas", "Vlachogiannis", "Zafeiriou",
                     "Alexopoulos", "Berdekes", "Chondros", "Doukas", "Enotriades",
                     "Fassoulas", "Geroulanos", "Hondrokoukis", "Iliopoulos", "Katsaros",
                     "Leventis", "Moraitis", "Nastos", "Panagopoulos", "Roussos",
                     "Sakellaropoulos", "Triantafyllou", "Vgenopoulos", "Zorbos", "Avgustis"],
    },
    "HUN": {
        "given_f": ["Andrea", "Beatrix", "Csilla", "Edit", "Erzsébet", "Fruzsina",
                    "Gizella", "Ilona", "Judit", "Katalin", "Luca", "Piroska"],
        "given_m": ["Albert", "Bence", "Csaba", "Dezső", "Ferenc", "Gábor",
                    "Imre", "János", "László", "Miklós", "Nándor", "Zoltán"],
        "surnames": ["Albertfalusi", "Balogh", "Czutor", "Dobos", "Erdélyi",
                     "Fodor", "Gulyás", "Halász", "Illés", "Juhász",
                     "Király", "Lukács", "Molnár", "Németh", "Orosz",
                     "Papp", "Rácz", "Szabó", "Takács", "Varga",
                     "Zsoldos", "Barta", "Csepregi", "Dudás", "Egressy",
                     "Fábián", "Gerencsér", "Hegedűs", "Izsó", "Kalotai",
                     "Lendvai", "Mészáros", "Nagypál", "Orosz", "Pintér",
                     "Ruskó", "Szilágyi", "Tamási", "Vörös", "Zana"],
    },
    "IRL": {
        "given_f": ["Aine", "Brona", "Caitriona", "Deirdre", "Eilish", "Fiona",
                    "Grainne", "Ita", "Maeve", "Nuala", "Orla", "Sinead"],
        "given_m": ["Aidan", "Brendan", "Cathal", "Darragh", "Eamonn", "Fergal",
                    "Gearoid", "Hugh", "Lorcan", "Malachy", "Padraig", "Ruairi"],
        "surnames": ["Aherne", "Blacker", "Cuddihy", "Devane", "Enright",
                     "Fanning", "Gantly", "Henchy", "Igoe", "Joyce",
                     "Kelleher", "Laffan", "Mulvihill", "Nestor", "O'Boyle",
                     "Prendergast", "Quinlivan", "Ronayne", "Scully", "Tobin",
                     "Usher", "Waldron", "Yelverton", "Zealand", "Bermingham",
                     "Corballis", "Daly", "Egan", "Fitzgerald", "Gleeson",
                     "Hannon", "Kavanagh", "Lambe", "MacNamara", "Nugent",
                     "O'Donoghue", "Phelan", "Roche", "Swords", "Tyrrell"],
    },
    "LTU": {
        "given_f": ["Aistė", "Dalia", "Eglė", "Giedrė", "Irena", "Jurgita",
                    "Laima", "Nijolė", "Ona", "Rasa", "Sigita", "Vida"],
        "given_m": ["Algirdas", "Darius", "Edmundas", "Gintaras", "Jonas", "Kęstutis",
                    "Laimonas", "Mindaugas", "Nerijus", "Orestas", "Rimantas", "Vytautas"],
        "surnames": ["Adomaitis", "Balčiūnas", "Čepas", "Dobilaitis", "Eidukas",
                     "Grigas", "Jankauskas", "Kairys", "Laukaitis", "Mažeika",
                     "Norkūnas", "Petrauskas", "Ragauskas", "Sakalauskas", "Tumėnas",
                     "Urbonavičius", "Valančius", "Žilys", "Adamkevičius", "Burokas",
                     "Cirtautas", "Danišas", "Ėmužis", "Fokas", "Gudauskas",
                     "Ivanauskas", "Juozapavičius", "Kazlauskas", "Lukoševičius", "Matulis",
                     "Navickas", "Paulauskas", "Ramanauskas", "Simkus", "Tamošiūnas",
                     "Uleckas", "Vaitkus", "Zaborskis", "Baltušis", "Dvariakis"],
    },
    "LVA": {
        "given_f": ["Aija", "Dace", "Elīna", "Gunta", "Ilze", "Jurita",
                    "Kristīne", "Lasma", "Maija", "Nellija", "Ruta", "Velta"],
        "given_m": ["Aivars", "Dzintars", "Edgars", "Gunārs", "Imants", "Jānis",
                    "Kārlis", "Laimdots", "Māris", "Normunds", "Ojārs", "Viktors"],
        "surnames": ["Aizsilnieks", "Bērziņš", "Celms", "Dzene", "Egle",
                     "Freimanis", "Grīnbergs", "Kalnins", "Lācis", "Mazpanāks",
                     "Ozolins", "Pētersons", "Riekstiņš", "Skujenieks", "Taurins",
                     "Ulmanis", "Vilks", "Zariņš", "Apsītis", "Briedis",
                     "Cīrulis", "Dūmiņš", "Fogels", "Gailītis", "Hūns",
                     "Ikaunieks", "Jansonis", "Kroders", "Lēmanis", "Mucenieks",
                     "Naumanis", "Purmalis", "Rijnieks", "Straume", "Vagners",
                     "Zaķis", "Bāliņš", "Ķeizārs", "Rubenis", "Skujins"],
    },
    "MLT": {
        "given_f": ["Angela", "Carmen", "Doreen", "Evelyn", "Giovanna", "Josephine",
                    "Louise", "Marthese", "Nathalie", "Pauline", "Rita", "Sylvana"],
        "given_m": ["Anthony", "Carmel", "David", "Emanuel", "Godfrey", "Joseph",
                    "Lawrence", "Mario", "Noel", "Patrick", "Raymond", "Vincent"],
        "surnames": ["Agius", "Borg", "Cassar", "Debono", "Ellul",
                     "Farrugia", "Grima", "Hili", "Inglott", "Jones",
                     "Magro", "Navarro", "Portelli", "Rizzo", "Said",
                     "Vella", "Zammit", "Azzopardi", "Buhagiar", "Camilleri",
                     "Chircop", "Dalli", "Ebejer", "Fenech", "Galea",
                     "Gauci", "Micallef", " Pace", "Pisani", "Sciberras",
                     "Sultana", "Tabone", "Vassallo", "Xuereb", "Zahra",
                     "Agius", "Buhagiar", "Cachia", "Cremona", "Falzon"],
    },
    "POL": {
        "given_f": ["Agnieszka", "Barbara", "Danuta", "Ewa", "Halina", "Iwona",
                    "Jadwiga", "Krystyna", "Lucyna", "Malgorzata", "Renata", "Zofia"],
        "given_m": ["Andrzej", "Bronisław", "Czesław", "Dariusz", "Grzegorz", "Henryk",
                    "Jan", "Kazimierz", "Marek", "Piotr", "Stanisław", "Zbigniew"],
        "surnames": ["Adamczyk", "Barcicki", "Cieszkowski", "Dmochowski", "Ejsmont",
                     "Filipowicz", "Głowacki", "Hermanowski", "Iwański", "Jabłonowski",
                     "Kamiński", "Lewandowicz", "Michalak", "Nowicki", "Olszewski",
                     "Piotrowski", "Rybicki", "Sobolewski", "Tołwiński", "Ulanowski",
                     "Wiśniewski", "Zalewski", "Adamowski", "Biliński", "Cybulski",
                     "Dąbrowski", "Ernestowicz", "Fijas", "Godlewski", "Horodyński",
                     "Jakubowski", "Kowalczyk", "Lipiński", "Malinowski", "Nieborowski",
                     "Orzechowski", "Pułaski", "Romanowski", "Sadowski", "Wojcik"],
    },
    "PRT": {
        "given_f": ["Amália", "Beatriz", "Catarina", "Dulce", "Elvira", "Filipa",
                    "Graça", "Inês", "Joana", "Lurdes", "Marília", "Natália"],
        "given_m": ["Alexandre", "Bernardino", "Duarte", "Eusébio", "Fernando", "Gaspar",
                    "Henrique", "João", "Lourenço", "Miguel", "Nuno", "Rui"],
        "surnames": ["Abreu", "Bettencourt", "Correia", "Delgado", "Esteves",
                     "Freitas", "Guerra", "Hilário", "Isidoro", "Janes",
                     "Lourenço", "Meireles", "Nogueira", "Oliveira", "Pacheco",
                     "Quintela", " Rebelo", "Sousa", "Tavares", "Vasconcelos",
                     "Aguiar", "Bragança", "Cunha", "Durão", "Encarnação",
                     "Figueiredo", "Gonçalves", "Hipólito", "Julião", "Leitão",
                     "Mendes", "Narciso", "Pina", "Ramos", "Sequeira",
                     "Simões", "Trindade", "Valente", "Xavier", "Zagalo"],
    },
    "ROU": {
        "given_f": ["Adina", "Camelia", "Doina", "Elena", "Florentina", "Georgeta",
                    "Ilinca", "Larisa", "Mioara", "Nadia", "Rodica", "Viorica"],
        "given_m": ["Adrian", "Cornel", "Dumitru", "Emil", " Florin", "Gheorghe",
                    "Ion", "Lucian", "Marian", "Nicolae", "Petru", "Sorin"],
        "surnames": ["Alecsandrescu", "Bălcescu", "Carp", "Dobrescu", "Enache",
                     "Filipescu", "Hurmuzache", "Ionescu", "Jalea",
                     "Kretzulescu", "Lupescu", "Munteanu", "Năstase", "Odobescu",
                     "Petrescu", "Rosetti", "Sturdza", "Titulescu", "Ureche",
                     "Vodă", "Zamfirescu", "Andronescu", "Brătianu", "Cîrstea",
                     "Diaconescu", "Eftimie", "Fălcoianu", "Golescu", "Hasdeu",
                     "Ilie", "Lazăr", "Mănescu", "Negruzzi", "Popescu",
                     "Racoviță", "Slătineanu", "Tănăsescu", "Vlădescu", "Zosim"],
    },
    "SVK": {
        "given_f": ["Alžbeta", "Božena", "Danica", "Eva", "Gabriela", "Hana",
                    "Ivana", "Jana", "Katarína", "Ľudmila", "Mária", "Zuzana"],
        "given_m": ["Andrej", "Branislav", "Ctibor", "Dušan", "Erik", "František",
                    "Gabriel", "Igor", "Jozef", "Karol", "Ladislav", "Marek"],
        "surnames": ["Baník", "Cupák", "Ďurčanský", "Erdélyi", "Ferkoly",
                     "Gašpar", "Hlin", "Ihrík", "Jánoš", "Kostka",
                     "Lupták", "Martinák", "Nádašský", "Oravec", "Palárik",
                     "Rusnák", "Slávik", "Turček", "Urda", "Vansa",
                     "Záborský", "Bernolák", "Cabaj", "Dolinský", "Fabian",
                     "Gregor", "Hruška", "Illáš", "Jedinák", "Kolenčík",
                     "Labuda", "Mikloš", "Novota", "Ondruš", "Pribiš",
                     "Rezeik", "Sokol", "Tomašov", "Vlček", "Zimka"],
    },
    "SVN": {
        "given_f": ["Alenka", "Breda", "Cvetka", "Dragica", "Eva", "Irena",
                    "Jasna", "Karmen", "Lidija", "Mojca", "Nataša", "Vesna"],
        "given_m": ["Aleš", "Bojan", "Darko", "Erik", "Franci", "Gregor",
                    "Ivan", "Jože", "Klemen", "Luka", "Marko", "Tine"],
        "surnames": ["Ambrož", "Breg", "Cerar", "Dolinšek", "Erjavec",
                     "Faganeli", "Gantar", "Hočevar", "Ilija", "Juvan",
                     "Kastelic", "Lenarčič", "Mavret", "Novak", "Ocvirk",
                     "Pirc", "Rebolj", "Štimc", "Tavčar", "Vidmar",
                     "Zupan", "Avbelj", "Bavčar", "Cvikl", "Demšar",
                     "Ferfolja", "Grašič", "Hribar", "Jenko",
                     "Kopač", "Lipnik", "Mihelčič", "Nared", "Osole",
                     "Pečar", "Rupnik", "Suhadolc", "Vodopivec", "Zorko"],
    },
    "SWE": {
        "given_f": ["Agnes", "Birgitta", "Cecilia", "Disa", "Elsa", "Freja",
                    "Greta", "Hilma", "Ingrid", "Karin", "Lovisa", "Märta"],
        "given_m": ["Anders", "Birger", "Claes", "Dag", "Eskil", "Folke",
                    "Gustav", "Henrik", "Ingvar", "Johan", "Knut", "Lennart"],
        "surnames": ["Ahlström", "Bergström", "Cronholm", "Dahlgren", "Ekström",
                     "Falk", "Gullbrandsson", "Hellström", "Ingves", "Jansson",
                     "Källström", "Lindgren", "Månsson", "Norrlow", "Olofsson",
                     "Persson", "Quarnström", "Rask", "Stenmark", "Tegnér",
                     "Ulvaeus", "Werner", "Zetterling", "Åkerlund", "Bohlin",
                     "Cassel", "Drakenberg", "Edfeldt", "Frisk", "Gyllenhammar",
                     "Hofsten", "Isberg", "Jonsson", "Krogh", "Lundquist",
                     "Molander", "Nordfeldt", "Odhner", "Rylander", "Sörvik"],
    },
}

# The sidecar's physical descriptor pools (the V3.7 generator's own shape).
BUILDS = ["slim", "average build", "stocky", "broad-shouldered", "wiry"]
HAIR = ["short cropped hair", "layered mid-length hair", "receding hairline",
        "thick wavy hair", "straight shoulder-length hair", "tight curls",
        "silver hair swept back", "close-cropped grey hair"]
GLASSES = ["no glasses", "rectangular glasses", "round glasses", "thin-framed glasses"]
FACES = ["oval face with soft features", "broad face with a strong jaw",
         "narrow face with high cheekbones", "weathered face with deep lines",
         "round face with full cheeks", "angular face with a prominent nose"]
QUIRKS = ["widow's peak", "heavy brow", "dimpled chin", "scar on the left eyebrow",
          "pronounced smile lines", "straight brows", "asymmetric smirk lines"]
WARDROBES = ["open-collar dark blazer", "charcoal suit with a patterned tie",
             "plain dark suit", "knitted jumper over a collared shirt",
             "high-collared shirt", "beige linen jacket", "tweed jacket",
             "dark cardigan over a shirt", "crisp white shirt, sleeves rolled"]
SKINS = ["fair skin", "olive skin", "pale skin with freckles", "tanned skin",
         "light brown skin", "sallow skin"]
EYES = ["brown eyes", "blue eyes", "grey eyes", "green eyes", "hazel eyes"]

PROGRAMME_PORTFOLIO_KEYS = ["health", "education", "defence", "pensions", "infrastructure"]
METER_KEYS = ["grievance", "press_freedom", "judicial_independence"]


def fold(s: str) -> str:
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


def slug(s: str) -> str:
    s = fold(s).lower()
    s = s.replace("ł", "l").replace("ø", "o").replace("đ", "d").replace("ß", "ss")
    s = s.replace("å", "a").replace("æ", "ae").replace("œ", "oe")
    out = []
    for c in s:
        if c.isalnum():
            out.append(c)
        elif c in " -'":
            out.append("_")
        else:
            out.append("_")
    s = "".join(out)
    while "__" in s:
        s = s.replace("__", "_")
    return s.strip("_")


def kind_for_roll(roll: float) -> str:
    acc = 0.0
    for kind, weight in KIND_PLAN:
        acc += weight
        if roll <= acc:
            return kind
    return KIND_PLAN[-1][0]


def traits_for(rng: random.Random, kind: str) -> list:
    affinity = TRAIT_AFFINITY[kind]
    pool = []
    for t in TRAITS:
        pool.append(t)
        if t in affinity:
            pool.append(t)  # double weight for the affinity
    count = rng.choice([1, 2, 2, 2, 3, 3])
    picked = []
    while len(picked) < count:
        t = rng.choice(pool)
        if t not in picked:
            picked.append(t)
    return sorted(picked)


def wants_for(rng: random.Random, person_kind: str, nation: str, party_ids: list,
              programme_ids: list) -> list:
    lo, hi = WANT_COUNTS[person_kind]
    count = rng.randint(lo, hi)
    wants = []
    seen = set()

    candidates = []
    # politicians claim offices and sponsor programmes
    if person_kind in ("politician", "regional_figure"):
        for pid in party_ids:
            candidates.append({"object": "office:party_leadership:%s" % pid, "stance": "want"})
        for key in PROGRAMME_PORTFOLIO_KEYS:
            candidates.append({"object": "office:portfolio:%s" % key, "stance": "want"})
        candidates.append({"object": "office:premiership", "stance": "want"})
    for entry in programme_ids:
        candidates.append({"object": "programme:%s" % entry, "stance": "sponsor"})
        candidates.append({"object": "programme:%s" % entry, "stance": "oppose"})
    # The metered kinds' want lists are METERS FIRST -- the probe's reachable
    # betrayal (review C2's re-derivation) found the first mix authored 130
    # meter wants across 1595 people because 74 programme candidates buried
    # 9 meter candidates under every shuffle. A union leader's want list IS
    # grievance and press; a judge's IS the court. Meters are placed BEFORE
    # the shuffle-pick so the metered kinds draw them, and weighted x2 for
    # everyone else so a politician can still care about the country.
    meter_first = person_kind in ("union_leader", "activist", "press_owner", "judge")
    meter_candidates = []
    for key in METER_KEYS:
        direction, band = METER_BANDS[key]
        reps = 6 if meter_first else 2
        for _ in range(reps):
            want = {"object": "meter:%s" % key, "stance": "demand" if direction == "below" else "defend"}
            want[direction] = round(rng.uniform(band[0], band[1]), 1)
            meter_candidates.append(want)
    if meter_first:
        candidates = meter_candidates + candidates
    else:
        candidates += meter_candidates

    rng.shuffle(candidates)
    for cand in candidates:
        if len(wants) >= count:
            break
        obj = cand["object"]
        if obj in seen:
            continue
        seen.add(obj)
        wants.append(cand)
    return wants


def sidecar_entry(rng: random.Random, sex: str, age: int) -> dict:
    return {
        "sex": sex,
        "age": age,
        "build": rng.choice(BUILDS),
        "hair": rng.choice(HAIR),
        "glasses": rng.choice(GLASSES),
        "face": rng.choice(FACES),
        "quirk": rng.choice(QUIRKS),
        "wardrobe": rng.choice(WARDROBES),
        "skin": rng.choice(SKINS),
        "eyes": rng.choice(EYES),
        "bust": "average bust" if sex == "female" else "flat chest",
    }


def main() -> int:
    check_only = "--check" in sys.argv
    rng = random.Random(SEED)

    programme_ids = []
    for f in sorted((ROOT / "data" / "programme").glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        programme_ids += [e["id"] for e in d.get("programme", [])]

    sidecar = json.loads(SIDECAR_PATH.read_text(encoding="utf-8"))
    sidecar_changed = False

    total_people = 0
    report = []
    for nation in sorted(NAMES.keys()):
        path = PEOPLE_DIR / ("%s.json" % nation)
        d = json.loads(path.read_text(encoding="utf-8"))
        existing = d["people"]

        party_ids = []
        ppath = ROOT / "data" / "parties" / ("%s.json" % nation)
        pd = json.loads(ppath.read_text(encoding="utf-8"))
        party_ids = [p["id"] for p in pd.get("parties", [])]

        existing_ids = {p["id"] for p in existing}
        existing_surnames = set()
        for p in existing:
            # regnal names have no surname; their id slug IS the surname key
            existing_surnames.add(p["id"].split("_", 1)[1])

        # --- retrofit the political cast -------------------------------------
        # --regen-wants: rebuild the BENCH's want lists (the 213 originals keep
        # theirs -- the political cast's content is authored, not generated).
        # Used when the want MIX changes: the committed bench's wants were
        # drawn from the old candidate ordering, and re-running the same seed
        # with the new mix produces the new register deterministically.
        regen = "--regen-wants" in sys.argv
        for p in existing:
            if "kind" in p and not (regen and p.get("bench", False)):
                continue  # already retrofitted (idempotent re-run)
            if regen and p.get("bench", False):
                # rebuild THIS person's wants from their OWN kind's mix --
                # the 213 originals never enter this branch (bench: False)
                p["wants"] = wants_for(rng, p["kind"], nation, party_ids, programme_ids)
                continue
            is_regnal = " " not in p["name"] and any(c.isdigit() for c in p["name"])
            if is_regnal:
                # a monarch: regional_figure (no slot points at the crown's
                # claimant beyond the head-of-state edge, which IS the slot),
                # contented ambition, no wants -- a monarch wants nothing the
                # register can price.
                p["kind"] = "regional_figure"
                p["traits"] = ["principled", "stubborn"]
                p["ambition"] = 0.2
                p["wants"] = []
            else:
                p["kind"] = "politician"
                p["traits"] = traits_for(rng, "politician")
                p["ambition"] = round(rng.uniform(0.3, 0.9), 2)
                p["wants"] = wants_for(rng, "politician", nation, party_ids, programme_ids)
            p["bench"] = False

        # --- generate the bench ----------------------------------------------
        # The inline table's 40 plus the second curated wave's 20, per nation.
        names = NAMES[nation]
        all_surnames = list(names["surnames"]) + list(EXTRA_SURNAMES.get(nation, []))
        surnames = [s for s in all_surnames if slug(s) not in existing_surnames]
        taken_ids = set(existing_ids)
        target = 55
        bench_count = target - len(existing)
        new_people = []
        i = 0
        for surname in surnames:
            if i >= bench_count:
                break
            given_list = names["given_f"] if rng.random() < 0.35 else names["given_m"]
            given = rng.choice(given_list)
            base_id = "%s_%s" % (nation, slug(surname))
            pid = base_id
            if pid in taken_ids:
                continue
            taken_ids.add(pid)
            kind = kind_for_roll(rng.random())
            traits = traits_for(rng, kind)
            ambition = round(rng.uniform(0.2, 0.95), 2)
            wants = wants_for(rng, kind, nation, party_ids, programme_ids)
            person = {
                "id": pid,
                "name": "%s %s" % (given, surname.strip()),
                "kind": kind,
                "traits": traits,
                "ambition": ambition,
                "wants": wants,
                "bench": True,
            }
            if kind in ("politician", "regional_figure"):
                # Orphan-rule compliance: a politician with no slot and no
                # party is the one orphan the loader refuses (people-model 4).
                person["party_id"] = rng.choice(party_ids)
            new_people.append(person)

            if pid not in sidecar:
                sidecar[pid] = sidecar_entry(rng, "female" if given in names["given_f"] else "male",
                                             rng.randint(38, 68))
                sidecar_changed = True
            i += 1

        d["people"] = existing + new_people
        total_people += len(d["people"])
        report.append("%s %d (+%d)" % (nation, len(d["people"]), len(new_people)))

        if not check_only:
            path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if sidecar_changed and not check_only:
        # Deterministic ordering: keys sorted, so two runs write the same bytes.
        SIDECAR_PATH.write_text(json.dumps(dict(sorted(sidecar.items())), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    print(" | ".join(report))
    print("total people: %d" % total_people)
    print("sidecar entries: %d" % len(sidecar))

    if check_only:
        print("(check mode: no writes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
