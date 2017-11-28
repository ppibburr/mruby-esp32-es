module MEES
  # The time this pass started
  def self.time
    @time ||= Time.now
  end
  
  # update
  def self.pass!
    @lt ||= time.to_f
    time.initialize
    
    return unless time.to_f > @lt
    
    Timer.fire
    
    @lt = time.to_f;
    
    if !@wifi_connected and wifi_has_ip?
      @wifi_connected = true
      
      if @wifi_on_connected_cb
        @wifi_on_connected_cb.call wifi_get_ip
      end
    else
      if @wifi_connected and !wifi_has_ip?
        if @wifi_on_disconnected_cb
          @wifi_on_disconnected_cb.call
        end
        
        @wifi_connected = false
      end
    end
    
    if gc_will_fire
       GC.start
       @start_ram = ESP32::System.available_memory
    end
    
    return true
  end
  
  # perform a loop, handling events each pass
  def self.loop
    while yield
      pass!
    end
  end
  
  # Iterate an enumerator, handling events in between each yield
  def self.iterate group, start=0
    for i in start..group.length-1
      yield group[i]
      pass!
    end
  end

  # use WiFi.on_discconect
  def self.wifi_on_disconnect &b
    @wifi_on_disconnected_cb = b
  end

  # use WiFi.connect
  def self.wifi_connect ssid, pass, &b
    @wifi_on_connected_cb = b
    wifi__connect ssid,pass  
  end 
  
  # use WiFi.connected?
  def self.wifi_connected?
    @wifi_connected
  end  
  
  # Start the main loop
  def self.main cb=nil, &b
    on_idle cb, &b
    
    @start_ram = ESP32::System.available_memory
        
    main__run
  end
  
  # Code to be repeated on idle passes
  def self.on_idle cb=nil, &b
    if !cb and b
      @_real_idle = b
    elsif cb
      @_real_idle = cb
    end
    
    @on_idle = Proc.new do
      next unless pass!
      @_real_idle.call if @_real_idle
    end
    
    main__on_idle @on_idle
  end
end

module MEES
  module Event
    # Number of events in queue
    def self.pending
      MEES.event_pending_events
    end
    
    # Execute the next event in queue, if exists
    def self.next!
      MEES.event_next_event
    end
  end
end

module MEES  
  class WiFi
    class << self
      attr_reader :ssid, :pass
    end
  
    def self.connect ssid, pass, &b
      @b = b
      MEES.wifi_connect ssid,pass, &@b
      @ssid = ssid
      @pass = pass
    end
    
    def self.ip
      return @ip if @ip
      connected? ? @ip=MEES.wifi_get_ip : nil
    end
    
    def self.connected?
      MEES.wifi_has_ip?
    end
    
    def self.on_disconnect &b
      MEES.wifi_on_disconnect &b
    end
  end
end

module MEES
  # Simple WebSocket client
  class WebSocket
    class Event
      NO_EXIST   = -1
      CONNECT    =  0
      DISCONNECT =  1
      MESSAGE    =  2
      
      attr_reader :data
      def initialize type = -1, data = nil
        @type = type
        @data = data
      end
      
      def type
        case @type
        when CONNECT
          :connect
        when DISCONNECT
          :disconnect
        when MESSAGE
          :message
        else
          nil
        end
      end
    end
    
    attr_reader :host
    def initialize host, &recv
      @host = host
      @recv = recv
      
      @evt  = Event.new
      
      @ws   = MEES::WebSocket.open host do |data|
        case data
        when Event::CONNECT
          @connected = true
          @evt.initialize data, nil
        when Event::DISCONNECT
          @connected=false
          @evt.initialize data, nil
        else
          if data.is_a?(String)
            @evt.initialize Event::MESSAGE, data
          else
            @evt.initialize -1, nil
          end
        end
        
        @recv.call self, @evt
      end
    end
    
    def connected?
      @connected
    end
    
    def puts s
      MEES::WebSocket.write @ws, s
    end
    
    def close
      MEES::WebSocket.close @ws
    end
    
    def self.open uri, &b
      MEES.ws_new uri, &b
    end
    
    def self.close ws
      MEES.ws_close ws
    end
    
    def self.write ws, s
      MEES.ws_write ws, s
    end
  end
