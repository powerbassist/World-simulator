"""V4.11. Name pools for the neighbourhood -- the nations that are simulated and
not playable, and that carry NO generated bench (the author's call: the met cast
plus the firms' chiefs, nothing deeper).

Kept OUT of bench_generate.NAMES on purpose: that generator draws one RNG over
sorted(NAMES), so a key added there reshuffles every existing nation's bench.
tools/firms_generate.py reads these for its chiefs and its firm stems. Same
rules as bench_generate's lists: invented on docs/fictionalization.md's rules,
each nation's own phonology, no officeholder or famous figure; tools/
check_names.sh scans this file like every other.
"""

NEIGHBOUR_NAMES = {
    "NOR": {
        "given_f": ["Astrid", "Bodil", "Eli", "Gro", "Hilde", "Ingeborg", "Kari",
                    "Liv", "Ragnhild", "Sigrid", "Solveig", "Tone"],
        "given_m": ["Arne", "Bjørn", "Einar", "Geir", "Halvard", "Jostein", "Knut",
                    "Leif", "Odd", "Rune", "Sverre", "Torbjørn"],
        "surnames": ["Aasland", "Bakketun", "Dalsbø", "Eidsvåg", "Fjellstad",
                     "Grøtteland", "Hovden", "Isaksen", "Jordal", "Kvamme",
                     "Lien", "Myrvold", "Nesheim", "Opsahl", "Rønneberg",
                     "Sandvik", "Tangen", "Ulvestad", "Vestby", "Aamot",
                     "Brattli", "Engebretsen", "Folkestad", "Hagerup", "Kleppe",
                     "Lysne", "Mjelde", "Nordbø", "Rugland", "Skarstein"],
    },
    "ISL": {
        "given_f": ["Ásta", "Birna", "Dagný", "Erla", "Guðrún", "Hrefna", "Jóhanna",
                    "Katla", "Lilja", "Rósa", "Signý", "Þórdís"],
        "given_m": ["Ari", "Baldur", "Davíð", "Einar", "Gísli", "Hjalti", "Jón",
                    "Kári", "Leifur", "Ragnar", "Snorri", "Þórir"],
        "surnames": ["Arnarson", "Baldursson", "Daníelsson", "Egilsson", "Finnsson",
                     "Grímsson", "Hauksson", "Ingvarsson", "Jökulsson", "Kolbeinsson",
                     "Leifsson", "Mýrdal", "Njálsson", "Óskarsson", "Pálsson",
                     "Runólfsson", "Sverrisson", "Tryggvason", "Úlfarsson", "Viðarsson",
                     "Ásgeirsdóttir", "Bragadóttir", "Eiríksdóttir", "Hlynsdóttir",
                     "Jónsdóttir", "Kjartansdóttir", "Sindradóttir", "Valdóttir"],
    },
    "SRB": {
        "given_f": ["Ana", "Biljana", "Danica", "Gordana", "Jasmina", "Ljiljana",
                    "Milica", "Nada", "Olivera", "Snežana", "Tamara", "Vesna"],
        "given_m": ["Bojan", "Dejan", "Goran", "Ivan", "Milan", "Miroslav", "Nebojša",
                    "Predrag", "Slobodan", "Srđan", "Uroš", "Vladimir"],
        "surnames": ["Babić", "Crnobrnja", "Đorđević", "Filipović", "Gavrilović",
                     "Ilić", "Janković", "Kostić", "Lukić", "Milenković",
                     "Novaković", "Obradović", "Pavlović", "Ristić", "Simić",
                     "Todorović", "Urošević", "Vasiljević", "Živković", "Zdravković",
                     "Aćimović", "Bogdanović", "Despotović", "Grujić", "Jovanović",
                     "Krstić", "Mladenović", "Stevanović", "Tasić", "Vuković"],
    },
    "TUR": {
        "given_f": ["Ayşegül", "Burcu", "Deniz", "Elif", "Gülşen", "Hülya", "Meltem",
                    "Nesrin", "Özlem", "Sevgi", "Tülin", "Zeynep"],
        "given_m": ["Ahmet", "Burak", "Cem", "Emre", "Gökhan", "Kemal", "Levent",
                    "Murat", "Orhan", "Serkan", "Tuncay", "Volkan"],
        "surnames": ["Akgül", "Balcı", "Çakır", "Dinçer", "Ergin", "Güneş",
                     "Işık", "Kaplan", "Keskin", "Koçak", "Polat", "Sarı",
                     "Tekin", "Uçar", "Yalçın", "Yavuz", "Zengin", "Aktaş",
                     "Bulut", "Coşkun", "Duman", "Erdem", "Karaca", "Kurt",
                     "Özkan", "Şahin", "Taş", "Toprak", "Ünal", "Yüksel"],
    },
    "ALB": {
        "given_f": ["Arta", "Blerina", "Drita", "Elona", "Flutura", "Jonida",
                    "Lindita", "Mirela", "Rudina", "Teuta", "Valbona", "Zana"],
        "given_m": ["Altin", "Ardian", "Bledar", "Dritan", "Erion", "Gentian",
                    "Ilir", "Klodian", "Lorenc", "Mirjan", "Sokol", "Teodor"],
        "surnames": ["Avdia", "Bardhi", "Çela", "Dibra", "Elezi", "Frashëri",
                     "Gjoka", "Hasani", "Kapllani", "Laçi", "Malaj", "Ndreu",
                     "Prifti", "Qosja", "Sinani", "Tafa", "Vata", "Xhafa",
                     "Zeneli", "Bregu", "Cani", "Duka", "Gjini", "Kraja",
                     "Lika", "Marku", "Nushi", "Pepa", "Rrapaj", "Spahiu"],
    },
    "MKD": {
        "given_f": ["Ana", "Biljana", "Daniela", "Elena", "Jasmina", "Katerina",
                    "Liljana", "Marija", "Natasha", "Sonja", "Tanja", "Vesna"],
        "given_m": ["Aleksandar", "Blagoja", "Dimitar", "Goce", "Igor", "Kiril",
                    "Ljupčo", "Nikola", "Petar", "Stojan", "Trajče", "Zoran"],
        "surnames": ["Atanasovski", "Blaževski", "Cvetanovski", "Dimovski", "Georgievski",
                     "Ilievski", "Jovanovski", "Kostovski", "Lazarevski", "Mitrevski",
                     "Naumovski", "Petrovski", "Ristevski", "Spasovski", "Todorovski",
                     "Velkovski", "Zafirovski", "Angelov", "Bojadžiev", "Grozdanovski",
                     "Janevski", "Kocevski", "Manevski", "Nedelkovski", "Popovski",
                     "Stefanovski", "Tasevski", "Uzunov", "Veljanovski", "Zdravkovski"],
    },
    "MNE": {
        "given_f": ["Bojana", "Dragana", "Ivana", "Jelena", "Ljubica", "Marija",
                    "Milena", "Nataša", "Sanja", "Tijana", "Vesna", "Zorana"],
        "given_m": ["Boris", "Branko", "Danilo", "Dušan", "Filip", "Igor", "Marko",
                    "Miloš", "Nikola", "Radomir", "Vuk", "Željko"],
        "surnames": ["Baošić", "Cerović", "Dragović", "Gazivoda", "Jovović",
                     "Kalezić", "Lakić", "Martinović", "Nikčević", "Perović",
                     "Radulović", "Šćepanović", "Tomašević", "Vučinić", "Zečević",
                     "Bošković", "Đurišić", "Ivanović", "Kovačević", "Lalović",
                     "Mijatović", "Popović", "Raičković", "Stanišić", "Vujović"],
    },
}
