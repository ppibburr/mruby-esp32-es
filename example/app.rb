class << self
  def init ssid, pass    
    @t           = 0
    @toggle_rate = 33  # millis
    @log_rate    = 1   # second
    @lmf         = nil # Least amount of free memory

    @time_toggled = @time_logged = MEES.time.to_f
  
    @pin   = ESP32::GPIO::Pin.new(23, :inout)
    
    def @pin.toggle
      write (read == 1) ? 0 : 1
    end

    MEES::WiFi.connect(ssid, pass) do |ip|
      puts "ip: #{ip}"
     
      @client = MEES::TCPClient.new("192.168.43.202", 8080)
    end
    
    MEES.interval 3.5 do |tmr|
      puts @ts||="Timeout"
    end
    
    @start_ram = ESP32::System.available_memory
  end

  def lmf
    q = ESP32::System.available_memory
    
    return @lmf=q if !@lmf
    
    if q < @lmf
      return @lmf = q
    end
    
    return @lmf
  end
  
  def log
    puts "\n
      looped:           #{@t}
      Events:           #{MEES::Event.pending}
      ip:               #{MEES::WiFi.ip}
      memory:     least #{@lmf}, current #{ESP32::System.available_memory}
      least free stack: #{MEES::Task.stack_watermark}"
  end
  
  def call
    b=false
    @t += 1
    lmf
    
    if ((MEES.time.to_f - @time_toggled) >= (@toggle_rate*0.001))  
      @time_toggled = MEES.time.to_f
      @pin.toggle
    end

    if (MEES.time.to_f - @time_logged) >= @log_rate
      @time_logged = MEES.time.to_f
      log
    end
    
    if @client and data = @client.recv_nonblock
      @client.write MEES.eval(data)
      @client.write @nl||="\n"
    end    
  end  
end

init "LGL64VL_7870", "FooBar12"

MEES.main self
