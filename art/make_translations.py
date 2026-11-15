# Writes Translate/<EN|RU|UA>/IG_UI.json and Sandbox.json from one table, so
# the three languages always hold the same keys.
#   python art/make_translations.py
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Contents", "mods", "DeliriumHeating", "42", "media", "lua", "shared", "Translate")

# key: (EN, RU, UA). A literal percent sign is written %% (the strings go
# through Java's Formatter).
IG = {
    "Boiler": ("Boiler house", "Котельная", "Котельня"),
    "Radiator": ("Radiator", "Радиатор", "Радіатор"),
    "Pump": ("Pump station", "Насосная станция", "Насосна станція"),
    "NoData": ("No data from the server yet", "Данные с сервера ещё не пришли", "Дані з сервера ще не надійшли"),
    "Burning": ("The furnace is burning", "Топка горит", "Топка горить"),
    "OutOfFuel": ("Lit, but out of fuel", "Растоплена, но топливо кончилось", "Розпалена, але паливо скінчилося"),
    "Off": ("The furnace is out", "Топка погашена", "Топка погашена"),
    "Water": ("Water: %1 C", "Вода: %1 °C", "Вода: %1 °C"),
    "Fuel": ("Fuel: %1 of %2", "Топливо: %1 из %2", "Паливо: %1 з %2"),
    "Radiators": ("Radiators fed: %1", "Радиаторов на линии: %1", "Радіаторів на лінії: %1"),
    "BurnRate": ("Burns %1 an hour, enough for %2 h", "Расход %1 в час, хватит на %2 ч",
                 "Витрата %1 на годину, вистачить на %2 год"),
    "SwitchOn": ("Light the furnace", "Растопить", "Розпалити"),
    "SwitchOff": ("Put the furnace out", "Погасить", "Погасити"),
    "SwitchedOn": ("The furnace is lit", "Котельная растоплена", "Котельню розпалено"),
    "SwitchedOff": ("The furnace is out", "Котельная погашена", "Котельню погашено"),
    "LoadFuel": ("Load fuel", "Загрузить топливо", "Завантажити паливо"),
    "NoFuelItems": ("Nothing to burn on you: logs, planks, charcoal, coke, a propane tank or petrol",
                    "С собой нет топлива: брёвна, доски, уголь, кокс, баллон пропана или бензин",
                    "Із собою немає палива: колоди, дошки, вугілля, кокс, балон пропану або бензин"),
    "LoadAll": ("All the fuel", "Всё топливо", "Усе паливо"),
    "LoadGroup": ("%1 x%2 (+%3)", "%1 x%2 (+%3)", "%1 x%2 (+%3)"),
    "Loaded": ("Fuel loaded: +%1, now %2", "Топливо загружено: +%1, теперь %2", "Паливо завантажено: +%1, тепер %2"),
    "Full": ("The furnace is full", "Топка полна", "Топка повна"),
    "NoRoom": ("Not enough room in the furnace for that", "Это в топку уже не влезет", "Це в топку вже не влізе"),
    "TooFar": ("Come up to the boiler house", "Подойдите к котельной", "Підійдіть до котельні"),
    "RadiatorDry": ("No hot water reaches this radiator", "Вода до этого радиатора не доходит",
                    "Вода до цього радіатора не доходить"),
    "RadiatorCold": ("Connected, the water is cold", "Подключён, вода холодная", "Підключений, вода холодна"),
    "RadiatorHot": ("Heating: %1%%", "Греет: %1%%", "Гріє: %1%%"),
    "PumpWorks": ("Working", "Работает", "Працює"),
    "PumpNoPower": ("No electricity: the water goes no further", "Нет электричества: дальше воду не качает",
                    "Немає електрики: далі воду не качає"),
    "Admin": ("Heating (admin)", "Отопление (админ)", "Опалення (адмін)"),
    "PlacePipe": ("Pipe here", "Труба здесь", "Труба тут"),
    "LineStart": ("Pipe run: start here", "Трасса труб: начало здесь", "Траса труб: початок тут"),
    "LineStartSet": ("Start set. Right-click the end of the run", "Начало задано. ПКМ по концу трассы",
                     "Початок задано. ПКМ по кінцю траси"),
    "LineEnd": ("Pipe run: lay to here (%1 cells)", "Трасса труб: проложить досюда (%1 клеток)",
                "Траса труб: прокласти сюди (%1 клітинок)"),
    "LineRemove": ("Pipe run: remove pipes to here (%1 cells)", "Трасса труб: убрать трубы досюда (%1 клеток)",
                   "Траса труб: прибрати труби сюди (%1 клітинок)"),
    "PlaceRadiator": ("Radiator here", "Радиатор здесь", "Радіатор тут"),
    "Wall_N": ("at the north wall", "у северной стены", "біля північної стіни"),
    "Wall_W": ("at the west wall", "у западной стены", "біля західної стіни"),
    "Wall_S": ("at the south wall", "у южной стены", "біля південної стіни"),
    "Wall_E": ("at the east wall", "у восточной стены", "біля східної стіни"),
    "PlacePump": ("Pump station here", "Насосная станция здесь", "Насосна станція тут"),
    "PlaceBoiler": ("Boiler house, this cell is the middle of its front", "Котельная, эта клетка — середина фасада",
                    "Котельня, ця клітинка — середина фасаду"),
    "Front_S": ("front to the south (3 wide, 2 deep)", "фасадом на юг (3 в ширину, 2 в глубину)",
                "фасадом на південь (3 завширшки, 2 завглибшки)"),
    "Front_E": ("front to the east (2 wide, 3 deep)", "фасадом на восток (2 в ширину, 3 в глубину)",
                "фасадом на схід (2 завширшки, 3 завглибшки)"),
    "Probe": ("Check the supply", "Проверить подачу", "Перевірити подачу"),
    "Refuel": ("Fill with fuel", "Заполнить топливом", "Заповнити паливом"),
    "Remove": ("Remove", "Убрать", "Прибрати"),
    "Placed": ("Placed", "Поставлено", "Поставлено"),
    "Removed": ("Removed", "Убрано", "Прибрано"),
    "Refuelled": ("Fuel: %1", "Топливо: %1", "Паливо: %1"),
    "NotLoaded": ("The place is not loaded, come closer", "Место не загружено, подойдите ближе",
                  "Місце не завантажене, підійдіть ближче"),
    "Occupied": ("The place is taken", "Место занято", "Місце зайняте"),
    "NoFloor": ("No floor there", "Там нет пола", "Там немає підлоги"),
    "LineTooLong": ("One run is %1 cells at most", "Одна трасса — не длиннее %1 клеток",
                    "Одна траса — не довша за %1 клітинок"),
    "LineLaid": ("Pipes laid: %1", "Проложено труб: %1", "Прокладено труб: %1"),
    "LineStopped": ("Pipes laid: %1, then stopped: %2", "Проложено труб: %1, дальше стоп: %2",
                    "Прокладено труб: %1, далі стоп: %2"),
    "LineRemoved": ("Pipes removed: %1", "Убрано труб: %1", "Прибрано труб: %1"),
    "ProbeNothing": ("Nothing of the heating here", "Здесь нет ничего от отопления", "Тут немає нічого від опалення"),
    "ProbeYes": ("Water gets here and would go %1 cells further", "Вода доходит, запас хода ещё %1 клеток",
                 "Вода доходить, запас ходу ще %1 клітинок"),
    "ProbeNo": ("Water does not get here: too far from a boiler or a working pump, or not connected",
                "Вода не доходит: далеко от котельной или работающего насоса либо нет соединения",
                "Вода не доходить: далеко від котельні чи працюючого насоса або немає сполучення"),
}

