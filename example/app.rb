while true
  s = ''
  if c = MEES::IO.getc(1)
    print s=MEES.bytes_to_s(c)
  else
    p :here
    MEES.inputc 49
    MEES::Task.delay 1000
  end
end
