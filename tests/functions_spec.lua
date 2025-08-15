local functions = require('CopilotChat.functions')

describe('CopilotChat.functions', function()
  describe('uri_to_url', function()
    it('replaces parameters in uri template', function()
      local uri = 'file://{path}'
      local input = { path = '/tmp/test.txt' }
      assert.equals('file:///tmp/test.txt', functions.uri_to_url(uri, input))
    end)
    it('leaves missing params empty', function()
      local uri = 'file://{path}/{id}'
      local input = { path = '/tmp' }
      assert.equals('file:///tmp/', functions.uri_to_url(uri, input))
    end)
  end)

  describe('match_uri', function()
    it('matches uri and extracts parameters', function()
      local uri = 'file:///tmp/test.txt'
      local pattern = 'file://{path}'
      local result = functions.match_uri(uri, pattern)
      assert.are.same({ path = '/tmp/test.txt' }, result)
    end)
    it('returns nil for non-matching uri', function()
      assert.is_nil(functions.match_uri('abc', 'file://{path}'))
    end)
    it('returns empty table for exact match with no params', function()
      assert.are.same({}, functions.match_uri('abc', 'abc'))
    end)
  end)

  describe('parse_schema', function()
    it('returns schema if present', function()
      local fn = { schema = { type = 'object', properties = { foo = { type = 'string' } } } }
      assert.equals(fn.schema, functions.parse_schema(fn))
    end)
    it('generates schema from uri if missing', function()
      local fn = { uri = 'file://{path}/{id}' }
      local schema = functions.parse_schema(fn)
      assert.are.same({
        type = 'object',
        properties = { path = { type = 'string' }, id = { type = 'string' } },
        required = { 'path', 'id' },
      }, schema)
    end)
  end)

  describe('parse_input', function()
    it('parses input string into table', function()
      local schema = { properties = { a = {}, b = {} }, required = { 'a', 'b' } }
      local input = 'foo;;bar'
      assert.are.same({ a = 'foo', b = 'bar' }, functions.parse_input(input, schema))
    end)
    it('returns input if already table', function()
      local input = { a = 1 }
      assert.equals(input, functions.parse_input(input))
    end)
    it('returns empty table if no schema', function()
      assert.are.same({}, functions.parse_input('foo'))
    end)
  end)
end)
