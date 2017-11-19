class << self
def init
  @pin   = ESP32::GPIO::Pin.new(23, :output)
  @t     = 0
  @level = false

  @half_cycle = 33
  @step = 33
  @dir  = 1

  ESP32::WiFi.connect("LGL64VL_7870", "FooBar12") do |ip|
   puts @ip = ip
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
  
  @printf ||= Printf.new("
  \nlooped: %s
  ip:     %s
  memory:     least %s, current %s
  least free stack: %s
  ")
  
  @st ||= ESP32::time.to_f
  @tt ||= ESP32::time.to_f
  ESP32.time.initialize
  #ESP32.pass!    

    if ((ESP32.time.to_f - @tt) >= (@half_cycle*0.001))  
      @tt = ESP32.time.to_f
      lvl = (@level = !@level) ? 1 : 0 
      @pin.write lvl 
    end

  
  if (ESP32.time.to_f - @st) >= 1
    @st = ESP32.time.to_f
    @printf.write @t,
                  ESP32::WiFi.ip,
                  lmf,
                  ESP32::System.available_memory, 
                  ESP32.watermark
    
  end
end
end

class Printf
  NIL = "nil"
  NIL.freeze
  
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
    else
      #ESP32.printfs a.inspect
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
end



init
while true
  run
end
