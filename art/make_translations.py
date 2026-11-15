# Writes Translate/<EN|RU|UA>/*.json from one table, so the three languages
# always hold the same keys.
#   python art/make_translations.py
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Contents", "mods", "DeliriumHeating", "42", "media", "lua", "shared", "Translate")

# key: (EN, RU, UA). A literal percent sign is written %% (the strings go
# through Java's Formatter).
IG = {
    "Kind_pipe": ("Heating pipe", "Труба отопления", "Труба опалення"),
    "Kind_pump": ("Pump station", "Насосная станция", "Насосна станція"),
    "Kind_inlet": ("Heat unit", "Тепловой узел", "Тепловий вузол"),
    "Kind_radiator": ("Radiator", "Радиатор", "Радіатор"),
    "Kind_boiler": ("Boiler house", "Котельная", "Котельня"),
    "Kind_intake": ("Water intake", "Водозабор", "Водозабір"),
    "NoData": ("No data from the server yet", "Данные с сервера ещё не пришли", "Дані з сервера ще не надійшли"),
    # boiler
    "Burning": ("The furnace is burning", "Топка горит", "Топка горить"),
    "OutOfFuel": ("Lit, but out of fuel", "Растоплена, но топливо кончилось", "Розпалена, але паливо скінчилося"),
    "OutOfWater": ("Lit, but there is no water in the boiler", "Растоплена, но в котле нет воды",
                   "Розпалена, але в котлі немає води"),
    "Off": ("The furnace is out", "Топка погашена", "Топка погашена"),
    "Temp": ("Water temperature: %1 C", "Температура воды: %1 °C", "Температура води: %1 °C"),
    "Fuel": ("Fuel: %1 of %2", "Топливо: %1 из %2", "Паливо: %1 з %2"),
    "Water": ("Water in the boiler: %1 of %2 l", "Вода в котле: %1 из %2 л", "Вода в котлі: %1 з %2 л"),
    "SupplyYes": ("Water intake connected", "Водозабор подключён", "Водозабір підключено"),
    "SupplyNo": ("No working water intake connected", "Работающий водозабор не подключён",
                 "Працюючий водозабір не підключено"),
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
    "FillFuel": ("Admin: fill with fuel", "Админ: заполнить топливом", "Адмін: заповнити паливом"),
    "FillWater": ("Admin: fill with water", "Админ: заполнить водой", "Адмін: заповнити водою"),
    "Refuelled": ("Fuel: %1", "Топливо: %1", "Паливо: %1"),
    "WaterFilled": ("Water: %1 l", "Вода: %1 л", "Вода: %1 л"),
    # other devices
    "RadiatorDry": ("No heat unit with hot water in range", "Рядом нет теплового узла с горячей водой",
                    "Поруч немає теплового вузла з гарячою водою"),
    "RadiatorCold": ("Connected, the water is cold", "Подключён, вода холодная", "Підключений, вода холодна"),
    "RadiatorHot": ("Heating: %1%%", "Греет: %1%%", "Гріє: %1%%"),
    "Works": ("Working", "Работает", "Працює"),
    "PumpNoPower": ("No electricity: the water goes no further", "Нет электричества: дальше воду не качает",
                    "Немає електрики: далі воду не качає"),
    "IntakeNoPower": ("No electricity: no water is pumped", "Нет электричества: вода не качается",
                      "Немає електрики: вода не качається"),
    "InletFed": ("Hot water reaches it", "Горячая вода подведена", "Гарячу воду підведено"),
    "InletDry": ("Hot water does not reach it", "Горячая вода не доходит", "Гаряча вода не доходить"),
    "InletRadius": ("Serves the radiators within %1 cells", "Питает радиаторы в радиусе %1 клеток",
                    "Живить радіатори в радіусі %1 клітинок"),
    # building
    "Build": ("Heating", "Отопление", "Опалення"),
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
    "PlaceInlet": ("Heat unit here", "Тепловой узел здесь", "Тепловий вузол тут"),
    "PlacePump": ("Pump station here", "Насосная станция здесь", "Насосна станція тут"),
    "PlaceIntake": ("Water intake (2x2), this cell is its near corner", "Водозабор (2x2), эта клетка — ближний угол",
                    "Водозабір (2x2), ця клітинка — ближній кут"),
    "PlaceBoiler": ("Boiler house, this cell is the middle of its front", "Котельная, эта клетка — середина фасада",
                    "Котельня, ця клітинка — середина фасаду"),
    "Front_S": ("front to the south (3 wide, 2 deep)", "фасадом на юг (3 в ширину, 2 в глубину)",
                "фасадом на південь (3 завширшки, 2 завглибшки)"),
    "Front_E": ("front to the east (2 wide, 3 deep)", "фасадом на восток (2 в ширину, 3 в глубину)",
                "фасадом на схід (2 завширшки, 3 завглибшки)"),
    "Probe": ("Check the supply", "Проверить подачу", "Перевірити подачу"),
    "Remove": ("Admin: remove", "Админ: убрать", "Адмін: прибрати"),
    "Dismantle": ("Take apart", "Разобрать", "Розібрати"),
    "Placed": ("Placed", "Поставлено", "Поставлено"),
    "Removed": ("Removed", "Убрано", "Прибрано"),
    "NoRights": ("Only an admin builds the heating here", "Строить отопление здесь может только админ",
                 "Будувати опалення тут може лише адмін"),
    # Delirium Economy: the activity the admin ticks for an organization.
    "Activity": ("Heat supply", "Теплоснабжение", "Теплопостачання"),
    "NotService": ("Only the staff of a heat supply organization build and take apart the heating network",
                   "Сеть отопления строят и разбирают только сотрудники организации теплоснабжения",
                   "Мережу опалення будують і розбирають лише працівники організації теплопостачання"),
    "NeedTool": ("A pipe wrench is needed", "Нужен разводной ключ", "Потрібен розвідний ключ"),
    "NeedItem": ("The part for it is not on you", "Нужной детали с собой нет", "Потрібної деталі з собою немає"),
    "NeedWater": ("A water intake goes next to a river or a lake", "Водозабор ставится у реки или озера",
                  "Водозабір ставиться біля річки чи озера"),
    "ComeCloser": ("Come closer", "Подойдите ближе", "Підійдіть ближче"),
    "Safehouse": ("This is somebody else's safehouse", "Это чужое убежище", "Це чуже сховище"),
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
    "ProbeHeatYes": ("Hot water: gets here, %1 cells to spare", "Горячая вода: доходит, запас %1 клеток",
                     "Гаряча вода: доходить, запас %1 клітинок"),
    "ProbeHeatNo": ("Hot water: does not get here", "Горячая вода: не доходит", "Гаряча вода: не доходить"),
    "ProbeWaterYes": ("Intake water: gets here, %1 cells to spare", "Вода водозабора: доходит, запас %1 клеток",
                      "Вода водозабору: доходить, запас %1 клітинок"),
    "ProbeWaterNo": ("Intake water: does not get here", "Вода водозабора: не доходит", "Вода водозабору: не доходить"),
}

