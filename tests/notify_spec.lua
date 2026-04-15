local notify = require('CopilotChat.notify')

describe('CopilotChat.notify', function()
  before_each(function()
    -- Clear all listeners before each test
    notify.clear()
  end)

  describe('publish and listen', function()
    it('calls listener when event is published', function()
      local called = false
      local received_data = nil

      notify.listen('test_event', function(data)
        called = true
        received_data = data
      end)

      notify.publish('test_event', 'test_data')

      assert.is_true(called)
      assert.equals('test_data', received_data)
    end)

    it('supports multiple listeners for same event', function()
      local count = 0

      notify.listen('test_event', function(data)
        count = count + 1
      end)
      notify.listen('test_event', function(data)
        count = count + 10
      end)

      notify.publish('test_event', 'data')

      assert.equals(11, count)
    end)

    it('does not call listeners for different events', function()
      local called = false

      notify.listen('event_a', function(data)
        called = true
      end)

      notify.publish('event_b', 'data')

      assert.is_false(called)
    end)

    it('passes correct data to listeners', function()
      local received = nil

      notify.listen('test_event', function(data)
        received = data
      end)

      notify.publish('test_event', { foo = 'bar', num = 123 })

      assert.are.same({ foo = 'bar', num = 123 }, received)
    end)

    it('handles nil and empty data', function()
      local received = 'not_called'

      notify.listen('test_event', function(data)
        received = data
      end)

      notify.publish('test_event', nil)
      assert.is_nil(received)

      notify.publish('test_event', '')
      assert.equals('', received)
    end)

    it('handles publishing to events with no listeners', function()
      -- Should not error
      assert.has_no.errors(function()
        notify.publish('nonexistent_event', 'data')
      end)
    end)
  end)

  describe('clear', function()
    it('removes all listeners', function()
      local called = false

      notify.listen('test_event', function(data)
        called = true
      end)

      notify.clear()
      notify.publish('test_event', 'data')

      assert.is_false(called)
    end)

    it('allows adding new listeners after clear', function()
      local called = false

      notify.listen('test_event', function(data)
        called = true
      end)
      notify.clear()

      notify.listen('test_event', function(data)
        called = true
      end)
      notify.publish('test_event', 'data')

      assert.is_true(called)
    end)
  end)

  describe('constants', function()
    it('defines STATUS constant', function()
      assert.equals('status', notify.STATUS)
    end)

    it('defines MESSAGE constant', function()
      assert.equals('message', notify.MESSAGE)
    end)
  end)
end)
