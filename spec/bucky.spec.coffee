describe 'The Bucky Object', ->
  it 'should be defined', ->
    expect(Bucky).toBeDefined()

  it 'should itself be a client', ->
    expect(Bucky.send).toBeDefined()
    expect(Bucky.timer).toBeDefined()
    expect(Bucky.count).toBeDefined()
    expect(Bucky.requests).toBeDefined()

  it 'should create clients when called', ->
    expect(Bucky().send).toBeDefined()

describe 'A Bucky Client', ->
  client = null

  beforeEach ->
    client = Bucky('prefix')

  it 'should have a send method', ->
    expect(client.send).toBeDefined()

describe 'getFullUrl', ->
  it 'should add the hostname if the url starts with slash', ->
    expect(Bucky.requests.getFullUrl('/test', {hostname: 'host'})).toBe('host/test')

describe 'urlToKey', ->
  utk = Bucky.requests.urlToKey

  it 'should convert slashes to dots', ->
    expect(utk('a/b/c')).toBe('a.b.c')

  it 'should add the method', ->
    expect(utk('x', 'GET')).toBe('x.get')
    
  it 'should strip leading and trailing slashes', ->
    expect(utk('/a/b/c/')).toBe('a.b.c')

  it 'should strip get parameters', ->
    url = '/contacts/53/lists/ajax/list/all/detail?properties=%5B%22firstname%22%2C%22lastname%22%2C%22photo%22%2C%22twitterhandle%22%2C%22twitterprofilephoto%22%2C%22website%22%2C%22company%22%2C%22lifecyclestage%22%2C%22city%22%2C%22state%22%2C%22twitterhandle%22%2C%22phone%22%2C%22email%22%5D&offset=0&vidOffset=0&count=100&recent=true'
    res = 'contacts.lists.ajax.list.all.detail'

    expect(utk(url)).toBe(res)

  it 'should strip url hashes', ->
    expect(utk('/test/abc#page')).toBe('test.abc')
    expect(utk('http://app.hubspot.com/analyze/landing-pages/#range=custom&frequency=weekly&start=03&end=06events')).toBe('app.hubspot.analyze.landing-pages')

  it 'should strip events', ->
    expect(utk('contacts/53/ajax/event/000000003176')).toBe('contacts.ajax.events')
    expect(utk('contacts/53/ajax/events/9pgMAm3nY6sh/test')).toBe('contacts.ajax.events.test')

  it 'should strip ids', ->
    expect(utk('test/33/test/3423421')).toBe('test.test')
    expect(utk('a/b/432;234;232334;23;23/c')).toBe('a.b.c')
    expect(utk('fdf/443_34223424_324')).toBe('fdf')
    expect(utk('/344-432/test')).toBe('test')

  it 'should strip .com and www.', ->
    expect(utk('http://www.google.com/test/site')).toBe('google.test.site')

  it 'should add the passed in root', ->
    expect(utk('test/as', null, 'root')).toBe('root.test.as')

  it 'should strip secure ids', ->
    expect(utk('https://app.hubspot.com/contacts/53/lists/ajax/contact/_AO_T-mNtu9TBKIkc1lTfjBFOMBYFx1B4TzhLV6gYdIpsP-AUbHrAzFUQ7-M5bkRdvdYHQ5ro9LqVxmc4nzeNZ7D2V0aqoaQXCg/detail?includeHistory=true&includeEmailSubscriptions=true&includePublicUrl=true')).toBe('app.hubspot.contacts.lists.ajax.contact.detail')

  it 'should strip email addresses', ->
    expect(utk('test/page/zack@comnet.org/me')).toBe('test.page.me')

  it 'should strip domain names in the path', ->
    expect(utk('test/page/hubspot.com/me')).toBe('test.page.me')

  it 'should strip static versions in the path', ->
    expect(utk('example.com/test/static-1.343/other')).toBe('example.test.static.other')

  it 'should strip port numbers in the host', ->
    expect(utk('http://www.awesome.com:1337/test/page')).toBe('awesome.test.page')

  it 'should strip guids', ->
    expect(utk('https://app.hubspot.com/content/53/cta/clone/05abcf1a-b5e3-4e48-9817-c003ad16660a')).toBe('app.hubspot.content.cta.clone')

  it 'should strip hashes', ->
    expect(utk('https://app.hubspot.com/analyze/53/api/pages/v3/pages/bd61568a93fc45637b8dceca1a34551b46627d26?errorsDismissed=1')).toBe('app.hubspot.analyze.api.pages.v3.pages')
    expect(utk('https://app.hubspot.com/analyze/53/api/pages/v3/pages/098F6BCD4621D373CADE4E832627B4F6')).toBe('app.hubspot.analyze.api.pages.v3.pages')

  it 'should decode uri entities', ->
    expect(utk('test/it%20expect/it/to/work')).toBe('test.it.expect.it.to.work')

  it 'should convert colons to underscores', ->
    expect(utk('test/path:with:colons/yea')).toBe('test.path_with_colons.yea')

  it 'should strip .js extensions', ->
    expect(utk('test/path/ending/in/something.js')).toBe('test.path.ending.in.something')

describe 'send', ->
  server = null

  beforeEach ->
    server = sinon.fakeServer.create()
    server.autoRespond = true

    window.BUCKY_DEPLOYED = true

  afterEach ->
    server.restore()

  it 'should send a datapoint', ->
    Bucky.send 'data.point', 4
    Bucky.flush()

    expect(server.requests.length).toBe(1)
    expect(JSON.parse(server.requests[0].requestBody)['data.point']).toBe("4.000|g")

  it 'should send timers', ->
    Bucky.send 'data.1', 5, 'timer'
    Bucky.send 'data.2', 3, 'timer'
    Bucky.flush()

    body = JSON.parse server.requests[0].requestBody
    expect(body['data.1']).toBe("5.000|ms")
    expect(body['data.2']).toBe("3.000|ms")

    expect(server.requests.length).toBe(1)
