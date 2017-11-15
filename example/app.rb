pin = ESP32::GPIO::Pin.new(23, :output)
p :one
$t     = 0
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

$lt = ESP32.time

$lmf=nil
def lmf
  q = ESP32::System.available_memory
  return $lmf=q if !$lmf
  
  if q < $lmf
    return $lmf = q
  end
  
  return $lmf
end

GC.start

ESP32.main do
  $t += 1
  
  #if ($t % 3) == 0
    GC.start 
  
  
  next unless $lt != ESP32.time
  
  $lt = ESP32.time
  
  if (tmr.count % 133) == 0   
    if (half_cycle += step*dir) > 133
      half_cycle = 133
      dir = -1
    elsif half_cycle < 11
      half_cycle = 11
      dir = 1
    end
  end
  
  if tmr.count > 0 and (tmr.count % 133) == 0
    # 20c ###################
    puts "\n"
    puts "0.5s Elapsed."
    puts "Looped: "
    puts "#{$t.inspect}"
    puts "WIFI: #{ESP32::WiFi.connected?.inspect}"
    puts "IP:"
    puts "#{ESP32::WiFi.ip.inspect}"
    puts "Memory Free:"
    puts "#{lmf} / #{ESP32::System.available_memory}"
    p ESP32.watermark
  end
end
