module ESP32
  def self.time
    @time ||= Time.now.to_f
  end
  
  def self.wifi_connected?
    @wifi_connected
  end
  
  def self.pass!
    event?# if events_enabled?   
    
    @time = Time.now.to_f
    
    Timer.fire_for(time)
    
    if !@wifi_connected and wifi_has_ip?
      @wifi_connected = true
      
      if cb = @on_wifi_connected_cb
        cb.call wifi_get_ip
      end
    else
      if @wifi_connected and !wifi_has_ip?
        if cb = @on_wifi_disconnected_cb
          cb.call
        end
        
        @wifi_connected = false
      end
    end
  end
  
  def self.loop
    while yield
      pass!
    end
  end
  
  def self.iterate group, start=0
    for i in start..group.length-1
      yield group[i]
      pass!
    end
  end

  def self.timeout d, res=:usec, &b
    Timer.new [d, res], 1, &b
  end
  
  def self.interval d, res=:usec, &b
    Timer.new [d, res], &b
  end
  
  @events_enabled        = false
  @event_poll_block_time = Constants::PORT_MAX_DELAY
  def self.enable_events block_time=@event_poll_block_time
    @events_enabled = true
    @event_poll_block_time = block_time
  end
  
  def self.disable_events
    @events_enabled = false
  end
  
  def self.events_enabled?
    @events_enabled
  end

  def self.on_wifi_disconnect &b
    @on_wifi_disconnected_cb = b
  end

  def self.wifi_connect ssid, pass, &b
    @on_wifi_connected_cb = b
    __wifi_connect__ ssid,pass  
  end 
  
  def self.main
    while 1
      pass!
    
      yield
    end  
  end
  
  class Timer
    attr_accessor :count, :max, :auto_reset, :n_tick
    attr_reader   :interval, :resolution
    
    @timers = []
    
    protected
    def self.add_timer tmr
      @timers << tmr
    end
    
    public
    def self.timers
      @timers.map do |t| t end
    end
    
    def self.remove_timer tmr
      @timers.delete tmr
      return tmr
    end
    
    def self.firing time
      @timers.find_all do |t|
        t.n_tick <= t
      end
    end
    
    def self.fire_for time
      @timers.each do |t|
        t.tick! if t.n_tick <= time
      end 
    end
    
    def initialize interval, max = -1, &b
      a = interval.is_a?(Array) ? interval : [interval]
      
      self.class.add_timer self
      
      @interval   = a[0]
      @resolution = a[1] || :usec
      
      p update_next_tick    
      
      max = max ? max : -1
      
      @max      = max
      @count    = 0
      
      if b and max < 0
        on_tick &b
        start
      elsif b
        on_expire &b
      end
    end
    
    def delete
      stop
      self.class.remove_timer self
    end
    
    def stop
      @enable = false
    end
    
    def reset
      @count = 0
      start unless enabled? 
    end
    
    def interval= i
      bool = enabled?
      stop
      @interval = i
      start if bool
      
      return i
    end
    
    def start
      @enable = true
    end
    
    def enabled?
      @enable
    end
  
    alias :enable :start
    alias :disable :stop
    
    def on_tick &b
      @on_tick_cb = b
    end
    
    def on_expire &b
      @on_expire_cb = b
    end
    
    def update_next_tick
      step = nil
      case resolution
      when :usec
        step = interval  *  0.000001
      when :millis
        step = interval * 0.001
      when :second
        step = interval
      end

      @n_tick = ESP32.time + step      
    end
    
    def tick!
      update_next_tick
    
      if enabled?
        @count += 1
      
        if count > max and max > 0
          if cb = @on_expire_cb
            cb.call self if enabled?
          end
          
          unless auto_reset
            stop
          else
            reset
          end
        end
        
        if cb = @on_tick_cb
          cb.call self, count
        end 
      end
    end
  end
  
  class WiFi
    class << self
      attr_reader :ssid, :pass
    end
  
    def self.connect ssid, pass, &b
      ESP32.wifi_connect ssid,pass, &b
      @ssid = ssid
      @pass = pass
    end
    
    def self.ip
      connected? ? ESP32.wifi_get_ip : nil
    end
    
    def self.connected?
      ESP32.wifi_has_ip?
    end
    
    def self.on_disconnect &b
      ESP32.on_wifi_disconnect &b
    end
  end
end

def print m
  ESP32.log m
end

def p m
  print m.inspect
end

def puts m
  print m.to_s
end