# Whole keys: the crafting tab.
IG_PLAIN = {
    "IGUI_CraftingCategories_Heating": ("Heating", "Отопление", "Опалення"),
}

ITEMS = {
    "DelHeat.Pipe": ("Heating Pipe", "Труба отопления", "Труба опалення"),
    "DelHeat.Radiator": ("Radiator", "Радиатор", "Радіатор"),
    "DelHeat.Inlet": ("Heat Unit", "Тепловой узел", "Тепловий вузол"),
    "DelHeat.Pump": ("Pump Station", "Насосная станция", "Насосна станція"),
    "DelHeat.Intake": ("Water Intake Kit", "Комплект водозабора", "Комплект водозабору"),
    "DelHeat.Boiler": ("Boiler House Kit", "Комплект котельной", "Комплект котельні"),
}

RECIPES = {
    "MakeHeatingPipe": ("Make Heating Pipes", "Сделать трубы отопления", "Зробити труби опалення"),
    "MakeHeatingRadiator": ("Make a Radiator", "Сделать радиатор", "Зробити радіатор"),
    "MakeHeatUnit": ("Make a Heat Unit", "Собрать тепловой узел", "Зібрати тепловий вузол"),
    "MakeHeatingPump": ("Make a Pump Station", "Собрать насосную станцию", "Зібрати насосну станцію"),
    "MakeWaterIntake": ("Make a Water Intake Kit", "Собрать комплект водозабора", "Зібрати комплект водозабору"),
    "MakeBoilerHouse": ("Make a Boiler House Kit", "Собрать комплект котельной", "Зібрати комплект котельні"),
}

HOW = ("Right-click the ground: Heating. A pipe wrench is needed.",
       "ПКМ по земле: «Отопление». Нужен разводной ключ.",
       "ПКМ по землі: «Опалення». Потрібен розвідний ключ.")


# Everything but a radiator.
SERVICE = ("Built only by the staff of a heat supply organization.",
           "Ставят только сотрудники организации теплоснабжения.",
           "Ставлять лише працівники організації теплопостачання.")


def how(en, ru, ua):
    return (en + " " + HOW[0], ru + " " + HOW[1], ua + " " + HOW[2])


def net(en, ru, ua):
    return how(en + " " + SERVICE[0], ru + " " + SERVICE[1], ua + " " + SERVICE[2])


