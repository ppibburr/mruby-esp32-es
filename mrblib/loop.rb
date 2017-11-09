module ESP32
  def self.time
    @time ||= Time.now.to_f
  end
  
  def self.__tick!
    return if time == t=Time.now.to_f
    
    @time = t
    t = nil
  
    if @__tick_queue__
      @__tick_queue__.each do |cb|
        begin
          cb.call cb
        rescue => e
          puts "\n#{e}"
          raise e
        end
      end
    end
  end
  
  def self.wifi_connected?
    @wifi_connected
  end
  
  def self.pass!
    event? if events_enabled?   
    __tick!
    if wifi_has_ip?
      if !@wifi_connected
        @wifi_connected = true
        if cb = @on_wifi_connected_cb
          cb.call wifi_get_ip
        end
      end
    else
      @wifi_connected = false
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
  
  def self.remove_tick b
    @__tick_queue__.delete(b)
  end

  def self.tick &b
    (@__tick_queue__ ||= []) << b
  end

  def self.timeout d, res=:usec, &b
    interval d, res do
      b.call
      
      next false
    end
  end

  def self.interval d, res=:usec, &b
    step = nil
    case res
    when :usec
      step = d  *  0.000001
    when :millis
      step = d * 0.001
    when :second
      step = d
    end

    n_tick = time + step
    
    tick do |t_cb|    
      if d > 0
        next unless (time() >= n_tick)
        n_tick += step
      end
      
      unless b.call t_cb
        remove_tick t_cb
      end
    end  
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

  def self.wifi_connect ssid, pass, &b
    @on_wifi_connected_cb = b
    __wifi_connect__ ssid,pass
    3000.times do
      yield!
    end  
  end 
  
  def self.main
    while 1
      pass!
    
      yield
    end  
  end
  
  class Timer
    attr_accessor :count, :max, :auto_reset
    attr_reader   :interval, :resolution
    
    def initialize interval, max = -1, &b
      a = interval.is_a?(Array) ? interval : [interval]
      
      @interval   = a[0]
      @resolution = a[1] || :usec
      
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
    
    def stop
      @enable = false
    end
    
    def delete
      ESP32.remove_tick @t_cb    
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
    
      ESP32.interval interval, resolution do |t_cb|
        @t_cb = t_cb
        
        if enabled?
          tick!
          next enabled?
        end
        
        next false
      end
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
    
    def tick!
      @count += 1 if enabled?
      
      if count > max and max > 0
        if cb = @on_expire_cb
          cb.call self if enabled?
          
          unless auto_reset
            stop
          end
        end
          
        reset
      end
        
      if cb = @on_tick_cb and enabled?
        cb.call self, count
      end    
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
