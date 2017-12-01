# Simple REPL Server

class << self
  def init prompt = "> ", ret = "#=> "
    @prompt = prompt
    @return = ret
    
    @clients = []

    MEES::WiFi.connect "kittykat", "FooBar-12" do |ip|
      puts "IP: #{ip}"

      @s = MEES::TCPServer.new do |c|
        c.write @prompt
        @clients << c
      end
    end
  end

  def call
    @clients.each do |c|
      if (data=c.recv_nonblock)
        c.write @return
        c.write MEES.eval(data)
        c.write @nl||="\n"
        c.write "# Free stack: #{MEES::Task.stack_watermark}. Free RAM: #{ESP32::System.available_memory}. % GC Fire: #{MEES.threshold_gc_fire}.\n"
        c.write @prompt
      end
    end if @s
  end
end

init

MEES::main self
