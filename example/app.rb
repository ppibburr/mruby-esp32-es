class << self
  include ESP32::Printf::Writer
  def init
    ESP32.tcp
    ESP32.read
    ESP32.write "test"
    @st ||= ESP32::time.to_f
    @tt ||= ESP32::time.to_f  
  
    @pin   = ESP32::GPIO::Pin.new(23, :inout)
    
    def @pin.toggle
      write (read == 1) ? 0 : 1
    end
    
    @t     = 0
    @level = false

    @half_cycle = 33
    @step = 33
    @dir  = 1

    @lt  = ESP32.time.to_f
    @lmf = nil

    @printf ||= ESP32::Printf.new("\n
    looped:           %s
    Events:           %s
    ip:               %s
    memory:     least %s, current %s
    least free stack: %s")

    ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|
      puts "ip: #{@ip = ip}"
     
      @client = TCPClient.new("192.168.43.202", 8080)
      @client.recv_nonblock # doesnt block
      @client.write "test\n"    
    
      ESP32.get "http://time.jsontest.com" do |body|
        puts body
      end
     
      @ws = WebSocket.new("ws://192.168.43.202:8080") do |ins, data|
        case data
        when WebSocket::Event::CONNECT
          puts "WebSocket: Connected to: #{ins.host}"
        when WebSocket::Event::DISCONNECT
          puts "WebSocket: Disconnected"
          @ws = nil
        else
          if data and !data.empty?
            begin
              @ws.puts ESP32.eval(data)
            rescue => e
              puts e
            end
          end
        end
      end
    end
  end

  def p x
    if @ws
      @ws.puts x.is_a?(String) ? x : x.inspect
    end
    
    super
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
    b=false
    @t += 1
    lmf
    
    if ((ESP32.time.to_f - @tt) >= (@half_cycle*0.001))  
      @tt = ESP32.time.to_f
      @pin.toggle
    end

    if (ESP32.time.to_f - @st) >= (@sr||=1)
      @st = ESP32.time.to_f
      @ws.puts @ka||="PBR_KEEP_ALIVE" if @ws
      log
    end
    
    if @client
      if data = @client.recv_nonblock
        puts @r||="read:"
        puts data
        @client.write "Read: #{data}\n"
      end
    end    
  end
  
  def log
    printf @t,
           ESP32.n_events,
           ESP32::WiFi.ip,
           @lmf,
           ESP32::System.available_memory, 
           ESP32.watermark  
  
    print @nl||="\n"
  end
  
  def call
    return unless ESP32.pass!
    #ESP32::System.delay 1
    run
  end
end



init
ESP32::app_run self