end

module MEES
  # Simple File Descriptor IO operations
  module IO
    attr_reader :fd
        
    def self.write fd, s
      MEES.io_write fd, s
    end
    
    def self.recv_nonblock fd, len=64      
      MEES.io_recv_nonblock fd, len
    end
    
    def self.getc fd
      if fd == 1
        return MEES.io_uart_getc
      end
      
      recv_nonblock fd, 1
    end
    
    def self.close fd
      MEES.io_close fd
    end
    
    def recv_nonblock len=64
      MEES::IO.recv_nonblock @fd, len
    end

    def getc
      MEES::IO.getc @fd
    end
    
    def write msg
      raise "WriteError" unless MEES::IO.write(@fd, msg)
      true
    end
    
    def puts msg
      write msg+"\n"
    end
    
    def close
      MEES::IO.close @fd
    end
  end
end

module MEES
  # Simple TCPClient
  class TCPClient
    include MEES::IO
  
    def initialize host,port
      @fd = MEES.tcp_client_new host, port
    end
  end
end

module MEES
  module HTTP
    # perform a HTTP GET request
    def self.get uri, &b
      MEES.http_get uri, &b
    end
  end
end

module MEES
  module Task
    # Yields to higher priority tasks
    def self.yield
      MEES.task_yield
    end
    
    # Delays task execution
    # @param i Integer the amount to delay in millis
    def self.delay i
      MEES.task_delay i
    end
    
    # Returns the least ever free stack for task
    def self.stack_watermark
      MEES.task_stack_watermark
    end
  end
end

module MEES
  class Timer
    @timers = []
    def self.timers
      @timers
    end
    
    def self.fire
      time = MEES.time.to_f
      i = 0
      while i < timers.length
        if timers[i].time <= time
          timers[i].timeout time
        end
        i+=1
      end
    end

    attr_accessor :repeat, :time
    def initialize interval, repeat=true, &b
      @cb = b
      
      @repeat = repeat
      
      set_interval interval
    
      self.class.timers.unshift self
    end
    
    def set_interval int
      @interval = int
      update MEES.time.to_f
    end
    
    def update time
      @time = time + @interval  
    end
    
    def timeout time
      @cb.call self
      
      if !repeat
        self.class.timers.delete self
        return
      end
      
      update time
    end
  end
  
  def self.interval i, &b
    MEES::Timer.new i, &b
  end
  
  def self.timeout i, &b
    MEES::Timer.new i, false, &b
  end  
end

module MEES
  DEFAULT_GC_FIRE_THRESHOLD = 0.88

  # sets the percentage of start ram to fire GC
  def self.threshold_gc_fire= v
    raise ArgumentError.new("Not Number: #{v}") unless v.is_a?(Numeric)
    
    @threshold_gc_fire = v.to_f
  end
  
  # percentage of start ram to fire GC
  def self.threshold_gc_fire
    @threshold_gc_fire ||= DEFAULT_GC_FIRE_THRESHOLD
  end

  # returns true if GC will fire next MEES.pass!
  def self.gc_will_fire
    (@start_ram * threshold_gc_fire ) >= ESP32::System.available_memory
  end
end

module MEES
  module self::Object
    def timeout i, &b
      MEES.timeout i, &b
    end

    def interval i, &b
      MEES.interval i, &b
    end
    
    def pass!
      MEES.pass!
    end
    
    def yield!
      MEES::Task.yield
    end
    
    def delay i
      MEES::Task.delay i
    end
    
    def next!
      MEES::Event.next!
    end
    
    def main obj=nil, &b
      MEES.main obj, &b
    end
    
    def on_idle obj=nil, &b
      MEES.on_idle obj, &b
    end
    
    def ip
      MEES::WiFi.ip
    end
    
    def max_delay
      MEES::Port::MAX_DELAY
    end
    
    def tick_rate
      MEES::Port::TICK_RATE_MS
    end
    
    def tick_period
      MEES::Port::TICK_PERIOD_MS
    end            
  end
end

GC.start
GC.step_ratio = 50
GC.interval_ratio = 50
