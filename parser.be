#META {"start":0}
import HTTP
import string

# Парсер графіків відключень житомиробленерго для SLZB-OS

var row = 5 # номер рядка вашої черги в таблиці. Рахунок починається з 1 від верху таблиці. Моя черга 3.1
var target_row = 2 + row # чому +2 ? тому, що потрібно пропустити 2 рядки заголовку таблиці

def time_entry(td_count, _type)
  var timeInfo = real((td_count - 4) / 2.0)
  var _h = int(timeInfo)
  var _m = (timeInfo % 1.0) > 0 ? 30 : 00
  var _tm = (_h * 100) + _m
  
  return {"start": _tm, "end": 2400, "action": _type, "started": false, "ended": false}
end

def parse()
var outages = []
var outages_counter = 0

if (HTTP.open("https://www.ztoe.com.ua/unhooking-search.php", "post", 0)) # 0байт - потоковий режим
  var postData = "rem_id=1&naspunkt_id=12612&vulica_id=119729"
  
  HTTP.setPostData(postData)
  HTTP.setHeader("Content-Type", "application/x-www-form-urlencoded")

  var code = HTTP.perform() # make req
  
  if (code == 200)
    var readed

    while readed != ""
      readed = HTTP.streamReadString(100)

      if string.find(readed, "<!--0<br>-->") != -1
        SLZB.log("Знайдено  графік! Парсинг...")
        
        var tr_count = 0
        
        while readed != ""
          if (HTTP.streamReadString(1) == "<" && HTTP.streamReadString(1) == "t" && HTTP.streamReadString(1) == "r") # <tr>
            readed = HTTP.streamReadString(1)
            tr_count += 1
            
            if (tr_count == target_row)
              var td_count = 0
              var outage_start = nil
              var outage_end = 2400
              
              while readed != ""
                if (HTTP.streamReadString(1) == "<" && HTTP.streamReadString(1) == "t" && HTTP.streamReadString(1) == "d") # <td
                  readed = HTTP.streamReadString(1)
                  td_count += 1
                  
                  if (td_count > 3) # пропускаємо перші 3 td
                    if (td_count > 51) # макс кількість клітинок в таблці
                      # SLZB.log("Відключення: " .. outages)
                      break
                    end
                    
                    var style = HTTP.streamReadString(165) # читаємо стиль
                    
                    if (string.find(style, "#ff3333") != -1) # шукаємо чи є червоний
                      if (outage_start == nil)
                        outage_start = time_entry(td_count, 1)
                        outages.push(outage_start)
                        outage_end = nil
                      end
                    else
                      if (outage_end == nil)
                        var __end = time_entry(td_count, 0)
                        outages[outages_counter]["end"] = __end["start"]
                        outage_end = __end
                        outage_start = nil
                        
                        outages_counter += 1
                      end
                    end
                  end
                end
              end
              
              break
            end
          end
        end
        
        break
      end
    end
    
    HTTP.streamFlush() # ігноруємо решту сторінки
    HTTP.close()
    return outages
  end
else
  SLZB.log("HTTP client failed!")
  HTTP.close()
  return outages
end
end

# SLZB.log("відключення: " .. parse())

var ztoe_parser = module("parser")
ztoe_parser.parse = parse
return ztoe_parser
