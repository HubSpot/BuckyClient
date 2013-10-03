(function() {
  describe('The Bucky Object', function() {
    it('should be defined', function() {
      return expect(Bucky).toBeDefined();
    });
    it('should itself be a client', function() {
      expect(Bucky.send).toBeDefined();
      expect(Bucky.timer).toBeDefined();
      expect(Bucky.count).toBeDefined();
      return expect(Bucky.requests).toBeDefined();
    });
    return it('should create clients when called', function() {
      return expect(Bucky().send).toBeDefined();
    });
  });

  describe('A Bucky Client', function() {
    var client;
    client = null;
    beforeEach(function() {
      return client = Bucky('prefix');
    });
    return it('should have a send method', function() {
      return expect(client.send).toBeDefined();
    });
  });

  describe('setOptions', function() {
    return it('should set options', function() {
      Bucky.setOptions({
        host: '/test'
      });
      return expect(Bucky.options.host).toBe('/test');
    });
  });

  describe('getFullUrl', function() {
    return it('should add the hostname if the url starts with slash', function() {
      return expect(Bucky.requests.getFullUrl('/test', {
        hostname: 'host'
      })).toBe('host/test');
    });
  });

  describe('urlToKey', function() {
    var utk;
    utk = Bucky.requests.urlToKey;
    it('should convert slashes to dots', function() {
      return expect(utk('a/b/c')).toBe('a.b.c');
    });
    it('should add the method', function() {
      return expect(utk('x', 'GET')).toBe('x.get');
    });
    it('should strip leading and trailing slashes', function() {
      return expect(utk('/a/b/c/')).toBe('a.b.c');
    });
    it('should strip get parameters', function() {
      var res, url;
      url = '/contacts/53/lists/ajax/list/all/detail?properties=%5B%22firstname%22%2C%22lastname%22%2C%22photo%22%2C%22twitterhandle%22%2C%22twitterprofilephoto%22%2C%22website%22%2C%22company%22%2C%22lifecyclestage%22%2C%22city%22%2C%22state%22%2C%22twitterhandle%22%2C%22phone%22%2C%22email%22%5D&offset=0&vidOffset=0&count=100&recent=true';
      res = 'contacts.lists.ajax.list.all.detail';
      return expect(utk(url)).toBe(res);
    });
    it('should strip url hashes', function() {
      expect(utk('/test/abc#page')).toBe('test.abc');
      return expect(utk('http://app.hubspot.com/analyze/landing-pages/#range=custom&frequency=weekly&start=03&end=06events')).toBe('app.hubspot.analyze.landing-pages');
    });
    it('should strip ids', function() {
      expect(utk('test/33/test/3423421')).toBe('test.test');
      expect(utk('a/b/432;234;232334;23;23/c')).toBe('a.b.c');
      expect(utk('fdf/443_34223424_324')).toBe('fdf');
      return expect(utk('/344-432/test')).toBe('test');
    });
    it('should strip .com and www.', function() {
      return expect(utk('http://www.google.com/test/site')).toBe('google.test.site');
    });
    it('should add the passed in root', function() {
      return expect(utk('test/as', null, 'root')).toBe('root.test.as');
    });
    it('should strip email addresses', function() {
      return expect(utk('test/page/zack@comnet.org/me')).toBe('test.page.me');
    });
    it('should strip domain names in the path', function() {
      return expect(utk('test/page/hubspot.com/me')).toBe('test.page.me');
    });
    it('should strip port numbers in the host', function() {
      return expect(utk('http://www.awesome.com:1337/test/page')).toBe('awesome.test.page');
    });
    it('should strip guids', function() {
      return expect(utk('https://app.hubspot.com/content/53/cta/clone/05abcf1a-b5e3-4e48-9817-c003ad16660a')).toBe('app.hubspot.content.cta.clone');
    });
    it('should strip hashes', function() {
      expect(utk('https://app.hubspot.com/analyze/53/api/pages/v3/pages/bd61568a93fc45637b8dceca1a34551b46627d26?errorsDismissed=1')).toBe('app.hubspot.analyze.api.pages.v3.pages');
      return expect(utk('https://app.hubspot.com/analyze/53/api/pages/v3/pages/098F6BCD4621D373CADE4E832627B4F6')).toBe('app.hubspot.analyze.api.pages.v3.pages');
    });
    it('should decode uri entities', function() {
      return expect(utk('test/it%20expect/it/to/work')).toBe('test.it.expect.it.to.work');
    });
    return it('should convert colons to underscores', function() {
      return expect(utk('test/path:with:colons/yea')).toBe('test.path_with_colons.yea');
    });
  });

  describe('send', function() {
    var server;
    server = null;
    beforeEach(function() {
      server = sinon.fakeServer.create();
      return server.autoRespond = true;
    });
    afterEach(function() {
      return server.restore();
    });
    it('should send a datapoint', function() {
      Bucky.send('data.point', 4);
      Bucky.flush();
      expect(server.requests.length).toBe(1);
      return expect(server.requests[0].requestBody).toBe("data.point:4|g\n");
    });
    return it('should send timers', function() {
      Bucky.send('data.1', 5, 'timer');
      Bucky.send('data.2', 3, 'timer');
      Bucky.flush();
      expect(server.requests.length).toBe(1);
      return expect(server.requests[0].requestBody).toBe("data.1:5|ms\ndata.2:3|ms\n");
    });
  });

}).call(this);
