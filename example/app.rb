class << self
  include ESP32::Printf::Writer
  def init
    @st ||= ESP32::time.to_f
    @tt ||= ESP32::time.to_f  
  
    @pin   = ESP32::GPIO::Pin.new(23, :output)
    @t     = 0
    @level = false

    @half_cycle = 33
    @step = 33
    @dir  = 1

    @lt  = ESP32.time.to_f
    @lmf = nil

    @printf ||= ESP32::Printf.new("\n
    looped:           %s
    ip:               %s
    memory:     least %s, current %s
    least free stack: %s")

    ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|
      puts "ip: #{@ip = ip}"
     
      ESP32.get "http://time.jsontest.com" do |body|
        puts body
      end
     
      @ws = WebSocket.new("ws://echo.websocket.org") do |ins, data|
        case data
        when WebSocket::Event::CONNECT
          puts "WebSocket: Connected to: #{ins.host}"
        when WebSocket::Event::DISCONNECT
          puts "WebSocket: Disconnected"
          @ws = nil
        else
          print "WebSocket: message - "
          puts data
          GC.start
        end
      end
    end
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
      @ws.puts "Hello" if @ws
    end    
  end
  
  def log
    printf @t,
           ESP32::WiFi.ip,
           lmf,
           ESP32::System.available_memory, 
           ESP32.watermark  
  
    print @nl||="\n"
  end
  
  def call
    ESP32.pass!
    run
  end
end



init
ESP32::app_run self
