local class = require('CopilotChat.utils.class')

describe('CopilotChat.utils.class', function()
  it('creates a simple class', function()
    local Foo = class(function(self, x)
      self.x = x
    end)
    local obj = Foo(42)
    assert.equals(42, obj.x)
  end)

  it('supports init method', function()
    local Bar = class(function(self, y)
      self.y = y
    end)
    local obj = Bar.new(7)
    assert.equals(7, obj.y)
    obj:init(8)
    assert.equals(8, obj.y)
  end)

  it('supports inheritance', function()
    local Parent = class(function(self) self.val = 1 end)
    local Child = class(function(self) self.val = 2 end, Parent)
    local obj = Child()
    assert.equals(2, obj.val)
    assert.equals(Parent, getmetatable(Child).__index)
  end)
end)
