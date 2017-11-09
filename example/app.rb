
$ip = nil

  pin = ESP32::GPIO::Pin.new(23, :output)

  t     = 0
  level = false

  half_cycle = 30
  step = 33
  dir  = 1

  tmr = ESP32::Timer.new [1, :millis] do |tmr, cnt|
    if (cnt % (half_cycle)) == 0  
      lvl = (level = !level) ? 1 : 0 
      pin.write lvl 
    end
  end

ESP32.wifi_connect("kittykat", "FooBar-12") do |ip|
  puts "\nIP: #{$ip = ip}\n"
end

  cnt = 0

  ESP32.main do
    t += 1
  
    next if cnt == tmr.count
  
    cnt = tmr.count
  
    if (cnt % 500) == 0
      print "\r\033[1A\rIDLE: #{t} times.                        "    
  
      if (half_cycle += step*dir) > 500
        half_cycle = 500
        dir = -1
      elsif half_cycle < 33
        half_cycle = 33
        dir = 1
      end
    end
  
    if (cnt % 5000) == 0
      print "\n5s Elapsed.\n"
    end
  end