SANDBOX = {
    "": ("Delirium Heating", "Delirium Heating", "Delirium Heating"),
    "FuelCapacity": ("Furnace capacity, fuel units", "Вместимость топки, единиц топлива",
                     "Місткість топки, одиниць палива"),
    "FuelCapacity_tooltip": (
        "How much fuel a boiler house holds. One unit is one game hour of an idle boiler.",
        "Сколько топлива вмещает котельная. Одна единица — один игровой час работы котельной без радиаторов.",
        "Скільки палива вміщує котельня. Одна одиниця — одна ігрова година роботи котельні без радіаторів."),
    "BurnPerHour": ("Fuel burnt per game hour", "Расход топлива за игровой час", "Витрата палива за ігрову годину"),
    "BurnPerHour_tooltip": (
        "Units a lit boiler burns every game hour whatever it feeds.",
        "Сколько единиц растопленная котельная сжигает за игровой час независимо от нагрузки.",
        "Скільки одиниць розпалена котельня спалює за ігрову годину незалежно від навантаження."),
    "BurnPerRadiator": ("Extra fuel per radiator per hour", "Добавка к расходу за каждый радиатор в час",
                        "Додаток до витрати за кожен радіатор на годину"),
    "BurnPerRadiator_tooltip": (
        "Added to the hourly burn for every radiator the boiler's water reaches.",
        "Прибавляется к часовому расходу за каждый радиатор, до которого доходит вода этой котельной.",
        "Додається до годинної витрати за кожен радіатор, до якого доходить вода цієї котельні."),
    "HeatUpPerMinute": ("Water heats up, degrees per game minute", "Нагрев воды, градусов за игровую минуту",
                        "Нагрів води, градусів за ігрову хвилину"),
    "HeatUpPerMinute_tooltip": (
        "Radiators start to warm at 30 degrees of water and give full heat at 80.",
        "Радиаторы начинают греть при 30 градусах воды и выходят на полную при 80.",
        "Радіатори починають гріти при 30 градусах води і виходять на повну при 80."),
    "CoolDownPerMinute": ("Water cools down, degrees per game minute", "Остывание воды, градусов за игровую минуту",
                          "Охолодження води, градусів за ігрову хвилину"),
    "CoolDownPerMinute_tooltip": (
        "While the furnace is out or has no fuel.",
        "Пока топка погашена или в ней нет топлива.",
        "Поки топка погашена або в ній немає палива."),
    "BoilerReach": ("Reach of a boiler house, cells", "Дальность котельной, клеток", "Дальність котельні, клітинок"),
    "BoilerReach_tooltip": (
        "How many cells of pipe the water travels from a boiler house without a pump.",
        "Сколько клеток трубы вода проходит от котельной без насоса.",
        "Скільки клітинок труби вода проходить від котельні без насоса."),
    "PumpReach": ("Reach of a pump station, cells", "Дальность насосной станции, клеток",
                  "Дальність насосної станції, клітинок"),
    "PumpReach_tooltip": (
        "A working pump sends the water that reached it this many cells further.",
        "Работающий насос отправляет дошедшую до него воду ещё на столько клеток.",
        "Працюючий насос відправляє воду, що дійшла до нього, ще на стільки клітинок."),
    "PumpNeedsPower": ("Pumps need electricity", "Насосам нужно электричество", "Насосам потрібна електрика"),
    "PumpNeedsPower_tooltip": (
        "A pump works only on a powered square (a generator nearby). Without power it passes the water like a plain pipe.",
        "Насос работает только на запитанной клетке (рядом генератор). Без питания пропускает воду как обычная труба.",
        "Насос працює лише на заживленій клітинці (поруч генератор). Без живлення пропускає воду як звичайна труба."),
    "RadiatorTemp": ("Radiator temperature at full heat", "Температура радиатора на полной мощности",
                     "Температура радіатора на повній потужності"),
    "RadiatorTemp_tooltip": (
        "Air temperature right at the radiator. A vanilla fireplace is 35.",
        "Температура воздуха вплотную к радиатору. У ванильного камина 35.",
        "Температура повітря впритул до радіатора. У ванільного каміна 35."),
    "RadiatorRadius": ("Radiator radius, cells", "Радиус радиатора, клеток", "Радіус радіатора, клітинок"),
    "RadiatorRadius_tooltip": (
        "The heat fades to nothing at this distance. Walls and closed doors stop it.",
        "На этом расстоянии тепло сходит на нет. Стены и закрытые двери его не пропускают.",
        "На цій відстані тепло сходить нанівець. Стіни й зачинені двері його не пропускають."),
    "PetrolPerLitre": ("Fuel units per litre of petrol", "Единиц топлива за литр бензина",
                       "Одиниць палива за літр бензину"),
    "PetrolPerLitre_tooltip": (
        "0 - the boiler takes no petrol.",
        "0 — бензин в котельную не заливается.",
        "0 — бензин у котельню не заливається."),
    "FuelTable": ("Fuel table", "Таблица топлива", "Таблиця палива"),
    "FuelTable_tooltip": (
        "item:units pairs separated by semicolons. A drainable item (a propane tank) gives its units when full. An unreadable table is replaced with the default one.",
        "Пары предмет:единицы через точку с запятой. Расходуемый предмет (баллон пропана) даёт указанное при полной заправке. Нечитаемая таблица заменяется таблицей по умолчанию.",
        "Пари предмет:одиниці через крапку з комою. Витратний предмет (балон пропану) дає вказане при повній заправці. Нечитабельна таблиця замінюється типовою."),
}

for i, lang in enumerate(("EN", "RU", "UA")):
    folder = os.path.join(OUT, lang)
    os.makedirs(folder, exist_ok=True)
    ig = {"IGUI_DelHeat_" + k: v[i] for k, v in IG.items()}
    sandbox = {"Sandbox_DelHeat" + ("_" + k if k else ""): v[i] for k, v in SANDBOX.items()}
    for name, data in (("IG_UI.json", ig), ("Sandbox.json", sandbox)):
        with open(os.path.join(folder, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")
print("written", len(IG), "IGUI and", len(SANDBOX), "sandbox keys x 3 languages")
