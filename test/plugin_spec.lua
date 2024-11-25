-- Mock packages
package.loaded['plenary.async'] = {
  wrap = function(fn)
    return function(...)
      return fn(...)
    end
  end,
}
package.loaded['plenary.curl'] = {}
package.loaded['plenary.log'] = {}
package.loaded['plenary.scandir'] = {}

describe('CopilotChat plugin', function()
  it('should be able to load', function()
    assert.truthy(require('CopilotChat'))
  end)
end)
