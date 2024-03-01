-- Mock packages
package.loaded['plenary.curl'] = {}
package.loaded['plenary.log'] = {}

describe('CopilotChat plugin', function()
  it('should be able to load', function()
    assert.truthy(require('CopilotChat'))
  end)
end)
