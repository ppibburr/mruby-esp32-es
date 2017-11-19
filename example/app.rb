class << self
  include ESP32::Printf::Writer
	def init
	  @pin   = ESP32::GPIO::Pin.new(23, :output)
	  @t     = 0
	  @level = false

	  @half_cycle = 33
	  @step = 33
	  @dir  = 1

	  @printf ||= ESP32::Printf.new("
	  \nlooped:         %s
	  ip:               %s
	  memory:     least %s, current %s
	  least free stack: %s\n")
	  
	  @st ||= ESP32::time.to_f
	  @tt ||= ESP32::time.to_f

	  ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|
	     puts "ip: #{@ip = ip}"
       ESP32.get "http://time.jsontest.com" do |body|
         puts body
       end
       
       ESP32.ws do |str|
         puts str
       end
	  end

	  @lt  = ESP32.time.to_f
	  @lmf = nil
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

		if ((ESP32.time.to_f - @tt) >= (@half_cycle*0.001))  
		  @tt = ESP32.time.to_f
		  lvl = (@level = !@level) ? 1 : 0 
		  @pin.write lvl 
		end

	  
	  if (ESP32.time.to_f - @st) >= 1
		  @st = ESP32.time.to_f
		  log
	  end
	end
  
  def log
    printf @t,
           ESP32::WiFi.ip,
           lmf,
           ESP32::System.available_memory, 
           ESP32.watermark  
  end
  
  def call
    ESP32.pass!
    run
  end
end



init
ESP32::app_run self
