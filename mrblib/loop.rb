module ESP32;class Printf
  NIL   = "nil"
  TRUE  = "true"
  FALSE = "false"
  
  def initialize fmt
    @fmt = fmt.split("%s")
    @args = []
  end
  
  def []= i,v
    @args[i]=v
  end
  
  def write_arg
    if @args[@i].is_a? Float
      ESP32.printff @args[@i]
    elsif @args[@i].is_a? String
      ESP32.printfs @args[@i]
    elsif @args[@i].is_a? Fixnum
      ESP32.printfd @args[@i]
    elsif @args[@i] == nil
      ESP32.printfs NIL
    elsif @args[@i] == true
      ESP32.printfs TRUE
    elsif @args[@i] == false
      ESP32.printfs FALSE    
    else
      ESP32.printfs a.inspect
    end  
  end
  
  def write a,b=nil,c=nil,d=nil,e=nil,f=nil,g=nil,h=nil,i=nil,j=nil,k=nil,l=nil,m=nil
    @args[0]=a
    @args[1]=b
    @args[2]=c
    @args[3]=d
    @args[4]=e
    @args[5]=f
    @args[6]=g
    @args[7]=h
    @args[8]=i
    @args[9]=j
    @args[10]=k
    @args[11]=l
    @args[12]=m
                                               
    @i=0
    arg=nil
    while @i < @fmt.length
      ESP32.printfs @fmt[@i]
      write_arg
      @i+=1
    end
  end
  
  module Writer
    def printf a,b=nil,c=nil,d=nil,e=nil,f=nil,g=nil,h=nil,i=nil,j=nil,k=nil,l=nil,m=nil
      @printf.write a,b,c,d,e,f,g,h,i,j,k,l,m
    end
  end
end;end

def puts s
  if s.is_a?(String)
    ESP32.printfs s
  elsif s.is_a?(Fixnum)
    ESP32.printfd s
  elsif s.is_a? Float
    ESP32.printff s
  else
    ESP32.printfs s.to_s
  end
  ESP32.printfs @nl||="\n"
end

def p s
  if s.is_a?(String)
    ESP32.printfs s
  elsif s.is_a?(Fixnum)
    ESP32.printfd s
  elsif s.is_a? Float
    ESP32.printff s
  else
    ESP32.printfs s.inspect
  end
  ESP32.printfs @nl||="\n"
end

def print s
  if s.is_a?(String)
    ESP32.printfs s
  elsif s.is_a?(Fixnum)
    ESP32.printfd s
  elsif s.is_a? Float
    ESP32.printff s
  else
    ESP32.printfs s.inspect
  end
end

module ESP32
  def self.time
    @time ||= Time.now
  end
  
  def self.wifi_connected?
    @wifi_connected
  end
  
  def self.pass!
    @lt ||= time.to_f
    time.initialize
    
    return unless time.to_f > @lt
    
    @lt = time.to_f;
    
    if !@wifi_connected and wifi_has_ip?
      @wifi_connected = true
      
      if @on_wifi_connected_cb
        @on_wifi_connected_cb.call wifi_get_ip
      end
    else
      if @wifi_connected and !wifi_has_ip?
        if @on_wifi_disconnected_cb
          @on_wifi_disconnected_cb.call
        end
        
        @wifi_connected = false
      end
    end
    
    return true
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

  def self.on_wifi_disconnect &b
    @on_wifi_disconnected_cb = b
  end

  def self.wifi_connect ssid, pass, &b
    @on_wifi_connected_cb = b
    __wifi_connect__ ssid,pass  
  end 
  
  def self.main &b
    app_run(Proc.new do
      pass!
      b.call
    end)
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
      return @ip if @ip
      connected? ? @ip=ESP32.wifi_get_ip : nil
    end
    
    def self.connected?
      ESP32.wifi_has_ip?
    end
    
    def self.on_disconnect &b
      ESP32.on_wifi_disconnect &b
    end
  end
end

class WebSocket
  class Event
    CONNECT    = 0
    DISCONNECT = 1
  end
  
  attr_reader :host
  def initialize host, &recv
    @host = host
    @a=[]
    @ws   = ESP32.ws host do |data|
      @a[0]=data
      case data
      when Event::CONNECT
        @connected = true
      when Event::DISCONNECT
        @connected=false
      end
      
      recv.call self, data
    end
  end
  
  def connected?
    @connected
  end
  
  def puts s
    ESP32.ws_write @ws, s
  end
  
  def close
    ESP32.ws_close @ws
  end
end
