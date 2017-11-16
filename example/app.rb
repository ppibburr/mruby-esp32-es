class << self
def init
  @pin = ESP32::GPIO::Pin.new(23, :output)
  p :one
  @t     = 0
  @level = false

  @half_cycle = 250
  @step = 33
  @dir  = 1

  lvl = nil
  @tmr = ESP32::Timer.new [1, :millis] do |tmr, cnt|
    if (cnt % (@half_cycle)) == 0  
      lvl = (@level = !@level) ? 1 : 0 
      @pin.write lvl 
    end
  end

  ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|
    puts "\nIP: #{ip}\n"
  end



  @lt = ESP32.time.to_f

  @lmf=nil
end

def lmf
  q = ESP32::System.available_memory
  return @lmf=q if !@lmf
  
  if q < @lmf
    return @lmf = q
  end
  
  return @lmf
end

def run
  @t += 1
  

  ESP32.pass!    
  
  return unless @lt != ESP32.time.to_f

  #if (@t % 50) == 0
    GC.start
  #end
  
  
  @lt = ESP32.time.to_f

  if (@tmr.count % 133) == 0   
    if (@half_cycle += @step*@dir) > 133
      @half_cycle = 133				
      @dir = -1
    elsif @half_cycle < 11
      @half_cycle = 11
      @dir = 1
    end
  end
  
  if @tmr.count > 0 and (@tmr.count % 500) == 0
    ESP32.log "\n
    looped: #{@t}
    ip:     #{ESP32::WiFi.ip}
    Memory:
    #{lmf} / #{ESP32::System.available_memory}
    Least Stack free:
    #{ESP32.watermark}
    "
  end
end
end





init
while true
  run
end
