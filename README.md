Bucky
=====

Bucky is a client and server for sending stats from the client and node into statsd+graphite, OpenTSDB, or any
other stats aggregator of your choice.

It can automatically measure how long your pages take to load, how long AJAX requests take and how long
various functions take to run.  Most importantly, it's taking the measurements on actual page loads,
so the data has the potential to be much more valuable than in vitro measurements.

If you already use statsd or OpenTSDB, you can get started in just a few minutes.  If you're not
collecting stats, you should start!  What gets measured gets managed.

### Server

You can play with Bucky just using the client, but if you'd like to start collecting data, see the
[Server Instructions](http://github.com/HubSpot/BuckyServer).

### Setup

#### From The Client

Include `BuckyClient/bucky.js` file on your page

The `Bucky` object will be available globally.

Bucky can also be loaded with AMD or Browserify.

#### From Node

```bash
npm install bucky
```

```coffeescript
bucky = require('bucky')
```

### Configuring

Before sending any data, call `setOptions`:

```javascript
Bucky.setOptions({
  host: 'http://myweb.site:9999/bucky'
});
```

Some options you might be interested in:

- `host`: Where we can reach your [http://github.com/HubSpot/BuckyServer](Bucky server), including the
  APP_ROOT.

  The Bucky server has a very liberal CORS config, so we should be able to connect to it even if
  it's on a different domain, but hosting it on the same domain and port will save you some preflight requests.

- `active`: Should Bucky actually send data?  Use this to disable Bucky during local dev for example.
- `sample`: What fraction of clients should actually send data?  Use to subsample your clients if you have
  too much data coming in.

Take a look at [the source](http://github.com/HubSpot/BuckyClient/blob/master/bucky.coffee#L27) for a
full list of options.

#### Sending Page Performance

Modern browsers log a bunch of page performance data, bucky includes a method for writing all of this in
one go.  It won't do anything on browsers which don't support the performance.timing api.  Call it whenver,
it will bind an event if the data isn't ready yet.

```coffeescript
Bucky.sendPerformanceData('where.the.data.should.go')
```

The two most relevant stats provided are `responseEnd` which is the amount of time it took for the
original page to be loaded and `domInteractive` which is the amount of time before the page has
finished loaded and can be interacted with by the user.

As a reminder: this data is browser specific, so it will likely skew lower than what users on
old browsers see.

If you're using Backbone, it might be a good idea to send your data based on route:

```coffeescript
Backbone.history.on 'route', (router, route) ->
   # Will only send on the initial page load:
   Bucky.sendPerformanceData("some.location.page.#{ route }")
```

#### Sending AJAX Request Time

Bucky can automatically log all ajax requests made by hooking into XMLHttpRequest and doing some transformations
on the url to try and create a graphite key from it.  Enable it as early in your app's load as is possible:

```coffeescript
Bucky.requests.monitor('my.project.requests')
```

#### Prefixing

You can build a client which will prefix all of your datapoints by calling bucky as a function:

```coffeescript
myBucky = Bucky('awesome.app.view')

# You can then use all of the normal methods:
myBucky.send('data.point', 5)
```

You can repeatedly call clients to add more prefixes:

```coffeescript
contactsBucky = bucky('contacts')
cwBucky = contactsBucky('web')

cwBucky.send('x', 1) # Data goes in contacts.web.x
```

#### Counting Things

Bucky includes a js client which can be used both on the client and in Node.  It will automatically
enqueue your messages and send them in bulk periodically.

By default `send` sends absolute values, this is rarely what you want when working from the client, incrementing
a counter is usually more helpful:

```coffeescript
bucky.count('my.awesome.thing')
bucky.count('number.of.chips.eaten', 5)
```

#### Timing Things

You can manually send ms durations using send:

```coffeescript
bucky.timer.send('timed.thing', 55)
```

Bucky includes a method to time async functions:

```coffeescript
bucky.timer.time 'my.awesome.function', (done) ->
  asyncThingy ->
    done()
```

You can also manually start and stop your timer:

```coffeescript
bucky.timer.start 'my.awesome.function'

asyncThingy ->
  bucky.timer.stop 'my.awesome.function'
```

You can time synchronous functions as well:

```coffeescript
bucky.timer.timeSync 'my.awesome.function', ->
  Math.sqrt(100)
```

The `time` and `timeSync` functions also accept a context and arguments to pass to the 
called function:

```coffeescript
bucky.timer.timeSync 'my.render.function', @render, @, arg1, arg2
```

You can wrap existing functions using `wrap`:

```coffeescript
func = bucky.timer.wrap('func.time', func)
```

It also supports a special syntax for methods:

```coffeescript
class SomeClass
  render: bucky.timer.wrap('render') ->
    # Normal render stuff
```

Note that this wrapping does not play nice with CoffeeScript `super` calls.

Bucky also includes a function for measuring the time since the navigationStart event was fired (the beginning of the request):

```coffeescript
bucky.timer.mark('my.thing.happened')
```

It acts like a timer where the start is always navigation start.

The stopwatch method allows you to begin a timer which can be stopped multiple times:

```coffeescript
watch = bucky.stopwatch('some.prefix.if.you.want')
```

You can then call `watch.mark('key')` to send the time since the stopwatch started, or
`watch.split('key')` to send the time since the last split.

### Sending Points

If you want to send absolute values (rare from the client), you can use send directly.

The one use we've had for this is sending `+new Date` from every client to get an idea
of how skewed their clocks are.

```coffeescript
Bucky.send 'my.awesome.datapoint', 2432.43434
```

### Your Stats

You can find your stats in the `stats` and `stats.timing` folders in graphite, or as written in OpenTSDB.

### Send Frequency

Bucky will send your data in bulk from the client either five seconds after the last datapoint is added, or thirty seconds after
the last send, whichever comes first.  If you log multiple datapoints within this send frequency, the points will
be averaged (and the appropriate frequency information will be sent to statsd) (with the exception of counters, they
are incremented).  This means that the max and min numbers you get from statsd actually represent the max and min 
5-30 second bucket.  Note that this is per-client, not for the entire bucky process (it's generally only important
on the server where you might be pushing out many points with the same key).

### Bucky Object

The Bucky object provides a couple extra properties you can access:

- `Bucky.history`: The history of all datapoints ever send.
- `Bucky.active`: Is Bucky sending data?  This can change if you change the `active` or `sample` settings.
- `Bucky.flush()`: Send the Bucky queue immediately
- `Bucky.timer.now()`: A clock based on the most precise time available (not guarenteed to be from the epoch)

### URL -> Key Transformation

`request.monitor` attempts to automatically transform your urls into keys.  It does a bunch of transformations
with the goal of removing anything which will vary per-request, so you end up with stats per-endpoint.  These
tranformations include:

- Stripping GUIDS, IDS, SHA1s, MD5s
- Stripping email addresses
- Stripping domains
- Stripping .com and www.
- Replacing slashes and spaces with '.'

If you find these tranformations too invasive, or not invasive enough, you can modify them.

```javascript
// You can diable tranforms with `.disable`
Bucky.requests.transforms.disable('guid');

// You can enable transforms with `.enable`
Bucky.requests.tranforms.enable('guid');

// `.enable` can also be used to add a new tranform:
Bucky.requests.transforms.enable('my-ids', /[0-9]{4}-[0-9]{12}/g)

// The third argument defines what the match is replaced with (rather than just eliminating it):
Bucky.requests.transforms.enable('campaign', /campaigns\/\w{15}/ig, '/campaigns')

// You can also just provide a function which takes in the url, and returns it modified:
Bucky.request.transforms.enable('soup', function(url){ return url.split('').reverse().join(''); })
```

Enabled tests will be added to the beginning of the `enabled` list, meaning they will be executed before
any other tranform.  Edit the `Bucky.requests.tranforms.enabled` array if you need more specific control.

### App Server

This project pushes data to the Bucky Server.

[http://github.com/HubSpot/BuckyServer/READM.md](Server Documentation)
