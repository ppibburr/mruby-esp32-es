class << self
def init
  @pin = ESP32::GPIO::Pin.new(23, :output)
  p :one
  @t     = 0
  @level = false

  @half_cycle = 33
  @step = 33
  @dir  = 1

  lvl = nil
#  @tmr = ESP32::Timer.new [1, :millis] do |tmr, cnt|
 #   if (cnt % (@half_cycle)) == 0  
  #    lvl = (@level = !@level) ? 1 : 0 
   #   @pin.write lvl 
    #end
  #end

  ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|hhh
   # puts "\nIP: #{ip}\n"
   @ip = ip
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
  @printf ||= Printf.new("
  \nlooped: %s
  ip:     %s
  memory:     least %s, current %s
  least free stack: %s
  ")
  @st ||= ESP32::time.to_f
  @tt ||= ESP32::time.to_f
  ESP32::time.initialize
  #ESP32.pass!    

    if ((ESP32.time.to_f - @tt) >= (@half_cycle*0.001))  
      @tt = ESP32.time.to_f
      lvl = (@level = !@level) ? 1 : 0 
      @pin.write lvl 
    end

  
  if (ESP32.time.to_f - @st) >= 1
    @st = ESP32.time.to_f
    @printf.write @t
    @printf.write ESP32::WiFi.ip
    @printf.write lmf
    @printf.write ESP32::System.available_memory 
    @printf.write ESP32.watermark
  end
end
end

class Printf
  NIL = "nil"
  NIL.freeze
  
  def initialize fmt
    @len = 0
    @var = fmt.split("%s").map do |q|
      @len += 1
      q
    end
  end
  
  def var i
    @var[i]
  end
  
  def write arg
    @i||=0
    @i = 0 if @i >= @len-1

    ESP32.printfs var(@i)  
    if arg.is_a? Float
      ESP32.printff arg
    elsif arg.is_a? String
      ESP32.printfs arg
    elsif arg.is_a? Fixnum
      ESP32.printfd arg
    elsif arg == nil
      ESP32.printfs NIL
    else
      #ESP32.printfs a.inspect
    end
    @i+=1
  end
end



init
ESP32.app_run do
  run
end