TOOLTIPS = {
    "Tooltip_DelHeat_Pipe": net(
        "Lies on the ground and carries the water. Laid one by one or as a run between two clicks. To cross a road in the air: build a floor one level up, lay the pipes on it and take the floor away.",
        "Лежит на земле и несёт воду. Кладётся по одной или трассой между двумя кликами. Чтобы пройти над дорогой по воздуху: постройте пол этажом выше, проложите по нему трубы и уберите пол.",
        "Лежить на землі й несе воду. Кладеться по одній або трасою між двома кліками. Щоб пройти над дорогою в повітрі: збудуйте підлогу поверхом вище, прокладіть нею труби й приберіть підлогу."),
    "Tooltip_DelHeat_Radiator": how(
        "Warms a room when a heat unit with hot water is within range. Needs no pipe of its own.",
        "Греет комнату, если рядом есть тепловой узел с горячей водой. Своя труба не нужна.",
        "Гріє кімнату, якщо поруч є тепловий вузол з гарячою водою. Своя труба не потрібна."),
    "Tooltip_DelHeat_Inlet": net(
        "Stands at a wall of a house on the end of a pipe and feeds the radiators around it.",
        "Ставится у стены дома на конце трубы и питает радиаторы вокруг себя.",
        "Ставиться біля стіни будинку на кінці труби й живить радіатори навколо себе."),
    "Tooltip_DelHeat_Pump": net(
        "Sends the water further along the pipe. Needs electricity.",
        "Гонит воду дальше по трубе. Нужно электричество.",
        "Жене воду далі трубою. Потрібна електрика."),
    "Tooltip_DelHeat_Intake": net(
        "2x2 cells by a river or a lake: pumps water into the pipes to a boiler house. Needs electricity.",
        "2x2 клетки у реки или озера: качает воду по трубам к котельной. Нужно электричество.",
        "2x2 клітинки біля річки чи озера: качає воду трубами до котельні. Потрібна електрика."),
    "Tooltip_DelHeat_Boiler": net(
        "2x3 cells: burns fuel and heats the water for a whole neighbourhood.",
        "2x3 клетки: жжёт топливо и греет воду на целый район.",
        "2x3 клітинки: палить паливо й гріє воду на цілий район."),
}

