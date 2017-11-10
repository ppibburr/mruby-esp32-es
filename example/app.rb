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

ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|
  puts "\nIP: #{ip}\n"
end

lt = ESP32.time

ESP32.main do
  t += 1
  
  next unless lt != ESP32.time
  
  lt = ESP32.time
  
  if (tmr.count % 500) == 0   
    if (half_cycle += step*dir) > 500
      half_cycle = 500
      dir = -1
    elsif half_cycle < 33
      half_cycle = 33
      dir = 1
    end
  end
  
  if (tmr.count % 2500) == 0
    print "\n2.5s Elapsed. Looped: #{t.inspect} times. WIFI: connected? #{ESP32::WiFi.connected?.inspect}, IP: #{ESP32::WiFi.ip.inspect}\n"
    p ESP32::System.available_memory
  end
end
