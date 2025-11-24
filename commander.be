#META {"start":1}
#Insert your code below
import ZHB
import TIME
import string

SLZB.log("Очікування запуску хабу...")
ZHB.waitForStart(0xff)
SLZB.log("Очікування синхронізації часу...")
TIME.waitSync(0xff)

var outages = []
var devices = [ZHB.getDevice("Кухня"), ZHB.getDevice("Бойлер")]
var current_outage = nil

def outage(_day, _start, _end)
  return {"day": _day, "start": _start, "end": _end, "started": false, "ended": false}
end

SLZB.log("--- заплановані відключення ---")
# -------------------------------
outages.push(outage(22, 0000, 0305))
outages.push(outage(22, 0800, 1105))
outages.push(outage(22, 1300, 1535))
outages.push(outage(22, 1800, 2205))
# -------------------------------

def formatTime(tm)
  return string.format("%02u:%02u", tm / 100, tm % 100)
end

def formatOutage(outage)
  var _day = outage["day"]
  var _start = formatTime(outage["start"])
  var _end = formatTime(outage["end"])
  
  return string.format("%02u. %s - %s", _day, _start, _end)
end

for _o: outages.keys()
  SLZB.log(formatOutage(outages[_o]))
end
SLZB.log("-------------------------------")

def send_state(dev, state)
  if dev
    dev.sendOnOff(state)
    
  else
    SLZB.log("УВАГА! Один з пристроїв не знайдено!")
  end
end

def update_all_devices(state)
   SLZB.log("Відправка стану: " .. state)
  
  for dev: devices
    send_state(dev, int(state))
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
      
      SLZB.log("Відключення закінчилось: " .. formatOutage(_o))
      
      pending_state = 1
      current_outage = nil
    end
    
    if (!_o["ended"] && (cur_day == _o["day"]) && (cur_tm >= _o["start"]))
      if (!_o["started"])
        SLZB.log("Відключення почалось: " .. formatOutage(_o))
      
        pending_state = 0
        _o["started"] = true
        current_outage = _o
      end
    end
  end
  
  if (pending_state != nil)
    update_all_devices(pending_state)
  end
  
  SLZB.delay(1000)
end
