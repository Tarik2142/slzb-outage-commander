#META {"start":0}
#Insert your code below
import ZHB
import TIME
import string
import GPIO
import parser

var subtract_count = 5 # за скільки хвилин до відключення вмикати інвертор і вимикати споживачів

var power_pin = 46 # оптопара на увімкнення інвертора
var ac_detect_pin = 45 # модуль датчика 220в

GPIO.pinMode(power_pin, GPIO.MOD_OUTPUT)
GPIO.pinMode(ac_detect_pin, GPIO.MOD_INPUT)
# GPIO.digitalWrite(power_pin, 0)

SLZB.log("Очікування запуску хабу...")
ZHB.waitForStart(0xff)
SLZB.log("Очікування синхронізації часу...")
TIME.waitSync(0xff)

var outages = [] # поточні відключення в роботі
var devices = [ZHB.getDevice("Кухня"), ZHB.getDevice("Кухня2"), ZHB.getDevice("Бойлер")] # розетки / реле, що потрібно відключати
var current_outage = nil # поточне відключення
var unplanned_outage = false # якщо відключили не за графіком
var prev_m = nil # попередній час перевірки графіку. перевірка кожні 30хв
var outages_updated = false # індикатор чи вдалось оновити графік

# віднімання певної кількості хв щоб запустити інвертор наперед
def subtract_minutes(tm, count)
  var _tm = tm
  
  if (tm > 0)
    _tm = tm - count
  end

  var h = tm / 100
  var m = _tm % 100
  
  if (m > 59)
    h -= 1
    m = 60
    m -= count
  end
  
  return (h * 100) + m
end

# конструктор об*єкту
def outage(_day, _start, _end, power)
  return {"day": _day, "start": _start, "end": _end, "started": false, "ended": false, "power": power}
end

# хелпер для порівняння графіків відключень. Повертає істину якщо однакові
def compare_outages(o1, o2)
  if (o1.size() != o2.size())
    return false
  end
  
  for _key: o1.keys()
    var _o1 = o1[_key]
    var _o2 = o2[_key]
    
    if(!((_o1["day"] == _o2["day"]) && (_o1["start"] == _o2["start"]) && (_o1["end"] == _o2["end"])))
      return false
    end
  end
  
  return true
end

# я не хочу щоб світло вмикалось коли я сплю :)
def should_enable_power(_start, _end)
  return ((_start >= 700) || (_end >= 700) || ((_start < 200) && (_end <= 200))) ? 1 : 0
end

def formatTime(tm)
  return string.format("%02u:%02u", tm / 100, tm % 100)
end

def formatOutage(outage)
  var _day = outage["day"]
  var _start = formatTime(outage["start"])
  var _end = formatTime(outage["end"])
  
  return string.format("%02u. %s - %s. інвертор: %d", _day, _start, _end, outage["power"])
end

def fetch_outages()
  SLZB.log("Оновлення графіків...")
  
  var __outages = parser.parse()
  
  if (__outages)
    # SLZB.log("Пропаршено: " .. __outages)
    outages_updated = true
    
    var cur_outages = []
    var curDay = TIME.getAll()["day"]
    
    for _o: __outages
      cur_outages.push(outage(curDay, subtract_minutes(_o["start"], subtract_count), _o["end"], should_enable_power(_o["start"], _o["end"])))
    end
    
    if (!compare_outages(cur_outages, outages))
      SLZB.log("Графік змінився! Новий графік:")
      
      outages = cur_outages
      
      for _o: outages.keys()
        SLZB.log(formatOutage(outages[_o]))
      end
      SLZB.log("-------------------------------")
    else
      SLZB.log("Графік не змінився")
    end
  else
    SLZB.log("Не вдалось отримати графік!")
    outages_updated = false
  end
end

fetch_outages() # перевіряємо графік на старті

# SLZB.log("--- заплановані відключення ---")
# -------------------------------
# outages.push(outage(26, 0555, 0800))
# -------------------------------

# логує список відключень при старті скрипта
# for _o: outages.keys()
#   SLZB.log(formatOutage(outages[_o]))
# end
# SLZB.log("-------------------------------")

def send_state(dev, state)
  if dev
    dev.sendOnOff(state)
    
  else
    SLZB.log("УВАГА! Один з пристроїв не знайдено!")
  end
end

def inverter_control(state)
  SLZB.log("Відправка стану інвертору: " .. state)
  GPIO.digitalWrite(power_pin, state)
end

def update_all_devices(state)
   SLZB.log("Відправка стану давайсам: " .. state)
  
  for dev: devices
    send_state(dev, int(state))
    SLZB.delay(100)
  end
end

while 1
  var pending_state = nil
  var datetime = TIME.getAll()
  var cur_tm = (datetime["hour"] * 100) + datetime["min"]
  var cur_day = datetime["day"]
  
  for _o: outages
    
    if (!_o["ended"] && (cur_day == _o["day"]) && (cur_tm >= _o["end"]))
      _o["ended"] = true
      current_outage = nil
      
      if (GPIO.digitalRead(ac_detect_pin))
        SLZB.log("Світла все ще нема :( очікуємо...")
        unplanned_outage = true # не за графіком!

      else
        pending_state = 1
        SLZB.log("Відключення закінчилось: " .. formatOutage(_o))
        inverter_control(0)
      end
    end
    
    if (!_o["ended"] && (cur_day == _o["day"]) && (cur_tm >= _o["start"]))
      if (!_o["started"])
        SLZB.log("Відключення почалось: " .. formatOutage(_o))
      
        pending_state = 0
        _o["started"] = true
        current_outage = _o
        
        if (_o["power"] == 1)
          inverter_control(1)
        end
      end
    end
    
    # якщо вимкнули не за графіком
    if ((current_outage == nil) && (!unplanned_outage) && GPIO.digitalRead(ac_detect_pin))
      unplanned_outage = true
      pending_state = nil
      
      update_all_devices(0)
      SLZB.delay(2000)
      inverter_control(1)
      
      SLZB.log("Відключення НЕ за графіком, вмикаю резерв!")
      
    elif (unplanned_outage && !GPIO.digitalRead(ac_detect_pin))
      unplanned_outage = false
      
      inverter_control(0)
      SLZB.delay(2000)
      update_all_devices(1)
      
      SLZB.log("Света прийшла!")
    end
  end
  
  if (pending_state != nil)
    update_all_devices(pending_state)
  end
  
  if (prev_m != datetime["min"])
    # перевіряємо кожні 30хв або пробуємо кожну хвилину якщо попередня спроба не вдалась
    if (outages_updated == false ? true : (datetime["min"] == 0)  || (datetime["min"] == 31))
      prev_m = datetime["min"]
      fetch_outages()
    end
  end
  
  SLZB.delay(1000)
end