SANDBOX = {
    "": ("Delirium Heating", "Delirium Heating", "Delirium Heating"),
    "PlayersBuild": ("Players build the heating", "Игроки строят отопление", "Гравці будують опалення"),
    "PlayersBuild_tooltip": (
        "With the crafted parts and a pipe wrench; the parts come back when a thing is taken apart. Radiators: any player. Everything else: the head and staff of an organization with the Heat supply activity (Delirium Economy, ticked by an admin). Off: only admins build.",
        "Из скрафченных деталей и с разводным ключом; при разборке деталь возвращается. Радиаторы — любой игрок. Всё остальное — голова и сотрудники организации с видом деятельности «Теплоснабжение» (Delirium Economy, галочку ставит админ). Выключено — строят только админы.",
        "Зі скрафчених деталей і з розвідним ключем; при розбиранні деталь повертається. Радіатори — будь-який гравець. Усе інше — голова і працівники організації з видом діяльності «Теплопостачання» (Delirium Economy, галочку ставить адмін). Вимкнено — будують лише адміни."),
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
        "Added to the hourly burn for every radiator the boiler feeds.",
        "Прибавляется к часовому расходу за каждый радиатор, который питает эта котельная.",
        "Додається до годинної витрати за кожен радіатор, який живить ця котельня."),
    "HeatUpPerMinute": ("Water heats up, degrees per game minute", "Нагрев воды, градусов за игровую минуту",
                        "Нагрів води, градусів за ігрову хвилину"),
    "HeatUpPerMinute_tooltip": (
        "Radiators start to warm at 30 degrees of water and give full heat at 80.",
        "Радиаторы начинают греть при 30 градусах воды и выходят на полную при 80.",
        "Радіатори починають гріти при 30 градусах води і виходять на повну при 80."),
    "CoolDownPerMinute": ("Water cools down, degrees per game minute", "Остывание воды, градусов за игровую минуту",
                          "Охолодження води, градусів за ігрову хвилину"),
    "CoolDownPerMinute_tooltip": (
        "While the furnace is out or has no fuel or water.",
        "Пока топка погашена либо в ней нет топлива или воды.",
        "Поки топка погашена або в ній немає палива чи води."),
    "WaterCapacity": ("Boiler water tank, litres", "Бак воды котельной, литров", "Бак води котельні, літрів"),
    "WaterCapacity_tooltip": (
        "A boiler house without water does not burn. The tank is filled by water intakes through the pipes.",
        "Котельная без воды не горит. Бак наполняют водозаборы по трубам.",
        "Котельня без води не горить. Бак наповнюють водозабори трубами."),
    "WaterPerHour": ("Water lost per game hour, litres", "Потери воды за игровой час, литров",
                     "Втрати води за ігрову годину, літрів"),
    "WaterPerHour_tooltip": (
        "What a burning boiler loses every game hour whatever it feeds.",
        "Сколько горящая котельная теряет за игровой час независимо от нагрузки.",
        "Скільки розпалена котельня втрачає за ігрову годину незалежно від навантаження."),
    "WaterPerRadiator": ("Extra water per radiator per hour, litres", "Добавка к потерям за каждый радиатор в час, литров",
                         "Додаток до втрат за кожен радіатор на годину, літрів"),
    "WaterPerRadiator_tooltip": (
        "Added to the hourly loss for every radiator the boiler feeds.",
        "Прибавляется к часовым потерям за каждый радиатор, который питает эта котельная.",
        "Додається до годинних втрат за кожен радіатор, який живить ця котельня."),
    "IntakeRate": ("Water intake output, litres per game hour", "Подача водозабора, литров за игровой час",
                   "Подача водозабору, літрів за ігрову годину"),
    "IntakeRate_tooltip": (
        "What every working intake adds to each boiler house its water reaches.",
        "Сколько каждый работающий водозабор добавляет каждой котельной, до которой доходит его вода.",
        "Скільки кожен працюючий водозабір додає кожній котельні, до якої доходить його вода."),
    "IntakeReach": ("Reach of a water intake, cells", "Дальность водозабора, клеток", "Дальність водозабору, клітинок"),
    "IntakeReach_tooltip": (
        "How many cells of pipe the water travels from an intake without a pump.",
        "Сколько клеток трубы вода проходит от водозабора без насоса.",
        "Скільки клітинок труби вода проходить від водозабору без насоса."),
    "BoilerReach": ("Reach of a boiler house, cells", "Дальность котельной, клеток", "Дальність котельні, клітинок"),
    "BoilerReach_tooltip": (
        "How many cells of pipe the hot water travels from a boiler house without a pump.",
        "Сколько клеток трубы горячая вода проходит от котельной без насоса.",
        "Скільки клітинок труби гаряча вода проходить від котельні без насоса."),
    "PumpReach": ("Reach of a pump station, cells", "Дальность насосной станции, клеток",
                  "Дальність насосної станції, клітинок"),
    "PumpReach_tooltip": (
        "A working pump sends the water that reached it this many cells further.",
        "Работающий насос отправляет дошедшую до него воду ещё на столько клеток.",
        "Працюючий насос відправляє воду, що дійшла до нього, ще на стільки клітинок."),
    "PumpNeedsPower": ("Pumps and intakes need electricity", "Насосам и водозаборам нужно электричество",
                       "Насосам і водозаборам потрібна електрика"),
    "PumpNeedsPower_tooltip": (
        "They work only on a powered square (a generator nearby). Without power a pump passes the water like a plain pipe and an intake gives none.",
        "Работают только на запитанной клетке (рядом генератор). Без питания насос пропускает воду как обычная труба, а водозабор воды не даёт.",
        "Працюють лише на заживленій клітинці (поруч генератор). Без живлення насос пропускає воду як звичайна труба, а водозабір води не дає."),
    "InletRadius": ("Heat unit radius, cells", "Радиус теплового узла, клеток", "Радіус теплового вузла, клітинок"),
    "InletRadius_tooltip": (
        "Radiators this close to a heat unit with hot water work, three floors up and down.",
        "Радиаторы на таком расстоянии от теплового узла с горячей водой работают, на три этажа вверх и вниз.",
        "Радіатори на такій відстані від теплового вузла з гарячою водою працюють, на три поверхи вгору і вниз."),
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
    ig.update({k: v[i] for k, v in IG_PLAIN.items()})
    files = {
        "IG_UI.json": ig,
        "Sandbox.json": {"Sandbox_DelHeat" + ("_" + k if k else ""): v[i] for k, v in SANDBOX.items()},
        "ItemName.json": {k: v[i] for k, v in ITEMS.items()},
        "Recipes.json": {k: v[i] for k, v in RECIPES.items()},
        "Tooltip.json": {k: v[i] for k, v in TOOLTIPS.items()},
    }
    for name, data in files.items():
        with open(os.path.join(folder, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(data, ensure_ascii=False, indent="\t") + "\n")
print("written", len(IG) + len(IG_PLAIN), "IGUI,", len(SANDBOX), "sandbox,", len(ITEMS), "item,",
      len(RECIPES), "recipe,", len(TOOLTIPS), "tooltip keys x 3 languages")
