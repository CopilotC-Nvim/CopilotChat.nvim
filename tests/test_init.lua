local T = MiniTest.new_set()

T['should be able to load'] = function()
  MiniTest.expect.no_error(function()
    require('CopilotChat')
  end)
end

return T
