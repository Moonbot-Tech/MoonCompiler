{ Объявления чистых шагов прохода по ленте.

  Файл подключается ДВУМЯ юнитами — листовым и тем, что стоит в кольце
  зависимостей. Текст обязан быть один и тот же до буквы: вся разница между
  двумя телами органа должна приходиться на положение юнита в графе, и ни на
  что больше. }

{ Оборот сделки: цена на количество. Количество берётся модулем знакового
  поля — того самого, чей знак несёт направление. }
function XNotional(const T: TChiTrade): Double; inline;

{ Индекс корзины по десятой доле секунды от свежайшего принта. }
function XBucket(const First, Time: TDateTime): Integer; inline;

{ Сырое расстояние в минутах и слот в кольце минут. Разнесены намеренно:
  первое — усечение произведения, второе — заворот индекса через ноль. }
function XMinuteRaw(const First, Time: TDateTime): Integer; inline;
function XMinuteSlot(Raw, CurMinute: Integer): Integer; inline;

{ Направление сделки по биту знака. }
function XIsSell(const T: TChiTrade): Boolean; inline;

{ Отклонение цены от опорной. }
function XDelta(const Price, Last: Double): Double; inline;

{ Сделка свежее границы окна. }
function XAfter(const Time, Edge: TDateTime): Boolean; inline;

{ Скользящее среднее объёма: деление на сотню внутри цикла. }
function XEma(const Prev, Q: Double): Double; inline;

{ Прошло ли меньше секунды с прошлой засечки. }
function XSameSecond(const Time, Mark: TDateTime): Boolean; inline;
